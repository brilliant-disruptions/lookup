/// "This year": the next twelve months' big dates where you are, a month to
/// a group (domain/events/year_ahead.dart). Opened from the Week tab's
/// header. A sky event opens its Look sheet; a season's start just says
/// what it means.
library;

import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../domain/events/year_ahead.dart';
import '../domain/sky/seasons.dart';
import '../state/providers.dart';
import 'format.dart';
import 'kit/kit.dart';
import 'look_sheet.dart';
import 'theme.dart';

/// The year from today at the saved place; empty without one.
final yearAheadProvider = FutureProvider<List<YearEntry>>((ref) async {
  final s = await ref.watch(settingsProvider.future);
  if (!s.hasLocation) return const [];
  return yearAhead(now: DateTime.now(), latDeg: s.latitude!, lonDeg: s.longitude!);
});

Future<void> openYearAhead(BuildContext context) =>
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const YearAheadScreen()));

class YearAheadButton extends StatelessWidget {
  const YearAheadButton({super.key});
  @override
  Widget build(BuildContext context) => CircleButton(
        key: const Key('year-ahead'),
        tooltip: 'This year',
        icon: Icons.calendar_month_rounded,
        onPressed: () => openYearAhead(context),
      );
}

class YearAheadScreen extends ConsumerWidget {
  const YearAheadScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final year = ref.watch(yearAheadProvider);
    final lat = ref.watch(settingsProvider).value?.latitude ?? 0;
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: const PageHeader(title: 'This year'),
      body: SkyBackdrop(
        stars: false,
        child: year.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, _) => LoadTrouble(what: 'The year ahead didn\'t load.', onRetry: () => ref.invalidate(yearAheadProvider)),
          data: (entries) {
            final months = <String, List<YearEntry>>{};
            for (final e in entries) {
              months.putIfAbsent(DateFormat.yMMMM().format(e.at.toLocal()), () => []).add(e);
            }
            return ListView(
              padding: EdgeInsets.fromLTRB(16, MediaQuery.paddingOf(context).top + 58 + 16, 16, tabBarClearance(context)),
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 0, 4, 16),
                  child: Text('The big dates of the next twelve months, worked out for where you are.',
                      style: TextStyle(color: LookUpColors.grey, fontSize: 14.5)),
                ),
                for (final m in months.entries) ...[
                  Padding(padding: const EdgeInsets.fromLTRB(4, 8, 4, 8), child: Kicker(m.key)),
                  GroupedList(indent: 64, children: [for (final e in m.value) _row(context, e, lat)]),
                  const SizedBox(height: 12),
                ],
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _row(BuildContext context, YearEntry y, double lat) {
    final day = DateFormat.MMMEd().format(y.at.toLocal());
    final e = y.event;
    if (e != null) {
      return ListRow(
        key: Key('year-${e.id}'),
        leading: EventGlyph.of(e),
        title: eventTitle(e),
        subtitle: '$day · ${eventSubtitle(e)}',
        chevron: true,
        onTap: () => showLookSheet(context, e),
      );
    }
    final s = y.season!;
    return ListRow(
      key: Key('year-season-${s.mark.name}-${s.at.year}'),
      leading: EventGlyph(
          icon: s.mark.equinox ? Icons.brightness_6_rounded : Icons.wb_sunny_rounded,
          color: s.mark.equinox ? LookUpColors.cyan : LookUpColors.orange),
      title: seasonName(s.mark, latDeg: lat),
      subtitle: '$day, ${fmtTime(s.at)} · ${seasonLine(s.mark, latDeg: lat)}',
    );
  }
}
