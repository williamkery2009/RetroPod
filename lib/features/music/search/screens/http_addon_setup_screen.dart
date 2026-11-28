import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:http/http.dart' as http;
import 'package:retropod/core/services/http_addon_service.dart';
import 'package:url_launcher/url_launcher.dart';

class HttpAddonSetupScreen extends StatefulWidget {
  const HttpAddonSetupScreen({super.key});
  @override
  State<HttpAddonSetupScreen> createState() => _HttpAddonSetupScreenState();
}

class _HttpAddonSetupScreenState extends State<HttpAddonSetupScreen> {
  final _url = TextEditingController();
  final _client = http.Client();
  String? _name;
  String? _message;
  bool _busy = false;
  List<HttpAddonSetting> _settings = const [];

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      final config = await HttpAddonService.readConfiguration();
      if (mounted) setState(() => _name = config?['name'] as String?);
      if (config != null) await _loadSettings();
    } catch (_) {
      if (mounted) {
        setState(
          () => _message =
              'Could not read the saved add-on. You can remove it or connect again.',
        );
      }
    }
  }

  Future<void> _loadSettings() async {
    try {
      final settings = await HttpAddonService(_client).editableSettings();
      if (mounted) setState(() => _settings = settings);
    } catch (error) {
      if (mounted) {
        setState(() {
          _settings = const [];
          _message = error is HttpAddonException
              ? error.message
              : 'Could not load add-on settings.';
        });
      }
    }
  }

  Future<void> _choose(String key, String value) async {
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await HttpAddonService(_client).updateSetting(key, value);
      await _loadSettings();
    } catch (error) {
      if (mounted) {
        setState(
          () => _message = error is HttpAddonException
              ? error.message
              : 'Could not save the add-on setting.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save() async {
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await HttpAddonService(_client).configure(_url.text);
      if (!mounted) return;
      _url.clear();
      await _load();
      if (mounted) {
        setState(
          () => _message =
              'Manifest checked and URL saved securely. Search and playback still need testing.',
        );
      }
    } catch (error) {
      if (mounted) {
        setState(
          () => _message = error is HttpAddonException
              ? error.message
              : 'Could not connect this add-on.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _url.dispose();
    _client.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => CupertinoPageScaffold(
    navigationBar: const CupertinoNavigationBar(middle: Text('Custom add-on')),
    child: SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Text(
            'LastWave Addons',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          const Text(
            'Create an account and complete the provider’s verification on its website. Copy your personal add-on URL from the dashboard, then paste it here. The website homepage is not a streaming URL.',
          ),
          CupertinoButton(
            onPressed: _busy
                ? null
                : () async {
                    final opened = await launchUrl(
                      Uri.parse(HttpAddonService.setupWebsite),
                      mode: LaunchMode.externalApplication,
                    );
                    if (!opened && mounted) {
                      setState(
                        () => _message = 'Could not open the setup website.',
                      );
                    }
                  },
            child: const Text('Open setup website'),
          ),
          if (_name != null) Text('Configured: $_name'),
          for (final setting in _settings) ...[
            const SizedBox(height: 12),
            Text(
              setting.label,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            if (setting.options.isEmpty)
              CupertinoTextFormFieldRow(
                key: ValueKey('${setting.key}=${setting.value}'),
                initialValue: setting.value,
                obscureText: setting.secret,
                autocorrect: false,
                enabled: !_busy,
                placeholder: 'Type a value, then press done',
                onFieldSubmitted: (value) =>
                    _choose(setting.key, value.trim()),
              ),
            for (final option in setting.options.entries)
              CupertinoButton(
                padding: const EdgeInsets.symmetric(vertical: 4),
                onPressed: _busy || option.key == setting.value
                    ? null
                    : () => _choose(setting.key, option.key),
                child: Row(
                  children: [
                    Expanded(child: Text(option.value)),
                    if (option.key == setting.value)
                      const Icon(CupertinoIcons.check_mark),
                  ],
                ),
              ),
          ],
          const SizedBox(height: 12),
          CupertinoTextField(
            controller: _url,
            obscureText: true,
            autocorrect: false,
            enableSuggestions: false,
            enabled: !_busy,
            keyboardType: TextInputType.url,
            placeholder: 'Personal add-on URL',
          ),
          const SizedBox(height: 12),
          const Text(
            'Your URL may contain an account token. It is encrypted on this device. The provider receives your searches and track IDs. Google sessions are never shared with it.',
          ),
          const SizedBox(height: 12),
          const Text(
            'Supports direct HTTPS streams. Lastwave-only app authorization and encrypted/hybrid streams are not supported. A successful connection check does not guarantee playback.',
          ),
          if (_message != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(_message!),
            ),
          if (_busy) const CupertinoActivityIndicator(),
          CupertinoButton.filled(
            onPressed: _busy ? null : _save,
            child: const Text('Check and save'),
          ),
          if (_name != null)
            CupertinoButton(
              onPressed: _busy ? null : () => Navigator.pop(context, true),
              child: const Text('Use this add-on'),
            ),
          CupertinoButton(
            onPressed: _busy
                ? null
                : () async {
                    setState(() => _busy = true);
                    try {
                      await HttpAddonService.remove();
                      if (mounted) {
                        setState(() {
                          _name = null;
                          _settings = const [];
                          _message = 'Private URL removed.';
                        });
                      }
                    } catch (_) {
                      if (mounted) {
                        setState(
                          () => _message = 'Could not remove the add-on.',
                        );
                      }
                    } finally {
                      if (mounted) setState(() => _busy = false);
                    }
                  },
            child: const Text('Remove saved add-on'),
          ),
        ],
      ),
    ),
  );
}
