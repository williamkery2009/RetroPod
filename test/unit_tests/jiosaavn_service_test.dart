import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:retropod/core/services/jiosaavn_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

Map<String, Object?> jioTrack() => {
  'id': 'track_12',
  'name': 'Example song',
  'duration': 123,
  'artists': {
    'primary': [
      {'name': 'Artist'},
    ],
  },
  'album': {'name': 'Album'},
  'image': [
    {'quality': '500x500', 'url': 'https://c.saavncdn.com/cover.jpg'},
  ],
  'downloadUrl': [
    {'quality': '96kbps', 'url': 'https://aac.saavncdn.com/song_96.mp4'},
    {'quality': '320kbps', 'url': 'https://aac.saavncdn.com/song_320.mp4'},
    {'quality': '999kbps', 'url': 'http://aac.saavncdn.com/insecure.mp4'},
  ],
};

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'search and fresh detail resolution preserve identity and select quality',
    () async {
      final requests = <String>[];
      final client = MockClient((request) async {
        requests.add(request.url.path);
        expect(request.headers.containsKey('authorization'), isFalse);
        if (request.url.path.endsWith('/search/songs')) {
          expect(request.url.queryParameters['query'], '日本 music');
          return http.Response(
            jsonEncode({
              'success': true,
              'data': {
                'results': [jioTrack()],
              },
            }),
            200,
          );
        }
        expect(request.url.path, '/api/songs/track_12');
        return http.Response(
          jsonEncode({
            'success': true,
            'data': [jioTrack()],
          }),
          200,
        );
      });
      addTearDown(client.close);
      final service = JioSaavnService(
        client,
        instance: () async => Uri.parse('https://jio.example/api'),
      );
      final song = (await service.search(' 日本 music ')).single;
      final resolved = await service.resolve(song);
      expect(song.filePath, 'retropod://jiosaavn/track_12');
      expect(resolved.filePath, 'https://aac.saavncdn.com/song_320.mp4');
      expect(song.trackDuration, 123000);
      expect(song.getMainArtistName, 'Artist');
      expect(requests, ['/api/search/songs', '/api/songs/track_12']);
    },
  );

  test('ignores unavailable rows, duplicate IDs and untrusted audio URLs', () {
    final bad = {
      ...jioTrack(),
      'id': 'bad',
      'downloadUrl': [
        {'quality': '320kbps', 'url': 'https://evil.example/audio.mp4'},
      ],
    };
    final rows = JioSaavnService.parseResults({
      'data': {
        'results': [bad, jioTrack(), jioTrack()],
      },
    });
    expect(rows, hasLength(1));
    expect(rows.single.thumbnailPath, 'https://c.saavncdn.com/cover.jpg');
  });

  test(
    'saves compatible base URL and refuses credentials or plaintext',
    () async {
      await JioSaavnService.saveInstance('https://jio.example/api/');
      expect(
        (await JioSaavnService.configuredInstance()).toString(),
        'https://jio.example/api',
      );
      await expectLater(
        JioSaavnService.saveInstance('http://jio.example'),
        throwsFormatException,
      );
      await expectLater(
        JioSaavnService.saveInstance('https://a:b@jio.example'),
        throwsFormatException,
      );
    },
  );

  test(
    'server failures give actionable errors without exposing response bodies',
    () async {
      final client = MockClient(
        (_) async => http.Response('private diagnostic', 503),
      );
      addTearDown(client.close);
      await expectLater(
        JioSaavnService(client).search('song'),
        throwsA(
          predicate<Object>(
            (e) =>
                e is JioSaavnException &&
                e.message.contains('JIO_SERVER') &&
                !e.message.contains('private diagnostic'),
          ),
        ),
      );
    },
  );
}
