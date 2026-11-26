import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:retropod/core/models/music_metadata.dart';
import 'package:retropod/core/services/audius_service.dart';
import 'package:retropod/core/services/soundcloud_service.dart';
import 'package:retropod/core/services/jiosaavn_service.dart';
import 'package:retropod/core/services/youtube_music_service.dart';
import 'package:retropod/core/services/piped_service.dart';

enum MusicSource {
  itunes('iTunes previews'),
  deezer('Deezer previews'),
  radio('Internet radio'),
  audius('Audius'),
  soundcloud('SoundCloud'),
  jiosaavn('JioSaavn (experimental)'),
  youtubeMusic('YouTube Music (experimental)'),
  youtubePiped('YouTube Music via Piped');

  const MusicSource(this.label);
  final String label;
}

final onlineMusicServiceProvider = Provider<OnlineMusicService>((ref) {
  final client = http.Client();
  ref.onDispose(client.close);
  return OnlineMusicService(client);
});

/// Uses public provider endpoints, not Mornye's implementation code.
class OnlineMusicService {
  OnlineMusicService(this._client, {YoutubeAudioResolver? resolveYoutubeAudio})
    : _youtube = YoutubeMusicService(
        _client,
        resolveAudio: resolveYoutubeAudio,
      );
  final http.Client _client;
  final YoutubeMusicService _youtube;

  late final SoundCloudService _soundcloud = SoundCloudService(_client);
  late final JioSaavnService _jiosaavn = JioSaavnService(_client);

  late final PipedService _piped = PipedService(_client);

  Future<MusicMetadata> resolveForPlayback(MusicMetadata song) async {
    if (SoundCloudService.idFor(song) != null) return _soundcloud.resolve(song);
    if (JioSaavnService.idFor(song) != null) return _jiosaavn.resolve(song);
    final id = YoutubeMusicService.videoIdFor(song);
    if (id == null) return song;
    final pipedOnly =
        Uri.parse(song.filePath!).queryParameters['provider'] == 'piped';
    if (!pipedOnly) {
      try {
        return await _youtube.resolveForPlayback(song);
      } catch (_) {
        // Search and stream extraction are independent. Try the proxy API once.
      }
    }
    final url = await _piped.resolveAudio(id);
    return song.copyWith(filePath: url.toString());
  }

  static List<MusicMetadata> _markPiped(List<MusicMetadata> songs) =>
      songs.map((song) {
        final uri = Uri.parse(song.filePath!);
        return song.copyWith(
          filePath: uri
              .replace(
                queryParameters: {...uri.queryParameters, 'provider': 'piped'},
              )
              .toString(),
        );
      }).toList();

  Future<Object?> _get(Uri uri, {bool allowNotFound = false}) async {
    final response = await _client
        .get(uri)
        .timeout(const Duration(seconds: 15));
    if (allowNotFound && response.statusCode == 404) return null;
    if (response.statusCode != 200) {
      throw StateError(
        'Service unavailable (${response.statusCode}). Try again.',
      );
    }
    return jsonDecode(utf8.decode(response.bodyBytes));
  }

  Future<List<MusicMetadata>> search(MusicSource source, String query) async {
    final term = query.trim();
    if (term.isEmpty) return [];
    if (source == MusicSource.soundcloud) return _soundcloud.search(term);
    if (source == MusicSource.jiosaavn) return _jiosaavn.search(term);
    if (source == MusicSource.youtubeMusic ||
        source == MusicSource.youtubePiped) {
      final songs = await _youtube.search(term);
      return source == MusicSource.youtubePiped ? _markPiped(songs) : songs;
    }
    final Uri uri = switch (source) {
      MusicSource.youtubeMusic ||
      MusicSource.youtubePiped ||
      MusicSource.soundcloud ||
      MusicSource.jiosaavn => throw StateError('Handled above'),
      MusicSource.audius => Uri.https('api.audius.co', '/v1/tracks/search', {
        'query': term,
        'limit': '40',
      }),
      MusicSource.itunes => Uri.https('itunes.apple.com', '/search', {
        'term': term,
        'entity': 'song',
        'limit': '40',
      }),
      MusicSource.deezer => Uri.https('api.deezer.com', '/2.0/search/track', {
        'q': term,
        'limit': '40',
      }),
      MusicSource.radio =>
        Uri.https('de1.api.radio-browser.info', '/json/stations/search', {
          'name': term,
          'limit': '40',
          'hidebroken': 'true',
          'is_https': 'true',
          'order': 'votes',
          'reverse': 'true',
        }),
    };
    Object? response;
    try {
      response = await _get(uri);
    } catch (_) {
      if (source != MusicSource.radio) rethrow;
      response = await _get(uri.replace(host: 'nl1.api.radio-browser.info'));
    }
    return parseResults(source, response);
  }

