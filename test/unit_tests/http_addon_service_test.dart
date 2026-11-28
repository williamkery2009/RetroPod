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

  test('lists manifest choices and saves one under the same ID', () async {
    Object? saved;
    messenger.setMockMethodCallHandler(channel, (call) async {
      saved = call.arguments;
      return '{}';
    });
    final client = MockClient(
      (_) async => http.Response(
        jsonEncode({
          'settings': [
            {
              'key': 'quality',
              'type': 'select',
              'default': 'lossless',
              'options': [
                {'label': 'Lossless', 'value': 'lossless'},
                {'label': 'High', 'value': 'high'},
              ],
            },
          ],
        }),
        200,
      ),
    );
    addTearDown(client.close);
    final service = HttpAddonService(client, configuration: () async => config);
    final setting = (await service.editableSettings()).single;
    expect(setting.value, 'lossless');
    expect(setting.options, {'lossless': 'Lossless', 'high': 'High'});
    await service.updateSetting('quality', 'high');
    expect(saved, {
      'id': 'local-id',
      'url': config['url'],
      'name': 'Example',
      'settings': {'quality': 'high'},
    });
  });

  test('rejects prank files sent in place of the requested song', () async {
    final client = MockClient(
      (request) async => http.Response(
        jsonEncode(
          request.url.path.endsWith('/search')
              ? [
                  {'id': '1', 'title': 'Song'},
                ]
              : {
                  'url':
                      'https://cdn.jsdelivr.net/gh/someone/pranks-cdn@main/a.mp3',
                  'format': 'flac',
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
          (e) => e.message.contains('ADDON_DECOY'),
        ),
      ),
    );
  });

  test('reads artist lists, album objects and other duration shapes', () async {
    final client = MockClient(
      (_) async => http.Response(
        jsonEncode({
          'results': [
            {
              'id': 'a',
              'name': 'First',
              'artists': [
                {'name': 'One'},
                'Two',
              ],
              'album': {'title': 'Record'},
              'duration': '3:21',
            },
            {'id': 'b', 'title': 'Second', 'durationMs': 90500},
          ],
        }),
        200,
      ),
    );
    addTearDown(client.close);
    final songs = await HttpAddonService(
      client,
      configuration: () async => config,
    ).search('x');
    expect(songs.first.trackName, 'First');
    expect(songs.first.trackArtistNames, ['One', 'Two']);
    expect(songs.first.albumName, 'Record');
    expect(songs.first.trackDuration, 201000);
    expect(songs.last.trackDuration, 90500);
  });

  test('retries a gateway failure once', () async {
    var calls = 0;
    final client = MockClient(
      (_) async => ++calls == 1
          ? http.Response('', 503)
          : http.Response('[{"id":"1","title":"Song"}]', 200),
    );
    addTearDown(client.close);
    final songs = await HttpAddonService(
      client,
      configuration: () async => config,
    ).search('x');
    expect(songs, hasLength(1));
    expect(calls, 2);
  });

  test('stops asking a rate limited provider until Retry-After', () async {
    var calls = 0;
    final client = MockClient((_) async {
      calls++;
      return http.Response('', 429, headers: {'retry-after': '60'});
    });
    addTearDown(client.close);
    final service = HttpAddonService(
      client,
      configuration: () async => {
        ...config,
        'url': 'https://limited.example/a',
      },
    );
    for (var i = 0; i < 2; i++) {
      await expectLater(
        service.search('x'),
        throwsA(
          predicate<HttpAddonException>(
            (e) => e.message.contains('ADDON_RATE_LIMIT'),
          ),
        ),
      );
    }
    expect(calls, 1);
  });

  test('offers on/off and free text settings', () async {
    final client = MockClient(
      (_) async => http.Response(
        jsonEncode({
          'settings': [
            {'key': 'explicit', 'type': 'toggle'},
            {'key': 'region', 'type': 'text'},
          ],
        }),
        200,
      ),
    );
    addTearDown(client.close);
    final settings = await HttpAddonService(
      client,
      configuration: () async => config,
    ).editableSettings();
    expect(settings.first.options, {'true': 'On', 'false': 'Off'});
    expect(settings.first.value, 'false');
    expect(settings.last.options, isEmpty);
    expect(settings.last.value, '');
  });
}
