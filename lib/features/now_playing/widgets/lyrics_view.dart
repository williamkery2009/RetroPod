import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/cupertino.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:retropod/core/models/lrc_lyrics.dart';
import 'package:retropod/core/services/audio_player_service.dart';
import 'package:retropod/features/now_playing/widgets/interlude_dots.dart';
import 'package:retropod/features/now_playing/widgets/karaoke_line.dart';

class LyricsView extends ConsumerStatefulWidget {
  final String? lyrics;
  final ScrollController scrollController;
  final String? thumbnailPath;
  final bool isOnDevice;

  const LyricsView({
    super.key,
    required this.lyrics,
    required this.scrollController,
    this.thumbnailPath,
    this.isOnDevice = true,
  });

  @override
  ConsumerState<LyricsView> createState() => _LyricsViewState();
}

class _LyricsViewState extends ConsumerState<LyricsView>
    with SingleTickerProviderStateMixin {
  /// Silences at least this long show [InterludeDots].
  static const Duration _interlude = Duration(seconds: 4);

  /// How long manual scrolling pauses auto-scroll.
  static const Duration _browseTimeout = Duration(seconds: 3);

  static const double _topPadding = 40;

  /// Updated every frame so the word fill moves smoothly.
  final ValueNotifier<Duration> _position = ValueNotifier(Duration.zero);
  final List<GlobalKey> _lineKeys = [];

  late final Ticker _ticker;
  LrcLyrics? _lrcLyrics;
  int _activeLineIndex = -1;
  bool _isBrowsing = false;
  Timer? _browseTimer;

  /// Identifies the latest auto-scroll, or 0 when none is running.
  int _autoScrollId = 0;
  int _autoScrollCount = 0;

  @override
  void initState() {
    super.initState();
    _parseLyrics();
    _ticker = createTicker((_) => _syncPosition());
    unawaited(_ticker.start());
  }

  @override
  void didUpdateWidget(LyricsView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.lyrics != widget.lyrics) {
      _parseLyrics();
    }
  }

  void _parseLyrics() {
    _lrcLyrics = parseLrcLyrics(widget.lyrics);
    _activeLineIndex = -1;
    _lineKeys
      ..clear()
      ..addAll(
        List.generate(_lrcLyrics?.lines.length ?? 0, (_) => GlobalKey()),
      );
  }

  void _syncPosition() {
    final LrcLyrics? lyrics = _lrcLyrics;
    if (lyrics == null) {
      return;
    }

    final Duration position = ref.read(audioPlayerProvider).position;
    _position.value = position;

    final int activeIndex = position < lyrics.lines.first.timestamp
        ? -1
        : lyrics.getActiveLineIndex(position);
    if (activeIndex == _activeLineIndex) {
      return;
    }

    setState(() {
      _activeLineIndex = activeIndex;
    });
    _scrollAfterFrame();
  }

  void _scrollAfterFrame() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !_isBrowsing) {
        unawaited(_scrollToActiveLine());
      }
    });
  }

  Future<void> _scrollToActiveLine() async {
    if (_activeLineIndex < 0 || !widget.scrollController.hasClients) {
      return;
    }

    final RenderObject? renderObject = _lineKeys[_activeLineIndex]
        .currentContext
        ?.findRenderObject();
    if (renderObject == null) {
      return;
    }

    final ScrollPosition scrollPosition = widget.scrollController.position;
    final double lineTop = RenderAbstractViewport.of(
      renderObject,
    ).getOffsetToReveal(renderObject, 0).offset;
    final double target = (lineTop - _topPadding).clamp(
      scrollPosition.minScrollExtent,
      scrollPosition.maxScrollExtent,
    );

    if ((target - scrollPosition.pixels).abs() < 1) {
      return;
    }

    final int id = ++_autoScrollCount;
    _autoScrollId = id;
    await widget.scrollController.animateTo(
      target,
      duration: const Duration(milliseconds: 600),
      curve: const Cubic(0.25, 0.1, 0.2, 1),
    );
    if (_autoScrollId == id) {
      _autoScrollId = 0;
    }
  }

  /// Any scroll that is not ours comes from touch or the click wheel.
  bool _handleScroll(ScrollNotification notification) {
    final bool isDrag =
        notification is ScrollStartNotification &&
        notification.dragDetails != null;
    if (isDrag) {
      _autoScrollId = 0;
    }
    if (notification is! ScrollUpdateNotification || _autoScrollId != 0) {
      return false;
    }

    if (!_isBrowsing) {
      setState(() {
        _isBrowsing = true;
      });
    }
    _browseTimer?.cancel();
    _browseTimer = Timer(_browseTimeout, _resumeFollowing);
    return false;
  }

  void _resumeFollowing() {
    if (!mounted) {
      return;
    }
    setState(() {
      _isBrowsing = false;
    });
    _scrollAfterFrame();
  }

  Future<void> _seekToLine(LrcLine line) async {
    _browseTimer?.cancel();
    _resumeFollowing();
    await ref.read(audioPlayerProvider).seek(line.timestamp);
  }

  @override
  void dispose() {
    _browseTimer?.cancel();
    _ticker.dispose();
    _position.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final String? lyrics = widget.lyrics;
    if (lyrics == null || lyrics.trim().isEmpty) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.only(right: 10),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Stack(
          fit: StackFit.expand,
          children: [
            _buildBackground(),
            LayoutBuilder(
              builder: (context, constraints) => NotificationListener(
                onNotification: _handleScroll,
                child: CupertinoScrollbar(
                  controller: widget.scrollController,
                  child: SingleChildScrollView(
                    controller: widget.scrollController,
                    padding: EdgeInsets.fromLTRB(
                      12,
                      _topPadding,
                      12,
                      // Room for the last line to scroll up to the top.
                      _lrcLyrics == null
                          ? 12
                          : math.max(0.0, constraints.maxHeight - 80),
                    ),
                    child: _lrcLyrics == null
                        ? _buildPlainText(lyrics)
                        : _buildSyncedLines(_lrcLyrics!),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Heavily blurred, darkened album art.
  Widget _buildBackground() {
    const Color fallback = Color(0xFF2A2A2E);
    final String? path = widget.thumbnailPath;
    if (path == null) {
      return const ColoredBox(color: fallback);
    }

    final ImageProvider image = widget.isOnDevice
        ? FileImage(File(path))
        : NetworkImage(path);

    return RepaintBoundary(
      child: Stack(
        fit: StackFit.expand,
        children: [
          const ColoredBox(color: fallback),
          ImageFiltered(
            imageFilter: ui.ImageFilter.blur(
              sigmaX: 30,
              sigmaY: 30,
              tileMode: TileMode.clamp,
            ),
            child: Image(
              image: image,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => const SizedBox.shrink(),
            ),
          ),
          const ColoredBox(color: Color(0x80000000)),
        ],
      ),
    );
  }

  Widget _buildPlainText(String lyrics) {
    return Text(
      lyrics,
      style: const TextStyle(
        fontSize: 18,
        height: 1.4,
        fontWeight: FontWeight.bold,
        color: CupertinoColors.white,
      ),
    );
  }

  Widget _buildSyncedLines(LrcLyrics lyrics) {
    final List<Widget> children = [];
    Duration? previousEnd = Duration.zero;

    for (int i = 0; i < lyrics.lines.length; i++) {
      final LrcLine line = lyrics.lines[i];
      // Line-synced lyrics have no end times, so breaks are only known
      // before the first line.
      if (previousEnd != null && line.timestamp - previousEnd >= _interlude) {
        children.add(
          InterludeDots(
            start: previousEnd,
            end: line.timestamp,
            position: _position,
          ),
        );
      }
      previousEnd = line.end;
      children.add(_buildLine(i, line));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: children,
    );
  }

  Widget _buildLine(int index, LrcLine line) {
    final bool isActive = index == _activeLineIndex;
    // The second singer in a duet sits on the right.
    final bool isRight = line.voice == 2;
    final TextAlign textAlign = isRight ? TextAlign.right : TextAlign.left;
    final int focusIndex = _activeLineIndex < 0 ? 0 : _activeLineIndex;
    final int distance = (index - focusIndex).abs();
    final double blur = isActive || _isBrowsing
        ? 0
        : math.min(distance * 0.8, 3.0);

    const TextStyle style = TextStyle(
      fontSize: 22,
      height: 1.25,
      fontWeight: FontWeight.bold,
      color: CupertinoColors.white,
    );

    final Widget text = isActive && line.words.isNotEmpty
        ? KaraokeLine(
            line: line,
            position: _position,
            style: style,
            textAlign: textAlign,
          )
        : Text(line.text, style: style, textAlign: textAlign);

    return GestureDetector(
      key: _lineKeys[index],
      behavior: HitTestBehavior.opaque,
      onTap: () async => _seekToLine(line),
      child: Padding(
        // Keeps the scaled active line and duet lines apart.
        padding: EdgeInsets.fromLTRB(isRight ? 24 : 0, 8, isRight ? 0 : 8, 8),
        child: AnimatedScale(
          scale: isActive ? 1 : 0.95,
          alignment: isRight ? Alignment.centerRight : Alignment.centerLeft,
          duration: const Duration(milliseconds: 400),
          curve: Curves.easeOut,
          child: AnimatedOpacity(
            opacity: isActive ? 1 : (_isBrowsing ? 0.6 : 0.35),
            duration: const Duration(milliseconds: 400),
            child: TweenAnimationBuilder<double>(
              tween: Tween(end: blur),
              duration: const Duration(milliseconds: 400),
              child: SizedBox(width: double.infinity, child: text),
              builder: (context, sigma, child) => ImageFiltered(
                enabled: sigma > 0.05,
                imageFilter: ui.ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
                child: child,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
