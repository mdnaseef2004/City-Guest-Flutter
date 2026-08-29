import 'dart:typed_data';
import 'package:printing/printing.dart';

class PdfSaver {
  static Future<void> saveOrPrintPdf({
    required Uint8List bytes,
    required String filename,
    bool isPrint = false,
  }) async {
    if (isPrint) {
      await Printing.layoutPdf(onLayout: (_) => bytes, name: filename);
    } else {
      await Printing.sharePdf(bytes: bytes, filename: filename);
    }
  }
}
