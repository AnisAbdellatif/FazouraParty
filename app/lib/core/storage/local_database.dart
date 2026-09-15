import 'package:sembast/sembast.dart';

import 'local_database_io.dart'
    if (dart.library.js_interop) 'local_database_web.dart'
    as platform;

/// The app's on-device database: IndexedDB on the web, a file on Android.
Future<Database> openLocalDatabase() =>
    platform.openLocalDatabase('fazoura_party.db');
