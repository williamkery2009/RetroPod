import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:retropod/core/models/music_metadata.dart';
import 'package:retropod/core/services/youtube_account_service.dart';
import 'package:retropod/core/services/youtube_music_service.dart';
import 'package:retropod/core/services/youtube_playback_error.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('retropod/youtube_account');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
  });
  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
    debugDefaultTargetPlatformOverride = null;
  });

  test(
    'session save, status, sign-out and cancellation use no credentials',
    () async {
      var saved = false;
      messenger.setMockMethodCallHandler(channel, (call) async {
        expect(call.arguments, isNull);
        switch (call.method) {
          case 'signIn':
            saved = true;
            return true;
          case 'signOut':
            saved = false;
            return true;
          case 'status':
            return saved;
        }
        throw StateError('Unexpected account operation');
      });
      const service = YoutubeAccountService.instance;
      expect(await service.hasSession(), isFalse);
      expect(await service.signIn(), isTrue);
      expect(await service.hasSession(), isTrue);
      await service.signOut();
      expect(await service.hasSession(), isFalse);
      messenger.setMockMethodCallHandler(channel, (_) async => false);
      expect(await service.signIn(), isFalse);
    },
  );

  test(
    'only video ID reaches native resolver; no session returns null',
    () async {
      messenger.setMockMethodCallHandler(channel, (call) async {
        expect(call.method, 'resolve');
        expect(call.arguments, {'videoId': 'abcdefghijk'});
        return null;
      });
      expect(
        await YoutubeAccountService.instance.resolve('abcdefghijk'),
        isNull,
      );
    },
  );

  test('signed-in audio bypasses anonymous extractor', () async {
    final client = MockClient(
      (_) async => throw StateError('Unexpected search'),
    );
    addTearDown(client.close);
    final service = YoutubeMusicService(
      client,
      resolveAccountAudio: (_) async =>
          Uri.parse('https://r1.googlevideo.com/audio'),
      createExtractor: () => throw StateError('Anonymous extractor was called'),
    );
    final track = MusicMetadata(
      filePath: 'https://music.youtube.com/watch?v=abcdefghijk',
      isOnDevice: false,
    );
    expect(
      (await service.resolveForPlayback(track)).filePath,
      'https://r1.googlevideo.com/audio',
    );
    expect(track.filePath, contains('music.youtube.com'));
  });

  test('session errors stay actionable without native details', () async {
    messenger.setMockMethodCallHandler(channel, (_) async {
      throw PlatformException(
        code: 'YT_SESSION_REJECTED',
        message: 'cookie=secret',
        details: 'signed-url-secret',
      );
    });
    await expectLater(
      YoutubeAccountService.instance.resolve('abcdefghijk'),
      throwsA(
        predicate<Object>((e) {
          final message = youtubePlaybackErrorMessage(e);
          return message.contains('YT_SESSION_REJECTED') &&
              !message.contains('secret');
        }),
      ),
    );
  });

  test('rejects credential URLs and unrelated stream hosts', () async {
    for (final value in [
      'http://r1.googlevideo.com/a',
      'https://googlevideo.com.evil.test/a',
      'https://user:secret@r1.googlevideo.com/a',
      'https://r1.googlevideo.com:444/a',
    ]) {
      messenger.setMockMethodCallHandler(channel, (_) async => value);
      await expectLater(
        YoutubeAccountService.instance.resolve('abcdefghijk'),
        throwsA(isA<YoutubeAccountException>()),
      );
    }
  });

  test('each playback failure has its own safe explanation', () async {
    final messages = <String>{};
    const codes = [
      'YT_PROTECTED_ONLY',
      'YT_ACCOUNT_VERIFY',
      'YT_TRACK_UNAVAILABLE',
      'YT_ACCOUNT_RATE_LIMIT',
      'YT_ACCOUNT_SERVER',
      'YT_ACCOUNT_NETWORK',
    ];
    for (final code in codes) {
      messenger.setMockMethodCallHandler(channel, (_) async {
        throw PlatformException(code: code, message: 'cookie=secret');
      });
      await expectLater(
        YoutubeAccountService.instance.resolve('abcdefghijk'),
        throwsA(
          predicate<Object>((e) {
            final message = youtubePlaybackErrorMessage(e);
            messages.add(message.replaceAll(code, ''));
            return message.contains(code) && !message.contains('secret');
          }),
        ),
      );
    }
    expect(messages, hasLength(codes.length));
  });
}
