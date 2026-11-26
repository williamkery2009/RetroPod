import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:retropod/core/models/lrc_lyrics.dart';
import 'package:retropod/core/services/audio_player_service.dart';
import 'package:retropod/features/now_playing/widgets/interlude_dots.dart';
import 'package:retropod/features/now_playing/widgets/karaoke_line.dart';
import 'package:retropod/features/now_playing/widgets/spring_offset.dart';

class LyricsView extends ConsumerStatefulWidget {
  final String? lyrics;
  final ScrollController scrollController;
  final double fontSize;

  const LyricsView({
    super.key,
    required this.lyrics,
    required this.scrollController,
    this.fontSize = 22,
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

  /// True while this view moves the scroll position itself.
  bool _isAutoScrolling = false;

  /// Each new bounce makes the lines spring from [_bounceDistance] away.
  int _bounceId = 0;
  double _bounceDistance = 0;

  /// Corrects the position once collapsing break dots have settled.
  Timer? _settleTimer;

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
        _scrollToActiveLine();
        _settleTimer?.cancel();
        _settleTimer = Timer(const Duration(milliseconds: 350), () {
          if (mounted && !_isBrowsing) {
            _scrollToActiveLine();
          }
        });
      }
    });
  }

  /// Jumps to the active line, then lets each line spring into its new
  /// place one after another.
  void _scrollToActiveLine() {
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

    final double distance = target - scrollPosition.pixels;
    _isAutoScrolling = true;
    widget.scrollController.jumpTo(target);
    _isAutoScrolling = false;

    if (!MediaQuery.disableAnimationsOf(context)) {
      setState(() {
        _bounceDistance = distance;
        _bounceId++;
      });
    }
  }

  /// Any scroll that is not ours comes from touch or the click wheel.
  bool _handleScroll(ScrollNotification notification) {
    if (notification is! ScrollUpdateNotification || _isAutoScrolling) {
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
    _settleTimer?.cancel();
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

    return LayoutBuilder(
      builder: (context, constraints) => NotificationListener(
        onNotification: _handleScroll,
        child: CupertinoScrollbar(
          controller: widget.scrollController,
          child: SingleChildScrollView(
            controller: widget.scrollController,
            padding: EdgeInsets.fromLTRB(
              2,
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
      children.add(
        SpringOffset(
          bounceId: _bounceId,
          distance: _bounceDistance,
          // Lines further below the active one start later.
          delayStep: (i - _activeLineIndex).clamp(0, 6),
          child: _buildLine(i, line),
        ),
      );
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
    // Blur grows with distance and then stays at its maximum.
    final double blur = isActive || _isBrowsing
        ? 0
        : math.min(distance * 0.7, 2.5);

    final TextStyle style = TextStyle(
      fontSize: widget.fontSize,
      height: 1.25,
      fontWeight: FontWeight.bold,
      color: CupertinoColors.white,
    );

    Widget buildText(TextStyle lineStyle) {
      final Widget leadText = isActive && line.words.isNotEmpty
          ? KaraokeLine(
              words: line.words,
              position: _position,
              style: style,
              textAlign: textAlign,
            )
          : Text(line.text, style: lineStyle, textAlign: textAlign);

      if (line.backgroundWords.isEmpty) {
        return leadText;
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          leadText,
          _buildBackgroundVocals(line, isActive, lineStyle, textAlign),
        ],
      );
    }

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
              builder: (context, sigma, _) => SizedBox(
                width: double.infinity,
                child: buildText(_softened(style, sigma)),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Blurs text by drawing only its shadow. This is cheap enough to apply to
  /// every inactive line, unlike a separate blur layer for each one.
  TextStyle _softened(TextStyle style, double sigma) {
    if (sigma < 0.6) {
      return style;
    }
    return style.copyWith(
      color: const Color(0x00FFFFFF),
      shadows: [
        Shadow(
          color: CupertinoColors.white,
          // Inverse of Shadow's radius to sigma conversion.
          blurRadius: (sigma - 0.5) / 0.57735,
        ),
      ],
    );
  }

  Widget _buildBackgroundVocals(
    LrcLine line,
    bool isActive,
    TextStyle leadStyle,
    TextAlign textAlign,
  ) {
    final TextStyle textStyle = leadStyle.copyWith(
      fontSize: widget.fontSize * 0.7,
    );

    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: isActive
          ? KaraokeLine(
              words: line.backgroundWords,
              position: _position,
              // The active line is never blurred.
              style: textStyle.copyWith(color: CupertinoColors.white),
              textAlign: textAlign,
            )
          : Text(
              line.backgroundWords.map((word) => word.text).join().trim(),
              style: textStyle,
              textAlign: textAlign,
            ),
    );
  }
}
