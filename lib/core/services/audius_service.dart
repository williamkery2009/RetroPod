import 'package:retropod/core/models/music_metadata.dart';

/// Public Audius tracks only. Never substitute a remix for a selected recording.
class AudiusService {
  static List<MusicMetadata> parseResults(Object? data) {
    if (data is! Map || data['data'] is! List || data['error'] != null) {
      throw const FormatException('Invalid Audius search response');
    }
    final songs = <MusicMetadata>[];
    final seen = <String>{};
    for (final row in (data['data'] as List).whereType<Map>()) {
      final id = row['id'];
      final title = row['title'];
      if (id is! String ||
          !RegExp(r'^[A-Za-z0-9]+$').hasMatch(id) ||
          title is! String ||
          title.trim().isEmpty ||
          row['is_streamable'] != true ||
          row['is_stream_gated'] == true ||
          row['stream_conditions'] != null ||
          row['is_available'] == false ||
          row['is_delete'] == true ||
          row['is_unlisted'] == true ||
          !seen.add(id))
        continue;
      final user = row['user'];
      final name = user is Map ? user['name'] : null;
      final artwork = row['artwork'];
      String? thumbnail;
      if (artwork is Map) {
        for (final size in ['1000x1000', '480x480', '150x150']) {
          final value = artwork[size];
          final uri = value is String ? Uri.tryParse(value) : null;
          if (uri != null &&
              uri.scheme == 'https' &&
              uri.host.isNotEmpty &&
              uri.userInfo.isEmpty) {
            thumbnail = uri.toString();
            break;
          }
        }
      }
      final seconds = row['duration'];
      songs.add(
        MusicMetadata(
          trackName: title.trim(),
          trackArtistNames: [
            name is String && name.trim().isNotEmpty
                ? name.trim()
                : 'Unknown uploader',
          ],
          albumName: 'Audius',
          // This stable endpoint redirects to current media; no signed CDN URL
          // is persisted. It needs no account credentials for public tracks.
          filePath: Uri.https(
            'api.audius.co',
            '/v1/tracks/$id/stream',
          ).toString(),
          thumbnailPath: thumbnail,
          trackDuration: seconds is num && seconds.isFinite && seconds > 0
              ? (seconds * 1000).round()
              : null,
          isOnDevice: false,
          originalSongIndex: -1 - songs.length,
        ),
      );
      if (songs.length == 40) break;
    }
    return songs;
  }
}
