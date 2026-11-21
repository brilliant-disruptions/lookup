/// Keeping a catch: the one way every camera path (the sky camera, the Pro
/// camera, Catch it) puts a picture in Photos and the Log.
///
/// The first time, LookUp says what iPhone is about to ask and recommends
/// Limited access: LookUp only needs the pictures it saves, in its own
/// LookUp album. Then the picture goes to that album, and the Log keeps
/// its Photos id and a small thumbnail. When Photos can't give it back
/// (access refused, an old phone), the Log keeps the whole picture
/// instead, as before.
library;

import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../data/local_store.dart';
import '../domain/models/sky_event.dart';
import '../domain/log/restore.dart';
import '../domain/photo/catch_tag.dart';
import '../services/photo_library.dart';
import '../services/photo_store.dart';
import '../state/providers.dart';
import 'kit/kit.dart';
import 'theme.dart';

/// What LookUp may do with Photos now (for Settings).
final photosAccessProvider = FutureProvider.autoDispose<PhotosAccess>((ref) => ref.watch(photoLibraryProvider).access());

/// The words for [a] in Settings: Limited is always the one recommended.
String photosAccessLine(PhotosAccess a) => switch (a) {
      PhotosAccess.unasked => 'Asked the first time you catch something. Limit Access is enough.',
      PhotosAccess.limited => 'Limited, as recommended. Catches go in your LookUp album and your Log shows them from there.',
      PhotosAccess.full => 'Full access. LookUp only looks at its own LookUp album, so Limited is enough.',
      PhotosAccess.denied => 'Off. Catches stay in your Log, not in Photos. Choose Limited in Settings to keep them in Photos.',
    };

/// Before the first save on iPhone: explain, then let iOS ask. Returns the
/// access LookUp ends up with.
Future<PhotosAccess> askAboutPhotos(BuildContext context, WidgetRef ref) async {
  final lib = ref.read(photoLibraryProvider);
  final now = await lib.access();
  if (now != PhotosAccess.unasked || !context.mounted) return now;
  await showModalBottomSheet<void>(
    context: context,
    isDismissible: false,
    enableDrag: false,
    isScrollControlled: true,
    builder: (_) => const PhotosAccessSheet(),
  );
  return lib.ask();
}

/// Saves [png] (a catch of [event]) to Photos and the Log. Returns where
/// the picture went.
Future<SavedPicture> keepCatch(
  BuildContext context,
  WidgetRef ref, {
  required SkyEvent event,
  required Uint8List png,
  required String title,
  required DateTime at,
  String? place,
}) async {
  await askAboutPhotos(context, ref);
  final s = ref.read(settingsProvider).value;
  final saved = await ref.read(photoLibraryProvider).save(
        png,
        name: 'LookUp-${at.millisecondsSinceEpoch}',
        tag: CatchTag(
          eventId: event.id,
          title: title,
          at: at,
          place: place,
          type: event.type.name,
          elevationDeg: event.peakElevationDeg,
          magnitude: (event.details['magnitude'] as num?)?.toDouble(),
        ),
        lat: s?.latitude,
        lon: s?.longitude,
      );
  // With the picture safe in Photos, the Log only needs a small copy.
  final copy = saved.assetId == null ? png : (await thumbnailPng(png) ?? png);
  final store = ref.read(storeProvider);
  final name = await const PhotoStore().saveBytes(event.id, copy);
  await store.addFeedback(SeenFeedback.forEvent(event, seen: true, place: place));
  await store.setPhoto(event.id, name, asset: saved.assetId);
  ref.invalidate(skyLogProvider);
  return saved;
}

/// Brings catches back into the Log from the LookUp album (a new phone,
/// or a reinstall): each picture's sighting, with its Photos id and a
/// small copy. Returns how many came back.
Future<int> restoreCatches(WidgetRef ref) async {
  final lib = ref.read(photoLibraryProvider);
  final store = ref.read(storeProvider);
  final have = {for (final f in await store.loadFeedback()) f.eventId};
  final found = restorable(await lib.albumCatches(), have);
  for (final (:sighting, :assetId) in found) {
    final s = sighting;
    await store.addFeedback(SeenFeedback(
      eventId: s.eventId,
      seen: true,
      at: s.at,
      type: s.type,
      eventTime: s.eventTime,
      peakElevationDeg: s.peakElevationDeg,
      magnitude: s.magnitude,
      place: s.place,
    ));
    final small = await lib.picture(assetId, px: 480);
    final name = small == null ? null : await const PhotoStore().saveBytes(s.eventId, small, ext: '.jpg');
    await store.setPhoto(s.eventId, name, asset: assetId);
  }
  if (found.isNotEmpty) ref.invalidate(skyLogProvider);
  return found.length;
}

/// A small PNG of [png], [px] wide at most.
Future<Uint8List?> thumbnailPng(Uint8List png, {int px = 480}) async {
  try {
    final codec = await ui.instantiateImageCodec(png, targetWidth: px, allowUpscaling: false);
    final frame = await codec.getNextFrame();
    final data = await frame.image.toByteData(format: ui.ImageByteFormat.png);
    frame.image.dispose();
    return data?.buffer.asUint8List();
  } catch (_) {
    return null;
  }
}

/// What iPhone is about to ask, and which answer LookUp recommends.
class PhotosAccessSheet extends StatelessWidget {
  const PhotosAccessSheet({super.key});

