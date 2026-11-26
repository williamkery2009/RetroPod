import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:retropod/core/models/music_metadata.dart';
import 'package:retropod/core/navigation/routes.dart';
import 'package:retropod/core/services/audio_player_service.dart';
import 'package:retropod/core/services/online_music_service.dart';
import 'package:retropod/core/services/youtube_music_service.dart';
import 'package:retropod/core/services/youtube_playback_error.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:retropod/core/widgets/input_text_bar.dart';
import 'package:retropod/features/custom_screen_elements/custom_input_text_screen.dart';
import 'package:retropod/features/now_playing/models/now_playing_model.dart';
import 'package:retropod/features/now_playing/provider/now_playing_details_provider.dart';
import 'package:retropod/features/status_bar/widgets/status_bar.dart';

class OnlineMusicScreen extends ConsumerStatefulWidget {
  const OnlineMusicScreen({super.key});

  @override
  ConsumerState<OnlineMusicScreen> createState() => _OnlineMusicScreenState();
}

class _OnlineMusicScreenState extends ConsumerState<OnlineMusicScreen>
    with CustomInputTextScreen {
  MusicSource _source = MusicSource.itunes;
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
    _debounce = Timer(const Duration(milliseconds: 500), () async {
      try {
        final results = await ref
            .read(onlineMusicServiceProvider)
            .search(source, value);
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
          _message = 'Source unavailable. Tap here to retry.';
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
            YoutubeMusicService.videoIdFor(song) != null
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
                  ? 'Source: ${_source.label}'
                  : index == 1
                  ? 'Search: $inputText'
                  : song!.getTrackName;
              final subtitle = index == 0
                  ? 'Select to change source'
                  : index == 1
                  ? 'Select to edit search'
                  : '${song!.getMainArtistName} · ${_source == MusicSource.radio
                        ? 'Live radio'
                        : _source == MusicSource.youtubeMusic
                        ? 'YouTube Music'
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
