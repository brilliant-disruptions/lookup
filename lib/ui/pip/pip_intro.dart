/// Meet Pip: three short pages before the first ask, and again from
/// Settings. Pip has no face; each page shows one of its moods
/// (pip_motion.dart), so the intro teaches what they mean: hello, flying to
/// where to look, and lighting up once you've found it.
library;

import 'package:material_ui/material_ui.dart';

import '../kit/kit.dart';
import '../theme.dart';

class PipIntro extends StatefulWidget {
  const PipIntro({super.key, required this.onDone, this.doneLabel = 'Nice to meet you'});

  final VoidCallback onDone;
  final String doneLabel;

  @override
  State<PipIntro> createState() => _PipIntroState();
}

class _Page {
  const _Page(this.state, this.title, this.body, {this.flyFrom});
  final PipState state;
  final String title, body;
  final Offset? flyFrom;
}

const _pages = [
  _Page(PipState.hello, 'Hi! I\'m Pip.', 'I\'ll help you rediscover the sky.'),
  _Page(PipState.idle, 'I fly there first.',
      'Hold your phone up. Wherever you need to look, I\'ll be there. Just follow my light.',
      flyFrom: Offset(-150, 150)),
  _Page(PipState.found, 'Then I light up.',
      'When you\'ve found it, you\'ll know. If I can\'t see, through cloud or without your location, I dim and say so.'),
];

class _PipIntroState extends State<PipIntro> {
  final _pager = PageController();
  int _page = 0;

  @override
  void dispose() {
    _pager.dispose();
    super.dispose();
  }

  void _next() {
    if (_page == _pages.length - 1) {
      widget.onDone();
    } else {
      _pager.nextPage(duration: const Duration(milliseconds: 380), curve: Curves.easeOutCubic);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = _pages[_page];
    final last = _page == _pages.length - 1;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(onPressed: widget.onDone, child: const Text('Skip')),
        ),
        // Pip changes with the page, and plays its mood from the start.
        Expanded(
          flex: 5,
          child: Center(
            child: PipMark(
              key: ValueKey('pip-intro-$_page'),
              size: 180,
              state: p.state,
              flyFrom: p.flyFrom,
            ),
          ),
        ),
        // Grows with the text and scrolls at large text sizes, never clips.
        Expanded(
          flex: 4,
          child: PageView.builder(
            controller: _pager,
            itemCount: _pages.length,
            onPageChanged: (i) => setState(() => _page = i),
            itemBuilder: (context, i) => SingleChildScrollView(child: Column(children: [
              Text(_pages[i].title,
                  textAlign: TextAlign.center, style: display(36, weight: FontWeight.w800, height: 1.1)),
              const SizedBox(height: 14),
              Text(_pages[i].body,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 17, color: LookUpColors.grey, height: 1.5)),
            ])),
          ),
        ),
        const SizedBox(height: 12),
        Semantics(
          label: 'Page ${_page + 1} of ${_pages.length}',
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            for (var i = 0; i < _pages.length; i++)
              AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                margin: const EdgeInsets.symmetric(horizontal: 4),
                width: i == _page ? 22 : 6,
                height: 6,
                decoration: BoxDecoration(
                  color: i == _page ? fireflyGlow : LookUpColors.greyDim.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
          ]),
        ),
        const SizedBox(height: 24),
        FilledButton(onPressed: _next, child: Text(last ? widget.doneLabel : 'Next')),
      ]),
    );
  }
}

/// Meet Pip again, from Settings.
Future<void> showPipIntro(BuildContext context) => Navigator.of(context).push(MaterialPageRoute(
      fullscreenDialog: true,
      builder: (context) => Scaffold(
        body: SkyBackdrop(
          child: SafeArea(child: PipIntro(doneLabel: 'Done', onDone: () => Navigator.of(context).maybePop())),
        ),
      ),
    ));