  @override
  Widget build(BuildContext context) => SafeArea(
        child: SingleChildScrollView(
          key: const Key('photos-access'),
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Center(child: PipMark(size: 64, mood: PipMood.shy)),
            const SizedBox(height: 10),
            Text('Your catches go in Photos', textAlign: TextAlign.center, style: display(26, weight: FontWeight.w700, height: 1.15)),
            const SizedBox(height: 8),
            const Text(
              'Pip puts every picture you catch in a LookUp album in Photos, and your Log shows them from there, so they '
              'don\'t take up space twice. Your iPhone will ask next.',
              textAlign: TextAlign.center,
              style: TextStyle(color: LookUpColors.grey, height: 1.45),
            ),
            const SizedBox(height: 16),
            const _Choice(
              key: Key('photos-access-limited'),
              title: 'Limit Access…',
              line: 'You don\'t need to pick any photos. LookUp only sees the pictures it saves, in its own LookUp album.',
              recommended: true,
            ),
            const SizedBox(height: 8),
            const _Choice(
              title: 'Allow Full Access',
              line: 'Works too, but LookUp doesn\'t need it: it still only looks at its album.',
            ),
            const SizedBox(height: 8),
            const _Choice(
              title: 'Don\'t Allow',
              line: 'Catches stay in your Log, not in Photos.',
            ),
            const SizedBox(height: 18),
            FilledButton(
              key: const Key('photos-access-continue'),
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('OK'),
            ),
          ]),
        ),
      );
}

class _Choice extends StatelessWidget {
  const _Choice({super.key, required this.title, required this.line, this.recommended = false});
  final String title, line;
  final bool recommended;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        decoration: BoxDecoration(
          color: recommended ? fireflyGlow.withValues(alpha: 0.1) : LookUpColors.glass,
          borderRadius: BorderRadius.circular(Radii.md),
          border: Border.all(color: recommended ? fireflyGlow.withValues(alpha: 0.55) : LookUpColors.line),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Wrap(spacing: 8, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
            Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
            if (recommended) const Pill('Recommended', color: fireflyGlow),
          ]),
          const SizedBox(height: 3),
          Text(line, style: const TextStyle(fontSize: 13, color: LookUpColors.grey, height: 1.35)),
        ]),
      );
}

/// A sighting's picture: from Photos when the Log has its id, else LookUp's
/// own copy. With [large], the full picture and a line when Photos no
/// longer has it.
class SightingPicture extends ConsumerStatefulWidget {
  const SightingPicture({super.key, required this.photo, this.asset, this.large = false});
  final String? photo, asset;
  final bool large;

  @override
  ConsumerState<SightingPicture> createState() => _SightingPictureState();
}

typedef _Loaded = ({Uint8List? bytes, File? file, bool fromPhotos, bool gone});

class _SightingPictureState extends ConsumerState<SightingPicture> {
  late Future<_Loaded> _load = _fetch();

  @override
  void didUpdateWidget(SightingPicture old) {
    super.didUpdateWidget(old);
    if (old.photo != widget.photo || old.asset != widget.asset || old.large != widget.large) _load = _fetch();
  }

  Future<_Loaded> _fetch() async {
    final id = widget.asset;
    if (id != null) {
      final b = await ref.read(photoLibraryProvider).picture(id, px: widget.large ? 1600 : 160);
      if (b != null) return (bytes: b, file: null, fromPhotos: true, gone: false);
    }
    final f = await const PhotoStore().fileFor(widget.photo);
    return (bytes: null, file: f, fromPhotos: false, gone: id != null);
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<_Loaded>(
        future: _load,
        builder: (context, snap) {
          final d = snap.data;
          final Widget image = d?.bytes != null
              ? Image.memory(d!.bytes!, fit: BoxFit.cover, gaplessPlayback: true)
              : d?.file != null
                  ? Image.file(d!.file!, fit: BoxFit.cover, cacheWidth: widget.large ? null : 120)
                  : const ColoredBox(color: LookUpColors.panelRaised);
          if (!widget.large) return image;
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(Radii.lg),
              child: d == null ? const SizedBox(height: 200, child: ColoredBox(color: LookUpColors.panelRaised)) : image,
            ),
            if (d?.gone ?? false)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text(
                  'It isn\'t in your Photos any more (or LookUp can\'t see it), so this is LookUp\'s small copy. The catch still counts.',
                  key: Key('picture-gone'),
                  style: TextStyle(fontSize: 12.5, color: LookUpColors.grey, height: 1.4),
                ),
              ),
          ]);
        },
      );
}

/// "Bring back my catches": finds catches in the LookUp album that the Log
/// doesn't have (a new phone, a reinstall) and puts them back.
class BringBackCatches extends ConsumerStatefulWidget {
  const BringBackCatches({super.key});

  @override
  ConsumerState<BringBackCatches> createState() => _BringBackCatchesState();
}

class _BringBackCatchesState extends ConsumerState<BringBackCatches> {
  bool _busy = false;

  Future<void> _go() async {
    setState(() => _busy = true);
    try {
      final a = await askAboutPhotos(context, ref);
      if (!mounted) return;
      final n = a == PhotosAccess.denied ? -1 : await restoreCatches(ref);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(switch (n) {
          -1 => 'Allow Photos for LookUp in Settings to find your catches.',
          0 => 'Nothing new in your LookUp album to bring back.',
          1 => 'Brought back 1 catch.',
          _ => 'Brought back $n catches.',
        }),
      ));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => OutlinedButton.icon(
        key: const Key('bring-back-catches'),
        onPressed: _busy ? null : _go,
        icon: _busy
            ? const SizedBox.square(dimension: 16, child: CircularProgressIndicator(strokeWidth: 2))
            : const Icon(Icons.restore_page_rounded, size: 18),
        label: const Text('Bring back my catches from Photos'),
      );
}

