import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:just_audio/just_audio.dart';
import 'package:retropod/core/services/http_addon_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('retropod/http_addon');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));
  final config = {
    'id': 'local-id',
    'url': 'https://provider.example/a/private-token',
    'name': 'Example',
    'settings': <String, String>{},
  };

  test('normalizes manifest URLs and rejects dashboard or credential URLs', () {
    expect(
      HttpAddonService.baseUrl(
        'https://provider.example/a/token/manifest.json/',
      ).toString(),
      'https://provider.example/a/token',
    );
    for (final value in [
      HttpAddonService.setupWebsite,
      'http://provider.example/a/token',
      'https://user:password@provider.example',
    ]) {
      expect(
        () => HttpAddonService.baseUrl(value),
        throwsA(isA<HttpAddonException>()),
      );
    }
  });

  test(
    'search and fresh stream resolution preserve IDs and hide private endpoint',
    () async {
      final calls = <Uri>[];
      final client = MockClient((request) async {
        calls.add(request.url);
        expect(request.followRedirects, isFalse);
        expect(request.headers.containsKey('cookie'), isFalse);
        expect(request.url.queryParameters.containsKey('quality'), isFalse);
        expect(request.url.queryParameters.containsKey('atmos'), isFalse);
        if (request.url.path.endsWith('/search')) {
          expect(request.url.queryParameters['q'], 'A song');
          return http.Response(
            jsonEncode({
              'tracks': [
                {
                  'id': 'track/1',
                  'title': 'A song (Live)',
                  'artist': 'Artist',
                  'duration': 120,
                  'artworkURL': 'https://art.example/a.jpg',
                },
                {'title': 'Missing ID'},
              ],
            }),
            200,
          );
        }
        expect(request.url.pathSegments.last, 'track/1');
        return http.Response(
          jsonEncode({
            'stream': {'url': 'https://audio.example/fresh.flac'},
          }),
          200,
        );
      });
      addTearDown(client.close);
      final service = HttpAddonService(
        client,
        configuration: () async => config,
      );
      final song = (await service.search(' A song ')).single;
      expect(song.trackName, 'A song (Live)');
      expect(song.trackDuration, 120000);
      expect(song.filePath, isNot(contains('private-token')));
      expect(
        (await service.resolve(song)).filePath,
        'https://audio.example/fresh.flac',
      );
      expect(calls.length, 2);
      expect(song.filePath, startsWith('retropod://addon/'));
    },
  );

  test('does not resolve old results against a replacement provider', () async {
    var current = config;
    final client = MockClient(
      (_) async => http.Response('[{"id":"1","title":"Song"}]', 200),
    );
    addTearDown(client.close);
    final service = HttpAddonService(
      client,
      configuration: () async => current,
    );
    final song = (await service.search('Song')).single;
    current = {...config, 'id': 'replacement'};
    await expectLater(
      service.resolve(song),
      throwsA(
        predicate<HttpAddonException>(
          (e) => e.message.contains('ADDON_CHANGED'),
        ),
      ),
    );
  });

  test(
    'rejects encrypted and hybrid streams rather than passing them to playback',
    () async {
      for (final protection in [
        {'encrypted': true},
        {
          'hybrid': {'key': 'secret'},
        },
      ]) {
        final client = MockClient(
          (request) async => request.url.path.endsWith('/search')
              ? http.Response('[{"id":"1","title":"Song"}]', 200)
              : http.Response(
                  jsonEncode({
                    ...protection,
                    'url': 'https://audio.example/encrypted',
                  }),
                  200,
                ),
        );
        addTearDown(client.close);
        final service = HttpAddonService(
          client,
          configuration: () async => config,
        );
        final song = (await service.search('Song')).single;
        await expectLater(
          service.resolve(song),
          throwsA(
            predicate<HttpAddonException>(
              (e) =>
                  e.message.contains('ADDON_UNSUPPORTED') &&
                  !e.message.contains('secret'),
            ),
          ),
        );
      }
    },
  );

  test('HTTP failures do not expose tokens or provider bodies', () async {
    final client = MockClient(
      (_) async => http.Response('private-token secret', 403),
    );
    addTearDown(client.close);
    final service = HttpAddonService(client, configuration: () async => config);
    await expectLater(
      service.search('Song'),
      throwsA(
        predicate<HttpAddonException>(
          (e) =>
              e.message.contains('403') &&
              !e.message.contains('secret') &&
              !e.message.contains('private-token'),
        ),
      ),
    );
  });

  test(
    'validates manifest before storing endpoint through native channel',
    () async {
      final calls = <String>[];
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call.method);
        expect(call.arguments, {
          'url': 'https://provider.example/a/token',
          'name': 'Test provider',
          'settings': <String, String>{},
        });
        return '{}';
      });
      final client = MockClient((request) async {
        expect(request.url.path, '/a/token/manifest.json');
        return http.Response(
          '{"id":"test","name":"Test provider","resources":["search","stream"]}',
          200,
        );
      });
      addTearDown(client.close);
      await HttpAddonService(
        client,
      ).configure('https://provider.example/a/token/manifest.json');
      expect(calls, ['set']);
    },
  );

  test('HTML dashboard cannot be saved as an add-on', () async {
    messenger.setMockMethodCallHandler(
      channel,
      (_) async => fail('Must not save invalid manifest'),
    );
    final client = MockClient(
      (_) async => http.Response('<html>Account required</html>', 200),
    );
    addTearDown(client.close);
    await expectLater(
      HttpAddonService(client).configure('https://provider.example'),
      throwsA(isA<HttpAddonException>()),
    );
  });

  test('settles declared defaults including untyped settings', () {
    expect(
      HttpAddonService.manifestSettings({
        'settings': [
          {
            'key': 'quality',
            'default': 'HI_RES',
            'options': ['LOSSLESS', 'HI_RES'],
          },
          {'key': 'region', 'default': 'IN'},
          {
            'key': 'mode',
            'default': 'invalid',
            'options': [
              {'value': 'direct'},
            ],
          },
          {'key': 'enabled', 'type': 'boolean'},
          {'key': 'q', 'default': 'wrong song'},
        ],
      }),
      {
        'quality': 'HI_RES',
        'region': 'IN',
        'mode': 'direct',
        'enabled': 'false',
      },
    );
  });

  test(
    'legacy endpoints load manifest settings for search and exact-ID stream',
    () async {
      final client = MockClient((request) async {
        expect(request.url.queryParameters['token'], 'private');
        if (request.url.path.endsWith('/manifest.json')) {
          return http.Response(
            jsonEncode({
              'settings': [
                {'key': 'quality', 'default': 'HI_RES'},
                {'key': 'region', 'default': 'IN'},
              ],
            }),
            200,
          );
        }
        expect(request.url.queryParameters['quality'], 'HI_RES');
        expect(request.url.queryParameters['region'], 'IN');
        expect(request.url.queryParameters.containsKey('atmos'), isFalse);
        if (request.url.path.endsWith('/search')) {
          return http.Response(
            jsonEncode({
              'tracks': [
                {'id': 'first', 'title': 'Other song'},
                {
                  'id': 'weeknd/track?1',
                  'title': 'Blinding Lights',
                  'artist': 'The Weeknd',
                },
              ],
            }),
            200,
          );
        }
        expect(request.url.pathSegments.last, 'weeknd/track?1');
        return http.Response(
          jsonEncode({
            'stream': 'media/selected',
            'format': 'dash',
            'headers': {'Authorization': 'Bearer playback-secret'},
          }),
          200,
        );
      });
      addTearDown(client.close);
      final legacy = {...config}..remove('settings');
      legacy['url'] = 'https://provider.example/a/token?token=private';
      final service = HttpAddonService(
        client,
        configuration: () async => legacy,
      );
      final selected = (await service.search('Blinding Lights The Weeknd'))[1];
      final playable = await service.resolve(selected);
      expect(playable.trackName, 'Blinding Lights');
      expect(
        playable.filePath,
        'https://provider.example/a/token/media/selected',
      );
      expect(playable.mimeType, 'application/dash+xml');
      final audio = playable.toAudioSource() as DashAudioSource;
      expect(audio.headers, {'Authorization': 'Bearer playback-secret'});
      expect(playable.toJson(), isNot(contains('playback-secret')));
      expect(playable.toString(), isNot(contains('playback-secret')));
      expect(selected.filePath, isNot(contains('private')));
    },
  );

  test('HLS MIME and relative URL survive wrapped stream responses', () async {
    final client = MockClient(
      (request) async => http.Response(
        jsonEncode(
          request.url.path.endsWith('/search')
              ? [
                  {'id': '1', 'title': 'Song'},
                ]
              : {
                  'data': {
                    'url': '/audio/live',
                    'mime': 'application/x-mpegURL',
                    'headers': {},
                  },
                },
        ),
        200,
      ),
    );
    addTearDown(client.close);
    final service = HttpAddonService(client, configuration: () async => config);
    final playable = await service.resolve(
      (await service.search('Song')).single,
    );
    expect(playable.filePath, 'https://provider.example/audio/live');
    expect(playable.toAudioSource(), isA<HlsAudioSource>());
  });

  test('rejects header injection without disclosing credentials', () async {
    final client = MockClient(
      (request) async => http.Response(
        jsonEncode(
          request.url.path.endsWith('/search')
              ? [
                  {'id': '1', 'title': 'Song'},
                ]
              : {
                  'url': 'https://audio.example/song',
                  'headers': {'X-Test': 'secret\r\nInjected: yes'},
                },
        ),
        200,
      ),
    );
    addTearDown(client.close);
    final service = HttpAddonService(client, configuration: () async => config);
    await expectLater(
      service.resolve((await service.search('Song')).single),
      throwsA(
        predicate<HttpAddonException>(
          (e) =>
              e.message.contains('ADDON_HEADERS') &&
              !e.message.contains('secret'),
        ),
      ),
    );
  });
}
