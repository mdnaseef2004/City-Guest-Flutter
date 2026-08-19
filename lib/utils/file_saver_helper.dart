import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:printing/printing.dart';

// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;

class FileSaverHelper {
  static Future<void> downloadFile({
    required List<int> bytes,
    required String filename,
    required String mimeType,
  }) async {
    if (kIsWeb) {
      final blob = html.Blob([bytes], mimeType);
      final url = html.Url.createObjectUrlFromBlob(blob);
      final anchor = html.AnchorElement(href: url)
        ..setAttribute("download", filename)
        ..style.display = 'none';
      html.document.body?.children.add(anchor);
      anchor.click();
      anchor.remove();
      html.Url.revokeObjectUrl(url);
    } else {
      await Printing.sharePdf(
        bytes: Uint8List.fromList(bytes),
        filename: filename,
      );
    }
  }
}
