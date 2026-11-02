/// Runs the streak stacker (domain/photo/streak_stacker.dart) off the UI
/// thread: frames go to a long-lived isolate as transferable bytes, and the
/// picture comes back when asked for. [StackRunner.inline] runs it right
/// here, for the practice run's small frames and for tests.
library;

import 'dart:async';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import '../../domain/photo/streak_stacker.dart';
import 'capture_backend.dart';

/// An RGBA picture.
class StackImage {
  const StackImage(this.rgba, this.width, this.height);
  final Uint8List rgba;
  final int width, height;
}

abstract class StackRunner {
  factory StackRunner.inline() = _InlineRunner;

  /// A runner in its own isolate.
  static Future<StackRunner> isolate() => _IsolateRunner.spawn();

  /// Adds a frame. Frames of another size than the first are skipped.
  Future<void> add(CaptureFrame f);

  /// The picture so far, turned [quarterTurns] clockwise, at most
  /// [maxLongPx] on its long side (0 = full size). Null before any frame.
  Future<StackImage?> picture({int quarterTurns = 0, int maxLongPx = 0});

  int get frames;

  /// Still working on an earlier frame: callers with frames to spare may
  /// drop this one.
  bool get busy;

  void dispose();
}

class _InlineRunner implements StackRunner {
  StreakStacker? _s;
  @override
  int frames = 0;

  @override
  bool get busy => false;

  @override
  Future<void> add(CaptureFrame f) async {
    final s = _s ??= StreakStacker(f.width, f.height);
    if (f.width != s.width || f.height != s.height) return;
    s.add(f.y, u: f.u, v: f.v);
    frames++;
  }

  @override
  Future<StackImage?> picture({int quarterTurns = 0, int maxLongPx = 0}) async => _picture(_s, quarterTurns, maxLongPx);

  @override
  void dispose() => _s = null;
}

StackImage? _picture(StreakStacker? s, int turns, int maxLongPx) {
  if (s == null || s.frameCount == 0) return null;
  final scale = maxLongPx <= 0 ? 1 : math.max(1, (math.max(s.width, s.height) / maxLongPx).ceil());
  final r = s.rgba(quarterTurns: turns, scale: scale);
  return StackImage(r.rgba, r.width, r.height);
}

class _IsolateRunner implements StackRunner {
  _IsolateRunner._(this._isolate, this._send);

  final Isolate _isolate;
  final SendPort _send;
  int _inFlight = 0;
  @override
  int frames = 0;

  static Future<_IsolateRunner> spawn() async {
    final hello = ReceivePort();
    final iso = await Isolate.spawn(_main, hello.sendPort, debugName: 'streak-stacker');
    final send = await hello.first as SendPort;
    return _IsolateRunner._(iso, send);
  }

  Future<Object?> _ask(List<Object?> msg) async {
    final reply = ReceivePort();
    _send.send([...msg, reply.sendPort]);
    final v = await reply.first;
    reply.close();
    return v;
  }

  @override
  bool get busy => _inFlight > 1;

  @override
  Future<void> add(CaptureFrame f) async {
    _inFlight++;
    try {
      await _ask([
        'add',
        f.width,
        f.height,
        TransferableTypedData.fromList([f.y]),
        f.u == null ? null : TransferableTypedData.fromList([f.u!]),
        f.v == null ? null : TransferableTypedData.fromList([f.v!]),
      ]);
      frames++;
    } finally {
      _inFlight--;
    }
  }

  @override
  Future<StackImage?> picture({int quarterTurns = 0, int maxLongPx = 0}) async {
    final r = await _ask(['picture', quarterTurns, maxLongPx]);
    if (r is! List) return null;
    return StackImage((r[0] as TransferableTypedData).materialize().asUint8List(), r[1] as int, r[2] as int);
  }

  @override
  void dispose() => _isolate.kill(priority: Isolate.immediate);

  static void _main(SendPort hello) {
    final inbox = ReceivePort();
    hello.send(inbox.sendPort);
    StreakStacker? s;
    inbox.listen((m) {
      final msg = m as List<Object?>;
      final reply = msg.last as SendPort;
      switch (msg.first) {
        case 'add':
          final w = msg[1] as int, h = msg[2] as int;
          final st = s ??= StreakStacker(w, h);
          if (w == st.width && h == st.height) {
            Uint8List? open(Object? t) => t == null ? null : (t as TransferableTypedData).materialize().asUint8List();
            st.add(open(msg[3])!, u: open(msg[4]), v: open(msg[5]));
          }
          reply.send(true);
        case 'picture':
          final p = _picture(s, msg[1] as int, msg[2] as int);
          reply.send(p == null ? null : [TransferableTypedData.fromList([p.rgba]), p.width, p.height]);
      }
    });
  }
}
