import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lookup/ui/help.dart';

void main() {
  test('the version support sees matches the app\'s', () {
    final v = RegExp(r'^version:\s*([0-9.]+)', multiLine: true).firstMatch(File('pubspec.yaml').readAsStringSync())!.group(1);
    expect(appVersion, v);
  });

  test('Report a problem: an email to support with the version and system, and nothing about where you are', () {
    final u = reportProblemUri(isPlus: true);
    expect((u.scheme, u.path), ('mailto', supportEmail));
    final body = Uri.decodeComponent(u.query);
    expect(body, contains('LookUp $appVersion · LookUp+'));
    expect(body, isNot(matches(RegExp(r'lat|lon|-?\d+\.\d{3,}'))));
  });

  test('Terms are Apple\'s standard licence; privacy and help are pages on LookUp\'s site', () {
    expect(termsUri.host, 'www.apple.com');
    expect(privacyUri.path, '/privacy');
    expect(supportUri.path, '/support');
    expect(privacyUri.scheme, 'https');
  });
}
