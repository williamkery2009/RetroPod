import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:retropod/core/services/audius_service.dart';
import 'package:retropod/core/services/online_music_service.dart';

Map<String, Object?> track(String id) => {
  'id': id,
  'title': 'Blinding Lights - Zaza Remix',
  'user': {'name': 'zaza'},
  'duration': 227,
  'is_streamable': true,
  'is_stream_gated': false,
  'stream_conditions': null,
  'artwork': {'480x480': 'https://image.example/cover.jpg'},
};

void main() {
  test('retains remix title and uploader with a stable stream endpoint', () {
    final songs = AudiusService.parseResults({
      'data': [track('5KZ2E72'), track('5KZ2E72')],
    });
    expect(songs, hasLength(1));
    final song = songs.single;
    expect(song.trackName, 'Blinding Lights - Zaza Remix');
    expect(song.getMainArtistName, 'zaza');
    expect(song.filePath, 'https://api.audius.co/v1/tracks/5KZ2E72/stream');
    expect(song.trackDuration, 227000);
    expect(song.thumbnailPath, 'https://image.example/cover.jpg');
    expect(song.isOnDevice, isFalse);
  });

  test('excludes gated, unavailable, unlisted, deleted and invalid tracks', () {
    final invalid = [
      {...track('a'), 'is_streamable': false},
      {...track('b'), 'is_stream_gated': true},
      {
        ...track('c'),
        'stream_conditions': {'purchase': {}},
      },
      {...track('d'), 'is_available': false},
      {...track('e'), 'is_unlisted': true},
      {...track('f'), 'is_delete': true},
      {...track('g'), 'title': ''},
      track('../other'),
    ];
    expect(AudiusService.parseResults({'data': invalid}), isEmpty);
    expect(
      () => AudiusService.parseResults({'error': 'blocked'}),
      throwsFormatException,
    );
  });

  test('search encodes Unicode and streams bypass YouTube resolvers', () async {
    final client = MockClient((request) async {
      expect(request.url.host, 'api.audius.co');
      expect(request.url.path, '/v1/tracks/search');
      expect(request.url.queryParameters['query'], '日本 music');
      return http.Response(
        jsonEncode({
          'data': [track('5KZ2E72')],
        }),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    });
    addTearDown(client.close);
    final service = OnlineMusicService(
      client,
      resolveYoutubeAudio: (_) async {
        fail('Audius must not invoke YouTube extraction');
      },
    );
    final songs = await service.search(MusicSource.audius, ' 日本 music ');
    expect(await service.resolveForPlayback(songs.single), same(songs.single));
  });
}
