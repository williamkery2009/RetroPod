import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:retropod/core/models/music_metadata.dart';

class SoundCloudException implements Exception {
  const SoundCloudException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Public SoundCloud web API adapter. No login cookies or account tokens.
class SoundCloudService {
  SoundCloudService(this._http);
  final http.Client _http;
  String? _clientId;
  Future<String>? _discovery;
  static final _idPattern = RegExp(r'^[0-9]+$');
  static final _publicId = RegExp(
    r'''client_id\s*[:=]\s*["']([A-Za-z0-9]{32})''',
  );

  Future<http.Response> _get(Uri uri) =>
      _http.get(uri).timeout(const Duration(seconds: 10));

  Future<String> _discover() async {
    final home = await _get(Uri.https('soundcloud.com', '/'));
    if (home.statusCode != 200)
      throw const SoundCloudException(
        'SoundCloud is unavailable (SC_DISCOVERY). Try again later.',
      );
    final direct = _publicId.firstMatch(home.body);
    if (direct != null) return direct.group(1)!;
    final scripts = RegExp(
      r'''src=["'](https://a-v2\.sndcdn\.com/assets/[^"']+\.js)["']''',
    ).allMatches(home.body).map((m) => m.group(1)!).toSet().toList();
    // Only inspect a bounded set of SoundCloud's own public asset bundles.
    final ids = await Future.wait(
      scripts.reversed.take(6).map((url) async {
        try {
          final response = await _get(Uri.parse(url));
          return response.statusCode == 200
              ? _publicId.firstMatch(response.body)?.group(1)
              : null;
        } catch (_) {
          return null;
        }
      }),
    );
    for (final id in ids) {
      if (id != null) return id;
    }
    throw const SoundCloudException(
      'SoundCloud web configuration changed (SC_DISCOVERY). '
      'This provider may need an update.',
    );
  }

  Future<String> _getClientId() async {
    if (_clientId != null) return _clientId!;
    final pending = _discovery ??= _discover();
    try {
      return _clientId = await pending;
    } finally {
      if (identical(_discovery, pending)) _discovery = null;
    }
  }

  Future<Map> _api(String path, [Map<String, String> query = const {}]) async {
    for (var attempt = 0; attempt < 2; attempt++) {
      final id = await _getClientId();
      final response = await _get(
        Uri.https('api-v2.soundcloud.com', path, {...query, 'client_id': id}),
      );
      if ((response.statusCode == 401 || response.statusCode == 403) &&
          attempt == 0) {
        _clientId = null;
        continue;
      }
      if (response.statusCode != 200)
        throw const SoundCloudException(
          'SoundCloud rejected this request (SC_API). Try again later.',
        );
      final data = jsonDecode(utf8.decode(response.bodyBytes));
      if (data is! Map)
        throw const FormatException('Invalid SoundCloud response');
      return data;
    }
    throw const SoundCloudException('SoundCloud is unavailable (SC_API).');
  }

  static List<Map> _candidates(Map track) {
    if (track['streamable'] != true ||
        track['policy'] != 'ALLOW' ||
        track['sharing'] == 'private')
      return [];
    final media = track['media'];
    final rows = media is Map ? media['transcodings'] : null;
    if (rows is! List) return [];
    return rows.whereType<Map>().where((row) {
      final format = row['format'];
      final preset = row['preset']?.toString() ?? '';
      final url = row['url'] is String ? Uri.tryParse(row['url']) : null;
      return row['snipped'] != true &&
          !preset.toLowerCase().contains('preview') &&
          format is Map &&
          ['hls', 'progressive'].contains(format['protocol']) &&
          format['mime_type'] is String &&
          (format['mime_type'] as String).startsWith('audio/') &&
          url?.scheme == 'https' &&
          url?.host == 'api-v2.soundcloud.com' &&
          url!.userInfo.isEmpty;
    }).toList()..sort((a, b) {
      int rank(Map row) =>
          (row['format']['protocol'] == 'progressive' ? 1000 : 0) +
          (int.tryParse(
                RegExp(
                      r'_(\d+)k',
                    ).firstMatch(row['preset']?.toString() ?? '')?.group(1) ??
                    '',
              ) ??
              0);
      return rank(b).compareTo(rank(a));
    });
  }

  Future<List<MusicMetadata>> search(String query) async {
    if (query.trim().isEmpty) return [];
    return parseResults(
      await _api('/search/tracks', {
        'q': query.trim(),
        'limit': '40',
        'access': 'playable',
      }),
    );
  }

  static List<MusicMetadata> parseResults(Object? data) {
    if (data is! Map || data['collection'] is! List) {
      throw const FormatException('Invalid SoundCloud search response');
    }
    final seen = <String>{};
    final songs = <MusicMetadata>[];
    for (final row in (data['collection'] as List).whereType<Map>()) {
      final id = row['id']?.toString() ?? '';
      final title = row['title'];
      if (!_idPattern.hasMatch(id) ||
          title is! String ||
          title.trim().isEmpty ||
          _candidates(row).isEmpty ||
          !seen.add(id))
        continue;
      final user = row['user'];
      final name = user is Map ? user['username'] : null;
      final art = row['artwork_url'];
      final artUri = art is String ? Uri.tryParse(art) : null;
      final duration = row['duration'];
      songs.add(
        MusicMetadata(
          trackName: title.trim(),
          trackArtistNames: [
            name is String && name.isNotEmpty ? name : 'Unknown uploader',
          ],
          albumName: 'SoundCloud',
          filePath: 'retropod://soundcloud/$id',
          thumbnailPath: artUri?.scheme == 'https' && artUri!.host.isNotEmpty
              ? art
              : null,
          trackDuration: duration is num && duration.isFinite && duration > 0
              ? duration.round()
              : null,
          originalSongIndex: -1 - songs.length,
          isOnDevice: false,
        ),
      );
    }
    return songs;
  }

  static String? idFor(MusicMetadata song) {
    if (song.isOnDevice) return null;
    final uri = Uri.tryParse(song.filePath ?? '');
    if (uri?.scheme != 'retropod' ||
        uri?.host != 'soundcloud' ||
        uri!.pathSegments.length != 1)
      return null;
    final id = uri.pathSegments.single;
    return _idPattern.hasMatch(id) ? id : null;
  }

  Future<MusicMetadata> resolve(MusicMetadata song) async {
    final id = idFor(song);
    if (id == null) return song;
    // Refetch the track: media URLs and track authorization are short-lived.
    final track = await _api('/tracks/$id');
    for (final candidate in _candidates(track).take(3)) {
      try {
        final endpoint = Uri.parse(candidate['url'] as String);
        final response = await _api(endpoint.path, {
          ...endpoint.queryParameters,
          if (track['track_authorization'] is String)
            'track_authorization': track['track_authorization'] as String,
        });
        final raw = response['url'];
        final url = raw is String ? Uri.tryParse(raw) : null;
        if (url == null ||
            url.scheme != 'https' ||
            url.userInfo.isNotEmpty ||
            !(url.host.endsWith('.sndcdn.com') ||
                url.host.endsWith('.soundcloud.cloud')))
          continue;
        return song.copyWith(
          filePath: url.toString(),
          mimeType: candidate['format']['protocol'] == 'hls'
              ? 'application/vnd.apple.mpegurl'
              : 'audio/mpeg',
        );
      } catch (_) {
        // Try another supported format, with a strict maximum of three.
      }
    }
    throw const SoundCloudException(
      'No full SoundCloud stream is available (SC_NO_AUDIO). '
      'Preview-only and restricted tracks are not played.',
    );
  }
}
