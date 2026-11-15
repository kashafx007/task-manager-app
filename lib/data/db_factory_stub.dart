import 'package:sqflite_common/sqlite_api.dart';

/// Fallback used only on platforms that are neither web nor dart:io based.
DatabaseFactory getDatabaseFactory() =>
    throw UnsupportedError('SQLite is not supported on this platform.');
