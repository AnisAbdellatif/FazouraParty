import 'dart:async';
import 'dart:io';

import 'package:phoenix_socket/phoenix_socket.dart';

/// Runs [body] in a zone that absorbs one known stray error.
///
/// `phoenix_socket` tracks each pending reply as
/// `completer.future.whenComplete(...)` and never listens to what that
/// returns. When a socket closes with a reply outstanding — every time a room
/// closes, since closing it is what drops the socket — the reply's own future
/// fails and is handled, and the copy fails with nobody listening: an uncaught
/// `PhoenixException`. Flutter's error zone swallows it, which is why the app
/// never noticed. A plain Dart program exits on it.
///
/// So this zone drops that exception and nothing else: any other uncaught
/// error still reaches stderr and fails the run.
Future<T> absorbSocketNoise<T>(Future<T> Function() body) {
  final result = Completer<T>();
  runZonedGuarded(
    () => body().then(result.complete, onError: result.completeError),
    (error, stack) {
      if (error is PhoenixException) return;
      if (!result.isCompleted) {
        result.completeError(error, stack);
      } else {
        stderr.writeln('fazoura: $error\n$stack');
      }
    },
  );
  return result.future;
}
