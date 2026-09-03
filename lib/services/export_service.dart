import 'dart:convert';
import 'package:excel/excel.dart';
import '../models/event_model.dart';
import '../models/guest_visit.dart';
import '../services/pdf_service.dart';
import '../utils/file_saver_helper.dart';

class ExportService {
  // Export to CSV
  static Future<void> exportToCSV({
    required String filename,
    required List<String> headers,
    required List<List<dynamic>> rows,
  }) async {
    final StringBuffer sb = StringBuffer();
    sb.writeln(headers.map((h) => '"${h.replaceAll('"', '""')}"').join(','));

    for (final row in rows) {
      sb.writeln(row.map((cell) => '"${cell?.toString().replaceAll('"', '""') ?? ''}"').join(','));
    }

    final bytes = utf8.encode(sb.toString());
    await FileSaverHelper.downloadFile(
      bytes: bytes,
      filename: filename.endsWith('.csv') ? filename : '$filename.csv',
      mimeType: 'text/csv;charset=utf-8',
    );
  }

  // Export to Excel (.xlsx)
  static Future<void> exportToExcel({
    required String filename,
    required List<String> headers,
    required List<List<dynamic>> rows,
  }) async {
    final excel = Excel.createExcel();
    final Sheet sheet = excel['Sheet1'];

    sheet.appendRow(headers.map((h) => TextCellValue(h)).toList());

    for (final row in rows) {
      sheet.appendRow(row.map((cell) => TextCellValue(cell?.toString() ?? '')).toList());
    }

    final bytes = excel.save();
    if (bytes != null) {
      await FileSaverHelper.downloadFile(
        bytes: bytes,
        filename: filename.endsWith('.xlsx') ? filename : '$filename.xlsx',
        mimeType: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      );
    }
  }

  // Export Admin Performance PDF
  static Future<void> exportAdminPerformancePdf({
    required String reportTitle,
    required List<Map<String, dynamic>> rows,
    required String roleLabel,
  }) async {
    final pdfBytes = await PdfService.generateAdminPerformancePdf(
      reportTitle: reportTitle,
      rows: rows,
      roleLabel: roleLabel,
    );
    await FileSaverHelper.downloadFile(
      bytes: pdfBytes,
      filename: '${roleLabel.toLowerCase()}-performance-report.pdf',
      mimeType: 'application/pdf',
    );
  }

  // Export Admin Event Performance PDF
  static Future<void> exportAdminEventPerformancePdf({
    required String reportTitle,
    required Map<String, List<EventModel>> eventsByAdmin,
    required int totalEvents,
    required int totalParticipants,
  }) async {
    final pdfBytes = await PdfService.generateAdminEventPerformancePdf(
      reportTitle: reportTitle,
      eventsByAdmin: eventsByAdmin,
      totalEvents: totalEvents,
      totalParticipants: totalParticipants,
    );
    await FileSaverHelper.downloadFile(
      bytes: pdfBytes,
      filename: 'admin-events-performance-report.pdf',
      mimeType: 'application/pdf',
    );
  }

  // Export Donations PDF
  static Future<void> exportDonationsPdf({
    required String reportTitle,
    required List<GuestVisit> guests,
  }) async {
    final pdfBytes = await PdfService.generateDonationsPdfReport(
      reportTitle: reportTitle,
      guests: guests,
    );
    await FileSaverHelper.downloadFile(
      bytes: pdfBytes,
      filename: 'donations-report.pdf',
      mimeType: 'application/pdf',
    );
  }

  // Export Events PDF
  static Future<void> exportEventReportPdf({
    required String reportTitle,
    required List<Map<String, dynamic>> events,
  }) async {
    final pdfBytes = await PdfService.generateEventReportPdf(
      reportTitle: reportTitle,
      events: events,
    );
    await FileSaverHelper.downloadFile(
      bytes: pdfBytes,
      filename: 'events-analytics-report.pdf',
      mimeType: 'application/pdf',
    );
  }
}
