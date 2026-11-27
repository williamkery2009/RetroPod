import 'dart:async';

import 'package:retropod/core/services/piped_service.dart';

class YoutubePlaybackFailure implements Exception {
  const YoutubePlaybackFailure(this.directError, this.fallbackError);
  final Object directError;
  final Object fallbackError;

  @override
  String toString() => 'YouTube and Piped audio resolution failed.';
}

/// Safe diagnostics: never display signed URLs, cookies or raw server bodies.
String youtubePlaybackErrorMessage(Object error) {
  if (error is YoutubePlaybackFailure) {
    return '${youtubePlaybackErrorMessage(error.directError)}\n\n'
        'Piped fallback: ${youtubePlaybackErrorMessage(error.fallbackError)}';
  }
  if (error is PipedPlaybackException) return error.message;
  final reason = error.toString().toLowerCase();
  if (error is TimeoutException) {
    return 'YouTube audio resolution timed out (YT_TIMEOUT). '
        'Try again with a stable connection.';
  }
  if (reason.contains('sign in') ||
      reason.contains('not a bot') ||
      reason.contains('login_required')) {
    return 'YouTube requires verification on this connection (YT_SIGN_IN). '
        'Anonymous playback is unavailable. Open this track in YouTube Music.';
  }
  if (reason.contains('403') || reason.contains('forbidden')) {
    return 'YouTube rejected the audio stream (YT_403). '
        'Try again to request a fresh stream, or open YouTube Music.';
  }
  if (reason.contains('429') || reason.contains('rate limit')) {
    return 'YouTube temporarily limited requests (YT_RATE_LIMIT). '
        'Wait a while before trying again.';
  }
  return 'YouTube audio could not be loaded (YT_PLAYBACK). '
      'Search can work even when streaming is unavailable. '
      'Try again, or open YouTube Music.';
}
