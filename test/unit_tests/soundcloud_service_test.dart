import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:just_audio/just_audio.dart';
import 'package:retropod/core/services/soundcloud_service.dart';

Map<String, Object?> scTrack({String policy = 'ALLOW', bool snipped = false}) =>
    {
      'id': 123,
      'title': 'Blinding Lights (remake)',
      'user': {'username': 'Uploader'},
      'streamable': true,
      'policy': policy,
      'sharing': 'public',
      'duration': 210000,
      'track_authorization': 'ephemeral-track-token',
      'media': {
        'transcodings': [
          {
            'url': 'https://api-v2.soundcloud.com/media/123',
            'snipped': snipped,
            'preset': 'aac_160k',
            'format': {'protocol': 'hls', 'mime_type': 'audio/mp4'},
          },
        ],
      },
    };

void main() {
  test('excludes snippets, private and blocked tracks', () {
    final rows = [
      scTrack(policy: 'SNIP'),
      scTrack(policy: 'BLOCK'),
      scTrack(snipped: true),
      {...scTrack(), 'sharing': 'private'},
      {...scTrack(), 'streamable': false},
    ];
    expect(SoundCloudService.parseResults({'collection': rows}), isEmpty);
    final results = SoundCloudService.parseResults({
      'collection': [scTrack(), scTrack()],
    });
    expect(results, hasLength(1));
    expect(results.single.trackName, 'Blinding Lights (remake)');
    expect(results.single.getMainArtistName, 'Uploader');
    expect(results.single.filePath, 'retropod://soundcloud/123');
  });

  test(
    'discovers public ID, refreshes it on rejection and resolves fresh HLS',
    () async {
      var homes = 0;
      var searches = 0;
      var resolutions = 0;
      final client = MockClient((request) async {
        expect(request.headers.containsKey('cookie'), isFalse);
        expect(request.headers.containsKey('authorization'), isFalse);
        if (request.url.host == 'soundcloud.com') {
          homes++;
          return http.Response(
            '<script src="https://a-v2.sndcdn.com/assets/app.js"></script>',
            200,
          );
        }
        if (request.url.host == 'a-v2.sndcdn.com') {
          return http.Response(
            'client_id:"${List.filled(32, homes == 1 ? 'a' : 'b').join()}"',
            200,
          );
        }
        if (request.url.path == '/search/tracks') {
          searches++;
          if (searches == 1) return http.Response('{}', 401);
          expect(request.url.queryParameters['q'], '日本 music');
          expect(
            request.url.queryParameters['client_id'],
            List.filled(32, 'b').join(),
          );
          return http.Response(
            jsonEncode({
              'collection': [scTrack()],
            }),
            200,
          );
        }
        if (request.url.path == '/tracks/123') {
          return http.Response(jsonEncode(scTrack()), 200);
        }
        expect(request.url.path, '/media/123');
        expect(
          request.url.queryParameters['track_authorization'],
          'ephemeral-track-token',
        );
        resolutions++;
        return http.Response(
          jsonEncode({
            'url':
                'https://playback.media-streaming.soundcloud.cloud/no-extension?sig=$resolutions',
          }),
          200,
        );
      });
      addTearDown(client.close);
      final service = SoundCloudService(client);
      final song = (await service.search(' 日本 music ')).single;
      final first = await service.resolve(song);
      final second = await service.resolve(song);
      expect(homes, 2);
      expect(first.filePath, isNot(second.filePath));
      expect(first.toAudioSource(), isA<HlsAudioSource>());
      expect(first.mimeType, 'application/vnd.apple.mpegurl');
      expect(song.filePath, 'retropod://soundcloud/123');
      expect(song.filePath, isNot(contains('token')));
    },
  );

  test('rejects unsafe resolver endpoints before sending public IDs', () {
    final row = scTrack();
    row['media'] = {
      'transcodings': [
        {
          'url': 'https://evil.example/media',
          'snipped': false,
          'format': {'protocol': 'hls', 'mime_type': 'audio/mp4'},
        },
      ],
    };
    expect(
      SoundCloudService.parseResults({
        'collection': [row],
      }),
      isEmpty,
    );
  });

  test(
    'fails safely when the public web client cannot be discovered',
    () async {
      final client = MockClient(
        (_) async => http.Response('<html>No assets</html>', 200),
      );
      addTearDown(client.close);
      await expectLater(
        SoundCloudService(client).search('song'),
        throwsA(isA<SoundCloudException>()),
      );
    },
  );
}
