/// Where LookUp's relay is (relay/): clouds, rare events, invites and
/// "Seen near you" all go through it.
///
/// The address comes in at build time:
/// `--dart-define=LOOKUP_RELAY_URL=https://…`. A release build must have
/// one: `tool/check_release_env.sh` refuses to build without it (Android CI,
/// Xcode Cloud), and [relayMissingInRelease] says so loudly at launch if one
/// slips through. Without it there are no clouds: the app says "No forecast"
/// and never calls a sky clear it hasn't seen.
library;

import 'package:flutter/foundation.dart';

const relayUrl = String.fromEnvironment('LOOKUP_RELAY_URL');

/// Whether this build knows a relay at all.
bool get relayConfigured => relayUrl.isNotEmpty;

/// A release build with no relay: a build mistake, never a choice. Debug
/// and test builds may leave it out.
bool relayMissing({required bool release, String url = relayUrl}) => release && url.isEmpty;

bool get relayMissingInRelease => relayMissing(release: kReleaseMode);
