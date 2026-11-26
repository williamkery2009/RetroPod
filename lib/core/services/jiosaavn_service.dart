import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:retropod/core/models/music_metadata.dart';
import 'package:retropod/core/services/piped_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class JioSaavnException implements Exception {
  const JioSaavnException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Adapter for the MIT-licensed sumitkolhe/jiosaavn-api response format.
/// API servers can be changed without sending account credentials.
class JioSaavnService {
  JioSaavnService(this._http, {Future<Uri> Function()? instance})
    : _instance = instance ?? configuredInstance;
  final http.Client _http;
  final Future<Uri> Function() _instance;
  static const defaultInstance = 'https://saavn.dev/api';
  static const _key = 'jiosaavnApiBaseUrl';
  static final _id = RegExp(r'^[A-Za-z0-9_-]+$');

  static Future<Uri> configuredInstance() async {
    final prefs = await SharedPreferences.getInstance();
    return PipedService.validateInstance(
      prefs.getString(_key) ?? defaultInstance,
    );
  }

  static Future<void> saveInstance(String value) async {
    final uri = PipedService.validateInstance(value);
    final prefs = await SharedPreferences.getInstance();
    if (!await prefs.setString(_key, uri.toString()))
      throw StateError('Could not save server');
  }

  Future<Map> _get(String path, [Map<String, String>? query]) async {
    try {
      final base = PipedService.validateInstance(
        (await _instance()).toString(),
      );
      final response = await _http
          .get(base.replace(path: '${base.path}$path', queryParameters: query))
          .timeout(const Duration(seconds: 12));
      if (response.statusCode != 200)
        throw const FormatException('Server unavailable');
      final data = jsonDecode(utf8.decode(response.bodyBytes));
      if (data is! Map || data['success'] == false || data['error'] != null) {
        throw const FormatException('Invalid server response');
      }
      return data;
    } catch (_) {
      throw const JioSaavnException(
        'JioSaavn API unavailable (JIO_SERVER). Use JioSaavn server to set '
        'a working compatible HTTPS API address. Public servers may be blocked.',
      );
    }
  }

  Future<List<MusicMetadata>> search(String query) async {
    if (query.trim().isEmpty) return [];
    return parseResults(
      await _get('/search/songs', {'query': query.trim(), 'limit': '40'}),
    );
  }

  static Uri? _best(Object? rows) {
    if (rows is! List) return null;
    final candidates = <({Uri uri, int quality})>[];
    for (final row in rows.whereType<Map>()) {
      final raw = row['url'];
      final uri = raw is String ? Uri.tryParse(raw) : null;
      if (uri == null ||
          uri.scheme != 'https' ||
          uri.userInfo.isNotEmpty ||
          !uri.host.endsWith('.saavncdn.com'))
        continue;
      final quality =
          int.tryParse(
            RegExp(
                  r'\d+',
                ).firstMatch(row['quality']?.toString() ?? '')?.group(0) ??
                '',
          ) ??
          0;
      candidates.add((uri: uri, quality: quality));
    }
    candidates.sort((a, b) => b.quality.compareTo(a.quality));
    return candidates.isEmpty ? null : candidates.first.uri;
  }

  static List<MusicMetadata> parseResults(Object? response) {
    final data = response is Map ? response['data'] : null;
    final rows = data is Map ? data['results'] : null;
    if (rows is! List)
      throw const JioSaavnException(
        'Invalid JioSaavn response (JIO_RESPONSE).',
      );
    final seen = <String>{};
    final songs = <MusicMetadata>[];
    for (final row in rows.whereType<Map>()) {
      final id = row['id'];
      final title = row['name'];
      if (id is! String ||
          !_id.hasMatch(id) ||
          title is! String ||
          title.trim().isEmpty ||
          _best(row['downloadUrl']) == null ||
          !seen.add(id))
        continue;
      final artists = row['artists'];
      final primary = artists is Map ? artists['primary'] : null;
      final names = primary is List
          ? primary
                .whereType<Map>()
                .map((a) => a['name'])
                .whereType<String>()
                .where((s) => s.trim().isNotEmpty)
                .toList()
          : <String>[];
      final album = row['album'];
      final duration = row['duration'];
      songs.add(
        MusicMetadata(
          trackName: title.trim(),
          trackArtistNames: names.isEmpty ? ['Unknown artist'] : names,
          albumName: album is Map && album['name'] is String
              ? album['name']
              : 'JioSaavn',
          filePath: 'retropod://jiosaavn/$id',
          thumbnailPath: _best(row['image'])?.toString(),
          trackDuration: duration is num && duration.isFinite && duration > 0
              ? (duration * 1000).round()
              : null,
          isOnDevice: false,
          originalSongIndex: -1 - songs.length,
        ),
      );
    }
    return songs;
  }

  static String? idFor(MusicMetadata song) {
    if (song.isOnDevice) return null;
    final uri = Uri.tryParse(song.filePath ?? '');
    if (uri?.scheme != 'retropod' ||
        uri?.host != 'jiosaavn' ||
        uri!.pathSegments.length != 1)
      return null;
    return _id.hasMatch(uri.pathSegments.single)
        ? uri.pathSegments.single
        : null;
  }

  Future<MusicMetadata> resolve(MusicMetadata song) async {
    final id = idFor(song);
    if (id == null) return song;
    final response = await _get('/songs/$id');
    final rows = response['data'];
    if (rows is List) {
      for (final row in rows.whereType<Map>()) {
        if (row['id'] != id) continue;
        final audio = _best(row['downloadUrl']);
        if (audio != null) return song.copyWith(filePath: audio.toString());
      }
    }
    throw const JioSaavnException(
      'No playable JioSaavn stream (JIO_NO_AUDIO). Try another server or track.',
    );
  }
}
