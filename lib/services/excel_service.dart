import 'dart:io';
import 'package:excel/excel.dart';
import 'package:file_picker/file_picker.dart';
import '../models/guest_visit.dart';
import '../core/utils.dart';

class ExcelService {
  static Future<String?> exportGuestsToExcel(List<GuestVisit> guests) async {
    final excel = Excel.createExcel();
    final Sheet sheet = excel['Guest Visits'];
    excel.delete('Sheet1');

    // Header Row
    sheet.appendRow([
      TextCellValue('S.No'),
      TextCellValue('Guest Name'),
      TextCellValue('Phone Number'),
      TextCellValue('Occupation'),
      TextCellValue('Place / Address'),
      TextCellValue('District'),
      TextCellValue('State / Country'),
      TextCellValue('Purpose'),
      TextCellValue('Donation Amount (INR)'),
      TextCellValue('Receipt No'),
      TextCellValue('Handled By'),
      TextCellValue('Entered By'),
      TextCellValue('Created At'),
    ]);

    // Data Rows
    for (int i = 0; i < guests.length; i++) {
      final g = guests[i];
      sheet.appendRow([
        IntCellValue(i + 1),
        TextCellValue(g.guestName),
        TextCellValue(g.phoneNumber),
        TextCellValue(g.occupation ?? '-'),
        TextCellValue(g.place),
        TextCellValue(g.district),
        TextCellValue(g.isInternational ? (g.country ?? '-') : (g.state ?? '-')),
        TextCellValue(g.purpose),
        DoubleCellValue(g.donationAmount),
        TextCellValue(g.receiptNo ?? '-'),
        TextCellValue(g.handledBy ?? '-'),
        TextCellValue(g.createdByName ?? '-'),
        TextCellValue(AppUtils.formatDateTime(g.createdAt)),
      ]);
    }

    final fileBytes = excel.save();
    if (fileBytes == null) return null;

    // Prompt user to save desktop/mobile file
    final outputFile = await FilePicker.platform.saveFile(
      dialogTitle: 'Save Guest Records Excel Report',
      fileName: 'guest_records_${DateTime.now().millisecondsSinceEpoch}.xlsx',
      type: FileType.custom,
      allowedExtensions: ['xlsx'],
    );

    if (outputFile != null) {
      final file = File(outputFile);
      await file.writeAsBytes(fileBytes);
      return outputFile;
    }

    return null;
  }
}
