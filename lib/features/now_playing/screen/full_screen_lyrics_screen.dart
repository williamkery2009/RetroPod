import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:retropod/core/extensions/build_context_extensions.dart';
import 'package:retropod/core/services/audio_player_service.dart';
import 'package:retropod/features/now_playing/provider/now_playing_details_provider.dart';
import 'package:retropod/features/now_playing/widgets/fluid_art_background.dart';
import 'package:retropod/features/now_playing/widgets/lyrics_view.dart';
import 'package:retropod/features/now_playing/widgets/playback_progress_bar.dart';

/// Lyrics covering the whole phone, with playback controls.
class FullScreenLyricsScreen extends ConsumerStatefulWidget {
  const FullScreenLyricsScreen({super.key});

  @override
  ConsumerState<FullScreenLyricsScreen> createState() =>
      _FullScreenLyricsScreenState();
}

class _FullScreenLyricsScreenState
    extends ConsumerState<FullScreenLyricsScreen> {
  final ScrollController _scrollController = ScrollController();
  int? _songIndex;

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final details = ref.watch(nowPlayingDetailsProvider);
    final song = details.currentMetadata;
    final String? lyrics = song?.lyrics;

    // A new song starts from the top.
    if (_songIndex != song?.originalSongIndex) {
      _songIndex = song?.originalSongIndex;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollController.hasClients) {
          _scrollController.jumpTo(0);
        }
      });
    }

    return CupertinoTheme(
      data: CupertinoTheme.of(context).copyWith(brightness: Brightness.dark),
      child: CupertinoPageScaffold(
        child: Stack(
          fit: StackFit.expand,
          children: [
            FluidArtBackground(
              thumbnailPath: song?.thumbnailPath,
              isOnDevice: song?.isOnDevice ?? true,
            ),
            SafeArea(
              child: DefaultTextStyle(
                style: context.appTextStyle.copyWith(
                  color: CupertinoColors.white,
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Column(
                    children: [
                      _buildHeader(
                        song?.getTrackName ?? '',
                        song?.getTrackArtistNames ?? '',
                      ),
                      Expanded(
                        child: lyrics == null || lyrics.trim().isEmpty
                            ? const Center(
                                child: Icon(
                                  CupertinoIcons.music_note_2,
                                  size: 64,
                                  color: Color(0x80FFFFFF),
                                ),
                              )
                            : LyricsView(
                                key: ValueKey(song?.originalSongIndex),
                                lyrics: lyrics,
                                scrollController: _scrollController,
                                fontSize: 30,
                              ),
                      ),
                      const SizedBox(height: 8),
                      const PlaybackProgressBar(),
                      _buildControls(details.isPlaying),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(String title, String artist) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                artist,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 15,
                  color: Color(0x99FFFFFF),
                ),
              ),
            ],
          ),
        ),
        _buildButton(
          CupertinoIcons.chevron_down,
          () async => Navigator.of(context).maybePop(),
        ),
      ],
    );
  }

  Widget _buildControls(bool isPlaying) {
    final player = ref.read(audioPlayerServiceProvider.notifier);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _buildButton(CupertinoIcons.backward_fill, player.seekBackwards),
          _buildButton(
            isPlaying ? CupertinoIcons.pause_fill : CupertinoIcons.play_fill,
            player.togglePlayback,
            size: 44,
          ),
          _buildButton(CupertinoIcons.forward_fill, player.nextSong),
        ],
      ),
    );
  }

  Widget _buildButton(
    IconData icon,
    Future<void> Function() onPressed, {
    double size = 30,
  }) {
    return CupertinoButton(
      padding: const EdgeInsets.all(8),
      onPressed: onPressed,
      child: Icon(icon, size: size, color: CupertinoColors.white),
    );
  }
}
