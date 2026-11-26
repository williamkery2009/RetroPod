/// A timed word or syllable inside an [LrcLine].
class LrcWord {
  /// The moment [text] starts being sung.
  final Duration start;

  /// The moment [text] stops being sung.
  final Duration end;

  /// The word or syllable, including any trailing space.
  final String text;

  const LrcWord({required this.start, required this.end, required this.text});

  /// How much of the word has been sung at [position], from 0 to 1.
  double progressAt(Duration position) {
    if (position >= end) {
      return 1;
    }
    if (position <= start) {
      return 0;
    }
    return (position - start).inMicroseconds / (end - start).inMicroseconds;
  }
}

/// A single timestamped line of synchronized lyrics.
class LrcLine {
  /// The moment in the track where [text] should be shown.
  final Duration timestamp;

  /// The lyric text associated with [timestamp].
  final String text;

  /// Word timings in singing order. Empty for line-synced lyrics.
  final List<LrcWord> words;

  /// Singer number from a `v1:` style label. Defaults to 1.
  final int voice;

  /// When the last word ends, or `null` for line-synced lyrics.
  Duration? get end => words.isEmpty ? null : words.last.end;

  const LrcLine({
    required this.timestamp,
    required this.text,
    this.words = const [],
    this.voice = 1,
  });
}

/// Parsed synchronized (LRC) lyrics.
class LrcLyrics {
  /// Timed lines sorted by [LrcLine.timestamp].
  final List<LrcLine> lines;

  const LrcLyrics(this.lines);

  /// Returns the index of the line active at [position].
  ///
  /// Returns `-1` when [position] precedes every line or [lines] is empty.
  int getActiveLineIndex(Duration position) {
    if (lines.isEmpty) {
      return -1;
    }

    int activeIndex = 0;
    for (int i = 0; i < lines.length; i++) {
      if (lines[i].timestamp <= position) {
        activeIndex = i;
      } else {
        break;
      }
    }
    return activeIndex;
  }
}

/// Matches an LRC timestamp token such as `[00:11.12]` or `[00:11]`.
final RegExp _timestampPattern = RegExp(
  r'\[(\d{1,3}):(\d{1,2})(?:[.:](\d{1,3}))?\]',
);

/// Matches an enhanced LRC word token such as `<00:11.120>`.
final RegExp _wordTimestampPattern = RegExp(
  r'<(\d{1,3}):(\d{1,2})(?:[.:](\d{1,3}))?>',
);

/// Matches a singer label such as `v1:` at the start of a line.
final RegExp _voicePattern = RegExp(r'^v(\d+):\s*');

/// Matches an LRC `[offset:+500]` metadata tag.
final RegExp _offsetPattern = RegExp(r'\[offset:([+-]?\d+)\]');

/// Parses [source] into synchronized lyrics.
///
/// Returns `null` when the text has no timestamped lines and therefore
/// should be shown as plain unsynchronized text.
LrcLyrics? parseLrcLyrics(String? source) {
  if (source == null || source.trim().isEmpty) {
    return null;
  }

  final List<LrcLine> lines = [];
  int? offsetMilliseconds;

  for (final String rawLine in source.split('\n')) {
    final String line = rawLine.trim();
    if (line.isEmpty) {
      continue;
    }

    final RegExpMatch? offsetMatch = _offsetPattern.firstMatch(line);
    if (offsetMatch != null) {
      offsetMilliseconds = int.tryParse(offsetMatch.group(1)!);
      continue;
    }

    final List<RegExpMatch> matches = _timestampPattern
        .allMatches(line)
        .toList();
    if (matches.isEmpty) {
      continue;
    }

    String content = line.substring(matches.last.end).trim();

    int voice = 1;
    final RegExpMatch? voiceMatch = _voicePattern.firstMatch(content);
    if (voiceMatch != null) {
      voice = int.parse(voiceMatch.group(1)!);
      content = content.substring(voiceMatch.end);
    }

    final String text = content.replaceAll(_wordTimestampPattern, '').trim();

    for (final RegExpMatch match in matches) {
      final int offset = offsetMilliseconds ?? 0;

      lines.add(
        LrcLine(
          timestamp: Duration(milliseconds: _toMilliseconds(match) + offset),
          text: text,
          // Word times are absolute, so they cannot be reused by a line
          // that repeats under several line timestamps.
          words: matches.length == 1 ? _parseWords(content, offset) : const [],
          voice: voice,
        ),
      );
    }
  }

  if (lines.isEmpty) {
    return null;
  }

  lines.sort((a, b) => a.timestamp.compareTo(b.timestamp));

  return LrcLyrics(lines);
}

int _toMilliseconds(RegExpMatch match) {
  return int.parse(match.group(1)!) * 60000 +
      int.parse(match.group(2)!) * 1000 +
      _parseFraction(match.group(3));
}

/// Splits [content] into timed words.
///
/// Each word ends where the next token starts. A trailing token only marks
/// the end of the last word.
List<LrcWord> _parseWords(String content, int offset) {
  final List<RegExpMatch> tokens = _wordTimestampPattern
      .allMatches(content)
      .toList();
  final List<LrcWord> words = [];

  for (int i = 0; i < tokens.length; i++) {
    final bool isLast = i == tokens.length - 1;
    final String text = content.substring(
      tokens[i].end,
      isLast ? content.length : tokens[i + 1].start,
    );
    if (text.trim().isEmpty) {
      continue;
    }

    final int start = _toMilliseconds(tokens[i]) + offset;
    // Without a closing token, assume a short final word.
    final int end = isLast
        ? start + 500
        : _toMilliseconds(tokens[i + 1]) + offset;

    words.add(
      LrcWord(
        start: Duration(milliseconds: start),
        end: Duration(milliseconds: end < start ? start : end),
        text: text,
      ),
    );
  }

  return words;
}

int _parseFraction(String? fraction) {
  if (fraction == null || fraction.isEmpty) {
    return 0;
  }
  return (double.parse('0.$fraction') * 1000).round();
}
