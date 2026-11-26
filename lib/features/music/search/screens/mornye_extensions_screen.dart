import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:retropod/core/services/mornye_extension_service.dart';

class MornyeExtensionsScreen extends StatefulWidget {
  const MornyeExtensionsScreen({super.key});
  @override
  State<MornyeExtensionsScreen> createState() => _MornyeExtensionsScreenState();
}

class _MornyeExtensionsScreenState extends State<MornyeExtensionsScreen> {
  final _service = MornyeExtensionService.instance;
  List<Map<String, dynamic>> _installed = [];
  List<Map<String, dynamic>> _catalog = [];
  bool _busy = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_refresh());
  }

  Future<void> _refresh() async {
    await _run(() async {
      _installed = await _service.installed();
      // Installed extensions remain usable if the repository is unavailable.
      try {
        _catalog = await _service.registry();
      } catch (_) {
        _error = 'Catalog unavailable. Installed extensions are still listed.';
      }
    });
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } catch (e) {
      _error = e is MornyeExtensionException
          ? e.message
          : 'Extension operation failed.';
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _install(Map<String, dynamic> entry) => _run(() async {
    final prepared =
        await _service.call('prepare', {
              'url': entry['download_url'],
              'sha256': entry['sha256'],
              'id': entry['id'],
              'version': entry['version'],
            })
            as Map;
    final manifest = prepared['manifest'] as Map;
    bool accepted = false;
    try {
      if (!mounted) return;
      accepted =
          await showCupertinoDialog<bool>(
            context: context,
            builder: (context) => CupertinoAlertDialog(
              title: Text('Install ${manifest['displayName'] ?? entry['id']}?'),
              content: SingleChildScrollView(
                child: Text(
                  'Third-party extension code runs on this device.\n\n'
                  'Requested permissions:\n${_permissions(manifest['permissions'])}\n\n'
                  'Some providers need their own account or verification. '
                  'Browser sign-in and Mornye session grants are not supported yet.',
                ),
              ),
              actions: [
                CupertinoDialogAction(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Cancel'),
                ),
                CupertinoDialogAction(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('Install'),
                ),
              ],
            ),
          ) ??
          false;
    } finally {
      await _service.call(accepted ? 'install' : 'discard', {
        'token': prepared['token'],
      });
    }
    _installed = await _service.installed();
  });

  String _permissions(Object? value) {
    if (value is! Map) return 'No declared permissions';
    final domains = value['network'];
    return [
      if (domains is List && domains.isNotEmpty)
        'Network: ${domains.join(', ')}',
      if (value['storage'] == true) 'Private extension storage',
      if (value['file'] == true) 'Private audio and extension files',
      if (value['allowHttp'] == true) 'Unencrypted HTTP requests',
    ].join('\n');
  }

  Future<void> _settings(Map<String, dynamic> extension) async {
    await _run(() async {
      final current = Map<String, dynamic>.from(
        await _service.call('settings', {'id': extension['id']}) as Map,
      );
      if (!mounted) return;
      await Navigator.of(context).push<void>(
        CupertinoPageRoute(
          builder: (_) =>
              _ExtensionSettings(extension: extension, values: current),
        ),
      );
      _installed = await _service.installed();
    });
  }

  @override
  Widget build(BuildContext context) => CupertinoPageScaffold(
    navigationBar: const CupertinoNavigationBar(
      middle: Text('Mornye extensions'),
    ),
    child: SafeArea(
      child: Column(
        children: [
          if (_busy) const CupertinoActivityIndicator(),
          if (_error != null)
            Padding(padding: const EdgeInsets.all(8), child: Text(_error!)),
          Expanded(
            child: ListView(
              children: [
                const Padding(
                  padding: EdgeInsets.all(12),
                  child: Text(
                    'Install an extension, then select Use for search. Audio providers '
                    'prepare a file before playback. Account sign-in is not supported yet.',
                    style: TextStyle(fontSize: 13),
                  ),
                ),
                CupertinoButton(
                  child: const Text('Runtime licenses'),
                  onPressed: () async {
                    final notice = await rootBundle.loadString(
                      'assets/licenses/MORNYE-NOTICE.txt',
                    );
                    final lgpl = await rootBundle.loadString(
                      'assets/licenses/MORNYE-LGPL-3.0.txt',
                    );
                    final gpl = await rootBundle.loadString(
                      'assets/licenses/MORNYE-GPL-3.0.txt',
                    );
                    if (!context.mounted) return;
                    await Navigator.of(context).push<void>(
                      CupertinoPageRoute(
                        builder: (_) => CupertinoPageScaffold(
                          navigationBar: const CupertinoNavigationBar(
                            middle: Text('Runtime licenses'),
                          ),
                          child: SafeArea(
                            child: SingleChildScrollView(
                              padding: const EdgeInsets.all(16),
                              child: Text('$notice\n$lgpl\n$gpl'),
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
                ..._installed.map(
                  (entry) => CupertinoListSection.insetGrouped(
                    header: Text(
                      '${entry['display_name']} · ${entry['version']}',
                    ),
                    children: [
                      CupertinoListTile(
                        title: const Text('Enabled'),
                        subtitle: Text(entry['status']?.toString() ?? ''),
                        trailing: CupertinoSwitch(
                          value: entry['enabled'] == true,
                          onChanged: _busy
                              ? null
                              : (enabled) => _run(() async {
                                  await _service.call('enable', {
                                    'id': entry['id'],
                                    'enabled': enabled,
                                  });
                                  _installed = await _service.installed();
                                }),
                        ),
                      ),
                      CupertinoListTile(
                        title: const Text('Use for search'),
                        subtitle: Text(
                          entry['has_download_provider'] == true
                              ? 'Audio provider'
                              : 'Metadata only; cannot play audio',
                        ),
                        onTap:
                            !_busy &&
                                entry['enabled'] == true &&
                                entry['status'] != 'error' &&
                                entry['has_metadata_provider'] == true
                            ? () => Navigator.pop(context, entry)
                            : null,
                      ),
                      CupertinoListTile(
                        title: const Text('Settings'),
                        onTap: _busy ? null : () => _settings(entry),
                      ),
                      CupertinoListTile(
                        title: const Text('Remove'),
                        onTap: _busy
                            ? null
                            : () => _run(() async {
                                await _service.call('remove', {
                                  'id': entry['id'],
                                });
                                _installed = await _service.installed();
                              }),
                      ),
                    ],
                  ),
                ),
                CupertinoListSection.insetGrouped(
                  header: const Text('Mornye catalog'),
                  children: _catalog.map((entry) {
                    final same = _installed.any(
                      (item) =>
                          item['id'] == entry['id'] &&
                          item['version'] == entry['version'],
                    );
                    return CupertinoListTile(
                      title: Text(
                        entry['display_name']?.toString() ??
                            entry['id'].toString(),
                      ),
                      subtitle: Text(
                        '${entry['version']} · ${entry['category']}',
                      ),
                      trailing: Text(same ? 'Installed' : 'Install/update'),
                      onTap: _busy || same ? null : () => _install(entry),
                    );
                  }).toList(),
                ),
              ],
            ),
          ),
          CupertinoButton(
            onPressed: _busy ? null : _refresh,
            child: const Text('Refresh'),
          ),
        ],
      ),
    ),
  );
}

class _ExtensionSettings extends StatefulWidget {
  const _ExtensionSettings({required this.extension, required this.values});
  final Map<String, dynamic> extension;
  final Map<String, dynamic> values;
  @override
  State<_ExtensionSettings> createState() => _ExtensionSettingsState();
}

class _ExtensionSettingsState extends State<_ExtensionSettings> {
  late final _values = Map<String, dynamic>.from(widget.values);
  bool _saving = false;
  String? _error;
  @override
  Widget build(BuildContext context) {
    final definitions = (widget.extension['settings'] as List? ?? [])
        .whereType<Map>();
    return CupertinoPageScaffold(
      navigationBar: const CupertinoNavigationBar(
        middle: Text('Extension settings'),
      ),
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            for (final field in definitions)
              if (field['key'] is String &&
                  !(field['key'] as String).startsWith('_'))
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _field(field),
                ),
            if (definitions.isEmpty)
              const Text('This extension has no settings.'),
            if (_error != null) Text(_error!),
            CupertinoButton.filled(
              onPressed: _saving
                  ? null
                  : () async {
                      setState(() => _saving = true);
                      try {
                        await MornyeExtensionService.instance.call(
                          'saveSettings',
                          {'id': widget.extension['id'], 'settings': _values},
                        );
                        if (context.mounted) Navigator.pop(context);
                      } catch (_) {
                        if (mounted) {
                          setState(() {
                            _saving = false;
                            _error = 'Could not apply settings.';
                          });
                        }
                      }
                    },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _field(Map field) {
    final key = field['key'] as String;
    final label = field['label']?.toString() ?? key;
    final value = _values[key] ?? field['default'];
    if (field['type'] == 'boolean' || field['type'] == 'bool') {
      return Row(
        children: [
          Expanded(child: Text(label)),
          CupertinoSwitch(
            value: value == true,
            onChanged: _saving ? null : (v) => setState(() => _values[key] = v),
          ),
        ],
      );
    }
    if (field['type'] == 'action') {
      return Text('$label: extension actions are not supported yet.');
    }
    if (field['options'] is List && (field['options'] as List).isNotEmpty) {
      return CupertinoButton(
        onPressed: _saving
            ? null
            : () async {
                final selected = await showCupertinoModalPopup<Object>(
                  context: context,
                  builder: (context) => CupertinoActionSheet(
                    title: Text(label),
                    actions: [
                      for (final option
                          in (field['options'] as List).whereType<Map>())
                        CupertinoActionSheetAction(
                          onPressed: () =>
                              Navigator.pop(context, option['value']),
                          child: Text(
                            option['label']?.toString() ?? '${option['value']}',
                          ),
                        ),
                    ],
                    cancelButton: CupertinoActionSheetAction(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Cancel'),
                    ),
                  ),
                );
                if (selected != null && mounted) {
                  setState(() => _values[key] = selected);
                }
              },
        child: Text('$label: ${value ?? ''}'),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label),
        CupertinoTextFormFieldRow(
          initialValue: value?.toString() ?? '',
          obscureText: field['secret'] == true || field['type'] == 'password',
          autocorrect: false,
          enableSuggestions: false,
          enabled: !_saving,
          onChanged: (v) =>
              _values[key] = field['type'] == 'number' ? num.tryParse(v) : v,
        ),
      ],
    );
  }
}
