import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:retropod/core/models/music_metadata.dart';
import 'package:retropod/core/services/youtube_music_service.dart';

enum MusicSource {
  itunes('iTunes previews'),
  deezer('Deezer previews'),
  radio('Internet radio'),
  youtubeMusic('YouTube Music (experimental)');

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
  OnlineMusicService(this._client);
  final http.Client _client;
  late final YoutubeMusicService _youtube = YoutubeMusicService(_client);

  Future<MusicMetadata> resolveForPlayback(MusicMetadata song) =>
      _youtube.resolveForPlayback(song);

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
    if (source == MusicSource.youtubeMusic) return _youtube.search(term);
    final Uri uri = switch (source) {
      MusicSource.youtubeMusic => throw StateError('Handled above'),
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
    if (source == MusicSource.youtubeMusic) {
      return YoutubeMusicService.parseResults(data);
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
        MusicSource.youtubeMusic => null,
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
              MusicSource.youtubeMusic => 'Unknown Artist',
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
            MusicSource.youtubeMusic => null,
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
