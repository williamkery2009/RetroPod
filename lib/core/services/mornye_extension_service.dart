import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:retropod/core/models/music_metadata.dart';

class MornyeExtensionException implements Exception {
  const MornyeExtensionException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Runs installed packages through the native Mornye manager on Android.
class MornyeExtensionService {
  MornyeExtensionService({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel('retropod/mornye');
  static final instance = MornyeExtensionService();
  static bool get supported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
  final MethodChannel _channel;

  Future<Object?> call(String method, [Map<String, dynamic>? args]) async {
    try {
      final raw = await _channel.invokeMethod<String>(
        method,
        jsonEncode(args ?? {}),
      );
      return (jsonDecode(raw!) as Map)['value'];
    } on PlatformException catch (e) {
      throw MornyeExtensionException(errorMessage(e.code, fallback: e.message));
    } on MissingPluginException {
      throw const MornyeExtensionException(
        'Mornye extensions require the Android build with its native runtime.',
      );
    }
  }

  static String errorMessage(String code, {String? fallback}) {
    final message = switch (code) {
      'EXT_SESSION' =>
        'This extension requires Mornye session verification, which RetroPod does not support yet.',
      'EXT_AUTH' =>
        'This provider requires sign-in or verification. Browser account sign-in is not supported yet.',
      'EXT_FORBIDDEN' =>
        'The provider rejected the request (HTTP 403). An extension update may help; playback is not currently available.',
      'EXT_RATE_LIMIT' =>
        'The provider limited requests. Wait before trying again.',
      'EXT_TIMEOUT' => 'The extension timed out while contacting its provider.',
      'EXT_SERVER' => 'The provider server is unavailable. Try again later.',
      'EXT_QUALITY' => 'The requested audio quality is unavailable.',
      'EXT_PERMISSION' =>
        'The extension requested access outside its allowed permissions.',
      'EXT_COMPATIBILITY' =>
        'This extension needs a runtime feature or version not supported by this build.',
      'EXT_DISABLED' => 'This extension is disabled or no longer installed.',
      'EXT_NO_AUDIO' =>
        'This provider returned no playable audio for the selected track.',
      'EXT_NO_FILE' => 'The extension did not produce a valid audio file.',
      'EXT_FINALIZATION' =>
        'This extension output requires audio finalization that RetroPod does not support yet.',
      'EXT_FAILED' =>
        'The extension failed without a recognized cause. Try an extension update or another track.',
      _ => fallback ?? 'Extension operation failed.',
    };
    return '$message ($code)';
  }

  /// Mornye manifests accept both string choices and labeled object choices.
  static List<Map<String, dynamic>> settingOptions(Object? input) =>
      input is List
      ? input.expand<Map<String, dynamic>>((option) {
          if (option is String)
            return [
              {'value': option, 'label': option},
            ];
          if (option is Map && option['value'] != null) {
            return [
              {
                'value': option['value'],
                'label': option['label']?.toString() ?? '${option['value']}',
              },
            ];
          }
          return [];
        }).toList()
      : [];

  Future<List<Map<String, dynamic>>> installed() async =>
      _maps(await call('installed'));

  Future<List<Map<String, dynamic>>> registry() async {
    final response = await http
        .get(
          Uri.parse(
            'https://raw.githubusercontent.com/mornyeapp/'
            'Mornye-Extension/main/registry.json',
          ),
        )
        .timeout(const Duration(seconds: 20));
    if (response.statusCode != 200 || response.bodyBytes.length > 1024 * 1024) {
      throw const MornyeExtensionException('Extension catalog unavailable.');
    }
    return parseRegistry(jsonDecode(response.body));
  }

  static List<Map<String, dynamic>> parseRegistry(Object? data) {
    if (data is! Map || data['version'] != 1 || data['extensions'] is! List) {
      throw const FormatException('Unsupported extension catalog');
    }
    final seen = <String>{};
    return _maps(data['extensions']).where((entry) {
      final id = entry['id'];
      final uri = Uri.tryParse(entry['download_url']?.toString() ?? '');
      return id is String &&
          RegExp(r'^[a-z0-9_-]+$').hasMatch(id) &&
          entry['version'] is String &&
          RegExp(
            r'^[a-f0-9]{64}$',
          ).hasMatch(entry['sha256']?.toString() ?? '') &&
          uri != null &&
          uri.scheme == 'https' &&
          uri.host == 'raw.githubusercontent.com' &&
          !uri.hasPort &&
          uri.userInfo.isEmpty &&
          !uri.hasQuery &&
          !uri.hasFragment &&
          uri.path.startsWith('/mornyeapp/Mornye-Extension/main/extensions/') &&
          uri.path.endsWith('.sflx') &&
          seen.add(id);
    }).toList();
  }

  static List<Map<String, dynamic>> _maps(Object? value) => value is List
      ? value.whereType<Map>().map(Map<String, dynamic>.from).toList()
      : [];

  static Uri? reference(MusicMetadata song) {
    final uri = Uri.tryParse(song.filePath ?? '');
    return uri?.scheme == 'retropod' &&
            uri?.host == 'mornye' &&
            uri!.pathSegments.length == 2
        ? uri
        : null;
  }

  Future<List<MusicMetadata>> search(String provider, String query) async {
    final rows = _maps(await call('search', {'id': provider, 'query': query}));
    return parseTracks(provider, rows);
  }

  static List<MusicMetadata> parseTracks(String provider, Object? value) {
    final seen = <String>{};
    return _maps(value)
        .where(
          (row) =>
              row['id'] is String &&
              (row['id'] as String).isNotEmpty &&
              row['name'] is String &&
              seen.add(row['id'] as String),
        )
        .map((row) {
          final image = Uri.tryParse(row['cover_url']?.toString() ?? '');
          return MusicMetadata(
            trackName: row['name'] as String,
            trackArtistNames: [row['artists']?.toString() ?? 'Unknown artist'],
            albumName: row['album_name']?.toString() ?? provider,
            trackDuration: row['duration_ms'] is int
                ? row['duration_ms'] as int
                : null,
            thumbnailPath: image?.scheme == 'https' && image!.host.isNotEmpty
                ? image.toString()
                : null,
            filePath: Uri(
              scheme: 'retropod',
              host: 'mornye',
              pathSegments: [provider, row['id'] as String],
            ).toString(),
            isOnDevice: false,
            originalSongIndex: -1,
          );
        })
        .toList();
  }

  Future<MusicMetadata> resolve(MusicMetadata song) async {
    final uri = reference(song);
    if (uri == null) return song;
    final provider = uri.pathSegments[0];
    final id = uri.pathSegments[1];
    final available = await installed();
    final matches = available.where(
      (e) => e['id'] == provider && e['enabled'] == true,
    );
    if (matches.isEmpty || matches.first['has_download_provider'] != true) {
      throw const MornyeExtensionException(
        'This extension is disabled or only supplies metadata, not audio.',
      );
    }
    final qualities = _maps(matches.first['quality_options']);
    final url = await call('download', {
      'id': provider,
      'trackId': id,
      'quality': qualities.isEmpty ? 'high' : qualities.first['id'],
    });
    final file = Uri.tryParse(url?.toString() ?? '');
    if (file?.scheme != 'file') {
      throw const MornyeExtensionException(
        'The extension did not produce audio.',
      );
    }
    return song.copyWith(filePath: file.toString());
  }
}
