import 'dart:typed_data';
import 'pdf_saver.dart';

class FileSaverHelper {
  static Future<void> downloadFile({
    required List<int> bytes,
    required String filename,
    required String mimeType,
  }) async {
    await PdfSaver.saveOrPrintPdf(
      bytes: Uint8List.fromList(bytes),
      filename: filename,
      isPrint: false,
    );
  }
}
