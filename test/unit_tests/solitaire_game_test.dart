import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:retropod/features/games/models/solitaire_game.dart';

PlayingCard up(int suit, int rank) =>
    PlayingCard(suit: suit, rank: rank, isFaceUp: true);

void main() {
  const waste = PileId(PileType.waste);
  const first = PileId(PileType.tableau);
  const second = PileId(PileType.tableau, 1);

  group('SolitaireGame', () {
    test('deals 52 distinct cards', () {
      final game = SolitaireGame.deal(Random(1));
      final cards = [
        ...game.stock,
        for (final pile in game.tableaus) ...pile,
      ];

      expect(game.stock.length, 24);
      expect(cards.map((c) => '${c.suit}-${c.rank}').toSet().length, 52);
      for (int i = 0; i < 7; i++) {
        expect(game.tableaus[i].length, i + 1);
        expect(game.tableaus[i].last.isFaceUp, isTrue);
      }
    });

    test('draws and then recycles the stock in order', () {
      final game = SolitaireGame.deal(Random(1));
      final top = game.stock.last;
      for (int i = 0; i < 24; i++) {
        game.draw();
      }
      expect(game.stock, isEmpty);
      game.draw();
      expect(game.waste, isEmpty);
      expect(game.stock.last, same(top));
      expect(top.isFaceUp, isFalse);
    });

    test('moves the part of a run that fits and turns the next card', () {
      final game = SolitaireGame.empty();
      game.tableaus[0].addAll([
        PlayingCard(suit: 0, rank: 2),
        up(1, 9),
        up(0, 8),
      ]);
      game.tableaus[1].add(up(2, 10));

      expect(game.move(first, second), isTrue);
      expect(game.tableaus[1].map((c) => c.rank), [10, 9, 8]);
      expect(game.tableaus[0].single.isFaceUp, isTrue);
    });

    test('rejects a card of the same color', () {
      final game = SolitaireGame.empty();
      game.waste.add(up(0, 9));
      game.tableaus[0].add(up(2, 10));

      expect(game.move(waste, first), isFalse);
    });

    test('allows only a king on an empty column', () {
      final game = SolitaireGame.empty();
      game.waste.add(up(0, 12));
      expect(game.move(waste, first), isFalse);
      game.waste.add(up(0, 13));
      expect(game.move(waste, first), isTrue);
    });

    test('builds foundations by suit from the ace', () {
      final game = SolitaireGame.empty();
      game.waste.addAll([up(1, 2), up(1, 1)]);

      expect(game.moveToFoundation(waste), isTrue);
      expect(game.moveToFoundation(waste), isTrue);
      expect(game.foundations[0].map((c) => c.rank), [1, 2]);
    });
  });
}
