// Android / iOS: writes the file to a temp folder and opens the share sheet
// (the user can save it to Files / Drive, send it on WhatsApp, e-mail it, ...).
import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

Future<void> saveFile(String fileName, Uint8List bytes, String mimeType) async {
  final dir = await getTemporaryDirectory();
  final file = File('${dir.path}/$fileName');
  await file.writeAsBytes(bytes, flush: true);
  await Share.shareXFiles(
    [XFile(file.path, mimeType: mimeType)],
    subject: 'TaskNest export',
  );
}
