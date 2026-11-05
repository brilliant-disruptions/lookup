import 'dart:convert';
import 'dart:isolate';

/// Bodies this big are decoded off the UI thread so a first launch's
/// downloads don't stall the screen.
const offThreadBytes = 256 * 1024;

/// `jsonDecode(body)` passed through [then], on another isolate when the
/// body is big (so only [then]'s result crosses back, not the whole tree).
Future<T> decodeJson<T>(String body, T Function(Object? json) then) =>
    body.length < offThreadBytes ? Future.value(then(jsonDecode(body))) : Isolate.run(() => then(jsonDecode(body)));
