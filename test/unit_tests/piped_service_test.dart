import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:retropod/core/models/music_metadata.dart';
import 'package:retropod/core/services/online_music_service.dart';
import 'package:retropod/core/services/piped_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

Map<String, Object?> audio(
  String url,
  String mime,
  int bitrate, {
  bool videoOnly = false,
}) => {
  'url': url,
  'mimeType': mime,
  'bitrate': bitrate,
  'videoOnly': videoOnly,
};

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('selects highest bitrate M4A, ignoring video and insecure URLs', () {
    final result = PipedService.parseAudio({
      'audioStreams': [
        audio('https://audio.example/opus', 'audio/webm', 200000),
        audio('https://audio.example/low', 'audio/mp4', 64000),
        audio('https://audio.example/high?sig=token', 'audio/mp4', 128000),
        audio('http://audio.example/bad', 'audio/mp4', 999999),
        audio(
          'https://audio.example/video',
          'audio/mp4',
          999999,
          videoOnly: true,
        ),
      ],
    });
    expect(result.toString(), 'https://audio.example/high?sig=token');
    expect(
      PipedService.parseAudio({
        'audioStreams': [
          audio('https://audio.example/opus', 'audio/webm', 200000),
        ],
      }).path,
      '/opus',
    );
  });

  test('rejects error responses and unsupported or absent audio', () {
    for (final data in [
      null,
      {'error': 'blocked'},
      {'audioStreams': []},
      {
        'audioStreams': [audio('https://media.example/v', 'video/mp4', 100)],
      },
    ]) {
      expect(
        () => PipedService.parseAudio(data),
        throwsA(isA<PipedPlaybackException>()),
      );
    }
  });

  test(
    'validates and persists HTTPS API addresses with a path prefix',
    () async {
      await PipedService.saveInstance(' https://piped.example/api/ ');
      expect(
        (await PipedService.configuredInstance()).toString(),
        'https://piped.example/api',
      );
      for (final url in [
        'http://piped.example',
        'https://user:pass@piped.example',
        'https://piped.example/?token=secret',
        'https://piped.example/#fragment',
        'invalid',
      ]) {
        expect(() => PipedService.validateInstance(url), throwsFormatException);
      }
    },
  );

  test(
    'Piped source skips local extraction and preserves stable metadata',
    () async {
      await PipedService.saveInstance('https://piped.example/api');
      var requests = 0;
      final client = MockClient((request) async {
        requests++;
        expect(
          request.url.toString(),
          'https://piped.example/api/streams/abcdefghijk',
        );
        expect(request.headers.containsKey('authorization'), isFalse);
        expect(request.headers.containsKey('cookie'), isFalse);
        return http.Response(
          jsonEncode({
            'audioStreams': [
              audio(
                'https://audio.example/file?sig=fresh',
                'audio/mp4',
                128000,
              ),
            ],
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });
      addTearDown(client.close);
      var directCalls = 0;
      final service = OnlineMusicService(
        client,
        resolveYoutubeAudio: (_) async {
          directCalls++;
          throw StateError('Direct unavailable');
        },
      );
      final song = MusicMetadata(
        isOnDevice: false,
        filePath:
            'https://music.youtube.com/watch?v=abcdefghijk&provider=piped',
      );
      final result = await service.resolveForPlayback(song);
      expect(result.filePath, 'https://audio.example/file?sig=fresh');
      expect(song.filePath, contains('provider=piped'));
      expect(directCalls, 0);
      expect(requests, 1);
      // The original source gets one fallback when its resolver fails.
      await service.resolveForPlayback(
        song.copyWith(
          filePath: 'https://music.youtube.com/watch?v=abcdefghijk',
        ),
      );
      expect(directCalls, 1);
      expect(requests, 2);
      // Ordinary remote streams never go to Piped.
      final radio = MusicMetadata(
        isOnDevice: false,
        filePath: 'https://radio.example/live',
      );
      expect(await service.resolveForPlayback(radio), same(radio));
      expect(requests, 2);
    },
  );

  test(
    'server errors and HTML responses produce safe actionable diagnostics',
    () async {
      for (final status in [200, 500]) {
        final client = MockClient(
          (_) async => http.Response('<html>secret</html>', status),
        );
        final service = PipedService(
          client,
          instance: () async => Uri.parse('https://piped.example'),
        );
        addTearDown(client.close);
        await expectLater(
          service.resolveAudio('abcdefghijk'),
          throwsA(
            predicate<Object>(
              (error) =>
                  error is PipedPlaybackException &&
                  error.message.contains('PIPED_') &&
                  !error.message.contains('secret'),
            ),
          ),
        );
      }
    },
  );
}