  static String? _text(Object? value) =>
      value is String && value.trim().isNotEmpty ? value.trim() : null;

  static String? _https(Object? value) {
    final uri = Uri.tryParse(_text(value) ?? '');
    return uri != null && uri.scheme == 'https' && uri.host.isNotEmpty
        ? uri.toString()
        : null;
  }

  static List<MusicMetadata> parseResults(MusicSource source, Object? data) {
    if (source == MusicSource.audius) return AudiusService.parseResults(data);
    if (source == MusicSource.soundcloud)
      return SoundCloudService.parseResults(data);
    if (source == MusicSource.jiosaavn)
      return JioSaavnService.parseResults(data);
    if (source == MusicSource.youtubeMusic ||
        source == MusicSource.youtubePiped) {
      final songs = YoutubeMusicService.parseResults(data);
      return source == MusicSource.youtubePiped ? _markPiped(songs) : songs;
    }
    if (data is Map && data['error'] != null) {
      throw StateError('Provider rejected the search. Try again later.');
    }
    final Object? rows = source == MusicSource.radio
        ? data
        : data is Map
        ? data[source == MusicSource.itunes ? 'results' : 'data']
        : null;
    if (rows is! List) throw const FormatException('Invalid search response');
    final results = <MusicMetadata>[];
    final seen = <String>{};
    for (final row in rows.whereType<Map>()) {
      final url = _https(switch (source) {
        MusicSource.youtubeMusic ||
        MusicSource.youtubePiped ||
        MusicSource.audius ||
        MusicSource.soundcloud ||
        MusicSource.jiosaavn => null,
        MusicSource.itunes => row['previewUrl'],
        MusicSource.deezer => row['preview'],
        MusicSource.radio => row['url_resolved'],
      });
      if (url == null || !seen.add(url)) continue;
      final artist = row['artist'];
      final album = row['album'];
      results.add(
        MusicMetadata(
          trackName:
              _text(
                row[source == MusicSource.itunes
                    ? 'trackName'
                    : source == MusicSource.deezer
                    ? 'title'
                    : 'name'],
              ) ??
              'Untitled',
          trackArtistNames: [
            switch (source) {
              MusicSource.youtubeMusic ||
              MusicSource.youtubePiped ||
              MusicSource.audius ||
              MusicSource.soundcloud ||
              MusicSource.jiosaavn => 'Unknown Artist',
              MusicSource.itunes =>
                _text(row['artistName']) ?? 'Unknown Artist',
              MusicSource.deezer =>
                artist is Map
                    ? _text(artist['name']) ?? 'Unknown Artist'
                    : 'Unknown Artist',
              MusicSource.radio => _text(row['country']) ?? 'Internet radio',
            },
          ],
          albumName: source.label,
          filePath: url,
          thumbnailPath: _https(switch (source) {
            MusicSource.youtubeMusic ||
            MusicSource.youtubePiped ||
            MusicSource.audius ||
            MusicSource.soundcloud ||
            MusicSource.jiosaavn => null,
            MusicSource.itunes => row['artworkUrl100'],
            MusicSource.deezer => album is Map ? album['cover_medium'] : null,
            MusicSource.radio => row['favicon'],
          }),
          // The player's stream supplies the preview duration, never the
          // full recording's duration returned by the catalog API.
          isOnDevice: false,
          originalSongIndex: -1 - results.length,
        ),
      );
    }
    return results;
  }

  /// LRCLIB is also used by Mornye. Exact metadata lookup avoids choosing
  /// the first fuzzy search hit, which may be a different recording.
  Future<String?> findLyrics(MusicMetadata song) async {
    if (!song.isOnDevice ||
        song.trackName == null ||
        song.getTrackDuration <= 0) {
      return null;
    }
    final data = await _get(
      Uri.https('lrclib.net', '/api/get', {
        'track_name': song.getTrackName,
        'artist_name': song.getTrackArtistNames ?? '',
        if (song.albumName != null) 'album_name': song.albumName!,
        'duration': (song.getTrackDuration / 1000).round().toString(),
      }),
      allowNotFound: true,
    );
    if (data == null) return null;
    if (data is! Map) throw const FormatException('Invalid lyrics response');
    return _text(data['syncedLyrics']) ?? _text(data['plainLyrics']);
  }
}
