import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:retropod/core/services/mornye_extension_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('test/mornye');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test('catalog rejects foreign package hosts and malformed digests', () {
    final valid = {
      'id': 'soundcloud',
      'version': '1.0.15',
      'download_url':
          'https://raw.githubusercontent.com/mornyeapp/Mornye-Extension/main/extensions/soundcloud.sflx',
      'sha256': List.filled(64, 'a').join(),
    };
    final rows = MornyeExtensionService.parseRegistry({
      'version': 1,
      'extensions': [
        valid,
        valid,
        {
          ...valid,
          'id': 'foreign',
          'download_url': 'https://example.com/package.sflx',
        },
        {...valid, 'id': 'broken', 'sha256': 'bad'},
      ],
    });
    expect(rows, hasLength(1));
  });

  test('track IDs round trip without replacing catalog identity', () {
    final songs = MornyeExtensionService.parseTracks('test', [
      {
        'id': 'a/b?c',
        'name': 'A remix',
        'artists': 'Uploader',
        'duration_ms': 12345,
        'cover_url': 'http://insecure.example/image',
      },
      {'id': 'a/b?c', 'name': 'Duplicate'},
    ]);
    expect(songs, hasLength(1));
    expect(MornyeExtensionService.reference(songs.single)!.pathSegments, [
      'test',
      'a/b?c',
    ]);
    expect(songs.single.trackName, 'A remix');
    expect(songs.single.thumbnailPath, isNull);
  });

  test(
    'resolves extension result to prepared file and retains stable metadata',
    () async {
      final calls = <String>[];
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call.method);
        final args = jsonDecode(call.arguments as String) as Map;
        final Object value;
        switch (call.method) {
          case 'search':
            expect(args['query'], 'Test');
            value = [
              {'id': '1', 'name': 'Test', 'artists': 'Artist'},
            ];
          case 'installed':
            value = [
              {
                'id': 'test',
                'enabled': true,
                'has_download_provider': true,
                'quality_options': [
                  {'id': 'aac_160'},
                ],
              },
            ];
          case 'download':
            expect(args['quality'], 'aac_160');
            expect(args['trackId'], '1');
            value = 'file:///private/audio/test.m4a';
          default:
            throw StateError(call.method);
        }
        return jsonEncode({'value': value});
      });
      final service = MornyeExtensionService(channel: channel);
      final song = (await service.search('test', 'Test')).single;
      final playable = await service.resolve(song);
      expect(playable.filePath, 'file:///private/audio/test.m4a');
      expect(song.filePath, startsWith('retropod://mornye/'));
      expect(calls, ['search', 'installed', 'download']);
    },
  );

  test('metadata-only extensions cannot enter audio download', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'installed');
      return jsonEncode({
        'value': [
          {'id': 'test', 'enabled': true, 'has_download_provider': false},
        ],
      });
    });
    final song = MornyeExtensionService.parseTracks('test', [
      {'id': '1', 'name': 'Test'},
    ]).single;
    expect(
      MornyeExtensionService(channel: channel).resolve(song),
      throwsA(isA<MornyeExtensionException>()),
    );
  });
}
