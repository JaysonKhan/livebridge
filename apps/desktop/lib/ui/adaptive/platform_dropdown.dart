import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../theme/tokens.dart';

/// One choice in a [PlatformDropdown].
typedef PlatformDropdownEntry<T> = ({T value, String label});

/// The one pop-up picker of the app (device pickers, the header language picker, the session languages), so the
/// theme decides every menu's look in one place (`platformMenuStyle`, `platformMenuItemStyle`).
///
/// macOS: a pop-up button with chevrons opening an NSMenu-like list, the current item marked by a check mark in front
/// of it. Windows: a ComboBox with a chevron opening a flyout list, the current item marked by a 3×16 accent pill and
/// the subtle fill. With [filter] the field is typed into and narrows the list (the session languages); otherwise it
/// is a button that only opens the list (keyboard: Enter opens it, the arrow keys move through it).
class PlatformDropdown<T> extends StatelessWidget {
  const PlatformDropdown({
    super.key,
    required this.entries,
    required this.value,
    required this.onChanged,
    this.filter = false,
    this.hint,
    this.expand = true,
    this.menuHeight = 320,
  });

  final List<PlatformDropdownEntry<T>> entries;

  /// The current choice; null shows [hint].
  final T? value;
  final ValueChanged<T> onChanged;
  final bool filter;
  final String? hint;

  /// Full width (setup fields) or as wide as the longest choice (the header picker).
  final bool expand;
  final double menuHeight;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final text = Theme.of(context).textTheme;
    return IconButtonTheme(
      // The menu button inside the field: small enough that the field keeps the control height.
      data: IconButtonThemeData(
        style: IconButtonTheme.of(context).style!.copyWith(
          minimumSize: WidgetStatePropertyAll(Size.square(t.controlHeight - 8)),
          padding: const WidgetStatePropertyAll(EdgeInsets.zero),
        ),
      ),
      child: DropdownMenu<T>(
        // Re-created when the choice or the list changes from outside, so the field shows the current label.
        key: ValueKey((value, entries.map((e) => e.label).join('\n'))),
        initialSelection: value,
        hintText: hint,
        expandedInsets: expand ? EdgeInsets.zero : null,
        menuHeight: menuHeight,
        enableFilter: filter,
        // Without a filter nothing is highlighted until the keyboard moves through the list; the check mark (pill)
        // shows the current item.
        enableSearch: filter,
        requestFocusOnTap: true,
        selectOnly: !filter,
        inputDecorationTheme: filter ? null : comboBoxDecorationTheme(t, text),
        trailingIcon: Icon(t.isWindows ? Icons.keyboard_arrow_down : Icons.unfold_more, size: 16),
        selectedTrailingIcon: Icon(t.isWindows ? Icons.keyboard_arrow_up : Icons.unfold_more, size: 16),
        onSelected: (choice) {
          if (choice != null) onChanged(choice);
        },
        dropdownMenuEntries: [
          for (final e in entries)
            DropdownMenuEntry<T>(
              value: e.value,
              label: e.label,
              labelWidget: Text(e.label, maxLines: 1, overflow: TextOverflow.ellipsis),
              leadingIcon: _CurrentMarker(current: e.value == value),
              style: platformMenuItemStyle(t, text, current: e.value == value),
            ),
        ],
      ),
    );
  }
}

/// macOS: a check mark in front of the current item (the same width left empty for the others). Windows: a 3×16
/// accent pill at the item's left edge.
class _CurrentMarker extends StatelessWidget {
  const _CurrentMarker({required this.current});

  final bool current;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    if (t.isWindows) {
      return Container(
        width: 3,
        height: 16,
        decoration: BoxDecoration(
          color: current ? t.accent : Colors.transparent,
          borderRadius: BorderRadius.circular(1.5),
        ),
      );
    }
    // The icon colour follows the row (white on the highlighted row).
    return SizedBox(width: 12, child: current ? const Icon(Icons.check, size: 13) : null);
  }
}
