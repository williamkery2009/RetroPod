import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:retropod/core/extensions/go_router_extensions.dart';
import 'package:retropod/core/navigation/routes.dart';
import 'package:retropod/features/device/models/device_action.dart';
import 'package:retropod/features/device/services/device_buttons_service_provider.dart';
import 'package:retropod/features/games/models/solitaire_game.dart';
import 'package:retropod/features/status_bar/widgets/status_bar.dart';

/// Wheel moves the cursor, center picks up and drops, holding center deals
/// a new game, and Menu leaves.
class SolitaireScreen extends ConsumerStatefulWidget {
  const SolitaireScreen({super.key});

  @override
  ConsumerState<SolitaireScreen> createState() => _SolitaireScreenState();
}

class _SolitaireScreenState extends ConsumerState<SolitaireScreen> {
  /// Cursor order: top row left to right, then the columns.
  static const List<PileId> _targets = [
    PileId(PileType.stock),
    PileId(PileType.waste),
    PileId(PileType.foundation),
    PileId(PileType.foundation, 1),
    PileId(PileType.foundation, 2),
    PileId(PileType.foundation, 3),
    PileId(PileType.tableau),
    PileId(PileType.tableau, 1),
    PileId(PileType.tableau, 2),
    PileId(PileType.tableau, 3),
    PileId(PileType.tableau, 4),
    PileId(PileType.tableau, 5),
    PileId(PileType.tableau, 6),
  ];

  static const List<String> _suits = ['♠', '♥', '♣', '♦'];

  SolitaireGame _game = SolitaireGame.deal();
  int _cursor = 0;
  PileId? _picked;

  @override
  void initState() {
    super.initState();
    ref.listenManual(deviceButtonsServiceProvider, _onDeviceAction);
  }

  void _onDeviceAction(DeviceAction? previous, DeviceAction? action) {
    if (action == null ||
        context.router.locationNamed != Routes.solitaire.name) {
      return;
    }
    switch (action) {
      case DeviceAction.menu:
        context.pop();
      case DeviceAction.rotateForward:
        setState(() => _cursor = (_cursor + 1) % _targets.length);
      case DeviceAction.rotateBackward:
        setState(
          () => _cursor = (_cursor - 1 + _targets.length) % _targets.length,
        );
      case DeviceAction.select:
        _choose(_targets[_cursor]);
      case DeviceAction.selectLongPress:
        _newGame();
      case DeviceAction.seekForward:
      case DeviceAction.seekBackward:
      case DeviceAction.seekForwardLongPress:
      case DeviceAction.seekBackwardLongPress:
      case DeviceAction.longPressEnd:
      case DeviceAction.playPause:
        break;
    }
  }

  void _newGame() {
    setState(() {
      _game = SolitaireGame.deal();
      _cursor = 0;
      _picked = null;
    });
  }

  void _choose(PileId target) {
    if (_game.isWon) {
      _newGame();
      return;
    }
    setState(() {
      _cursor = _targets.indexOf(target);
      final PileId? picked = _picked;

      if (picked == null) {
        if (target.type == PileType.stock) {
          _game.draw();
        } else if (_game.pile(target).isNotEmpty) {
          _picked = target;
        }
        return;
      }

      if (picked == target) {
        // Choosing the same pile twice sends its card to a foundation.
        _game.moveToFoundation(picked);
      } else {
        _game.move(picked, target);
      }
      _picked = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      child: Column(
        children: [
          StatusBar(title: Routes.solitaire.title(context)),
          Expanded(
            child: ColoredBox(
              color: const Color(0xFF0B6B3A),
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: LayoutBuilder(
                  builder: (context, constraints) => _game.isWon
                      ? _buildWin()
                      : _buildTable(constraints.maxWidth / 7),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWin() {
    return GestureDetector(
      onTap: _newGame,
      child: const Center(
        child: Text(
          '♠ ♥ ♣ ♦',
          style: TextStyle(fontSize: 40, color: CupertinoColors.white),
        ),
      ),
    );
  }

  Widget _buildTable(double slotWidth) {
    final double cardWidth = slotWidth - 4;
    final double cardHeight = cardWidth * 1.25;

    return Column(
      children: [
        Row(
          children: [
            for (int i = 0; i < 2; i++)
              _buildTopPile(_targets[i], slotWidth, cardHeight),
            SizedBox(width: slotWidth),
            for (int i = 2; i < 6; i++)
              _buildTopPile(_targets[i], slotWidth, cardHeight),
          ],
        ),
        const SizedBox(height: 6),
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (int i = 6; i < _targets.length; i++)
                SizedBox(
                  width: slotWidth,
                  child: _buildColumn(_targets[i], cardWidth, cardHeight),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTopPile(PileId id, double width, double height) {
    final List<PlayingCard> cards = _game.pile(id);

    return GestureDetector(
      onTap: () => _choose(id),
      child: SizedBox(
        width: width,
        height: height,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2),
          child: _buildCard(cards.isEmpty ? null : cards.last, id),
        ),
      ),
    );
  }

  /// Overlaps the cards, squeezing long columns to fit the screen.
  Widget _buildColumn(PileId id, double cardWidth, double cardHeight) {
    final List<PlayingCard> cards = _game.pile(id);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _choose(id),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final double gap = cards.length < 2
              ? 0
              : ((constraints.maxHeight - cardHeight) / (cards.length - 1))
                    .clamp(0.0, 16.0);

          return Stack(
            children: [
              if (cards.isEmpty)
                Positioned(
                  top: 0,
                  left: 2,
                  width: cardWidth,
                  height: cardHeight,
                  child: _buildCard(null, id),
                ),
              for (int i = 0; i < cards.length; i++)
                Positioned(
                  top: i * gap,
                  left: 2,
                  width: cardWidth,
                  height: cardHeight,
                  child: _buildCard(
                    cards[i],
                    id,
                    isTop: i == cards.length - 1,
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildCard(PlayingCard? card, PileId id, {bool isTop = true}) {
    final bool hasCursor = isTop && _targets[_cursor] == id;
    final bool isPicked = isTop && _picked == id;
    final bool isFaceUp = card != null && card.isFaceUp;

    final Color fill = card == null
        ? const Color(0x33000000)
        : !isFaceUp
        ? const Color(0xFF2456A6)
        : isPicked
        ? const Color(0xFFFFE58A)
        : CupertinoColors.white;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(3),
        border: Border.all(
          color: hasCursor ? const Color(0xFFFF9500) : const Color(0x80000000),
          width: hasCursor ? 3 : 1,
        ),
      ),
      child: !isFaceUp
          ? null
          : Align(
              alignment: Alignment.topCenter,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  '${card.rankLabel}${_suits[card.suit]}',
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.1,
                    fontWeight: FontWeight.bold,
                    color: card.isRed
                        ? const Color(0xFFD0021B)
                        : CupertinoColors.black,
                  ),
                ),
              ),
            ),
    );
  }
}
