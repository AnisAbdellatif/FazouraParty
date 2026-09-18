/// LAN hosting, or a stub where it is impossible.
///
/// `dart:io` is behind this conditional export so the Web build still compiles
/// (AGENTS.md §7). Check [lanHostingSupported] before offering it in the UI.
library;

export 'lan_host_io.dart' if (dart.library.js_interop) 'lan_host_stub.dart';

/// False on Web, where no listening socket can be opened.
const lanHostingSupported = bool.fromEnvironment('dart.library.io');
