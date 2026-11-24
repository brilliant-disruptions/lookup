/// When a once-a-day feed (Celestrak's elements) is downloaded, so a
/// thousand phones never ask at once.
///
/// Each install picks its own daily slot, a local time between 1 AM and
/// noon, when nobody is out looking up: the slots of many installs spread
/// evenly over those hours (and over every time zone). The background
/// refresh downloads in the few hours after the slot. Opening the app never
/// downloads a feed that is merely a day old: dusk, when everyone opens it,
/// is the spike this avoids. Only a cache well past its day (the phone
/// skipped its background runs, as iPhones do) is fetched on opening, and
/// nothing is ever fetched twice in [minGap].
library;

import 'dart:math';

/// The earliest slot: 1 AM local.
const slotFirstMinute = 60;

/// After the slot, how long a background run may still download. The
/// background job runs every few hours ([backgroundEvery]), so one always
/// lands inside it when the phone lets it.
const slotWindow = Duration(hours: 4);

/// The latest slot: so the window closes by 4 PM, before anyone is out.
const slotLastMinute = 16 * 60 - 4 * 60;

/// How often the background refresh asks to run (Android WorkManager; an
/// iPhone runs it when it chooses).
const backgroundEvery = Duration(hours: 3);

/// Never two downloads of one feed closer than this (one window a day).
const minGap = Duration(hours: 20);

/// Past this, opening the app may download: background runs didn't happen.
/// Well inside the 5 days a Starlink train's elements are trusted for.
const overdueAfter = Duration(hours: 36);

/// A new install's slot: a local minute of the day in
/// [[slotFirstMinute], [slotLastMinute]).
int pickRefreshSlot(Random r) => slotFirstMinute + r.nextInt(slotLastMinute - slotFirstMinute);

/// Whether the feed fetched at [fetchedAt] (null: never) is due now.
/// [localMinute] is now's local minute of the day; [background] is true for
/// the background refresh, false when someone has the app open.
bool feedDue({
  required DateTime? fetchedAt,
  required DateTime now,
  required int localMinute,
  required int slotMinute,
  required bool background,
}) {
  if (fetchedAt == null) return true;
  final age = now.toUtc().difference(fetchedAt.toUtc());
  if (age < minGap) return false;
  if (age >= overdueAfter) return true;
  if (!background) return false;
  return inSlotWindow(localMinute, slotMinute);
}

/// Whether [localMinute] falls in the window that opens at [slotMinute].
bool inSlotWindow(int localMinute, int slotMinute) {
  final since = (localMinute - slotMinute) % (24 * 60);
  return since < slotWindow.inMinutes;
}
