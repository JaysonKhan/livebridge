import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:livebridge/state/host_platform.dart';
import 'package:livebridge/ui/adaptive/control_border.dart';
import 'package:livebridge/ui/adaptive/fluent_switch.dart';
import 'package:livebridge/ui/adaptive/platform_header.dart';
import 'package:livebridge/ui/setup_panel.dart';
import 'package:livebridge/ui/theme/app_theme.dart';
import 'package:livebridge/ui/theme/brand.dart';
import 'package:livebridge/ui/theme/macos_theme.dart';
import 'package:livebridge/ui/theme/tokens.dart';

import 'harness.dart';

/// Pumps the app with [platform]'s look in [brightness] (the theme follows the system appearance).
Future<void> _pump(WidgetTester tester, HostPlatform platform, Brightness brightness) async {
  tester.platformDispatcher.platformBrightnessTestValue = brightness;
  addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
  await pumpApp(tester, platform: platform);
}

LiveBridgeTokens _tokens(WidgetTester tester) => tester.element(find.byType(SetupPanel)).tokens;

/// The Material that paints a widget's surface (a Card's or a button's).
Material _surface(WidgetTester tester, Finder of) =>
    tester.widget<Material>(find.descendant(of: of, matching: find.byType(Material)).first);

double _radius(ShapeBorder? shape) => switch (shape) {
  RoundedRectangleBorder(:final borderRadius) => (borderRadius as BorderRadius).topLeft.x,
  ControlBorder(:final radius) => radius,
  _ => throw StateError('unexpected shape $shape'),
};

