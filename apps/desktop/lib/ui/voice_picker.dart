import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../bridge/languages.dart';
import '../bridge/models.dart';
import '../bridge/voices_client.dart';
import '../l10n/app_localizations.dart';
import '../l10n/labels.dart';
import '../state/providers.dart';
import '../state/sample_player.dart';
import '../state/setup_state.dart';
import 'adaptive/control_border.dart';
import 'adaptive/labeled_field.dart';
import 'adaptive/platform_dropdown.dart';
import 'adaptive/platform_tag.dart';
import 'adaptive/pressable.dart';
import 'theme/tokens.dart';

/// Lets the owner choose the voice of one direction: search, filter, listen, pick. Closing it stops any sample.
Future<void> showVoicePicker(BuildContext context, {required Direction direction}) => showDialog<void>(
  context: context,
  builder: (_) => _VoicePicker(direction: direction),
);

/// The labels a voice can be filtered by, in the order the filters are shown.
enum _Facet {
  gender(Icons.person_outline),
  age(Icons.schedule),
  accent(Icons.record_voice_over_outlined),
  language(Icons.language),
  use(Icons.sell_outlined);

  const _Facet(this.icon);

  final IconData icon;

  String? of(Voice voice) => switch (this) {
    gender => voice.gender,
    age => voice.age,
    accent => voice.accent,
    language => voice.language,
    use => voice.useCase,
  };

  String title(AppLocalizations l) => switch (this) {
    gender => l.voiceFilterGender,
    age => l.voiceFilterAge,
    accent => l.voiceFilterAccent,
    language => l.voiceFilterLanguage,
    use => l.voiceFilterUseCase,
  };

  /// A value in words: our own for gender and age, the language's name for a session language, and for anything
  /// else the provider's own word, tidied.
  String label(String value, AppLocalizations l, Map<String, String> languageNames) => switch ((this, value)) {
    (gender, 'male') => l.voiceGenderMale,
    (gender, 'female') => l.voiceGenderFemale,
    (gender, 'neutral') => l.voiceGenderNeutral,
    (age, 'young') => l.voiceAgeYoung,
    (age, 'middle aged') => l.voiceAgeMiddle,
    (age, 'old') => l.voiceAgeOld,
    (language, _) when kLanguages.containsKey(value) => l.languageName(value, languageNames),
    _ => value[0].toUpperCase() + value.substring(1),
  };
}

/// One spelling per value: the provider writes both `middle_aged` and `middle-aged`. Null when there is none.
String? _value(_Facet facet, Voice voice) {
  final value = facet.of(voice)?.toLowerCase().replaceAll(RegExp(r'[\s_-]+'), ' ').trim();
  return value == null || value.isEmpty ? null : value;
}

class _VoicePicker extends ConsumerStatefulWidget {
  const _VoicePicker({required this.direction});

  final Direction direction;

  @override
  ConsumerState<_VoicePicker> createState() => _VoicePickerState();
}

class _VoicePickerState extends ConsumerState<_VoicePicker> {
  final _search = TextEditingController();
  final _filters = <_Facet, String>{};
  late final SamplePlayer _player = ref.read(samplePlayerProvider);
  late final StreamSubscription<String?> _playingChanges;

  /// The sample address being played.
  String? _playing;

  @override
  void initState() {
    super.initState();
    _playingChanges = _player.playing.listen((url) => setState(() => _playing = url));
  }

  @override
  void dispose() {
    _playingChanges.cancel();
    unawaited(_player.stop());
    _search.dispose();
    super.dispose();
  }

  bool _matches(Voice voice) {
    final words = _search.text.trim().toLowerCase();
    if (words.isNotEmpty &&
        !voice.name.toLowerCase().contains(words) &&
        !(voice.description?.toLowerCase().contains(words) ?? false)) {
      return false;
    }
    return _filters.entries.every((filter) => _value(filter.key, voice) == filter.value);
  }

