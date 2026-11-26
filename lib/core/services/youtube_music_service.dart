import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:retropod/core/models/music_metadata.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

typedef YoutubeAudioResolver = Future<Uri> Function(String videoId);

/// Public, unauthenticated YouTube Music search. This is an unofficial API.
/// Search results retain watch URLs; expiring audio URLs are resolved on play.
class YoutubeMusicService {
  YoutubeMusicService(
    this._client, {
    YoutubeAudioResolver? resolveAudio,
    YoutubeExplode Function()? createExtractor,
  }) : _resolveAudio =
           resolveAudio ??
           ((id) =>
               _resolvePublicAudio(id, createExtractor ?? YoutubeExplode.new));

  final http.Client _client;
  final YoutubeAudioResolver _resolveAudio;
  static final RegExp _videoId = RegExp(r'^[a-zA-Z0-9_-]{11}$');

  Future<List<MusicMetadata>> search(String query) async {
    if (query.trim().isEmpty) return [];
    final date = DateTime.now()
        .toUtc()
        .toIso8601String()
        .substring(0, 10)
        .replaceAll('-', '');
    final response = await _client
        .post(
          Uri.https('music.youtube.com', '/youtubei/v1/search', {
            'alt': 'json',
          }),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'context': {
              'client': {
                'clientName': 'WEB_REMIX',
                'clientVersion': '1.$date.01.00',
                'hl': 'en',
              },
            },
            'query': query.trim(),
            // Songs-only filter documented by sigma67/ytmusicapi.
            'params': 'EgWKAQIIAWoMEA4QChADEAQQCRAF',
          }),
        )
        .timeout(const Duration(seconds: 15));
    if (response.statusCode != 200) {
      throw StateError('YouTube Music search is unavailable.');
    }
    return parseResults(jsonDecode(utf8.decode(response.bodyBytes)));
  }

  static Object? _at(Object? object, List<Object> path) {
    Object? value = object;
    for (final key in path) {
      if (value is Map && key is String) {
        value = value[key];
      } else if (value is List &&
          key is int &&
          key >= 0 &&
          key < value.length) {
        value = value[key];
      } else {
        return null;
      }
    }
    return value;
  }

  static String? _text(Object? value) =>
      value is String && value.trim().isNotEmpty ? value.trim() : null;

  static Iterable<Map> _renderers(Object? node) sync* {
    if (node is Map) {
      final renderer = node['musicResponsiveListItemRenderer'];
      if (renderer is Map) {
        yield renderer;
      } else {
        for (final child in node.values) {
          yield* _renderers(child);
        }
      }
    } else if (node is List) {
      for (final child in node) {
        yield* _renderers(child);
      }
    }
  }

  static List<MusicMetadata> parseResults(Object? data) {
    if (data is! Map ||
        data['error'] != null ||
        !data.containsKey('contents')) {
      throw const FormatException('Invalid YouTube Music search response');
    }
    final results = <MusicMetadata>[];
    final seen = <String>{};
    for (final row in _renderers(data['contents'])) {
      final titleRuns = _at(row, [
        'flexColumns',
        0,
        'musicResponsiveListItemFlexColumnRenderer',
        'text',
        'runs',
      ]);
      final id =
          _text(_at(row, ['playlistItemData', 'videoId'])) ??
          _text(
            _at(titleRuns, [
              0,
              'navigationEndpoint',
              'watchEndpoint',
              'videoId',
            ]),
          );
      final title = _text(_at(titleRuns, [0, 'text']));
      if (id == null ||
          !_videoId.hasMatch(id) ||
          title == null ||
          !seen.add(id)) {
        continue;
      }
      final artists = <String>[];
      String? album;
      final runs = _at(row, [
        'flexColumns',
        1,
        'musicResponsiveListItemFlexColumnRenderer',
        'text',
        'runs',
      ]);
      if (runs is List) {
        for (final run in runs) {
          final browseId = _text(
            _at(run, ['navigationEndpoint', 'browseEndpoint', 'browseId']),
          );
          final name = _text(_at(run, ['text']));
          if (name == null || browseId == null) continue;
          if (browseId.startsWith('UC')) artists.add(name);
          if (browseId.startsWith('MPRE')) album = name;
        }
      }
      final thumbs = _at(row, [
        'thumbnail',
        'musicThumbnailRenderer',
        'thumbnail',
        'thumbnails',
      ]);
      String? artwork;
      if (thumbs is List) {
        for (final thumb in thumbs) {
          final url = Uri.tryParse(_text(_at(thumb, ['url'])) ?? '');
          if (url != null && url.scheme == 'https' && url.host.isNotEmpty) {
            artwork = url.toString();
          }
        }
      }
      results.add(
        MusicMetadata(
          trackName: title,
          trackArtistNames: artists.isEmpty ? ['Unknown Artist'] : artists,
          albumName: album ?? 'YouTube Music',
          filePath: Uri.https('music.youtube.com', '/watch', {
            'v': id,
          }).toString(),
          thumbnailPath: artwork,
          originalSongIndex: -1 - results.length,
          isOnDevice: false,
        ),
      );
      if (results.length == 40) break;
    }
    return results;
  }

  static String? videoIdFor(MusicMetadata song) {
    if (song.isOnDevice) return null;
    final uri = Uri.tryParse(song.filePath ?? '');
    if (uri?.scheme != 'https' ||
        uri?.host != 'music.youtube.com' ||
        uri?.path != '/watch') {
      return null;
    }
    final id = uri!.queryParameters['v'];
    return id != null && _videoId.hasMatch(id) ? id : null;
  }

  Future<MusicMetadata> resolveForPlayback(MusicMetadata song) async {
    final id = videoIdFor(song);
    if (id == null) return song;
    final url = await _resolveAudio(id).timeout(const Duration(seconds: 25));
    if (url.scheme != 'https' || url.host.isEmpty) {
      throw StateError('YouTube did not return a playable stream.');
    }
    return song.copyWith(filePath: url.toString());
  }

  // Compatibility profile proposed upstream in youtube_explode_dart PR #389.
  // The 3.1.0 default Android client currently returns 403 for audio streams.
  // Keep this local until the dependency ships the upstream fix.
  static const _musicClient = YoutubeApiClient({
    'context': {
      'client': {
        'clientName': 'VISIONOS',
        'clientVersion': '1.02',
        'deviceMake': 'Apple',
        'deviceModel': 'RealityDevice17,1',
        'osName': 'visionOS',
        'osVersion': '26.5.23O471',
        'userAgent':
            'Mozilla/5.0 (Macintosh; Intel Mac OS X 15_7_3) '
            'AppleWebKit/605.1.15 (KHTML, like Gecko) '
            'Version/26.0 Safari/605.1.15',
        'hl': 'en',
        'timeZone': 'UTC',
        'utcOffsetMinutes': 0,
      },
    },
  }, 'https://www.youtube.com/youtubei/v1/player?prettyPrint=false');

  static Future<Uri> _resolvePublicAudio(
    String videoId,
    YoutubeExplode Function() createExtractor,
  ) async {
    final youtube = createExtractor();
    try {
      final manifest = await youtube.videos.streams
          .getManifest(
            videoId,
            ytClients: [_musicClient],
            // This profile provides direct URLs without a watch-page JS solver.
            requireWatchPage: false,
          )
          .timeout(const Duration(seconds: 20));
      final streams = manifest.audioOnly.toList();
      // AAC/MP4 is the most broadly supported format across our players.
      final mp4 = streams
          .where((stream) => stream.container == StreamContainer.mp4)
          .toList();
      final candidates = mp4.isNotEmpty ? mp4 : streams;
      if (candidates.isEmpty) {
        throw StateError('No public audio stream available.');
      }
      candidates.sort((a, b) => b.bitrate.compareTo(a.bitrate));
      return candidates.first.url;
    } finally {
      youtube.close();
    }
  }
}
