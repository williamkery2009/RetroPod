import 'dart:convert';

import 'package:audio_service/audio_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:just_audio/just_audio.dart';
import 'package:retropod/core/models/music_metadata.dart';
import 'package:retropod/core/services/online_music_service.dart';

void main() {
  test(
    'iTunes uses the preview URL and does not claim full track duration',
    () {
      final songs = OnlineMusicService.parseResults(MusicSource.itunes, {
        'results': [
          {
            'trackName': 'Song',
            'artistName': 'Artist',
            'previewUrl': 'https://audio.example/preview.m4a',
            'artworkUrl100': 'https://art.example/cover.jpg',
            'trackTimeMillis': 240000,
          },
          {'trackName': 'Unavailable'},
          {'previewUrl': 'file:///private/file.mp3'},
          {'previewUrl': 'https://audio.example/preview.m4a'},
        ],
      });
      expect(songs, hasLength(1));
      expect(songs.single.isOnDevice, isFalse);
      expect(songs.single.originalSongIndex, lessThan(0));
      expect(songs.single.trackDuration, isNull);
      final source = songs.single.toAudioSource() as UriAudioSource;
      expect((source.tag as MediaItem).artUri!.scheme, 'https');
      expect(source.uri.path, '/preview.m4a');
    },
  );

  test('Deezer accepts playable previews and handles missing metadata', () {
    final songs = OnlineMusicService.parseResults(MusicSource.deezer, {
      'data': [
        {
          'title': 'Song',
          'preview': 'https://audio.example/one.mp3',
          'artist': {'name': 'Singer'},
          'album': {'cover_medium': 'https://art.example/one.jpg'},
        },
        {'preview': 'https://audio.example/two.mp3'},
        {'preview': ''},
        null,
      ],
    });
    expect(songs, hasLength(2));
    expect(songs.first.getMainArtistName, 'Singer');
    expect(songs.last.getMainArtistName, 'Unknown Artist');
    expect(songs.map((song) => song.originalSongIndex).toSet(), hasLength(2));
  });

  test('radio filters insecure and empty streams', () {
    final songs = OnlineMusicService.parseResults(MusicSource.radio, [
      {
        'name': 'Jazz',
        'country': 'India',
        'url_resolved': 'https://radio.example/live',
        'favicon': 'not a URL',
      },
      {'url_resolved': 'http://radio.example/live'},
      {'url_resolved': ''},
    ]);
    expect(songs, hasLength(1));
    expect(songs.single.trackDuration, isNull);
    expect(songs.single.thumbnailPath, isNull);
  });

  test('malformed responses and provider errors are not empty successes', () {
    expect(
      () => OnlineMusicService.parseResults(MusicSource.deezer, {
        'error': {'message': 'quota'},
      }),
      throwsStateError,
    );
    expect(
      () => OnlineMusicService.parseResults(MusicSource.itunes, {
        'results': 'bad',
      }),
      throwsFormatException,
    );
  });

  test('search encodes query parameters without altering the term', () async {
    final client = MockClient((request) async {
      expect(request.url.host, 'itunes.apple.com');
      expect(request.url.queryParameters['term'], 'A & B/日本');
      return http.Response('{"results":[]}', 200);
    });
    addTearDown(client.close);
    final service = OnlineMusicService(client);
    expect(await service.search(MusicSource.itunes, ' A & B/日本 '), isEmpty);
  });

  test('empty searches do not make a network request', () async {
    final client = MockClient((_) async => throw StateError('unexpected call'));
    addTearDown(client.close);
    expect(
      await OnlineMusicService(client).search(MusicSource.radio, ' '),
      isEmpty,
    );
  });

  test('radio retries on a second directory server', () async {
    final hosts = <String>[];
    final client = MockClient((request) async {
      hosts.add(request.url.host);
      return hosts.length == 1
          ? http.Response('unavailable', 503)
          : http.Response('[]', 200);
    });
    addTearDown(client.close);
    expect(
      await OnlineMusicService(client).search(MusicSource.radio, 'jazz'),
      isEmpty,
    );
    expect(hosts, ['de1.api.radio-browser.info', 'nl1.api.radio-browser.info']);
  });

  final song = MusicMetadata(
    trackName: 'Song',
    trackArtistNames: ['Artist'],
    albumName: 'Album',
    trackDuration: 123000,
  );

  test('LRCLIB prefers synced lyrics and sends recording metadata', () async {
    final client = MockClient((request) async {
      expect(request.url.host, 'lrclib.net');
      expect(request.url.path, '/api/get');
      expect(request.url.queryParameters, {
        'track_name': 'Song',
        'artist_name': 'Artist',
        'album_name': 'Album',
        'duration': '123',
      });
      return http.Response(
        jsonEncode({'syncedLyrics': '[00:01.00]Hello', 'plainLyrics': 'Hello'}),
        200,
      );
    });
    addTearDown(client.close);
    expect(
      await OnlineMusicService(client).findLyrics(song),
      '[00:01.00]Hello',
    );
  });

  test('LRCLIB missing lyrics and plain-text fallback', () async {
    final notFound = MockClient((_) async => http.Response('{}', 404));
    final plain = MockClient(
      (_) async =>
          http.Response('{"syncedLyrics":"", "plainLyrics":"Hello"}', 200),
    );
    addTearDown(notFound.close);
    addTearDown(plain.close);
    expect(await OnlineMusicService(notFound).findLyrics(song), isNull);
    expect(await OnlineMusicService(plain).findLyrics(song), 'Hello');
  });

  test('LRCLIB rejects previews and unknown recording duration', () async {
    final client = MockClient((_) async => throw StateError('unexpected call'));
    addTearDown(client.close);
    final service = OnlineMusicService(client);
    expect(await service.findLyrics(song.copyWith(isOnDevice: false)), isNull);
    expect(
      await service.findLyrics(MusicMetadata(trackName: 'Unknown')),
      isNull,
    );
  });
}
