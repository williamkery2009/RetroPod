import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:retropod/core/models/music_metadata.dart';

class HttpAddonException implements Exception {
  const HttpAddonException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Independent client for Lastwave's manifest/search/stream HTTP protocol.
class HttpAddonService {
  HttpAddonService(
    this._client, {
    Future<Map<String, dynamic>?> Function()? configuration,
  }) : _configuration = configuration ?? readConfiguration;
  final http.Client _client;
  final Future<Map<String, dynamic>?> Function() _configuration;
  static const _channel = MethodChannel('retropod/http_addon');
  static const setupWebsite = 'https://lastwaveaddons.clashprojects.qd.je';

  static Uri baseUrl(String value) {
    final uri = Uri.tryParse(value.trim());
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment ||
        value.length > 8192) {
      throw const HttpAddonException(
        'Enter your private HTTPS add-on base or manifest URL without query parameters (ADDON_URL).',
      );
    }
    var path = uri.path.replaceAll(RegExp(r'/+$'), '');
    if (path.endsWith('/manifest.json'))
      path = path.substring(0, path.length - 14);
    if (uri.host == Uri.parse(setupWebsite).host && path.isEmpty) {
      throw const HttpAddonException(
        'This is the signup website. Use the personal add-on URL from your verified dashboard (ADDON_SETUP).',
      );
    }
    return uri.replace(path: path);
  }

  static Future<Map<String, dynamic>?> readConfiguration() async {
    try {
      final raw = await _channel.invokeMethod<String>('get');
      return raw == null
          ? null
          : Map<String, dynamic>.from(jsonDecode(raw) as Map);
    } catch (_) {
      throw const HttpAddonException(
        'Could not read private add-on settings. Android is required (ADDON_STORAGE).',
      );
    }
  }

  Future<void> configure(String value) async {
    final base = baseUrl(value);
    final manifest = await _get(
      base.replace(path: '${base.path}/manifest.json'),
    );
    if (manifest is! Map ||
        manifest['id'] is! String ||
        manifest['name'] is! String ||
        (manifest['id'] as String).isEmpty ||
        (manifest['name'] as String).isEmpty) {
      throw const HttpAddonException(
        'The URL did not return an add-on manifest (ADDON_MANIFEST).',
      );
    }
    final resources = manifest['resources'];
    if (resources is List &&
        resources.isNotEmpty &&
        (!resources.contains('search') || !resources.contains('stream'))) {
      throw const HttpAddonException(
        'The add-on does not declare both search and stream support (ADDON_MANIFEST).',
      );
    }
    try {
      await _channel.invokeMethod<String>('set', {
        'url': base.toString(),
        'name': manifest['name'],
      });
    } catch (_) {
      throw const HttpAddonException(
        'Could not securely save the add-on (ADDON_STORAGE).',
      );
    }
  }

  static Future<void> remove() async {
    try {
      await _channel.invokeMethod<String>('remove');
    } catch (_) {
      throw const HttpAddonException(
        'Could not remove the add-on (ADDON_STORAGE).',
      );
    }
  }

  Future<Map<String, dynamic>> _config() async {
    final config = await _configuration();
    if (config == null) {
      throw const HttpAddonException(
        'Open Add-on settings and enter your personal provider URL (ADDON_SETUP).',
      );
    }
    return config;
  }

  Future<Object?> _get(Uri uri) async {
    try {
      final request = http.Request('GET', uri)..followRedirects = false;
      request.headers['Accept'] = 'application/json';
      final response = await _client
          .send(request)
          .timeout(const Duration(seconds: 15));
      if (response.statusCode != 200) {
        await response.stream.listen((_) {}).cancel();
        throw HttpAddonException(
          'Add-on returned HTTP ${response.statusCode} (ADDON_HTTP). The provider may require account verification, quota or app authorization not supported here.',
        );
      }
      final data = <int>[];
      await for (final chunk in response.stream.timeout(
        const Duration(seconds: 15),
      )) {
        if (data.length + chunk.length > 2 * 1024 * 1024) {
          throw const HttpAddonException(
            'Add-on response is too large (ADDON_RESPONSE).',
          );
        }
        data.addAll(chunk);
      }
      return jsonDecode(utf8.decode(data));
    } on HttpAddonException {
      rethrow;
    } catch (_) {
      throw const HttpAddonException(
        'Add-on timed out or returned invalid data (ADDON_RESPONSE).',
      );
    }
  }

