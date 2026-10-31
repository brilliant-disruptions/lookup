import 'package:flutter_test/flutter_test.dart';
import 'package:lookup/ui/format.dart';

void main() {
  test('never "Appears in 0s": the last few seconds say it is appearing now', () {
    expect(fmtAppears(const Duration(minutes: 4, seconds: 10)), 'Appears in 4m 10s');
    expect(fmtAppears(const Duration(seconds: 12)), 'Appears in 12s');
    expect(fmtAppears(const Duration(seconds: 4)), 'Appearing now');
    expect(fmtAppears(Duration.zero), 'Appearing now');
    expect(fmtAppears(const Duration(seconds: -3)), 'Appearing now');
  });
}
