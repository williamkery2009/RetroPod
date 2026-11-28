import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:retropod/core/extensions/build_context_extensions.dart';
import 'package:retropod/core/navigation/routes.dart';
import 'package:retropod/core/services/online_music_service.dart';
import 'package:retropod/core/widgets/options_list_tile.dart';
import 'package:retropod/features/custom_screen_elements/custom_screen.dart';
import 'package:retropod/features/music/album/providers/album_details_provider.dart';
import 'package:retropod/features/music/playlist/providers/playlists_provider.dart';
import 'package:retropod/features/music/songs/screens/song_edit_screen.dart';
import 'package:retropod/features/now_playing/provider/now_playing_details_provider.dart';

enum _NowPlayingMoreOptions {
  addToOnTheGo,
  browseAlbum,
  browseArtist,
  editSong,
  findLyrics,
  sleepTimer,
  cancel;

  String title(BuildContext context) {
    switch (this) {
      case addToOnTheGo:
        return context.localization.addToOnTheGoPlaylist;
      case browseAlbum:
        return context.localization.browseAlbum;
      case browseArtist:
        return context.localization.browseArtist;
      case findLyrics:
        return 'Find lyrics (LRCLIB)';
      case editSong:
        return context.localization.editSongOption;
      case sleepTimer:
        return context.localization.sleepTimerTitle;
      case cancel:
        return context.localization.cancelText;
    }
  }
}

class NowPlayingMoreOptionsModal extends ConsumerStatefulWidget {
  const NowPlayingMoreOptionsModal({super.key});

  @override
  ConsumerState createState() => _NowPlayingMoreOptionsModalState();
}

class _NowPlayingMoreOptionsModalState
    extends ConsumerState<NowPlayingMoreOptionsModal>
    with CustomScreen {
  bool _findingLyrics = false;

  @override
  String get routeName => Routes.nowPlayingMoreOptions.name;

  @override
  List<_NowPlayingMoreOptions> get displayItems =>
      _NowPlayingMoreOptions.values;

  @override
  Future<void> onSelectPressed() =>
      _navigateToScreen(_NowPlayingMoreOptions.values[selectedDisplayItem]);

  Future<void> _navigateToScreen(_NowPlayingMoreOptions optionItem) async {
    if (_findingLyrics) return;
    setState(() => selectedDisplayItem = displayItems.indexOf(optionItem));
    final currentSongMetadata = ref
        .read(nowPlayingDetailsProvider)
        .currentMetadata;
    switch (optionItem) {
      case _NowPlayingMoreOptions.addToOnTheGo:
        ref
            .read(playlistsProvider.notifier)
            .addSongToPlaylist(currentSongMetadata);
        context.pop();
        break;
      case _NowPlayingMoreOptions.browseAlbum:
        final albumDetailIndex = ref
            .read(albumDetailsProvider)
            .indexWhere((e) => e == currentSongMetadata?.getAlbumDetail);
        if (albumDetailIndex != -1) {
          await context.pushNamed(
            Routes.albumSongs.name,
            extra: ref.read(albumDetailsProvider)[albumDetailIndex],
          );
        }
        break;
      case _NowPlayingMoreOptions.browseArtist:
        await context.pushNamed(
          Routes.artistAlbums.name,
          pathParameters: {
            "artistName":
                currentSongMetadata?.getMainArtistName ?? "Unknown Artist",
          },
        );
        break;
      case _NowPlayingMoreOptions.editSong:
        if (currentSongMetadata == null) {
          context.pop();
          return;
        }
        await showCupertinoDialog(
          context: context,
          builder: (dialogContext) =>
              SongEditScreen(songMetadata: currentSongMetadata),
        );
        if (mounted) {
          context.pop();
        }
        break;
      case _NowPlayingMoreOptions.findLyrics:
        if (currentSongMetadata == null) return;
        if (!currentSongMetadata.isOnDevice) {
          await _showLyricsMessage(
            'Lyrics lookup is for local songs. '
            'Previews do not start at the beginning of a recording.',
          );
          return;
        }
        if (currentSongMetadata.lyrics?.trim().isNotEmpty ?? false) {
          await _showLyricsMessage(
            'This song already has lyrics. '
            'Use Edit Song if you want to change them.',
          );
          return;
        }
        setState(() => _findingLyrics = true);
        try {
          final lyrics = await ref
              .read(onlineMusicServiceProvider)
              .findLyrics(currentSongMetadata);
          if (!mounted) return;
          if (lyrics == null) {
            await _showLyricsMessage(
              'No matching lyrics found. '
              'Check the song title, artist, album and duration.',
            );
          } else {
            // Do not overwrite lyrics edited while the request was running.
            final current = ref.read(nowPlayingDetailsProvider).currentMetadata;
            if (current?.filePath != currentSongMetadata.filePath ||
                (current?.lyrics?.trim().isNotEmpty ?? false)) {
              return;
            }
            await ref
                .read(nowPlayingDetailsProvider.notifier)
                .updateMetadata(current!.copyWith(lyrics: lyrics));
            if (mounted) await _showLyricsMessage('Lyrics added to this song.');
          }
        } catch (_) {
          if (mounted) {
            await _showLyricsMessage(
              'Lyrics service unavailable. Please try again.',
            );
          }
        } finally {
          if (mounted) setState(() => _findingLyrics = false);
        }
        break;
      case _NowPlayingMoreOptions.sleepTimer:
        await context.pushNamed(Routes.sleepTimer.name);
        break;
      case _NowPlayingMoreOptions.cancel:
        context.pop();
        break;
    }
  }

  Future<void> _showLyricsMessage(String message) => showCupertinoDialog<void>(
    context: context,
    builder: (context) => CupertinoAlertDialog(
      title: const Text('LRCLIB lyrics'),
      content: Text(message),
      actions: [
        CupertinoDialogAction(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('OK'),
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: context.appSurfaceColor,
        border: Border.all(color: context.appOutlineColor),
      ),
      child: ListView.builder(
        shrinkWrap: true,
        controller: scrollController,
        itemCount: displayItems.length,
        prototypeItem: const OptionsListTile(text: '', isSelected: false),
        itemBuilder: (context, index) {
          return OptionsListTile(
            text:
                _findingLyrics &&
                    displayItems[index] == _NowPlayingMoreOptions.findLyrics
                ? 'Finding lyrics...'
                : displayItems[index].title(context),
            isSelected: index == selectedDisplayItem,
            onTap: () async => _navigateToScreen(displayItems[index]),
          );
        },
      ),
    );
  }
}
