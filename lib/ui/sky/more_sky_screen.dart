/// "More of the sky": asks what you'd like to do, and each answer is one
/// page with one job. Tonight's clouds, the story and favourites sit under
/// the two jobs, since they're read rather than done.
library;

import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../state/sky_state.dart';
import '../kit/kit.dart';
import '../theme.dart';
import 'night_strip.dart';
import 'sky_screen.dart';
import 'sky_shortcuts.dart';

class MoreSkyScreen extends ConsumerWidget {
  const MoreSkyScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final outlook = ref.watch(tonightSkyProvider).value?.outlook;
    void go(SkyMode mode) => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => SkyScreen(mode: mode)));
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: const PageHeader(title: 'More of the sky'),
      body: SkyBackdrop(
        stars: false,
        child: ListView(
          padding: EdgeInsets.fromLTRB(16, MediaQuery.paddingOf(context).top + 58 + 16, 16, tabBarClearance(context)),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 0, 4, 12),
              child: Text('What would you like to do?', style: display(24, weight: FontWeight.w700)),
            ),
            GroupedList(indent: 64, children: [
              ListRow(
                key: const Key('sky-find'),
                leading: const EventGlyph(icon: Icons.search_rounded, color: LookUpColors.blue),
                title: 'Find something',
                subtitle: 'Pick a planet, constellation or showpiece and see when and where to look',
                chevron: true,
                onTap: () => go(SkyMode.browse),
              ),
              ListRow(
                key: const Key('sky-time'),
                leading: const EventGlyph(icon: Icons.schedule_rounded, color: LookUpColors.violet),
                title: 'See another time',
                subtitle: 'The sky later tonight, or any night this week',
                chevron: true,
                onTap: () => go(SkyMode.time),
              ),
            ]),
            if (outlook != null) ...[
              const SizedBox(height: 20),
              GlassCard(
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  const Kicker('Tonight\'s clouds'),
                  const SizedBox(height: 6),
                  NightStrip(outlook: outlook),
                ]),
              ),
            ],
            const SizedBox(height: 20),
            const SkyShortcuts(),
          ],
        ),
      ),
    );
  }
}
