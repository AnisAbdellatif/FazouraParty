/// Which host the next connection talks to.
///
/// The `GameConnection` seam means nothing above this layer knows whether a
/// game is Cloud or LAN (AGENTS.md §7). This provider is the one switch, set
/// before a room is joined and cleared when the session ends.
library;

import 'dart:async';

import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../game/pack.dart';
import '../lan/lan_host.dart';

part 'lan_providers.g.dart';

/// Where the current session's room lives.
sealed class GameTarget {
  const GameTarget();
}

/// The cloud server configured for this build.
class CloudTarget extends GameTarget {
  const CloudTarget();
}

/// A room on this LAN, at `http://<address>:<port>`.
class LanTarget extends GameTarget {
  const LanTarget(this.baseUrl);
  final String baseUrl;
}

/// Cloud unless something sets otherwise; reset when a session ends so a later
/// game never silently inherits a dead LAN address.
@Riverpod(keepAlive: true)
class CurrentGameTarget extends _$CurrentGameTarget {
  @override
  GameTarget build() => const CloudTarget();

  void useCloud() => state = const CloudTarget();

  void useLan(String baseUrl) => state = LanTarget(baseUrl);
}

/// The LAN room this device is hosting, if any.
///
/// Held here rather than in a screen because the server must outlive any one
/// widget: the host navigating between screens must not take the party down
/// with it. Disposing the provider stops the server and ends the room out loud.
@Riverpod(keepAlive: true)
class HostedLanRoom extends _$HostedLanRoom {
  /// Mirrors [state], because a dispose callback may not read `state` or touch
  /// another provider — and a server left running because teardown threw would
  /// hold the port open for the rest of the process.
  LanHost? _running;

  @override
  LanHost? build() {
    ref.onDispose(() {
      final host = _running;
      _running = null;
      if (host != null) unawaited(host.stop());
    });
    return null;
  }

  /// Starts hosting [quiz] on this device and points the session at it.
  ///
  /// Throws [UnsupportedError] on Web, where no socket can listen — callers
  /// should check [lanHostingSupported] first and not offer the option at all.
  Future<LanHost> start() async {
    await stop();
    final host = await LanHost.start(pack: const Pack.empty());
    _running = host;
    state = host;
    // The host joins its own server like any other client, over loopback: one
    // code path for hosting, and the game logic never special-cases the host's
    // own connection.
    ref
        .read(currentGameTargetProvider.notifier)
        .useLan('http://127.0.0.1:${host.port}');
    return host;
  }

  /// Ends the hosted room and returns the session to cloud mode.
  Future<void> stop() async {
    final host = _running;
    if (host == null) return;
    _running = null;
    state = null;
    await host.stop();
    ref.read(currentGameTargetProvider.notifier).useCloud();
  }
}
