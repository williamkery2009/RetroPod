import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class YoutubeAccountException implements Exception {
  const YoutubeAccountException(this.code);
  final String code;

  String get message => switch (code) {
    'YT_SESSION_EXPIRED' =>
      'The saved YouTube session expired or could not be '
          'read. Sign out and sign in again.',
    'YT_SESSION_REJECTED' =>
      'YouTube rejected playback with the saved session. '
          'Sign-in does not remove all playback restrictions.',
    'YT_SESSION_NO_AUDIO' =>
      'YouTube accepted the request but returned no '
          'supported direct audio. This session may require additional player '
          'support that RetroPod does not have yet.',
    'YT_PROTECTED_ONLY' =>
      'YouTube offered only protected links for this track. '
          'RetroPod does not decode them. Open it in YouTube Music.',
    'YT_ACCOUNT_VERIFY' =>
      'YouTube asked for sign-in or another check before playing this track. '
          'Open it in YouTube Music, or sign out and sign in again.',
    'YT_TRACK_UNAVAILABLE' =>
      'YouTube says this track cannot be played here. Try another version.',
    'YT_ACCOUNT_RATE_LIMIT' =>
      'YouTube limited requests. Wait a while before trying again.',
    'YT_ACCOUNT_SERVER' =>
      'YouTube had a server problem. Try again later.',
    'YT_ACCOUNT_NETWORK' =>
      'Could not reach YouTube. Check the connection and try again.',
    'YT_ACCOUNT_BUSY' => 'A YouTube sign-in window is already open.',
    _ => 'YouTube account access is unavailable. Try again on Android.',
  };

  @override
  String toString() => '$message ($code)';
}

/// Cookies remain in the native Android component, never in Dart or preferences.
class YoutubeAccountService {
  const YoutubeAccountService([
    this._channel = const MethodChannel('retropod/youtube_account'),
  ]);

  final MethodChannel _channel;
  static const instance = YoutubeAccountService();
  static bool get supported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  Future<T?> _call<T>(String method, [Map<String, Object>? arguments]) async {
    try {
      return await _channel.invokeMethod<T>(method, arguments);
    } on PlatformException catch (error) {
      // Never include native exception text or details in user-visible errors.
      throw YoutubeAccountException(error.code);
    }
  }

  Future<bool> hasSession() async => await _call<bool>('status') ?? false;
  Future<bool> signIn() async => await _call<bool>('signIn') ?? false;
  Future<void> signOut() async {
    await _call<bool>('signOut');
  }

  Future<Uri?> resolve(String videoId) async {
    if (!supported) return null;
    final String? value;
    try {
      value = await _call<String>('resolve', {'videoId': videoId});
    } on MissingPluginException {
      return null;
    }
    if (value == null) return null;
    final uri = Uri.tryParse(value);
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.userInfo.isNotEmpty ||
        uri.port != 443 ||
        (uri.host != 'googlevideo.com' &&
            !uri.host.endsWith('.googlevideo.com'))) {
      throw const YoutubeAccountException('YT_SESSION_NO_AUDIO');
    }
    return uri;
  }
}
