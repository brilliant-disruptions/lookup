/// Help, the support address, and the links Apple asks for wherever
/// LookUp+ is sold: Terms of Use (Apple's standard licence) and the privacy
/// policy (served by the relay, `relay/src/pages.ts`).
library;

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/aurora_reports_client.dart' show relayUrl;
import 'theme.dart';

const supportEmail = 'hello@brilliantdisruptions.com';

/// Keep in step with `version:` in pubspec.yaml (a test checks).
const appVersion = '1.0.1';

/// Where the public pages live: the relay this build talks to, or the
/// deployed one.
String get siteBase {
  const fallback = 'https://lookup-relay.brilliant-disruptions.workers.dev';
  final u = relayUrl.isNotEmpty ? relayUrl : fallback;
  return u.endsWith('/') ? u.substring(0, u.length - 1) : u;
}

Uri get privacyUri => Uri.parse('$siteBase/privacy');
Uri get supportUri => Uri.parse('$siteBase/support');
final termsUri = Uri.parse('https://www.apple.com/legal/internet-services/itunes/dev/stdeula/');

/// Where a subscription is changed or cancelled: the store's own page.
Uri get manageSubscriptionUri => Uri.parse(Platform.isIOS
    ? 'https://apps.apple.com/account/subscriptions'
    : 'https://play.google.com/store/account/subscriptions');

/// An email to support with the app's version and the phone's system
/// filled in (nothing else: no location, no account).
Uri reportProblemUri({required bool isPlus}) {
  final os = Platform.isIOS ? 'iOS' : Platform.isAndroid ? 'Android' : Platform.operatingSystem;
  final body = 'What happened?\n\n\n\n—\nLookUp $appVersion${isPlus ? ' · LookUp+' : ''} · $os ${Platform.operatingSystemVersion}';
  return Uri(scheme: 'mailto', path: supportEmail, query: _query({'subject': 'LookUp: a problem', 'body': body}));
}

String _query(Map<String, String> q) => q.entries.map((e) => '${e.key}=${Uri.encodeComponent(e.value)}').join('&');

/// Opens [uri] outside the app; if nothing can, offers the address to copy.
Future<void> openLink(BuildContext context, Uri uri) async {
  var ok = false;
  try {
    ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
  } catch (_) {}
  if (ok || !context.mounted) return;
  final text = uri.scheme == 'mailto' ? supportEmail : uri.toString();
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
    content: Text('Couldn\'t open it. $text'),
    action: SnackBarAction(label: 'Copy', onPressed: () => Clipboard.setData(ClipboardData(text: text))),
  ));
}

/// "Terms of Use · Privacy Policy", under anything that sells LookUp+.
class LegalLinks extends StatelessWidget {
  const LegalLinks({super.key});

  @override
  Widget build(BuildContext context) {
    const style = TextStyle(fontSize: 12.5, color: LookUpColors.grey, decoration: TextDecoration.underline, decorationColor: LookUpColors.greyDim);
    Widget link(String label, Uri uri, Key key) => InkWell(
          key: key,
          onTap: () => openLink(context, uri),
          borderRadius: BorderRadius.circular(6),
          child: Padding(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6), child: Text(label, style: style)),
        );
    return Wrap(alignment: WrapAlignment.center, crossAxisAlignment: WrapCrossAlignment.center, children: [
      link('Terms of Use', termsUri, const Key('terms-link')),
      const Text('·', style: TextStyle(color: LookUpColors.greyDim)),
      link('Privacy Policy', privacyUri, const Key('privacy-link')),
    ]);
  }
}
