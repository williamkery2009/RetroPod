import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:retropod/core/models/music_metadata.dart';
import 'package:retropod/core/services/youtube_music_service.dart';

Map<String, Object?> songRow(String id, {String title = 'Blinding Lights'}) => {
  'musicResponsiveListItemRenderer': {
    'playlistItemData': {'videoId': id},
    'flexColumns': [
      {
        'musicResponsiveListItemFlexColumnRenderer': {
          'text': {
            'runs': [
              {
                'text': title,
                'navigationEndpoint': {
                  'watchEndpoint': {'videoId': id},
                },
              },
            ],
          },
        },
      },
      {
        'musicResponsiveListItemFlexColumnRenderer': {
          'text': {
            'runs': [
              {
                'text': 'The Weeknd',
                'navigationEndpoint': {
                  'browseEndpoint': {'browseId': 'UCartist'},
                },
              },
              {'text': ' · '},
              {
                'text': 'After Hours',
                'navigationEndpoint': {
                  'browseEndpoint': {'browseId': 'MPREalbum'},
                },
              },
            ],
          },
        },
      },
    ],
    'thumbnail': {
      'musicThumbnailRenderer': {
        'thumbnail': {
          'thumbnails': [
            {'url': 'https://example.com/small.jpg'},
            {'url': 'https://example.com/large.jpg'},
          ],
        },
      },
    },
  },
};

Object searchResponse(List<Object?> rows) => {
  'contents': {
    'tabbedSearchResultsRenderer': {
      'tabs': [
        {
          'tabRenderer': {
            'content': {
              'sectionListRenderer': {
                'contents': [
                  {
                    'musicShelfRenderer': {'contents': rows},
                  },
                ],
              },
            },
          },
        },
      ],
    },
  },
};

void main() {
  test('music search maps songs, keeps watch IDs, and skips invalid rows', () {
    final songs = YoutubeMusicService.parseResults(
      searchResponse([
        songRow('abcdefghijk'),
        songRow('abcdefghijk'),
        songRow('bad'),
        {
          'musicResponsiveListItemRenderer': {'flexColumns': []},
        },
      ]),
    );
    expect(songs, hasLength(1));
    expect(songs.single.trackName, 'Blinding Lights');
    expect(songs.single.trackArtistNames, ['The Weeknd']);
    expect(songs.single.albumName, 'After Hours');
    expect(songs.single.thumbnailPath, 'https://example.com/large.jpg');
    expect(songs.single.isOnDevice, isFalse);
    expect(YoutubeMusicService.videoIdFor(songs.single), 'abcdefghijk');
  });

  test('music search handles genuine empty results and rejects API errors', () {
    expect(YoutubeMusicService.parseResults(searchResponse([])), isEmpty);
    expect(
      () => YoutubeMusicService.parseResults({'error': {}}),
      throwsFormatException,
    );
    expect(() => YoutubeMusicService.parseResults({}), throwsFormatException);
  });

  test('search sends songs-only Innertube request and Unicode query', () async {
    final client = MockClient((request) async {
      expect(request.method, 'POST');
      expect(request.url.host, 'music.youtube.com');
      expect(request.url.path, '/youtubei/v1/search');
      final body = jsonDecode(request.body) as Map;
      expect(body['query'], '日本 & music');
      expect(body['params'], 'EgWKAQIIAWoMEA4QChADEAQQCRAF');
      expect(body['context']['client']['clientName'], 'WEB_REMIX');
      return http.Response(
        jsonEncode(searchResponse([songRow('abcdefghijk')])),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    });
    addTearDown(client.close);
    expect(
      await YoutubeMusicService(client).search(' 日本 & music '),
      hasLength(1),
    );
  });

  test(
    'stream resolution is fresh per play and never changes stored metadata',
    () async {
      final client = MockClient(
        (_) async => throw StateError('unexpected search'),
      );
      addTearDown(client.close);
      int calls = 0;
      final service = YoutubeMusicService(
        client,
        resolveAudio: (id) async {
          expect(id, 'abcdefghijk');
          return Uri.parse('https://audio.example/play?generation=${++calls}');
        },
      );
      final song = YoutubeMusicService.parseResults(
        searchResponse([songRow('abcdefghijk')]),
      ).single;
      final first = await service.resolveForPlayback(song);
      final second = await service.resolveForPlayback(song);
      expect(first.filePath, isNot(second.filePath));
      expect(song.filePath, 'https://music.youtube.com/watch?v=abcdefghijk');
      expect(first.trackName, song.trackName);
      expect(calls, 2);
    },
  );

  test('ordinary streams and local files do not go through YouTube', () async {
    final client = MockClient(
      (_) async => throw StateError('unexpected search'),
    );
    addTearDown(client.close);
    final service = YoutubeMusicService(
      client,
      resolveAudio: (_) async => throw StateError('unexpected resolution'),
    );
    for (final song in [
      MusicMetadata(filePath: '/music/song.flac'),
      MusicMetadata(filePath: 'https://radio.example/live', isOnDevice: false),
      MusicMetadata(
        filePath: 'https://music.youtube.com.evil.test/watch?v=abcdefghijk',
        isOnDevice: false,
      ),
    ]) {
      expect(await service.resolveForPlayback(song), same(song));
    }
  });

  test(
    'failed or insecure stream extraction does not produce a playable result',
    () async {
      final client = MockClient((_) async => http.Response('{}', 403));
      addTearDown(client.close);
      final song = YoutubeMusicService.parseResults(
        searchResponse([songRow('abcdefghijk')]),
      ).single;
      final service = YoutubeMusicService(
        client,
        resolveAudio: (_) async => Uri.parse('file:///music'),
      );
      await expectLater(service.resolveForPlayback(song), throwsStateError);
      await expectLater(service.search('music'), throwsStateError);
    },
  );
}