  /// Null is "Default".
  void _choose(Voice? voice) {
    final setup = ref.read(setupProvider.notifier);
    widget.direction == Direction.out
        ? setup.setOutVoice(voice?.id, name: voice?.name)
        : setup.setInVoice(voice?.id, name: voice?.name);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final t = context.tokens;
    final theme = Theme.of(context);
    final out = widget.direction == Direction.out;
    final gateway = ref.watch(setupProvider.select((s) => (url: s.gatewayUrl.trim(), token: s.accessToken.trim())));
    final current = ref.watch(setupProvider.select((s) => out ? s.outVoiceId : s.inVoiceId));
    // The sample is in the language this direction speaks: the other person's for my voice, mine for theirs.
    final spoken = ref.watch(setupProvider.select((s) => out ? s.targetLang : s.myLang));
    final languageNames = ref.watch(languageNamesProvider(l.localeName)).value ?? const <String, String>{};
    final listing = ref.watch(voicesProvider(gateway));
    // Only a list that is on screen has filters; an earlier one is not used while it is reloading or after it failed.
    final voices = listing.isLoading || listing.hasError ? const <Voice>[] : listing.value ?? const <Voice>[];
    final padding = t.isWindows ? 24.0 : 20.0;

    // A filter is offered only when it can tell voices apart.
    final choices = {
      for (final facet in _Facet.values)
        facet: {for (final voice in voices) ?_value(facet, voice)}.toList()
          ..sort((a, b) => facet.label(a, l, languageNames).compareTo(facet.label(b, l, languageNames))),
    }..removeWhere((_, values) => values.length < 2);

    final defaultRow = _Row(
      key: const ValueKey('voice-row-default'),
      title: l.voiceDefault,
      current: current == null,
      onTap: () => _choose(null),
    );

    final Widget body;
    if (listing.isLoading) {
      body = ListView(
        children: [
          defaultRow,
          const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: CircularProgressIndicator()),
          ),
        ],
      );
    } else if (listing.hasError) {
      final error = listing.error;
      body = ListView(
        children: [
          defaultRow,
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 16, 4, 12),
            child: Text(l.voicesFailure(error is VoicesException ? error.failure : VoicesFailure.unavailable)),
          ),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: OutlinedButton(
                key: const Key('voices-retry'),
                onPressed: () => ref.invalidate(voicesProvider(gateway)),
                child: Text(l.voiceRetry),
              ),
            ),
          ),
        ],
      );
    } else {
      // The current voice first, so its check mark is in view however long the list is.
      final shown = [
        ...voices.where((voice) => voice.id == current),
        ...voices.where((voice) => voice.id != current),
      ].where(_matches).toList();
      body = ListView.builder(
        itemCount: math.max(shown.length, 1) + 1,
        itemBuilder: (context, index) {
          if (index == 0) return defaultRow;
          if (shown.isEmpty) {
            return Padding(
              padding: const EdgeInsets.fromLTRB(4, 16, 4, 0),
              child: Text(l.voiceNoMatch, style: theme.textTheme.bodyMedium!.copyWith(color: t.textSecondary)),
            );
          }
          final voice = shown[index - 1];
          final sample = voice.sampleFor(spoken);
          final playing = sample != null && sample == _playing;
          return _Row(
            key: ValueKey('voice-row-${voice.id}'),
            title: voice.name,
            current: voice.id == current,
            onTap: () => _choose(voice),
            leading: IconButton(
              key: Key('voice-play-${voice.id}'),
              tooltip: sample == null ? l.voiceNoSample : (playing ? l.voiceStopSample : l.voicePlaySample),
              onPressed: sample == null ? null : () => unawaited(playing ? _player.stop() : _player.play(sample)),
              icon: Icon(playing ? Icons.stop_circle_outlined : Icons.play_circle_outline),
            ),
            tags: [
              for (final facet in _Facet.values)
                if (_value(facet, voice) case final value?)
                  PlatformTag(icon: facet.icon, label: facet.label(value, l, languageNames)),
            ],
          );
        },
      );
    }

    return Dialog(
      insetPadding: const EdgeInsets.all(16),
      child: ConstrainedBox(
        key: const Key('voice-picker'),
        constraints: const BoxConstraints(maxWidth: 560, maxHeight: 640),
        child: Padding(
          padding: EdgeInsets.all(padding),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Semantics(
                header: true,
                child: Text(
                  out ? l.voicePickerTitleOut : l.voicePickerTitleIn,
                  style: theme.dialogTheme.titleTextStyle,
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                key: const Key('voice-search'),
                controller: _search,
                autofocus: true,
                autocorrect: false,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(hintText: l.voiceSearch),
              ),
              if (choices.isNotEmpty) ...[
                const SizedBox(height: 12),
                _Filters(
                  children: [
                    for (final MapEntry(key: facet, value: values) in choices.entries)
                      LabeledField(
                        key: Key('voice-filter-${facet.name}'),
                        label: facet.title(l),
                        mergeSemantics: false,
                        child: PlatformDropdown<String>(
                          entries: [
                            (value: '', label: l.voiceFilterAll),
                            for (final value in values) (value: value, label: facet.label(value, l, languageNames)),
                          ],
                          value: _filters[facet] ?? '',
                          onChanged: (value) => setState(() {
                            value.isEmpty ? _filters.remove(facet) : _filters[facet] = value;
                          }),
                        ),
                      ),
                  ],
                ),
              ],
              const SizedBox(height: 12),
              Expanded(child: body),
              const SizedBox(height: 16),
              Align(
                alignment: AlignmentDirectional.centerEnd,
                child: OutlinedButton(onPressed: () => Navigator.of(context).pop(), child: Text(l.cancel)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The filters side by side, as many per line as fit at a usable width, all the same width.
class _Filters extends StatelessWidget {
  const _Filters({required this.children});

  static const _gap = 8.0;
  static const _minWidth = 150.0;

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final perLine = ((constraints.maxWidth + _gap) / (_minWidth + _gap)).floor().clamp(1, children.length);
        final width = (constraints.maxWidth - _gap * (perLine - 1)) / perLine;
        return Wrap(
          spacing: _gap,
          runSpacing: _gap,
          children: [for (final child in children) SizedBox(width: width, child: child)],
        );
      },
    );
  }
}

/// One choice in the list: a sample button (or the space of one), the name, its tags, and a check mark on the
/// current one. Clicking the row chooses it; the sample button only plays.
class _Row extends StatelessWidget {
  const _Row({
    super.key,
    required this.title,
    required this.current,
    required this.onTap,
    this.leading,
    this.tags = const [],
  });

  final String title;
  final bool current;
  final VoidCallback onTap;
  final Widget? leading;
  final List<Widget> tags;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Semantics(
      button: true,
      selected: current,
      child: Pressable(
        onPressed: onTap,
        builder: (context, s) => FocusRing(
          visible: s.focused,
          radius: t.controlRadius,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
            decoration: BoxDecoration(
              color: s.pressed ? t.subtleFillPressed : (s.hovered ? t.subtleFill : Colors.transparent),
              borderRadius: BorderRadius.circular(t.controlRadius),
            ),
            child: Row(
              children: [
                SizedBox(width: 40, child: leading),
                const SizedBox(width: 4),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodyMedium!
                            .copyWith(color: t.textPrimary, fontWeight: current ? FontWeight.w600 : null),
                      ),
                      if (tags.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Wrap(spacing: 4, runSpacing: 4, children: tags),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(width: 20, child: current ? Icon(Icons.check, size: 18, color: t.accentText) : null),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
