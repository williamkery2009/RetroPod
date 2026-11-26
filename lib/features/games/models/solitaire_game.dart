import 'dart:math';

class PlayingCard {
  /// 0 spades, 1 hearts, 2 clubs, 3 diamonds.
  final int suit;

  /// 1 (ace) to 13 (king).
  final int rank;

  bool isFaceUp;

  PlayingCard({required this.suit, required this.rank, this.isFaceUp = false});

  bool get isRed => suit.isOdd;

  String get rankLabel => switch (rank) {
    1 => 'A',
    11 => 'J',
    12 => 'Q',
    13 => 'K',
    _ => '$rank',
  };
}

enum PileType { stock, waste, foundation, tableau }

class PileId {
  final PileType type;
  final int index;

  const PileId(this.type, [this.index = 0]);

  @override
  bool operator ==(Object other) =>
      other is PileId && other.type == type && other.index == index;

  @override
  int get hashCode => Object.hash(type, index);
}

/// Klondike solitaire, drawing one card at a time.
class SolitaireGame {
  final List<PlayingCard> stock = [];
  final List<PlayingCard> waste = [];
  final List<List<PlayingCard>> foundations = List.generate(4, (_) => []);
  final List<List<PlayingCard>> tableaus = List.generate(7, (_) => []);

  /// An empty table, for setting up positions.
  SolitaireGame.empty();

  /// A shuffled, dealt game.
  SolitaireGame.deal([Random? random]) {
    final List<PlayingCard> deck = [
      for (int suit = 0; suit < 4; suit++)
        for (int rank = 1; rank <= 13; rank++)
          PlayingCard(suit: suit, rank: rank),
    ]..shuffle(random);

    for (int column = 0; column < 7; column++) {
      for (int row = 0; row <= column; row++) {
        tableaus[column].add(deck.removeLast()..isFaceUp = row == column);
      }
    }
    stock.addAll(deck);
  }

  bool get isWon => foundations.every((pile) => pile.length == 13);

  List<PlayingCard> pile(PileId id) => switch (id.type) {
    PileType.stock => stock,
    PileType.waste => waste,
    PileType.foundation => foundations[id.index],
    PileType.tableau => tableaus[id.index],
  };

  /// Turns over the next card, or recycles the waste when the stock is empty.
  void draw() {
    if (stock.isNotEmpty) {
      waste.add(stock.removeLast()..isFaceUp = true);
      return;
    }
    while (waste.isNotEmpty) {
      stock.add(waste.removeLast()..isFaceUp = false);
    }
  }

  /// Index in [from] of the first card that can move to [to], or `null`.
  ///
  /// A run of tableau cards has distinct ranks, so at most one part of it
  /// fits the destination and the player never has to pick the card.
  int? _movableStart(PileId from, PileId to) {
    if (from == to || from.type == PileType.stock) {
      return null;
    }
    final List<PlayingCard> source = pile(from);
    final List<PlayingCard> target = pile(to);
    if (source.isEmpty) {
      return null;
    }

    if (to.type == PileType.foundation) {
      final PlayingCard card = source.last;
      final bool fits = target.isEmpty
          ? card.rank == 1
          : card.suit == target.last.suit && card.rank == target.last.rank + 1;
      return fits ? source.length - 1 : null;
    }

    if (to.type != PileType.tableau) {
      return null;
    }
    final int first = from.type == PileType.tableau ? 0 : source.length - 1;
    for (int i = first; i < source.length; i++) {
      final PlayingCard card = source[i];
      if (!card.isFaceUp) {
        continue;
      }
      final bool fits = target.isEmpty
          // Moving a king that already heads its column changes nothing.
          ? card.rank == 13 && !(from.type == PileType.tableau && i == 0)
          : card.isRed != target.last.isRed &&
                card.rank == target.last.rank - 1;
      if (fits) {
        return i;
      }
    }
    return null;
  }

  /// Moves cards if the rules allow it. Returns whether anything moved.
  bool move(PileId from, PileId to) {
    final int? start = _movableStart(from, to);
    if (start == null) {
      return false;
    }
    final List<PlayingCard> source = pile(from);
    pile(to).addAll(source.sublist(start));
    source.removeRange(start, source.length);

    if (from.type == PileType.tableau && source.isNotEmpty) {
      source.last.isFaceUp = true;
    }
    return true;
  }

  bool moveToFoundation(PileId from) {
    for (int i = 0; i < 4; i++) {
      if (move(from, PileId(PileType.foundation, i))) {
        return true;
      }
    }
    return false;
  }
}
