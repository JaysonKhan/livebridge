import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/brand.dart';
import '../theme/tokens.dart';

/// The macOS side of the window chrome (`macos/Runner/MainFlutterWindow.swift`). The Flutter header covers the
/// transparent title bar, so it asks the window to start a drag and to run the title bar's double-click action,
/// and it hears when the window enters or leaves full screen.
abstract final class MacWindow {
  static const _channel = MethodChannel('livebridge/window');
  static bool _listening = false;

  /// True in full screen, where macOS hides the title bar and its traffic lights (they slide in over the content
  /// only while the pointer is at the top edge), so the header needs no room for them.
  static final fullScreen = ValueNotifier<bool>(false);

  static void listen() {
    if (_listening) return;
    _listening = true;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'fullScreen') fullScreen.value = call.arguments == true;
    });
  }

  static void startDrag() => unawaited(_channel.invokeMethod<void>('startDrag'));

  static void titleBarDoubleClick() => unawaited(_channel.invokeMethod<void>('titleBarDoubleClick'));
}

/// The window header in place of a Material AppBar. macOS: the 52 pt unified toolbar row on the window colour,
/// clear of the traffic lights, brand mark (20) and name in headline weight, [trailing] on the right; dragging it
/// moves the window. Windows: a 48 px brand bar on the base colour under the native title bar, brand mark (24) and
/// name in Subtitle.
class PlatformHeader extends StatefulWidget {
  const PlatformHeader({super.key, required this.trailing});

  final Widget trailing;

  @override
  State<PlatformHeader> createState() => _PlatformHeaderState();
}

class _PlatformHeaderState extends State<PlatformHeader> {
  @override
  void initState() {
    super.initState();
    MacWindow.listen();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final text = Theme.of(context).textTheme;
    final brand = IgnorePointer(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Image.asset(
            Brand.logoAsset,
            width: t.brandMarkSize,
            height: t.brandMarkSize,
            filterQuality: FilterQuality.medium,
            excludeFromSemantics: true,
          ),
          SizedBox(width: t.isWindows ? 12 : 8),
          Semantics(
            header: true,
            child: Text(
              Brand.appName,
              style: (t.isWindows ? text.titleLarge : text.titleSmall)!.copyWith(color: t.textPrimary),
            ),
          ),
        ],
      ),
    );
    if (t.isWindows) {
      return Container(
        key: const Key('platform-header'),
        height: t.headerHeight,
        color: t.header,
        padding: EdgeInsets.symmetric(horizontal: t.headerLeadingInset),
        child: Row(children: [brand, const Spacer(), widget.trailing]),
      );
    }
    return ValueListenableBuilder<bool>(
      valueListenable: MacWindow.fullScreen,
      builder: (context, fullScreen, _) => Container(
        key: const Key('platform-header'),
        height: t.headerHeight,
        decoration: BoxDecoration(
          color: t.header,
          border: Border(bottom: BorderSide(color: t.divider)),
        ),
        child: Stack(
          alignment: AlignmentDirectional.centerStart,
          children: [
            // Behind the content: empty header space drags the window, as a title bar does.
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onPanStart: (_) => MacWindow.startDrag(),
                onDoubleTap: MacWindow.titleBarDoubleClick,
              ),
            ),
            Padding(
              padding: EdgeInsets.only(left: fullScreen ? 16 : t.headerLeadingInset, right: 12),
              child: Row(children: [brand, const Spacer(), widget.trailing]),
            ),
          ],
        ),
      ),
    );
  }
}
