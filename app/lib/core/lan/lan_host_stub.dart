/// Web stand-in for the LAN host.
///
/// A browser cannot open a listening socket, so LAN hosting is impossible on
/// Web by platform constraint, not by choice (assessment §4.2). This keeps the
/// Web build compiling without `dart:io` (AGENTS.md §7); [lanHostingSupported]
/// lets the UI hide the option rather than offer something that throws.
library;

import '../game/lan_room.dart';
import '../game/pack.dart';

const defaultLanPort = 4040;
const heartbeatTimeout = Duration(seconds: 60);

class LanHost {
  LanHost._();

  static Future<LanHost> start({
    Pack? pack,
    int port = defaultLanPort,
    LanRoom? room,
  }) => throw UnsupportedError(
    'LAN hosting needs a listening socket, which a browser cannot open. '
    'Host from the Android app, or use Cloud mode.',
  );

  LanRoom get room =>
      throw UnsupportedError('LAN hosting is not available on the web.');
  int get port =>
      throw UnsupportedError('LAN hosting is not available on the web.');
  List<String> get addresses => const [];
  String get roomCode =>
      throw UnsupportedError('LAN hosting is not available on the web.');
  String get hostToken =>
      throw UnsupportedError('LAN hosting is not available on the web.');
  String? get joinUrl => null;

  Future<void> stop({LanCloseReason reason = LanCloseReason.shutdown}) async {}
}

String lanErrorMessage(String code) => 'Malformed request.';
