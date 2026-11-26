import 'package:flutter_test/flutter_test.dart';
import 'package:retropod/core/models/lrc_lyrics.dart';

void main() {
  group('parseLrcLyrics', () {
    test('returns null for empty lyrics', () {
      expect(parseLrcLyrics(null), isNull);
      expect(parseLrcLyrics(''), isNull);
      expect(parseLrcLyrics('   '), isNull);
    });

    test('returns null for plain text without timestamps', () {
      expect(parseLrcLyrics('just a plain lyric line'), isNull);
    });

    test('parses single timestamped line', () {
      final lyrics = parseLrcLyrics('[00:11.12] You were the shadow');
      expect(lyrics, isNotNull);
      expect(lyrics!.lines.length, 1);
      expect(lyrics.lines.first.timestamp, const Duration(milliseconds: 11120));
      expect(lyrics.lines.first.text, 'You were the shadow');
    });

    test('parses multiple lines and sorts them by timestamp', () {
      final lyrics = parseLrcLyrics(
        '[00:30.00] second line\n[00:11.12] first line',
      );
      expect(lyrics!.lines.map((line) => line.text), [
        'first line',
        'second line',
      ]);
    });

    test('duplicates a line for every timestamp it carries', () {
      final lyrics = parseLrcLyrics('[00:11.12][00:45.00] repeated line');
      expect(lyrics!.lines.length, 2);
      expect(lyrics.lines[0].timestamp, const Duration(milliseconds: 11120));
      expect(lyrics.lines[1].timestamp, const Duration(milliseconds: 45000));
    });

    test('ignores LRC metadata tags', () {
      final lyrics = parseLrcLyrics(
        '[ti:My Song]\n[ar:My Artist]\n[00:11.12] a lyric\n',
      );
      expect(lyrics!.lines.length, 1);
      expect(lyrics.lines.first.text, 'a lyric');
    });

    test('applies offset tag to all timestamps', () {
      final lyrics = parseLrcLyrics('[offset:+500]\n[00:11.00] a lyric');
      expect(
        lyrics!.lines.first.timestamp,
        const Duration(milliseconds: 11500),
      );
    });

    test('parses fraction-less timestamps', () {
      final lyrics = parseLrcLyrics('[00:11] a lyric');
      expect(
        lyrics!.lines.first.timestamp,
        const Duration(milliseconds: 11000),
      );
    });

    test('parses word timings and removes tags from the text', () {
      final line = parseLrcLyrics(
        '[00:01.00]v1: <00:01.000>one <00:01.500>two<00:02.250>',
      )!.lines.single;

      expect(line.text, 'one two');
      expect(line.voice, 1);
      expect(line.words.map((word) => word.text), ['one ', 'two']);
      expect(line.words.first.end, const Duration(milliseconds: 1500));
      expect(line.end, const Duration(milliseconds: 2250));
    });

    test('keeps syllables joined and reads the singer number', () {
      final line = parseLrcLyrics(
        '[00:01.00]v2: <00:01.000>hel<00:01.200>lo<00:01.600>',
      )!.lines.single;

      expect(line.text, 'hello');
      expect(line.voice, 2);
      expect(line.words.length, 2);
    });

    test('applies offset tag to word timings', () {
      final line = parseLrcLyrics(
        '[offset:+500]\n[00:01.00]<00:01.000>one<00:02.000>',
      )!.lines.single;

      expect(line.words.single.start, const Duration(milliseconds: 1500));
      expect(line.end, const Duration(milliseconds: 2500));
    });

    test('reports word progress between its start and end', () {
      const word = LrcWord(
        start: Duration(seconds: 1),
        end: Duration(seconds: 3),
        text: 'one',
      );

      expect(word.progressAt(Duration.zero), 0);
      expect(word.progressAt(const Duration(seconds: 2)), 0.5);
      expect(word.progressAt(const Duration(seconds: 4)), 1);
    });

    test('getActiveLineIndex returns active line for a position', () {
      final lyrics = parseLrcLyrics('[00:11.12] one\n[00:14.90] two');
      expect(
        lyrics!.getActiveLineIndex(const Duration(milliseconds: 11120)),
        0,
      );
      expect(lyrics.getActiveLineIndex(const Duration(milliseconds: 14000)), 0);
      expect(lyrics.getActiveLineIndex(const Duration(milliseconds: 14900)), 1);
      expect(lyrics.getActiveLineIndex(const Duration(seconds: 3)), 0);
    });

    test('getActiveLineIndex returns -1 for empty lyrics', () {
      expect(const LrcLyrics([]).getActiveLineIndex(Duration.zero), -1);
    });
  });
}
