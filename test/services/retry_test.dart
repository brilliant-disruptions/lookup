import 'package:flutter_test/flutter_test.dart';
import 'package:lookup/data/retry.dart';

void main() {
  test('retries transient failures, then succeeds', () async {
    var calls = 0;
    final waits = <Duration>[];
    final v = await withRetry(() async {
      calls++;
      if (calls < 3) throw Exception('connection reset');
      return 42;
    }, sleep: (d) async => waits.add(d));
    expect(v, 42);
    expect(calls, 3);
    expect(waits, [const Duration(seconds: 2), const Duration(seconds: 4)]);
  });

  test('gives up after the last attempt and rethrows', () async {
    var calls = 0;
    await expectLater(
      withRetry<int>(() async {
        calls++;
        throw StateError('down');
      }, attempts: 3, sleep: (_) async {}),
      throwsStateError,
    );
    expect(calls, 3);
  });
}
