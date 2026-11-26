import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:retropod/core/extensions/build_context_extensions.dart';
import 'package:retropod/core/extensions/go_router_extensions.dart';
import 'package:retropod/core/services/audio_player_service.dart';
import 'package:retropod/core/utils/scroll_accelerator.dart';
import 'package:retropod/core/widgets/index_letter_popup.dart';
import 'package:retropod/features/device/models/device_action.dart';
import 'package:retropod/features/device/services/device_buttons_service_provider.dart';

mixin CustomScreen<T extends ConsumerStatefulWidget> on ConsumerState<T> {
  abstract final String routeName;
  abstract final List displayItems;
  int selectedDisplayItem = 0;
  int extraDisplayItems = 0;
  int topStatusBarHeight = 30;
  final double displayTileHeight = 30;
  final ScrollController scrollController = ScrollController();

  final ScrollAccelerator _scrollAccelerator = ScrollAccelerator();
  final IndexLetterPopup _indexLetterPopup = IndexLetterPopup();

  void onSelectPressed();

  /// Title of the item at [index], for lists sorted by name. Other lists
  /// return `null` and show no letter popup.
  String? indexTitleFor(int index) => null;

  /// Handles one wheel step, moving several items during a fast spin.
  void _spinWheel({required bool isForward}) {
    final int step = _scrollAccelerator.stepSize(
      now: DateTime.now(),
      isForward: isForward,
      listLength: displayItems.length + extraDisplayItems,
    );
    for (int i = 0; i < step; i++) {
      if (isForward) {
        scrollForward();
      } else {
        scrollBackward();
      }
    }

    if (step > 1) {
      final String? title = indexTitleFor(selectedDisplayItem);
      if (title != null) {
        _indexLetterPopup.show(context, indexLetter(title));
      }
    }
  }

  void onSelectLongPress() {}

  void scrollForward() {
    if (selectedDisplayItem < displayItems.length + extraDisplayItems - 1) {
      setState(() {
        selectedDisplayItem++;
      });

      final double currentSelectedDisplayItemsHeight =
          (selectedDisplayItem + 1) * displayTileHeight + topStatusBarHeight;

      final double currentScrollHeight =
          context.screenSize.height + scrollController.offset;

      if (currentSelectedDisplayItemsHeight > currentScrollHeight) {
        scrollController.jumpTo(scrollController.offset + displayTileHeight);
      }
    }
  }

  void scrollBackward() {
    if (selectedDisplayItem > 0) {
      setState(() {
        selectedDisplayItem--;
      });
    }

    if (selectedDisplayItem * displayTileHeight < scrollController.offset) {
      scrollController.jumpTo(displayTileHeight * selectedDisplayItem);
    }
  }

  void onMenuButtonPressed() {
    context.pop();
  }

  Future<void> seekForward() async {
    await ref.read(audioPlayerServiceProvider.notifier).nextSong();
  }

  Future<void> seekBackward() async {
    await ref.read(audioPlayerServiceProvider.notifier).seekBackwards();
  }

  Future<void> deviceControlHandler(_, DeviceAction? newState) async {
    if (newState == null || context.router.locationNamed != routeName) {
      return;
    }
    switch (newState) {
      case DeviceAction.menu:
        onMenuButtonPressed();
        break;
      case DeviceAction.select:
        onSelectPressed();
        break;
      case DeviceAction.selectLongPress:
        onSelectLongPress();
        break;
      case DeviceAction.rotateForward:
        _spinWheel(isForward: true);
        break;
      case DeviceAction.rotateBackward:
        _spinWheel(isForward: false);
        break;
      case DeviceAction.seekForward:
        await seekForward();
        break;
      case DeviceAction.seekBackward:
        await seekBackward();
        break;
      case DeviceAction.seekForwardLongPress:
        break;
      case DeviceAction.seekBackwardLongPress:
        break;
      case DeviceAction.playPause:
        break;
      case DeviceAction.longPressEnd:
        break;
    }
  }

  @override
  void initState() {
    super.initState();
    ref.listenManual(deviceButtonsServiceProvider, deviceControlHandler);
  }

  @override
  void dispose() {
    _indexLetterPopup.dispose();
    scrollController.dispose();
    super.dispose();
  }
}
