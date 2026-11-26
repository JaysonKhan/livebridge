import 'package:flutter/material.dart' hide ConnectionState;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../bridge/account_client.dart';
import '../l10n/app_localizations.dart';
import '../l10n/labels.dart';
import '../state/connection_state.dart';
import 'adaptive/control_border.dart';
import 'adaptive/pressable.dart';
import 'theme/tokens.dart';

/// The packages to buy with their prices; choosing one opens the checkout in the browser and closes the sheet.
Future<void> showTopUpSheet(BuildContext context) =>
    showDialog<void>(context: context, builder: (_) => const _TopUpSheet());

/// Whole dollars without decimals ("$6"), else with cents ("$7.50").
String priceLabel(int cents) => cents % 100 == 0 ? '\$${cents ~/ 100}' : '\$${(cents / 100).toStringAsFixed(2)}';

class _TopUpSheet extends ConsumerStatefulWidget {
  const _TopUpSheet();

  @override
  ConsumerState<_TopUpSheet> createState() => _TopUpSheetState();
}

class _TopUpSheetState extends ConsumerState<_TopUpSheet> {
  /// The packages are being read again.
  late bool _loading = ref.read(connectionProvider).packages.isEmpty;

  /// A checkout was asked for and has not answered.
  bool _busy = false;

  String? _error;

  @override
  void initState() {
    super.initState();
    if (_loading) Future.microtask(_load);
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    await ref.read(connectionProvider.notifier).refreshAccount();
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _choose(Package package) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final failure = await ref.read(connectionProvider.notifier).topUp(package.code);
    if (!mounted) return;
    // Signed out meanwhile: the onboarding takes over, nothing to say here.
    if (failure == null || failure == 'signed_out') {
      Navigator.of(context).pop();
      return;
    }
    setState(() {
      _busy = false;
      _error = failure;
    });
  }

  String _errorText(AppLocalizations l, String code) => switch (code) {
    'rate_limited' => l.topUpRateLimited,
    'network' => l.topUpNetwork,
    _ => l.topUpUnavailable,
  };

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final t = context.tokens;
    final packages = ref.watch(connectionProvider.select((s) => s.packages));
    final small = Theme.of(context).textTheme.bodySmall!.copyWith(color: t.textSecondary);
    return AlertDialog(
      key: const Key('top-up-sheet'),
      title: Text(l.topUpTitle),
      content: SizedBox(
        width: 360,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (packages.isEmpty)
                if (_loading)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 16),
                    child: Center(
                      child: SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                    ),
                  )
                else ...[
                  Text(l.topUpNoPackages),
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: TextButton(onPressed: _load, child: Text(l.topUpTryAgain)),
                  ),
                ]
              else
                for (final p in packages)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: _PackageRow(package: p, onPressed: _busy ? null : () => _choose(p)),
                  ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(_errorText(l, _error!), style: TextStyle(color: t.critical.foreground)),
                ),
              Text(l.topUpTaxNote, style: small),
            ],
          ),
        ),
      ),
      actions: [OutlinedButton(onPressed: () => Navigator.of(context).pop(), child: Text(l.cancel))],
    );
  }
}

class _PackageRow extends StatelessWidget {
  const _PackageRow({required this.package, required this.onPressed});

  final Package package;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final text = Theme.of(context).textTheme;
    final minutes = context.l10n.topUpMinutes(package.minutes);
    final price = priceLabel(package.priceCents);
    return MergeSemantics(
      child: Semantics(
        button: true,
        enabled: onPressed != null,
        child: Pressable(
          key: Key('package-${package.code}'),
          onPressed: onPressed,
          builder: (context, s) => FocusRing(
            visible: s.focused,
            radius: t.controlRadius,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: s.pressed ? t.subtleFillPressed : (s.hovered ? t.subtleFill : Colors.transparent),
                borderRadius: BorderRadius.circular(t.controlRadius),
                border: Border.all(color: t.strongStroke),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      minutes,
                      style: text.bodyLarge!.copyWith(
                        color: onPressed == null ? t.textDisabled : t.textPrimary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Text(
                    price,
                    style: text.bodyLarge!.copyWith(color: onPressed == null ? t.textDisabled : t.accentText),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
