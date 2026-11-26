import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class PipedPlaybackException implements Exception {
  const PipedPlaybackException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Uses the Piped HTTP API; no NewPipe code is linked into the app.
class PipedService {
  PipedService(this._client, {Future<Uri> Function()? instance})
    : _instance = instance ?? configuredInstance;

  final http.Client _client;
  final Future<Uri> Function() _instance;
  static const defaultInstance = 'https://pipedapi.kavin.rocks';
  static const _preferenceKey = 'pipedApiBaseUrl';

  static Uri validateInstance(String value) {
    final uri = Uri.tryParse(value.trim());
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment) {
      throw const FormatException(
        'Enter an HTTPS Piped API URL without credentials, query or fragment.',
      );
    }
    return uri.replace(path: uri.path.replaceAll(RegExp(r'/+$'), ''));
  }

  static Future<Uri> configuredInstance() async {
    final prefs = await SharedPreferences.getInstance();
    return validateInstance(prefs.getString(_preferenceKey) ?? defaultInstance);
  }

  static Future<void> saveInstance(String value) async {
    final uri = validateInstance(value);
    final prefs = await SharedPreferences.getInstance();
    if (!await prefs.setString(_preferenceKey, uri.toString())) {
      throw StateError('Could not save the Piped server.');
    }
  }

  Future<Uri> resolveAudio(String videoId) async {
    if (!RegExp(r'^[A-Za-z0-9_-]{11}$').hasMatch(videoId)) {
      throw const FormatException('Invalid YouTube video ID');
    }
    try {
      final base = validateInstance((await _instance()).toString());
      final response = await _client
          .get(
            base.replace(path: '${base.path}/streams/$videoId'),
            headers: {'Accept': 'application/json'},
          )
          .timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) {
        throw const PipedPlaybackException(
          'The Piped server could not resolve this track (PIPED_SERVER). '
          'Select Piped server to try a different API instance.',
        );
      }
      return parseAudio(jsonDecode(utf8.decode(response.bodyBytes)));
    } on PipedPlaybackException {
      rethrow;
    } on TimeoutException {
      throw const PipedPlaybackException(
        'The Piped server timed out (PIPED_TIMEOUT). '
        'Select Piped server to change the instance.',
      );
    } catch (_) {
      throw const PipedPlaybackException(
        'Piped returned an invalid response or could not be reached '
        '(PIPED_UNAVAILABLE). Check the API server address.',
      );
    }
  }

  static Uri parseAudio(Object? data) {
    if (data is! Map ||
        data['error'] != null ||
        data['audioStreams'] is! List) {
      throw const PipedPlaybackException(
        'This is not a usable Piped stream response (PIPED_RESPONSE). '
        'Use an API server address, not its website address.',
      );
    }
    final candidates = <({Uri url, bool mp4, num bitrate})>[];
    for (final row in (data['audioStreams'] as List).whereType<Map>()) {
      final url = row['url'] is String ? Uri.tryParse(row['url']) : null;
      final mime = row['mimeType'];
      if (url == null ||
          url.scheme != 'https' ||
          url.host.isEmpty ||
          url.userInfo.isNotEmpty ||
          row['videoOnly'] == true ||
          (mime != 'audio/mp4' && mime != 'audio/webm'))
        continue;
      candidates.add((
        url: url,
        mp4: mime == 'audio/mp4',
        bitrate: row['bitrate'] is num ? row['bitrate'] as num : 0,
      ));
    }
    if (candidates.isEmpty) {
      throw const PipedPlaybackException(
        'Piped returned no supported audio streams (PIPED_NO_AUDIO). '
        'Try another instance; this server may be blocked by YouTube.',
      );
    }
    candidates.sort((a, b) {
      if (a.mp4 != b.mp4) return a.mp4 ? -1 : 1;
      return b.bitrate.compareTo(a.bitrate);
    });
    return candidates.first.url;
  }
}
