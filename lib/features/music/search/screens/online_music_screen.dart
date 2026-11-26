import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:retropod/core/models/music_metadata.dart';
import 'package:retropod/core/navigation/routes.dart';
import 'package:retropod/core/services/audio_player_service.dart';
import 'package:retropod/core/services/jiosaavn_service.dart';
import 'package:retropod/core/services/mornye_extension_service.dart';
import 'package:retropod/core/services/online_music_service.dart';
import 'package:retropod/core/services/piped_service.dart';
import 'package:retropod/core/services/soundcloud_service.dart';
import 'package:retropod/core/services/youtube_music_service.dart';
import 'package:retropod/core/services/youtube_playback_error.dart';
import 'package:retropod/core/widgets/input_text_bar.dart';
import 'package:retropod/features/custom_screen_elements/custom_input_text_screen.dart';
import 'package:retropod/features/music/search/screens/mornye_extensions_screen.dart';
import 'package:retropod/features/now_playing/models/now_playing_model.dart';
import 'package:retropod/features/now_playing/provider/now_playing_details_provider.dart';
import 'package:retropod/features/status_bar/widgets/status_bar.dart';
import 'package:url_launcher/url_launcher.dart';

class OnlineMusicScreen extends ConsumerStatefulWidget {
  const OnlineMusicScreen({super.key});

  @override
  ConsumerState<OnlineMusicScreen> createState() => _OnlineMusicScreenState();
}