void main() {
  for (final platform in HostPlatform.values) {
    for (final brightness in Brightness.values) {
      final windows = platform == HostPlatform.windows;
      final light = brightness == Brightness.light;
      group('${platform.name} ${brightness.name}', () {
        testWidgets('tokens follow the platform and the system appearance', (tester) async {
          await _pump(tester, platform, brightness);
          final t = _tokens(tester);
          expect(t.platform, platform);
          expect(Theme.of(tester.element(startButton)).brightness, brightness);
          expect(t.page, windows ? Color(light ? 0xFFF3F3F3 : 0xFF202020) : Color(light ? 0xFFF5F5F5 : 0xFF1E1E1E));
        });

        testWidgets('setup sections are cards on the page: card fill, card stroke, platform radius, no shadow', (
          tester,
        ) async {
          await _pump(tester, platform, brightness);
          final card = find.descendant(of: find.byType(SectionCard).first, matching: find.byType(Card));
          final surface = _surface(tester, card);
          final shape = surface.shape! as RoundedRectangleBorder;
          expect(
            surface.color,
            windows ? Color(light ? 0xFFFBFBFB : 0xFF2B2B2B) : Color(light ? 0xFFFFFFFF : 0xFF2A2A2A),
          );
          expect(
            shape.side.color,
            windows ? Color(light ? 0x0F000000 : 0x19000000) : Color(light ? 0x0F000000 : 0x14FFFFFF),
          );
          expect(_radius(shape), windows ? 8 : 10);
          expect(surface.elevation, 0);
          // Windows keeps the section title inside the card; macOS puts the group title above the box.
          final title = find.text(en.sectionLanguageMode);
          expect(find.descendant(of: card, matching: title), windows ? findsOneWidget : findsNothing);
        });

        testWidgets('the Start button is the brand accent button', (tester) async {
          await _pump(tester, platform, brightness);
          await fillToken();
          await tester.pumpAndSettle();
          final surface = _surface(tester, startButton);
          final accent = windows ? (light ? Brand.teal : Brand.mint) : (light ? Brand.teal : Brand.macDarkAccent);
          expect(surface.color, accent);
          expect(_radius(surface.shape), windows ? 4 : 6);
          expect(tester.getSize(startButton).height, windows ? 32 : 24);
          final label = tester.widget<Text>(find.descendant(of: startButton, matching: find.text(en.startSession)));
          final style = DefaultTextStyle.of(tester.element(find.text(en.startSession))).style.merge(label.style);
          expect(style.color, windows && !light ? Colors.black : Colors.white);
        });

        testWidgets('text boxes and drop-downs have the control height and the platform border', (tester) async {
          await _pump(tester, platform, brightness);
          // A text box, an editable drop-down (with its menu button) and a plain drop-down.
          for (final key in ['access-token', 'my-language', 'mic-dropdown']) {
            final box = find.descendant(of: find.byKey(Key(key)), matching: find.byType(InputDecorator));
            expect(tester.getSize(box).height, windows ? 32 : 24, reason: key);
          }
          final field = tester.widget<InputDecorator>(
            find.descendant(of: find.byKey(const Key('access-token')), matching: find.byType(InputDecorator)),
          );
          final border = WidgetStateProperty.resolveAs(field.decoration.border, <WidgetState>{}) as ControlInputBorder;
          final focused =
              WidgetStateProperty.resolveAs(field.decoration.border, {WidgetState.focused}) as ControlInputBorder;
          final t = _tokens(tester);
          expect(border.radius, windows ? 4 : 5);
          if (windows) {
            // The strong-stroke bottom line at rest, a 2 px accent line when focused.
            expect((border.bottomColor, border.bottomWidth), (t.strongStroke, 1));
            expect((focused.bottomColor, focused.bottomWidth), (t.accent, 2));
          } else {
            // An accent border with the focus ring outside.
            expect(focused.borderSide.color, t.accent);
            expect(focused.focusRing, isNotNull);
          }
        });

        testWidgets('the switches are the platform switch and toggle', (tester) async {
          await _pump(tester, platform, brightness);
          await push(readyState);
          final mute = find.byKey(const Key('mute-out'));
          expect(
            find.descendant(of: mute, matching: find.byType(FluentSwitch)),
            windows ? findsOneWidget : findsNothing,
          );
          expect(
            find.descendant(of: mute, matching: find.byType(CupertinoSwitch)),
            windows ? findsNothing : findsOneWidget,
          );
          if (windows) expect(tester.getSize(mute), const Size(40, 20));
          await tester.tap(mute);
          await tester.pump();
          expect(fake.calls, contains('setOutgoingMuted(true)'));
        });

        testWidgets('held push-to-talk turns accent with the mint glow', (tester) async {
          await _pump(tester, platform, brightness);
          await push(readyState);
          final ptt = find.byKey(const Key('ptt-button'));
          final t = _tokens(tester);
          BoxDecoration decoration() => tester.widget<AnimatedContainer>(ptt).decoration! as BoxDecoration;
          expect(decoration().color, t.pttIdleFill);
          expect(decoration().borderRadius, BorderRadius.circular(windows ? 8 : 12));

          final gesture = await tester.startGesture(tester.getCenter(ptt));
          await tester.pumpAndSettle();
          expect(decoration().color, t.accent);
          expect(decoration().boxShadow!.single.color, Brand.mint.withValues(alpha: 0.45));
          expect(decoration().boxShadow!.single.blurRadius, 24);
          await gesture.up();
          await tester.pumpAndSettle();
          expect(decoration().color, t.pttIdleFill);
        });

        testWidgets('the header carries the brand and leaves the traffic lights free on macOS', (tester) async {
          await _pump(tester, platform, brightness);
          final header = find.byKey(const Key('platform-header'));
          expect(find.byType(AppBar), findsNothing);
          expect(tester.getSize(header).height, windows ? 48 : macToolbarHeight);
          final mark = find.descendant(of: header, matching: find.byType(Image));
          expect(tester.getSize(mark), Size.square(windows ? 24 : 20));
          // macOS: the traffic lights end at 79 pt; nothing of ours starts before the inset.
          expect(tester.getTopLeft(mark).dx, windows ? 16 : macTrafficLightsInset);
          expect(tester.getTopLeft(find.text(Brand.appName)).dx, greaterThan(tester.getTopRight(mark).dx));
          expect(find.descendant(of: header, matching: find.byKey(const Key('language-picker'))), findsOneWidget);
        });
      });
    }
  }

  for (final platform in HostPlatform.values) {
    final windows = platform == HostPlatform.windows;
    testWidgets('${platform.name}: every picker opens the same platform menu', (tester) async {
      await pumpApp(tester, platform: platform);
      final t = _tokens(tester);
      final text = Theme.of(tester.element(find.byType(SetupPanel))).textTheme;
      // The highlighted row: accent with white text on macOS, the subtle fill on Windows.
      final item = platformMenuItemStyle(t, text);
      expect(item.backgroundColor!.resolve({WidgetState.hovered}), windows ? t.subtleFill : t.accent);
      expect(item.foregroundColor!.resolve({WidgetState.hovered}), windows ? t.textPrimary : Colors.white);
      expect(
        platformMenuItemStyle(t, text, current: true).backgroundColor!.resolve({}),
        windows ? t.subtleFill : Colors.transparent,
      );

      for (final (key, current, other) in [
        ('mic-dropdown', 'MacBook Microphone', 'BlackHole 2ch'),
        ('language-picker', 'English', 'Русский'),
        ('my-language', 'Uzbek', 'English'),
      ]) {
        await tester.tap(find.descendant(of: find.byKey(Key(key)), matching: find.byType(TextField)));
        await tester.pumpAndSettle();
        // The open menu's rows (the last of each label; DropdownMenu also keeps an invisible copy for measuring).
        final row = find.widgetWithText(MenuItemButton, current).last;
        final otherRow = find.widgetWithText(MenuItemButton, other).last;
        expect(tester.getSize(row).height, windows ? 32 : 22, reason: key);
        if (windows) {
          Color pill(Finder of) =>
              (tester
                          .widget<Container>(
                            find.descendant(
                              of: of,
                              matching: find.byWidgetPredicate(
                                (w) =>
                                    w is Container &&
                                    w.constraints == const BoxConstraints.tightFor(width: 3, height: 16),
                              ),
                            ),
                          )
                          .decoration!
                      as BoxDecoration)
                  .color!;
          expect(pill(row), t.accent, reason: key);
          expect(pill(otherRow), Colors.transparent, reason: key);
        } else {
          expect(
            find.descendant(of: row, matching: find.byIcon(Icons.check)),
            findsOneWidget,
            reason: key,
          );
          expect(
            find.descendant(of: otherRow, matching: find.byIcon(Icons.check)),
            findsNothing,
            reason: key,
          );
        }
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
      }
      // The header picker is a compact pop-up button, not a full-width field.
      expect(tester.getSize(find.byKey(const Key('language-picker'))).width, lessThan(240));
    });
  }

  testWidgets('macOS full screen drops the room kept for the hidden traffic lights', (tester) async {
    await pumpApp(tester, platform: HostPlatform.macos);
    final mark = find.descendant(of: find.byKey(const Key('platform-header')), matching: find.byType(Image));
    expect(tester.getTopLeft(mark).dx, macTrafficLightsInset);

    Future<void> fullScreen(bool on) async {
      await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
        'livebridge/window',
        const StandardMethodCodec().encodeMethodCall(MethodCall('fullScreen', on)),
        (_) {},
      );
      await tester.pump();
    }

    await fullScreen(true);
    expect(tester.getTopLeft(mark).dx, 16);
    await fullScreen(false);
    expect(tester.getTopLeft(mark).dx, macTrafficLightsInset);
    expect(MacWindow.fullScreen.value, isFalse);
  });

  testWidgets('the Windows switch toggles from the keyboard and shows the focus visual', (tester) async {
    await pumpApp(tester, platform: HostPlatform.windows);
    await push(readyState);
    final mute = find.byKey(const Key('mute-out'));
    final focus = Focus.of(tester.element(find.descendant(of: mute, matching: find.byType(GestureDetector)).first));
    FocusManager.instance.highlightStrategy = FocusHighlightStrategy.alwaysTraditional;
    addTearDown(() => FocusManager.instance.highlightStrategy = FocusHighlightStrategy.automatic);
    focus.requestFocus();
    await tester.pump();
    final ring = find.descendant(of: mute, matching: find.byType(FocusRing));
    expect(tester.widget<FocusRing>(ring).visible, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(fake.calls, contains('setOutgoingMuted(true)'));
    expect(
      tester.getSemantics(find.descendant(of: mute, matching: find.byType(FluentSwitch))),
      isSemantics(hasToggledState: true, isEnabled: true, isFocusable: true, hasTapAction: true),
    );
  });

  testWidgets('choice rows use the platform radio: checked state in semantics, bold title when selected', (
    tester,
  ) async {
    await pumpApp(tester, platform: HostPlatform.windows);
    final captions = find.text(en.modeCaptionsTitle);
    expect(tester.widget<Text>(captions).style!.fontWeight, FontWeight.w600);
    expect(tester.widget<Text>(find.text(en.modeBidirectionalTitle)).style!.fontWeight, isNot(FontWeight.w600));
    expect(
      tester.getSemantics(captions),
      isSemantics(isChecked: true, hasCheckedState: true, isInMutuallyExclusiveGroup: true, hasTapAction: true),
    );
    expect(
      tester.getSemantics(find.text(en.modeBidirectionalTitle)),
      isSemantics(isChecked: false, hasCheckedState: true, isInMutuallyExclusiveGroup: true),
    );
  });
}
