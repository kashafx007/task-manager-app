import 'package:sqflite/sqflite.dart' as sqflite;
import 'package:sqflite_common/sqlite_api.dart';

/// Android / iOS: the normal native SQLite implementation.
DatabaseFactory getDatabaseFactory() => sqflite.databaseFactory;