class _OnlineMusicScreenState extends ConsumerState<OnlineMusicScreen>
    with CustomInputTextScreen {
  MusicSource _source = MusicSource.itunes;
  Map<String, dynamic>? _extension;
  List<MusicMetadata> _results = [];
  Timer? _debounce;
  int _request = 0;
  bool _loading = false;
  bool _playing = false;
  String _message = 'Search for songs or radio stations.';

  @override
  String get routeName => Routes.onlineMusic.name;
  @override
  int get extraDisplayItems => 2;
  @override
  List<MusicMetadata> get displayItems => _results;

  void _search(String value) {
    _debounce?.cancel();
    final request = ++_request;
    setState(() {
      inputText = value;
      selectedDisplayItem = 0;
      _results = [];
      _loading = value.trim().isNotEmpty;
      _message = _loading ? 'Searching...' : 'Enter a search term.';
    });
    if (!_loading) return;
    final source = _source;
    final extension = _extension;
    _debounce = Timer(const Duration(milliseconds: 500), () async {
      try {
        final results = extension == null
            ? await ref.read(onlineMusicServiceProvider).search(source, value)
            : await MornyeExtensionService.instance.search(
                extension['id'] as String,
                value,
              );
        if (!mounted || request != _request) return;
        setState(() {
          _results = results;
          _loading = false;
          _message = results.isEmpty
              ? 'No playable results. Try another search or source.'
              : '${results.length} results';
        });
      } catch (_) {
        if (!mounted || request != _request) return;
        setState(() {
          _loading = false;
          _message = source == MusicSource.jiosaavn
              ? 'JioSaavn unavailable. Try changing JioSaavn server.'
              : 'Source unavailable. Tap here to retry.';
        });
      }
    });
  }

  @override
  Future<void> onSelectAction() => _select(selectedDisplayItem);

  Future<void> _select(int index) async {
    if (_playing) return;
    if (index == 0) {
      setState(() {
        _extension = null;
        _source =
            MusicSource.values[(_source.index + 1) % MusicSource.values.length];
      });
      _search(inputText);
      return;
    }
    if (index == 1) {
      setState(() => isInputTextBarActive = !isInputTextBarActive);
      return;
    }
    final resultIndex = index - 2;
    if (resultIndex < 0 || resultIndex >= _results.length) return;
    final song = _results[resultIndex];
    setState(() {
      _playing = true;
      selectedDisplayItem = index;
    });
    try {
      final player = ref.read(audioPlayerProvider);
      final details = ref.read(nowPlayingDetailsProvider.notifier);
      final playable = await ref
          .read(onlineMusicServiceProvider)
          .resolveForPlayback(song);
      if (!mounted) return;
      await player.setAudioSources([playable.toAudioSource()]);
      await player.setShuffleModeEnabled(false);
      // Keep the playback queue and its metadata in sync even if the user
      // leaves this screen while the stream is loading.
      details.setNewMetadataList(
        nowPlayingType: NowPlayingType.online,
        newMetadataList: [song],
      );
      // play() completes when playback ends, not when it starts.
      unawaited(
        player.play().catchError((Object error) {
          if (mounted) unawaited(_showPlaybackError(song, error));
        }),
      );
      if (mounted) await context.pushNamed(Routes.nowPlaying.name);
    } catch (error) {
      if (mounted) await _showPlaybackError(song, error);
    } finally {
      if (mounted) setState(() => _playing = false);
    }
  }

  Future<void> _showPlaybackError(MusicMetadata song, Object error) =>
      showCupertinoDialog<void>(
        context: context,
        builder: (context) => CupertinoAlertDialog(
          title: const Text('Unable to play'),
          content: Text(
            error is MornyeExtensionException
                ? error.message
                : error is SoundCloudException
                ? error.message
                : error is JioSaavnException
                ? error.message
                : YoutubeMusicService.videoIdFor(song) != null
                ? youtubePlaybackErrorMessage(error)
                : 'This stream is unavailable. Try another result.',
          ),
          actions: [
            if (YoutubeMusicService.videoIdFor(song) != null)
              CupertinoDialogAction(
                onPressed: () async {
                  await launchUrl(
                    Uri.parse(song.filePath!),
                    mode: LaunchMode.externalApplication,
                  );
                  if (context.mounted) Navigator.of(context).pop();
                },
                child: const Text('Open YouTube Music'),
              ),
            CupertinoDialogAction(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('OK'),
            ),
          ],
        ),
      );

  Future<void> _editProviderServer({bool jiosaavn = false}) async {
    final current = jiosaavn
        ? await JioSaavnService.configuredInstance()
        : await PipedService.configuredInstance();
    if (!mounted) return;
    final controller = TextEditingController(text: current.toString());
    String? validation;
    bool saving = false;
    await showCupertinoDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, update) => CupertinoAlertDialog(
          title: Text(jiosaavn ? 'JioSaavn API server' : 'Piped API server'),
          content: Column(
            children: [
              Text(
                jiosaavn
                    ? 'Use a compatible JioSaavn API base URL, including /api if required. '
                          'This server receives your searches and track IDs. Public servers may be unavailable.'
                    : 'This server receives the video IDs you play. '
                          'Use an HTTPS Piped API instance. Public servers may be unavailable.',
              ),
              CupertinoTextField(
                controller: controller,
                keyboardType: TextInputType.url,
                autocorrect: false,
                enabled: !saving,
              ),
              if (validation != null) Text(validation!),
            ],
          ),
          actions: [
            CupertinoDialogAction(
              onPressed: saving
                  ? null
                  : () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel'),
            ),
            CupertinoDialogAction(
              onPressed: saving
                  ? null
                  : () async {
                      update(() => saving = true);
                      try {
                        if (jiosaavn) {
                          await JioSaavnService.saveInstance(controller.text);
                        } else {
                          await PipedService.saveInstance(controller.text);
                        }
                        if (dialogContext.mounted) {
                          Navigator.of(dialogContext).pop();
                        }
                      } catch (_) {
                        if (dialogContext.mounted) {
                          update(() {
                            saving = false;
                            validation =
                                'Could not save. Enter an HTTPS API URL '
                                'without credentials, query or fragment.';
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
    // Keep the field controller alive until the closing animation finishes.
    await Future<void>.delayed(const Duration(milliseconds: 300));
    controller.dispose();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _request++;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => CupertinoPageScaffold(
    child: Column(
      children: [
        const StatusBar(title: 'Online Music'),
        Expanded(
          child: ListView.builder(
            controller: scrollController,
            itemCount: _results.length + 2,
            itemExtent: 54,
            itemBuilder: (context, index) {
              final song = index > 1 ? _results[index - 2] : null;
              final title = index == 0
                  ? 'Source: ${_extension?['display_name'] ?? _source.label}'
                  : index == 1
                  ? 'Search: $inputText'
                  : song!.getTrackName;
              final subtitle = index == 0
                  ? 'Select to change source'
                  : index == 1
                  ? 'Select to edit search'
                  : '${song!.getMainArtistName} · ${_extension != null
                        ? (_extension!['has_download_provider'] == true ? 'Extension audio' : 'Metadata only')
                        : _source == MusicSource.radio
                        ? 'Live radio'
                        : (_source == MusicSource.youtubeMusic || _source == MusicSource.youtubePiped)
                        ? 'YouTube Music'
                        : _source == MusicSource.audius
                        ? 'Audius · uploader'
                        : _source == MusicSource.soundcloud
                        ? 'SoundCloud · uploader'
                        : _source == MusicSource.jiosaavn
                        ? 'JioSaavn'
                        : 'Preview only'}';
              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => unawaited(_select(index)),
                child: ColoredBox(
                  color: index == selectedDisplayItem
                      ? CupertinoColors.activeBlue.withValues(alpha: 0.2)
                      : CupertinoColors.transparent,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        if (_source == MusicSource.youtubeMusic ||
            _source == MusicSource.youtubePiped)
          CupertinoButton(
            padding: EdgeInsets.zero,
            onPressed: _playing ? null : _editProviderServer,
            child: const Text('Piped server', style: TextStyle(fontSize: 12)),
          ),
        if (_source == MusicSource.jiosaavn)
          CupertinoButton(
            padding: EdgeInsets.zero,
            onPressed: _playing
                ? null
                : () => _editProviderServer(jiosaavn: true),
            child: const Text(
              'JioSaavn server',
              style: TextStyle(fontSize: 12),
            ),
          ),
        if (MornyeExtensionService.supported)
          CupertinoButton(
            padding: EdgeInsets.zero,
            onPressed: _playing
                ? null
                : () async {
                    final selected =
                        await Navigator.of(
                          context,
                          rootNavigator: true,
                        ).push<Map<String, dynamic>>(
                          CupertinoPageRoute(
                            builder: (_) => const MornyeExtensionsScreen(),
                          ),
                        );
                    if (selected != null && mounted) {
                      setState(() => _extension = selected);
                      _search(inputText);
                    }
                  },
            child: const Text('Extensions', style: TextStyle(fontSize: 12)),
          ),
        if (_playing && _extension != null)
          const Text(
            'Preparing extension audio...',
            style: TextStyle(fontSize: 11),
          ),
        if (_loading || _playing) const CupertinoActivityIndicator(),
        GestureDetector(
          onTap: () => _search(inputText),
          child: Padding(
            padding: const EdgeInsets.all(4),
            child: Text(_message, style: const TextStyle(fontSize: 11)),
          ),
        ),
        if (isInputTextBarActive)
          InputTextBar(
            inputTextBarController: inputTextBarController,
            onSearchTextChanged: _search,
          ),
      ],
    ),
  );
}
