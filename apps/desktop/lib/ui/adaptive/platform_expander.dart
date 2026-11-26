import 'package:flutter/material.dart';

import '../theme/tokens.dart';
import 'control_border.dart';
import 'pressable.dart';

/// A collapsible section that replaces [ExpansionTile]. Windows: the Expander look (header row with an optional
/// icon, title and description, and a chevron on the right that turns over when open; the open part on the
/// secondary card fill under a divider). macOS: a disclosure group (a chevron on the right that turns from › to ⌄).
///
/// Put the top-level expander in a [Card]: the card draws the outline and the rounded corners. [nested] expanders
/// (topics inside a section) are plain rows.
class PlatformExpander extends StatefulWidget {
  const PlatformExpander({
    super.key,
    required this.title,
    required this.children,
    this.subtitle,
    this.icon,
    this.controller,
    this.enabled = true,
    this.onExpansionChanged,
    this.childrenPadding = EdgeInsets.zero,
    this.nested = false,
  });

  final String title;
  final String? subtitle;
  final IconData? icon;
  final List<Widget> children;

  /// Drives the expander from outside (e.g. to fold it); one is made when null.
  final ExpansibleController? controller;
  final bool enabled;
  final ValueChanged<bool>? onExpansionChanged;
  final EdgeInsets childrenPadding;
  final bool nested;

  @override
  State<PlatformExpander> createState() => _PlatformExpanderState();
}

class _PlatformExpanderState extends State<PlatformExpander> {
  late ExpansibleController _controller = widget.controller ?? ExpansibleController();

  @override
  void initState() {
    super.initState();
    _controller.addListener(_changed);
  }

  @override
  void didUpdateWidget(PlatformExpander old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      _controller.removeListener(_changed);
      if (old.controller == null) _controller.dispose();
      _controller = widget.controller ?? ExpansibleController();
      _controller.addListener(_changed);
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_changed);
    if (widget.controller == null) _controller.dispose();
    super.dispose();
  }

  void _changed() {
    setState(() {});
    widget.onExpansionChanged?.call(_controller.isExpanded);
  }

  void _toggle() => _controller.isExpanded ? _controller.collapse() : _controller.expand();

  Widget _header(BuildContext context, Animation<double> animation) {
    final t = context.tokens;
    final text = Theme.of(context).textTheme;
    final expanded = _controller.isExpanded;
    final enabled = widget.enabled;
    final titleStyle = text.bodyMedium!.copyWith(
      color: enabled ? t.textPrimary : t.textDisabled,
      fontWeight: widget.nested ? null : FontWeight.w600,
    );
    // Windows turns a down chevron over (180°); macOS turns a right chevron down (90°).
    final chevron = RotationTransition(
      turns: animation.drive(Tween(begin: 0.0, end: t.isWindows ? 0.5 : 0.25)),
      child: Icon(
        t.isWindows ? Icons.keyboard_arrow_down : Icons.chevron_right,
        size: t.isWindows ? 16 : 18,
        color: enabled ? t.textSecondary : t.textDisabled,
      ),
    );
    return Semantics(
      button: true,
      expanded: expanded,
      child: Pressable(
        onPressed: enabled ? _toggle : null,
        builder: (context, s) {
          final radius = widget.nested ? t.controlRadius + 4 : t.cardRadius;
          return FocusRing(
            visible: s.focused,
            radius: radius,
            // Headers span the whole card, and the card clips anything outside it.
            inset: 4,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 83),
              constraints: BoxConstraints(minHeight: widget.nested ? t.controlHeight + 4 : (t.isWindows ? 64 : 48)),
              padding: widget.nested
                  ? EdgeInsets.symmetric(horizontal: t.cardPadding, vertical: 6)
                  : EdgeInsets.symmetric(horizontal: t.cardPadding, vertical: 10),
              decoration: BoxDecoration(
                color: s.pressed ? t.subtleFillPressed : (s.hovered ? t.subtleFill : Colors.transparent),
                borderRadius: BorderRadius.circular(radius),
              ),
              child: Row(
                children: [
                  if (widget.icon case final icon?) ...[
                    Icon(icon, size: t.isWindows ? 20 : 18, color: enabled ? t.textPrimary : t.textDisabled),
                    SizedBox(width: t.isWindows ? 16 : 10),
                  ],
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(widget.title, style: titleStyle),
                        if (widget.subtitle case final subtitle?)
                          Text(subtitle, style: text.bodySmall!.copyWith(color: t.textSecondary)),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (t.isWindows)
                    // WinUI puts the chevron in a 32 px subtle button.
                    SizedBox.square(dimension: 32, child: Center(child: chevron))
                  else
                    chevron,
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _body(BuildContext context, Animation<double> animation) {
    final t = context.tokens;
    // Full width: Expansible centres a body narrower than the header.
    final content = SizedBox(
      width: double.infinity,
      child: Padding(
        padding: widget.childrenPadding,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: widget.children),
      ),
    );
    if (widget.nested) return content;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: t.cardSecondary,
        border: Border(top: BorderSide(color: t.divider)),
      ),
      child: Padding(padding: const EdgeInsets.only(top: 12), child: content),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Expansible(
      controller: _controller,
      maintainState: false,
      animationStyle: MediaQuery.disableAnimationsOf(context)
          ? AnimationStyle.noAnimation
          : const AnimationStyle(duration: Duration(milliseconds: 200), curve: Curves.ease),
      headerBuilder: _header,
      bodyBuilder: _body,
      expansibleBuilder: (context, header, body, animation) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [header, body],
      ),
    );
  }
}
