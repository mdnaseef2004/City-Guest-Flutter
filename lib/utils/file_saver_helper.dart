import 'dart:typed_data';
import 'package:printing/printing.dart';

class FileSaverHelper {
  static Future<void> downloadFile({
    required List<int> bytes,
    required String filename,
    required String mimeType,
  }) async {
    await Printing.sharePdf(
      bytes: Uint8List.fromList(bytes),
      filename: filename,
    );
  }
}
