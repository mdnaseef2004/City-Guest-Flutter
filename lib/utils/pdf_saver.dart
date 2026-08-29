import 'dart:typed_data';
import 'pdf_saver_stub.dart'
    if (dart.library.html) 'pdf_saver_web.dart';

class PdfSaver {
  static Future<void> saveOrPrintPdf({
    required Uint8List bytes,
    required String filename,
    bool isPrint = false,
  }) {
    return saveOrPrintPdfImpl(bytes: bytes, filename: filename, isPrint: isPrint);
  }
}
