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

/// A manifest-declared choice the listener can change, such as quality.
class HttpAddonSetting {
  const HttpAddonSetting({
    required this.key,
    required this.label,
    required this.value,
    required this.options,
  });
  final String key;
  final String label;
  final String value;

  /// Provider value to display label.
  final Map<String, String> options;
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
        uri.hasFragment ||
        value.length > 8192) {
      throw const HttpAddonException(
        'Enter your private HTTPS add-on base or manifest URL (ADDON_URL).',
      );
    }
    var path = uri.path.replaceAll(RegExp(r'/+$'), '');
    if (path.endsWith('/manifest.json')) {
      path = path.substring(0, path.length - 14);
    }
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
    final declared = manifest['resources'];
    final resources = declared is List
        ? declared
              .map((r) => r is Map ? r['name'] ?? r['type'] : r)
              .whereType<String>()
              .map((r) => r.toLowerCase())
              .toList()
        : null;
    if (resources != null &&
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
        'settings': manifestSettings(manifest),
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

  /// Only declared settings travel to the provider; do not guess quality tiers.
  static Map<String, String> manifestSettings(Map manifest) {
    final result = <String, String>{};
    final rows = manifest['settings'];
    if (rows is! List) return result;
    for (final row in rows.whereType<Map>().take(20)) {
      final key = row['key'] ?? row['id'] ?? row['name'];
      if (key is! String ||
          !RegExp(r'^[A-Za-z0-9_.-]{1,64}$').hasMatch(key) ||
          key == 'q') {
        continue;
      }
      final options = row['options'];
      final values = options is List
          ? options
                .map((o) => o is Map ? o['value'] : o)
                .where((v) => v is String || v is num || v is bool)
                .map((v) => v.toString())
                .toList()
          : <String>[];
      final raw = row['default'];
      var value = raw is String || raw is num || raw is bool
          ? raw.toString()
          : null;
      if (values.isNotEmpty && !values.contains(value)) value = values.first;
      if ([
            'boolean',
            'bool',
            'toggle',
            'switch',
            'checkbox',
          ].contains(row['type']) &&
          value != 'true' &&
          value != 'false') {
        value = 'false';
      }
      if (value != null && value.length <= 256) result[key] = value;
    }
    return result;
  }

  /// Selectable settings from the live manifest with the saved choices.
  Future<List<HttpAddonSetting>> editableSettings() async {
    final config = await _config();
    final base = baseUrl(config['url'] as String);
    final manifest = await _get(
      base.replace(path: '${base.path}/manifest.json'),
    );
    if (manifest is! Map) {
      throw const HttpAddonException('Invalid manifest (ADDON_MANIFEST).');
    }
    final defaults = manifestSettings(manifest);
    final saved = config['settings'];
    final rows = manifest['settings'];
    final result = <HttpAddonSetting>[];
    for (final row in rows is List ? rows.whereType<Map>() : <Map>[]) {
      final key = row['key'] ?? row['id'] ?? row['name'];
      final raw = row['options'];
      if (key is! String || !defaults.containsKey(key) || raw is! List) {
        continue;
      }
      final options = <String, String>{};
      for (final option in raw.take(20)) {
        final value = option is Map ? option['value'] : option;
        if (value is! String && value is! num && value is! bool) continue;
        final text = value.toString();
        if (text.length > 256) continue;
        final label = option is Map ? option['label'] : null;
        options[text] = label is String && label.isNotEmpty ? label : text;
      }
      if (options.isEmpty) continue;
      final current = saved is Map ? saved[key] : null;
      final label = row['label'] ?? row['title'];
      result.add(
        HttpAddonSetting(
          key: key,
          label: label is String && label.isNotEmpty ? label : key,
          value: options.containsKey(current)
              ? current as String
              : defaults[key]!,
          options: options,
        ),
      );
    }
    return result;
  }

  /// Saves one choice. The configuration ID stays, so results remain valid.
  Future<void> updateSetting(String key, String value) async {
    final config = await _config();
    final settings = {...await _settings(config), key: value};
    try {
      await _channel.invokeMethod<String>('set', {
        'id': config['id'],
        'url': config['url'],
        'name': config['name'],
        'settings': settings,
      });
    } catch (_) {
      throw const HttpAddonException(
        'Could not save the add-on setting (ADDON_STORAGE).',
      );
    }
  }

  Future<Map<String, String>> _settings(Map<String, dynamic> config) async {
    final saved = config['settings'];
    if (saved is Map) return Map<String, String>.from(saved);
    // Upgrade endpoints saved before manifest settings were supported.
    final base = baseUrl(config['url'] as String);
    final manifest = await _get(
      base.replace(path: '${base.path}/manifest.json'),
    );
    if (manifest is! Map) {
      throw const HttpAddonException('Invalid manifest (ADDON_MANIFEST).');
    }
    return manifestSettings(manifest);
  }

  static Uri _endpoint(
    Uri base,
    List<String> path,
    Map<String, String> params,
  ) {
    final query = Uri(queryParameters: params).query;
    return base.replace(
      pathSegments: [...base.pathSegments.where((s) => s.isNotEmpty), ...path],
      query: [
        if (base.hasQuery) base.query,
        if (query.isNotEmpty) query,
      ].join('&'),
    );
  }

  Future<Object?> _get(Uri uri) async {
    try {
      final request = http.Request('GET', uri)..followRedirects = false;
      request.headers['Accept'] = 'application/json';
      request.headers['User-Agent'] = 'RetroPod';
      request.headers['Cache-Control'] = 'no-cache';
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
    final settings = await _settings(config);
    final data = await _get(
      _endpoint(base, ['search'], {'q': query.trim(), ...settings}),
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
    final settings = await _settings(config);
    final endpoint = _endpoint(base, [
      'stream',
      ref.pathSegments.last,
    ], settings);
    final data = await _get(endpoint);
    final nested = data is Map ? data['stream'] ?? data['data'] : null;
    final stream = nested is Map ? nested : data;
    if (stream is! Map) {
      throw const HttpAddonException(
        'Invalid stream response (ADDON_RESPONSE).',
      );
    }
    if (_flag(stream['encrypted']) ||
        stream['hybrid'] != null ||
        (stream['drm'] != null && stream['drm'] != false) ||
        stream['licenseUrl'] != null) {
      throw const HttpAddonException(
        'This provider requires encrypted playback or a license not supported by RetroPod (ADDON_UNSUPPORTED).',
      );
    }
    final headers = _playbackHeaders(stream['headers']);
    for (final key in [
      'url',
      'stream',
      'directUrl',
      'streamUrl',
      'downloadUrl',
      'mediaUrl',
    ]) {
      final value = stream[key];
      final relative = value is String && value.trim().isNotEmpty
          ? Uri.tryParse(value.trim())
          : null;
      final uri = relative == null
          ? null
          : base.replace(path: '${base.path}/', query: '').resolveUri(relative);
      if (uri?.scheme == 'https' &&
          uri!.host.isNotEmpty &&
          uri.userInfo.isEmpty) {
        if (_isDecoy(uri)) {
          throw const HttpAddonException(
            'The provider sent a prank file instead of this song. It may not allow playback in RetroPod. Contact the provider (ADDON_DECOY).',
          );
        }
        return song.copyWith(
          filePath: uri.toString(),
          mimeType: _streamMime(stream, uri),
          playbackHeaders: headers,
        );
      }
    }
    throw const HttpAddonException(
      'Add-on returned no direct HTTPS audio (ADDON_NO_AUDIO).',
    );
  }

  /// LastWave Addons was seen answering stream requests from this repository.
  static bool _isDecoy(Uri uri) =>
      uri.host.toLowerCase() == 'cdn.jsdelivr.net' &&
      uri.path.toLowerCase().contains('/pranks-cdn');

  static bool _flag(Object? value) =>
      value == true ||
      value == 1 ||
      value == '1' ||
      (value is String && value.toLowerCase() == 'true');

  static Map<String, String> _playbackHeaders(Object? raw) {
    if (raw == null) return const {};
    if (raw is! Map || raw.length > 10) {
      throw const HttpAddonException(
        'Invalid playback headers (ADDON_HEADERS).',
      );
    }
    final headers = <String, String>{};
    for (final entry in raw.entries) {
      final key = entry.key;
      final value = entry.value;
      if (key is! String ||
          value is! String ||
          !RegExp(r'^[A-Za-z0-9-]{1,64}$').hasMatch(key) ||
          value.length > 8192 ||
          value.contains('\r') ||
          value.contains('\n') ||
          [
            'host',
            'content-length',
            'connection',
            'transfer-encoding',
          ].contains(key.toLowerCase())) {
        throw const HttpAddonException(
          'Invalid playback headers (ADDON_HEADERS).',
        );
      }
      headers[key] = value;
    }
    return Map.unmodifiable(headers);
  }

  static String? _streamMime(Map stream, Uri uri) {
    final mime = '${stream['mimeType'] ?? stream['mime'] ?? ''}'.toLowerCase();
    final format =
        '${stream['format'] ?? stream['manifest'] ?? stream['type'] ?? ''}'
            .toLowerCase();
    final path = uri.path.toLowerCase();
    if (mime.contains('dash') ||
        ['dash', 'mpd'].contains(format) ||
        path.endsWith('.mpd')) {
      return 'application/dash+xml';
    }
    if (mime.contains('mpegurl') ||
        ['hls', 'm3u8'].contains(format) ||
        path.endsWith('.m3u8')) {
      return 'application/vnd.apple.mpegurl';
    }
    return mime.startsWith('audio/') ? mime : null;
  }
}
