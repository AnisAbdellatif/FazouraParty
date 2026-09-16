import 'package:web/web.dart' as web;

/// The origin this PWA was loaded from — the server that hosts it also serves
/// the API, so there's nothing to configure per deployment.
String? servedOrigin() {
  final origin = web.window.location.origin;
  return origin.startsWith('http') ? origin : null;
}
