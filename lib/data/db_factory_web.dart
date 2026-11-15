import 'package:sqflite_common/sqlite_api.dart';
import 'package:sqflite_common_ffi_web/sqflite_ffi_web.dart';

/// Chrome / web: SQLite compiled to WebAssembly, stored in the browser's
/// IndexedDB. Requires `web/sqlite3.wasm` (see README: `dart run
/// sqflite_common_ffi_web:setup`).
DatabaseFactory getDatabaseFactory() => databaseFactoryFfiWebNoWebWorker;
