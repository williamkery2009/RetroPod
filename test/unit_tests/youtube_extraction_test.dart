import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:retropod/core/models/music_metadata.dart';
import 'package:retropod/core/services/youtube_music_service.dart';
import 'package:retropod/core/services/online_music_service.dart';
import 'package:retropod/core/services/youtube_playback_error.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test(
    'failed fallback preserves direct verification failure safely',
    () async {
      final client = MockClient((_) async => http.Response('secret', 503));
      addTearDown(client.close);
      final service = OnlineMusicService(
        client,
        resolveYoutubeAudio: (_) async {
          throw StateError('Sign in Cookie: secret');
        },
      );
      await expectLater(
        service.resolveForPlayback(
          MusicMetadata(
            filePath: 'https://music.youtube.com/watch?v=abcdefghijk',
            isOnDevice: false,
          ),
        ),
        throwsA(
          predicate<Object>((error) {
            final message = youtubePlaybackErrorMessage(error);
            return message.contains('YT_SIGN_IN') &&
                message.contains('PIPED_SERVER') &&
                !message.contains('secret');
          }),
        ),
      );
    },
  );

  test(
    'extracts audio through the real parser without fetching a watch page',
    () async {
      final calls = <String>[];
      final transport = MockClient((request) async {
        calls.add('${request.method} ${request.url.path}');
        if (request.method == 'HEAD')
          return http.Response('', 200, request: request);
        expect(request.method, 'POST');
        expect(request.url.path, '/youtubei/v1/player');
        final body = jsonDecode(request.body) as Map;
        expect(body['videoId'], 'abcdefghijk');
        expect(body['context']['client']['clientName'], 'VISIONOS');
        return http.Response(
          jsonEncode({
            'playabilityStatus': {'status': 'OK'},
            'streamingData': {
              'adaptiveFormats': [
                {
                  'itag': 140,
                  'url': 'https://media.example/audio?sig=fresh&itag=140',
                  'mimeType': 'audio/mp4; codecs="mp4a.40.2"',
                  'bitrate': 128000,
                  'contentLength': '1000000',
                },
                {
                  'itag': 251,
                  'url': 'https://media.example/opus?sig=fresh&itag=251',
                  'mimeType': 'audio/webm; codecs="opus"',
                  'bitrate': 160000,
                  'contentLength': '1200000',
                },
              ],
            },
          }),
          200,
          headers: {'content-type': 'application/json'},
          request: request,
        );
      });
      final extractorHttp = YoutubeHttpClient(transport);
      final searchClient = MockClient((_) async => http.Response('{}', 200));
      addTearDown(searchClient.close);
      final service = YoutubeMusicService(
        searchClient,
        createExtractor: () => YoutubeExplode(httpClient: extractorHttp),
      );
      final song = MusicMetadata(
        filePath: 'https://music.youtube.com/watch?v=abcdefghijk',
        isOnDevice: false,
      );
      final playable = await service.resolveForPlayback(song);
      expect(
        playable.filePath,
        'https://media.example/audio?sig=fresh&itag=140',
      );
      expect(song.filePath, 'https://music.youtube.com/watch?v=abcdefghijk');
      expect(calls, ['POST /youtubei/v1/player', 'HEAD /audio']);
      expect(extractorHttp.closed, isTrue);
    },
  );

  test('sign-in rejection reaches the UI and closes the extractor', () async {
    final transport = MockClient(
      (request) async => http.Response(
        jsonEncode({
          'playabilityStatus': {
            'status': 'LOGIN_REQUIRED',
            'reason': "Sign in to confirm you're not a bot",
          },
        }),
        200,
        headers: {'content-type': 'application/json'},
        request: request,
      ),
    );
    final extractorHttp = YoutubeHttpClient(transport);
    final searchClient = MockClient((_) async => http.Response('{}', 200));
    addTearDown(searchClient.close);
    final service = YoutubeMusicService(
      searchClient,
      createExtractor: () => YoutubeExplode(httpClient: extractorHttp),
    );
    await expectLater(
      service.resolveForPlayback(
        MusicMetadata(
          filePath: 'https://music.youtube.com/watch?v=abcdefghijk',
          isOnDevice: false,
        ),
      ),
      throwsA(
        predicate<Object>(
          (error) => youtubePlaybackErrorMessage(error).contains('YT_SIGN_IN'),
        ),
      ),
    );
    expect(extractorHttp.closed, isTrue);
  });

  test(
    'playback diagnostics identify failures without exposing signed URLs',
    () {
      final errors = <Object, String>{
        TimeoutException('https://private.example/?sig=secret'): 'YT_TIMEOUT',
        StateError('Sign in to confirm you are not a bot'): 'YT_SIGN_IN',
        StateError('403 https://private.example/?sig=secret'): 'YT_403',
        StateError('429 https://private.example/?sig=secret'): 'YT_RATE_LIMIT',
        StateError('https://private.example/?sig=secret'): 'YT_PLAYBACK',
      };
      for (final entry in errors.entries) {
        final message = youtubePlaybackErrorMessage(entry.key);
        expect(message, contains(entry.value));
        expect(message, isNot(contains('secret')));
        expect(message, isNot(contains('private.example')));
      }
    },
  );
}