  Future<List<MusicMetadata>> search(String query) async {
    if (query.trim().isEmpty) return [];
    final config = await _config();
    final base = baseUrl(config['url'] as String);
    final data = await _get(
      base.replace(
        path: '${base.path}/search',
        queryParameters: {
          'q': query.trim(),
          'quality': 'lossless',
          'atmos': 'none',
        },
      ),
    );
    final rows = data is List
        ? data
        : data is Map
        ? data['tracks'] ?? data['data'] ?? data['results'] ?? data['items']
        : null;
    if (rows is! List) {
      throw const HttpAddonException(
        'Add-on returned no track list (ADDON_RESPONSE).',
      );
    }
    final songs = <MusicMetadata>[];
    final seen = <String>{};
    for (final row in rows.whereType<Map>()) {
      final id = row['id']?.toString() ?? '';
      final title = row['title'];
      if (id.isEmpty ||
          id.length > 256 ||
          title is! String ||
          title.isEmpty ||
          !seen.add(id)) {
        continue;
      }
      final duration = num.tryParse('${row['duration']}');
      final art = Uri.tryParse('${row['artworkURL'] ?? ''}');
      songs.add(
        MusicMetadata(
          trackName: title,
          trackArtistNames: [row['artist']?.toString() ?? 'Unknown Artist'],
          albumName: row['album']?.toString() ?? config['name'] as String?,
          trackDuration: duration != null && duration.isFinite && duration > 0
              ? (duration * 1000).round()
              : null,
          thumbnailPath: art?.scheme == 'https' && art!.userInfo.isEmpty
              ? art.toString()
              : null,
          filePath: Uri(
            scheme: 'retropod',
            host: 'addon',
            pathSegments: [config['id'] as String, id],
          ).toString(),
          isOnDevice: false,
          originalSongIndex: -1 - songs.length,
        ),
      );
      if (songs.length == 40) break;
    }
    return songs;
  }

  static bool handles(MusicMetadata song) {
    final uri = Uri.tryParse(song.filePath ?? '');
    return !song.isOnDevice &&
        uri?.scheme == 'retropod' &&
        uri?.host == 'addon';
  }

  Future<MusicMetadata> resolve(MusicMetadata song) async {
    final ref = Uri.parse(song.filePath!);
    final config = await _config();
    if (ref.pathSegments.length != 2 ||
        ref.pathSegments.first != config['id']) {
      throw const HttpAddonException(
        'This track belongs to a replaced add-on. Search again (ADDON_CHANGED).',
      );
    }
    final base = baseUrl(config['url'] as String);
    final endpoint = base.replace(
      pathSegments: [
        ...base.pathSegments.where((s) => s.isNotEmpty),
        'stream',
        ref.pathSegments.last,
      ],
      queryParameters: {'quality': 'lossless', 'atmos': 'none'},
    );
    final data = await _get(endpoint);
    final stream = data is Map ? data['stream'] ?? data['data'] ?? data : null;
    if (stream is! Map) {
      throw const HttpAddonException(
        'Invalid stream response (ADDON_RESPONSE).',
      );
    }
    if (stream['encrypted'] == true ||
        stream['hybrid'] != null ||
        stream['drm'] != null ||
        stream['licenseUrl'] != null ||
        stream['headers'] != null) {
      throw const HttpAddonException(
        'This provider requires encrypted playback, a license or custom headers not supported by RetroPod (ADDON_UNSUPPORTED).',
      );
    }
    for (final key in [
      'url',
      'directUrl',
      'streamUrl',
      'downloadUrl',
      'mediaUrl',
    ]) {
      final value = stream[key];
      final uri = value is String ? Uri.tryParse(value) : null;
      if (uri?.scheme == 'https' &&
          uri!.host.isNotEmpty &&
          uri.userInfo.isEmpty) {
        return song.copyWith(filePath: uri.toString());
      }
    }
    throw const HttpAddonException(
      'Add-on returned no direct HTTPS audio (ADDON_NO_AUDIO).',
    );
  }
}
