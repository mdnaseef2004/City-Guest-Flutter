import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import '../utils/pdf_saver.dart';
import '../config/constants.dart';
import '../core/utils.dart';
import '../models/event_model.dart';
import '../models/guest_visit.dart';
import '../services/notification_service.dart';
import '../utils/file_saver_helper.dart';

class PdfService {
  static Uint8List? _cachedLogoBytes;

  static String cleanPdfText(dynamic val) {
    if (val == null) return '';
    final str = val.toString();
    final cleaned = str.replaceAll(RegExp(r'[^\x20-\x7E\n\r\t]'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
    return cleaned.isNotEmpty ? cleaned : '-';
  }

  static String formatPdfCurrency(double amount) {
    final formatter = NumberFormat('#,##,##0', 'en_IN');
    return 'Rs. ${formatter.format(amount)}';
  }

  // Helper to load and cache logo bytes once in memory for instant PDF rendering
  static Future<pw.MemoryImage?> _getLogoImage() async {
    try {
      if (_cachedLogoBytes == null) {
        final ByteData logoData = await rootBundle.load('assets/full_mkc_logo.png');
        _cachedLogoBytes = logoData.buffer.asUint8List();
      }
      return pw.MemoryImage(_cachedLogoBytes!);
    } catch (_) {
      return null;
    }
  }

  // Interactive Print or Download Option Modal Dialog (Instant Pre-generated)
  static void showPrintOrDownloadDialog(BuildContext context, GuestVisit visit) {
    // Start pre-generating PDF in the background immediately
    Uint8List? pregeneratedPdfBytes;
    bool isGeneratingInBackground = true;

    generateGuestReceipt(visit).then((bytes) {
      pregeneratedPdfBytes = bytes;
      isGeneratingInBackground = false;
    }).catchError((_) {
      isGeneratingInBackground = false;
    });

    showDialog(
      context: context,
      builder: (ctx) {
        bool isProcessing = false;
        return StatefulBuilder(
          builder: (context, setModalState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.print_rounded, color: AppColors.primary, size: 22),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Guest Receipt Options',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                        ),
                        Text(
                          'Choose action for formatted PDF receipt',
                          style: TextStyle(fontSize: 12, color: AppColors.textSecondary, fontWeight: FontWeight.normal),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Guest: ${visit.guestName}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                        const SizedBox(height: 4),
                        Text('Place: ${visit.place} | Purpose: ${visit.purpose}', style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                        if (visit.donationAmount > 0) ...[
                          const SizedBox(height: 4),
                          Text('Donation: ${AppUtils.formatCurrency(visit.donationAmount)}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.primary)),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text('Select Format Action:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                  const SizedBox(height: 10),

                  // Option 1: Direct Print
                  InkWell(
                    onTap: isProcessing
                        ? null
                        : () async {
                            setModalState(() => isProcessing = true);
                            try {
                              final pdfBytes = pregeneratedPdfBytes ?? await generateGuestReceipt(visit);
                              await PdfSaver.saveOrPrintPdf(
                                bytes: pdfBytes,
                                filename: 'Receipt-${visit.guestName.replaceAll(' ', '_')}.pdf',
                                isPrint: true,
                              );
                              if (context.mounted) Navigator.pop(ctx);
                            } catch (e) {
                              if (context.mounted) AppUtils.showSnackBar(context, 'Printing failed: $e', isError: true);
                            } finally {
                              if (context.mounted) setModalState(() => isProcessing = false);
                            }
                          },
                    borderRadius: BorderRadius.circular(10),
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFECFDF5),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0xFFA7F3D0), width: 1.2),
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.print_rounded, color: Color(0xFF059669), size: 22),
                          SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Print PDF Receipt', style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF065F46), fontSize: 13)),
                                Text('Send directly to printer or browser print preview', style: TextStyle(fontSize: 11, color: Color(0xFF047857))),
                              ],
                            ),
                          ),
                          Icon(Icons.arrow_forward_ios_rounded, size: 14, color: Color(0xFF059669)),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 10),

                  // Option 2: Download PDF File (Instant)
                  InkWell(
                    onTap: isProcessing
                        ? null
                        : () async {
                            setModalState(() => isProcessing = true);
                            try {
                              final pdfBytes = pregeneratedPdfBytes ?? await generateGuestReceipt(visit);
                              final cleanName = visit.guestName.replaceAll(RegExp(r'[^\w\s\-]'), '').replaceAll(' ', '_');
                              final filename = 'Guest_Receipt_${cleanName}_${visit.id.substring(0, math.min(6, visit.id.length))}.pdf';

                              await FileSaverHelper.downloadFile(
                                bytes: pdfBytes,
                                filename: filename,
                                mimeType: 'application/pdf',
                              );
                              if (context.mounted) {
                                Navigator.pop(ctx);
                                NotificationService.notifyFileAction(
                                  context,
                                  actionLabel: 'downloaded',
                                  filename: filename,
                                  isSuccess: true,
                                );
                              }
                            } catch (e) {
                              if (context.mounted) {
                                NotificationService.notifyFileAction(
                                  context,
                                  actionLabel: 'download',
                                  filename: 'PDF Receipt',
                                  isSuccess: false,
                                  errorMessage: e.toString(),
                                );
                              }
                            } finally {
                              if (context.mounted) setModalState(() => isProcessing = false);
                            }
                          },
                    borderRadius: BorderRadius.circular(10),
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFEFF6FF),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0xFFBFDBFE), width: 1.2),
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.download_rounded, color: Color(0xFF2563EB), size: 22),
                          SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Download PDF File', style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF1E40AF), fontSize: 13)),
                                Text('Save PDF document file directly to your device storage', style: TextStyle(fontSize: 11, color: Color(0xFF1D4ED8))),
                              ],
                            ),
                          ),
                          Icon(Icons.arrow_forward_ios_rounded, size: 14, color: Color(0xFF2563EB)),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: isProcessing ? null : () => Navigator.pop(ctx),
                  child: const Text('Cancel'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  static Future<Uint8List> generateGuestReceipt(GuestVisit visit) async {
    final pdf = pw.Document();
    final primaryColor = PdfColor.fromHex('#059669');

    final logoImage = await _getLogoImage();

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              // Header with Logo
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      if (logoImage != null)
                        pw.Image(logoImage, height: 45, fit: pw.BoxFit.contain)
                      else
                        pw.Text(
                          'MARKAZ KNOWLEDGE CITY',
                          style: pw.TextStyle(
                            fontSize: 16,
                            fontWeight: pw.FontWeight.bold,
                            color: primaryColor,
                          ),
                        ),
                      pw.SizedBox(height: 4),
                      pw.Text(
                        'CITY GUEST RELATION MANAGEMENT',
                        style: pw.TextStyle(
                          fontSize: 11,
                          fontWeight: pw.FontWeight.bold,
                          color: PdfColors.grey700,
                        ),
                      ),
                      pw.Text(
                        'GUEST VISIT SUMMARY RECEIPT',
                        style: pw.TextStyle(
                          fontSize: 12,
                          fontWeight: pw.FontWeight.bold,
                          color: primaryColor,
                        ),
                      ),
                    ],
                  ),
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.end,
                    children: [
                      pw.Container(
                        padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: pw.BoxDecoration(
                          color: PdfColor.fromHex('#ECFDF5'),
                          border: pw.Border.all(color: primaryColor, width: 1),
                          borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
                        ),
                        child: pw.Text(
                          'DATE: ${AppUtils.formatDate(visit.createdAt)}',
                          style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10, color: primaryColor),
                        ),
                      ),
                      if (visit.receiptNo != null && visit.receiptNo!.trim().isNotEmpty) ...[
                        pw.SizedBox(height: 4),
                        pw.Text(
                          'Receipt No: ${visit.receiptNo}',
                          style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10, color: PdfColors.grey800),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
              pw.SizedBox(height: 10),
              pw.Divider(thickness: 1.5, color: primaryColor),
              pw.SizedBox(height: 16),

              // Guest Details Card Box
              pw.Container(
                padding: const pw.EdgeInsets.all(16),
                decoration: pw.BoxDecoration(
                  color: PdfColor.fromHex('#F8FAFC'),
                  border: pw.Border.all(color: PdfColors.grey300),
                  borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
                ),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text('GUEST INFORMATION', style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold, color: primaryColor)),
                    pw.SizedBox(height: 8),
                    _buildPdfRow('Guest Name:', visit.guestName),
                    _buildPdfRow('Phone Number:', visit.phoneNumber.isNotEmpty ? visit.phoneNumber : '-'),
                    if (visit.occupation != null && visit.occupation!.trim().isNotEmpty)
                      _buildPdfRow('Occupation:', visit.occupation!),
                    _buildPdfRow('Address / Place:', visit.place),
                    _buildPdfRow(
                      'Location:',
                      visit.isInternational
                          ? (visit.country ?? 'International')
                          : '${visit.district}, ${visit.state ?? ''}',
                    ),
                    _buildPdfRow('Purpose of Visit:', visit.purpose),
                    if (visit.donationAmount > 0)
                      _buildPdfRow('Donation Amount:', formatPdfCurrency(visit.donationAmount)),
                    _buildPdfRow('Handled By:', (visit.handledBy != null && visit.handledBy!.isNotEmpty) ? visit.handledBy! : '-'),
                    if (visit.remarks != null && visit.remarks!.trim().isNotEmpty)
                      _buildPdfRow('Remarks:', visit.remarks!),
                  ],
                ),
              ),

              pw.SizedBox(height: 16),

              // Visited Places Table
              if (visit.visitedPlaces.isNotEmpty) ...[
                pw.Text(
                  'VISITED PLACES DETAIL',
                  style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold, color: primaryColor),
                ),
                pw.SizedBox(height: 8),
                pw.TableHelper.fromTextArray(
                  headers: ['#', 'Place Name', 'Visit Date', 'Time In', 'Time Out'],
                  data: visit.visitedPlaces.asMap().entries.map((e) {
                    final idx = e.key + 1;
                    final vp = e.value;
                    return [
                      '$idx',
                      vp.visitedPlace,
                      vp.visitDate ?? '-',
                      vp.timeIn ?? '-',
                      vp.timeOut ?? '-'
                    ];
                  }).toList(),
                  headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColors.white, fontSize: 10),
                  headerDecoration: pw.BoxDecoration(color: primaryColor),
                  rowDecoration: const pw.BoxDecoration(color: PdfColors.grey100),
                  cellAlignment: pw.Alignment.centerLeft,
                  cellStyle: const pw.TextStyle(fontSize: 9),
                  border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
                ),
              ],

              pw.Spacer(),

              // Footer Signatures & System Stamp
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                crossAxisAlignment: pw.CrossAxisAlignment.end,
                children: [
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text('Authorized Signature', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10)),
                      pw.SizedBox(height: 35),
                      pw.Container(width: 140, height: 1, color: PdfColors.grey800),
                    ],
                  ),
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.end,
                    children: [
                      pw.Text('Markaz Knowledge City - City Guest System', style: pw.TextStyle(fontSize: 9, color: PdfColors.grey700)),
                      pw.Text('Verified Official Digital Receipt', style: pw.TextStyle(fontSize: 8, color: PdfColors.grey500)),
                    ],
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );

    return pdf.save();
  }

  // Generate Admin Performance PDF (Matching Website PDF Format with Logo & Clean Currency)
  static Future<Uint8List> generateAdminPerformancePdf({
    required String reportTitle,
    required List<Map<String, dynamic>> rows,
    required String roleLabel,
  }) async {
    final pdf = pw.Document();
    final todayStr = DateFormat('dd/MM/yyyy hh:mm a').format(DateTime.now());
    final primaryColor = PdfColor.fromHex('#059669');

    // Try loading logo image
    pw.MemoryImage? logoImage;
    try {
      final ByteData logoData = await rootBundle.load('assets/full_mkc_logo.png');
      logoImage = pw.MemoryImage(logoData.buffer.asUint8List());
    } catch (_) {}

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (pw.Context context) {
          return [
            // Header with Logo
            pw.Center(
              child: pw.Column(
                children: [
                  if (logoImage != null)
                    pw.Image(logoImage, height: 50, fit: pw.BoxFit.contain)
                  else
                    pw.Text(
                      'MARKAZ KNOWLEDGE CITY',
                      style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold, color: primaryColor),
                    ),
                  pw.SizedBox(height: 6),
                  pw.Text(
                    'CITY GUEST RELATION MANAGEMENT SYSTEM',
                    style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold, color: PdfColors.grey700),
                  ),
                  pw.SizedBox(height: 4),
                  pw.Text(
                    reportTitle.toUpperCase(),
                    style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold, color: primaryColor),
                  ),
                  pw.SizedBox(height: 8),
                  pw.Text('Generated On: $todayStr', style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey600)),
                ],
              ),
            ),
            pw.SizedBox(height: 12),
            pw.Divider(thickness: 1.5, color: primaryColor),
            pw.SizedBox(height: 16),

            // Performance Leaderboard Table
            pw.TableHelper.fromTextArray(
              headers: ['#', '$roleLabel Name', 'Total Entries', 'Total Donations (INR)', 'Last Entry'],
              data: rows.asMap().entries.map((e) {
                final idx = e.key + 1;
                final r = e.value;
                final double don = ((r['totalDonations'] ?? 0) as num).toDouble();
                final String lastRaw = r['lastEntry']?.toString() ?? '';
                final String lastStr = lastRaw.isNotEmpty
                    ? DateFormat('dd/MM/yyyy').format(DateTime.parse(lastRaw).toLocal())
                    : 'N/A';

                return [
                  '$idx',
                  r['name'] ?? 'User',
                  '${r['totalEntries']} guests',
                  formatPdfCurrency(don),
                  lastStr,
                ];
              }).toList(),
              headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColors.white, fontSize: 11),
              headerDecoration: pw.BoxDecoration(color: primaryColor),
              rowDecoration: const pw.BoxDecoration(color: PdfColors.grey100),
              cellAlignment: pw.Alignment.centerLeft,
              cellStyle: const pw.TextStyle(fontSize: 10),
              border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
            ),

            pw.SizedBox(height: 24),
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text('Report Summary Total Admins: ${rows.length}', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10)),
                pw.Text('Page 1 of 1', style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey600)),
              ],
            ),
          ];
        },
      ),
    );

    return pdf.save();
  }

  // Generate Event Performance PDF
  static Future<Uint8List> generateEventReportPdf({
    required String reportTitle,
    required List<Map<String, dynamic>> events,
  }) async {
    final pdf = pw.Document();
    final todayStr = DateFormat('dd/MM/yyyy hh:mm a').format(DateTime.now());
    final primaryColor = PdfColor.fromHex('#D97706'); // Amber/Orange

    pw.MemoryImage? logoImage;
    try {
      final ByteData logoData = await rootBundle.load('assets/full_mkc_logo.png');
      logoImage = pw.MemoryImage(logoData.buffer.asUint8List());
    } catch (_) {}

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4.landscape,
        margin: const pw.EdgeInsets.all(32),
        build: (pw.Context context) {
          return [
            pw.Center(
              child: pw.Column(
                children: [
                  if (logoImage != null)
                    pw.Image(logoImage, height: 50, fit: pw.BoxFit.contain)
                  else
                    pw.Text(
                      'MARKAZ KNOWLEDGE CITY',
                      style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold, color: primaryColor),
                    ),
                  pw.SizedBox(height: 6),
                  pw.Text(
                    'CITY GUEST RELATION MANAGEMENT SYSTEM',
                    style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold, color: PdfColors.grey700),
                  ),
                  pw.SizedBox(height: 4),
                  pw.Text(
                    reportTitle.toUpperCase(),
                    style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold, color: primaryColor),
                  ),
                  pw.SizedBox(height: 8),
                  pw.Text('Generated On: $todayStr', style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey600)),
                ],
              ),
            ),
            pw.SizedBox(height: 12),
            pw.Divider(thickness: 1.5, color: primaryColor),
            pw.SizedBox(height: 16),

            pw.TableHelper.fromTextArray(
              headers: ['#', 'Event Name', 'Location / Place', 'Attendees', 'Event Date', 'Handled By'],
              data: events.asMap().entries.map((e) {
                final idx = e.key + 1;
                final ev = e.value;
                final String dateRaw = ev['event_date']?.toString() ?? ev['created_at']?.toString() ?? '';
                final String dateStr = dateRaw.isNotEmpty
                    ? DateFormat('dd/MM/yyyy').format(DateTime.parse(dateRaw).toLocal())
                    : '-';

                return [
                  '$idx',
                  ev['event_name'] ?? 'Event',
                  ev['event_place'] ?? 'Main Campus',
                  '${ev['members_count'] ?? 1} members',
                  dateStr,
                  ev['handled_by'] ?? '-',
                ];
              }).toList(),
              headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColors.white, fontSize: 11),
              headerDecoration: pw.BoxDecoration(color: primaryColor),
              rowDecoration: const pw.BoxDecoration(color: PdfColors.grey100),
              cellAlignment: pw.Alignment.centerLeft,
              cellStyle: const pw.TextStyle(fontSize: 10),
              border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
            ),

            pw.SizedBox(height: 24),
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text('Total Events: ${events.length}', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10)),
                pw.Text('Page 1 of 1', style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey600)),
              ],
            ),
          ];
        },
      ),
    );

    return pdf.save();
  }

  static Future<void> exportAdminPerformancePdf({
    required String reportTitle,
    required List<Map<String, dynamic>> rows,
    required String roleLabel,
  }) async {
    final pdfBytes = await generateAdminPerformancePdf(
      reportTitle: reportTitle,
      rows: rows,
      roleLabel: roleLabel,
    );
    await PdfSaver.saveOrPrintPdf(
      bytes: pdfBytes,
      filename: '${roleLabel.toLowerCase()}-performance-report.pdf',
    );
  }

  static Future<void> exportEventReportPdf({
    required String reportTitle,
    required List<Map<String, dynamic>> events,
  }) async {
    final pdfBytes = await generateEventReportPdf(
      reportTitle: reportTitle,
      events: events,
    );
    await PdfSaver.saveOrPrintPdf(
      bytes: pdfBytes,
      filename: 'events-analytics-report.pdf',
    );
  }

  static Future<void> printReceipt(GuestVisit visit) async {
    final pdfBytes = await generateGuestReceipt(visit);
    await PdfSaver.saveOrPrintPdf(
      bytes: pdfBytes,
      filename: 'guest_receipt.pdf',
      isPrint: true,
    );
  }

  // Generate Guest Records Complete PDF (Matching Website Landscape Format with Dynamic Selected Columns)
  static Future<Uint8List> generateGuestRecordsPdf({
    required String reportTitle,
    required List<GuestVisit> guests,
    required List<String> selectedColumns,
  }) async {
    final pdf = pw.Document();
    final todayStr = DateFormat('dd/MM/yyyy hh:mm a').format(DateTime.now());
    final primaryColor = PdfColor.fromHex('#059669');
    final totalDonations = guests.fold<double>(0.0, (s, g) => s + g.donationAmount);

    pw.MemoryImage? logoImage;
    try {
      final ByteData logoData = await rootBundle.load('assets/full_mkc_logo.png');
      logoImage = pw.MemoryImage(logoData.buffer.asUint8List());
    } catch (_) {}

    final Map<String, String> columnHeaders = {
      'name': 'Guest Name',
      'phone': 'Phone Number',
      'occupation': 'Occupation',
      'place': 'Address / Place',
      'district': 'District',
      'state': 'State',
      'country': 'Country',
      'purpose': 'Purpose',
      'donation': 'Donation (Rs.)',
      'receipt': 'Receipt No',
      'donation_to': 'Donation Destination',
      'handled_by': 'Handled By',
      'created_by': 'Admin Name',
      'remarks': 'Remarks',
      'date': 'Date Entered',
    };

    final headers = ['#', ...selectedColumns.map((col) => columnHeaders[col] ?? col)];

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4.landscape,
        margin: const pw.EdgeInsets.all(24),
        header: (pw.Context context) {
          return pw.Column(
            children: [
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  if (logoImage != null)
                    pw.Image(logoImage, height: 32, fit: pw.BoxFit.contain)
                  else
                    pw.Text(
                      'MARKAZ KNOWLEDGE CITY',
                      style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold, color: primaryColor),
                    ),
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.end,
                    children: [
                      pw.Text(
                        'CITY GUEST RELATION MANAGEMENT SYSTEM',
                        style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, color: PdfColors.grey700),
                      ),
                      pw.Text(
                        reportTitle.toUpperCase(),
                        style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold, color: primaryColor),
                      ),
                    ],
                  ),
                ],
              ),
              pw.SizedBox(height: 6),
              pw.Divider(thickness: 1, color: primaryColor),
              pw.SizedBox(height: 8),
            ],
          );
        },
        footer: (pw.Context context) {
          return pw.Container(
            margin: const pw.EdgeInsets.only(top: 8),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text('Generated On: $todayStr | Total Records: ${guests.length} | Total Donations: Rs. ${NumberFormat('#,##,##0', 'en_IN').format(totalDonations)}', style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey600)),
                pw.Text('Page ${context.pageNumber} of ${context.pagesCount}', style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, color: primaryColor)),
              ],
            ),
          );
        },
        build: (pw.Context context) {
          return [
            pw.TableHelper.fromTextArray(
              headers: headers,
              data: guests.asMap().entries.map((e) {
                final idx = e.key + 1;
                final g = e.value;
                final row = <String>['$idx'];

                for (final col in selectedColumns) {
                  switch (col) {
                    case 'name':
                      row.add(g.guestName);
                      break;
                    case 'phone':
                      row.add(g.phoneNumber.isNotEmpty ? g.phoneNumber : '-');
                      break;
                    case 'occupation':
                      row.add((g.occupation != null && g.occupation!.isNotEmpty) ? g.occupation! : '-');
                      break;
                    case 'place':
                      row.add(g.place);
                      break;
                    case 'district':
                      row.add(g.district);
                      break;
                    case 'state':
                      row.add((g.state != null && g.state!.isNotEmpty) ? g.state! : '-');
                      break;
                    case 'country':
                      row.add((g.country != null && g.country!.isNotEmpty) ? g.country! : '-');
                      break;
                    case 'purpose':
                      row.add(g.purpose);
                      break;
                    case 'donation':
                      row.add(g.donationAmount > 0 ? NumberFormat('#,##,##0', 'en_IN').format(g.donationAmount) : '-');
                      break;
                    case 'receipt':
                      row.add((g.receiptNo != null && g.receiptNo!.trim().isNotEmpty) ? g.receiptNo!.trim() : '-');
                      break;
                    case 'donation_to':
                      row.add((g.donationTo != null && g.donationTo!.trim().isNotEmpty) ? g.donationTo!.trim() : '-');
                      break;
                    case 'handled_by':
                      row.add((g.handledBy != null && g.handledBy!.trim().isNotEmpty) ? g.handledBy!.trim() : '-');
                      break;
                    case 'created_by':
                      row.add((g.createdByName != null && g.createdByName!.trim().isNotEmpty) ? g.createdByName!.trim() : '-');
                      break;
                    case 'remarks':
                      row.add((g.remarks != null && g.remarks!.trim().isNotEmpty) ? g.remarks!.trim() : '-');
                      break;
                    case 'date':
                      row.add(AppUtils.formatDate(g.createdAt));
                      break;
                    default:
                      row.add('-');
                  }
                }
                return row.map((cell) => cleanPdfText(cell)).toList();
              }).toList(),
              headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColors.white, fontSize: 8),
              headerDecoration: pw.BoxDecoration(color: primaryColor),
              rowDecoration: const pw.BoxDecoration(color: PdfColors.grey100),
              cellAlignment: pw.Alignment.centerLeft,
              cellStyle: const pw.TextStyle(fontSize: 7.5),
              border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
            ),
            pw.SizedBox(height: 10),
            pw.Container(
              padding: const pw.EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: pw.BoxDecoration(
                color: primaryColor,
                borderRadius: pw.BorderRadius.circular(6),
              ),
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text(
                    'TOTAL GUESTS: ${guests.length}',
                    style: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColors.white, fontSize: 10),
                  ),
                  pw.Text(
                    'TOTAL DONATIONS: Rs. ${NumberFormat('#,##,##0', 'en_IN').format(totalDonations)}',
                    style: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColors.white, fontSize: 10),
                  ),
                ],
              ),
            ),
          ];
        },
      ),
    );

    return pdf.save();
  }

  // Interactive Print or Download Option Modal Dialog for Individual Event
  static void showIndividualEventPrintOrDownloadDialog(BuildContext context, EventModel event) {
    Uint8List? pregeneratedPdfBytes;
    bool isGeneratingInBackground = true;

    generateIndividualEventPdf(event).then((bytes) {
      pregeneratedPdfBytes = bytes;
      isGeneratingInBackground = false;
    }).catchError((_) {
      isGeneratingInBackground = false;
    });

    showDialog(
      context: context,
      builder: (ctx) {
        bool isProcessing = false;
        return StatefulBuilder(
          builder: (context, setModalState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.event_note_rounded, color: AppColors.primary, size: 22),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Event Document Options',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                        ),
                        Text(
                          'Print or download formatted event sheet with logo',
                          style: TextStyle(fontSize: 12, color: AppColors.textSecondary, fontWeight: FontWeight.normal),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Event: ${event.eventName}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                        const SizedBox(height: 4),
                        Text('Venue: ${event.eventPlace} | Date: ${AppUtils.formatDate(event.eventDate)}', style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                        const SizedBox(height: 4),
                        Text('Attendees: ${event.membersCount}  •  Organized by: ${event.organizedBy}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.primary)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text('Select Action:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                  const SizedBox(height: 10),

                  // Option 1: Direct Print PDF
                  InkWell(
                    onTap: isProcessing
                        ? null
                        : () async {
                            setModalState(() => isProcessing = true);
                            try {
                              final pdfBytes = pregeneratedPdfBytes ?? await generateIndividualEventPdf(event);
                              final cleanName = event.eventName.replaceAll(RegExp(r'[^\w\s\-]'), '').replaceAll(' ', '_');
                              await PdfSaver.saveOrPrintPdf(
                                bytes: pdfBytes,
                                filename: 'Event_Analytics_${cleanName}.pdf',
                                isPrint: true,
                              );
                              if (context.mounted) Navigator.pop(ctx);
                            } catch (e) {
                              if (context.mounted) AppUtils.showSnackBar(context, 'Printing failed: $e', isError: true);
                            } finally {
                              if (context.mounted) setModalState(() => isProcessing = false);
                            }
                          },
                    borderRadius: BorderRadius.circular(10),
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFECFDF5),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0xFFA7F3D0), width: 1.2),
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.print_rounded, color: Color(0xFF059669), size: 22),
                          SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Print Event Sheet', style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF065F46), fontSize: 13)),
                                Text('Send directly to printer or browser print preview', style: TextStyle(fontSize: 11, color: Color(0xFF047857))),
                              ],
                            ),
                          ),
                          Icon(Icons.arrow_forward_ios_rounded, size: 14, color: Color(0xFF059669)),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 10),

                  // Option 2: Download PDF File
                  InkWell(
                    onTap: isProcessing
                        ? null
                        : () async {
                            setModalState(() => isProcessing = true);
                            try {
                              final pdfBytes = pregeneratedPdfBytes ?? await generateIndividualEventPdf(event);
                              final cleanName = event.eventName.replaceAll(RegExp(r'[^\w\s\-]'), '').replaceAll(' ', '_');
                              final filename = 'Event_Sheet_${cleanName}_${DateFormat('yyyyMMdd').format(event.eventDate)}.pdf';

                              await FileSaverHelper.downloadFile(
                                bytes: pdfBytes,
                                filename: filename,
                                mimeType: 'application/pdf',
                              );
                              if (context.mounted) {
                                Navigator.pop(ctx);
                                NotificationService.notifyFileAction(
                                  context,
                                  actionLabel: 'downloaded',
                                  filename: filename,
                                  isSuccess: true,
                                );
                              }
                            } catch (e) {
                              if (context.mounted) {
                                NotificationService.notifyFileAction(
                                  context,
                                  actionLabel: 'download',
                                  filename: 'Event PDF',
                                  isSuccess: false,
                                  errorMessage: e.toString(),
                                );
                              }
                            } finally {
                              if (context.mounted) setModalState(() => isProcessing = false);
                            }
                          },
                    borderRadius: BorderRadius.circular(10),
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFEFF6FF),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0xFFBFDBFE), width: 1.2),
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.picture_as_pdf_rounded, color: Color(0xFF2563EB), size: 22),
                          SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Download PDF Document', style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF1E40AF), fontSize: 13)),
                                Text('Save high-quality PDF with MKC logo to device', style: TextStyle(fontSize: 11, color: Color(0xFF1D4ED8))),
                              ],
                            ),
                          ),
                          Icon(Icons.arrow_forward_ios_rounded, size: 14, color: Color(0xFF2563EB)),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Close'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // Generate Individual Event PDF with Official Markaz Knowledge City Logo
  static Future<Uint8List> generateIndividualEventPdf(EventModel event) async {
    final pdf = pw.Document();
    final logoImage = await _getLogoImage();
    const primaryColor = PdfColor.fromInt(0xFF047857); // Deep Emerald Green

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4.landscape,
        margin: const pw.EdgeInsets.all(32),
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              // Header Card with Official Logo
              pw.Container(
                padding: const pw.EdgeInsets.all(16),
                decoration: pw.BoxDecoration(
                  color: PdfColors.white,
                  border: pw.Border.all(color: primaryColor, width: 2),
                  borderRadius: pw.BorderRadius.circular(8),
                ),
                child: pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    if (logoImage != null)
                      pw.Image(logoImage, height: 60)
                    else
                      pw.Text(
                        'MARKAZ KNOWLEDGE CITY',
                        style: pw.TextStyle(
                          fontSize: 16,
                          fontWeight: pw.FontWeight.bold,
                          color: primaryColor,
                        ),
                      ),
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.end,
                      children: [
                        pw.Text(
                          'OFFICIAL EVENT SHEET',
                          style: pw.TextStyle(
                            fontSize: 14,
                            fontWeight: pw.FontWeight.bold,
                            color: primaryColor,
                          ),
                        ),
                        pw.SizedBox(height: 4),
                        pw.Text(
                          'Date: ${AppUtils.formatDate(event.eventDate)}',
                          style: pw.TextStyle(fontSize: 10, color: PdfColors.grey700),
                        ),
                        pw.Text(
                          'Ref ID: EVT-${event.id.substring(0, math.min(8, event.id.length)).toUpperCase()}',
                          style: pw.TextStyle(fontSize: 9, color: PdfColors.grey600),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              pw.SizedBox(height: 20),

              // Title Section Banner
              pw.Container(
                width: double.infinity,
                padding: const pw.EdgeInsets.symmetric(vertical: 10, horizontal: 14),
                decoration: pw.BoxDecoration(
                  color: primaryColor,
                  borderRadius: pw.BorderRadius.circular(6),
                ),
                child: pw.Text(
                  event.eventName.toUpperCase(),
                  style: pw.TextStyle(
                    fontSize: 14,
                    fontWeight: pw.FontWeight.bold,
                    color: PdfColors.white,
                  ),
                ),
              ),
              pw.SizedBox(height: 16),

              // Detailed Event Information Table Grid
              pw.Container(
                padding: const pw.EdgeInsets.all(16),
                decoration: pw.BoxDecoration(
                  border: pw.Border.all(color: PdfColors.grey300),
                  borderRadius: pw.BorderRadius.circular(6),
                ),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    _buildPdfRow('Event Name:', event.eventName),
                    pw.Divider(color: PdfColors.grey200),
                    _buildPdfRow('Venue / Place:', event.eventPlace),
                    pw.Divider(color: PdfColors.grey200),
                    _buildPdfRow('Event Date:', DateFormat('EEEE, MMMM dd, yyyy').format(event.eventDate)),
                    pw.Divider(color: PdfColors.grey200),
                    _buildPdfRow('Expected Attendees:', '${event.membersCount} Members'),
                    pw.Divider(color: PdfColors.grey200),
                    _buildPdfRow('Organized By:', event.organizedBy),
                    pw.Divider(color: PdfColors.grey200),
                    _buildPdfRow('Handled By:', event.handledBy),
                    if (event.remarks != null && event.remarks!.trim().isNotEmpty) ...[
                      pw.Divider(color: PdfColors.grey200),
                      _buildPdfRow('Special Remarks:', event.remarks!.trim()),
                    ],
                  ],
                ),
              ),

              pw.Spacer(),

              // Footer Stamp & Signatures
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Container(width: 140, height: 1, color: PdfColors.grey400),
                      pw.SizedBox(height: 4),
                      pw.Text('Event Organizer Signature', style: const pw.TextStyle(fontSize: 10)),
                    ],
                  ),
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.end,
                    children: [
                      pw.Container(width: 140, height: 1, color: PdfColors.grey400),
                      pw.SizedBox(height: 4),
                      pw.Text('Authorized Authority Stamp', style: const pw.TextStyle(fontSize: 10)),
                    ],
                  ),
                ],
              ),
              pw.SizedBox(height: 12),
              pw.Center(
                child: pw.Text(
                  'Markaz Knowledge City • Guest Relation Management System • Confidential',
                  style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey500),
                ),
              ),
            ],
          );
        },
      ),
    );

    return pdf.save();
  }

  // Generate Admin Event Performance PDF Report
  static Future<Uint8List> generateAdminEventPerformancePdf({
    required String reportTitle,
    required Map<String, List<EventModel>> eventsByAdmin,
    required int totalEvents,
    required int totalParticipants,
  }) async {
    final pdf = pw.Document();
    final primaryColor = PdfColor.fromInt(0xFF0D5C3A);
    final logoImage = await _getLogoImage();

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4.landscape,
        margin: const pw.EdgeInsets.all(32),
        header: (pw.Context context) {
          return pw.Column(
            children: [
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      if (logoImage != null)
                        pw.Image(logoImage, height: 40)
                      else
                        pw.Text(
                          'MARKAZ KNOWLEDGE CITY',
                          style: pw.TextStyle(
                            fontSize: 16,
                            fontWeight: pw.FontWeight.bold,
                            color: primaryColor,
                          ),
                        ),
                      pw.SizedBox(height: 4),
                      pw.Text(
                        'ADMIN EVENT PERFORMANCE REPORT',
                        style: pw.TextStyle(
                          fontSize: 12,
                          fontWeight: pw.FontWeight.bold,
                          color: primaryColor,
                        ),
                      ),
                    ],
                  ),
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.end,
                    children: [
                      pw.Text(
                        'Date: ${DateFormat("dd MMM yyyy").format(DateTime.now())}',
                        style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700),
                      ),
                      pw.Text(
                        'Generated By: Admin System',
                        style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700),
                      ),
                    ],
                  ),
                ],
              ),
              pw.SizedBox(height: 8),
              pw.Divider(color: primaryColor, thickness: 1.5),
              pw.SizedBox(height: 10),
            ],
          );
        },
        footer: (pw.Context context) {
          return pw.Container(
            alignment: pw.Alignment.centerRight,
            margin: const pw.EdgeInsets.only(top: 10),
            child: pw.Text(
              'Page ${context.pageNumber} of ${context.pagesCount}',
              style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey600),
            ),
          );
        },
        build: (pw.Context context) {
          final List<pw.Widget> content = [];

          // Summary Stats Container
          content.add(
            pw.Container(
              padding: const pw.EdgeInsets.all(12),
              decoration: pw.BoxDecoration(
                color: PdfColor.fromInt(0xFFF0FDF4),
                border: pw.Border.all(color: primaryColor, width: 1),
                borderRadius: pw.BorderRadius.circular(6),
              ),
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceAround,
                children: [
                  pw.Column(
                    children: [
                      pw.Text('Total Events Handled', style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700)),
                      pw.SizedBox(height: 2),
                      pw.Text('$totalEvents', style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold, color: primaryColor)),
                    ],
                  ),
                  pw.Container(height: 24, width: 1, color: PdfColors.grey300),
                  pw.Column(
                    children: [
                      pw.Text('Total Participants', style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700)),
                      pw.SizedBox(height: 2),
                      pw.Text(NumberFormat('#,##,###').format(totalParticipants), style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold, color: primaryColor)),
                    ],
                  ),
                  pw.Container(height: 24, width: 1, color: PdfColors.grey300),
                  pw.Column(
                    children: [
                      pw.Text('Active Admins', style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700)),
                      pw.SizedBox(height: 2),
                      pw.Text('${eventsByAdmin.length}', style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold, color: primaryColor)),
                    ],
                  ),
                ],
              ),
            ),
          );

          content.add(pw.SizedBox(height: 16));

          // Per Admin Breakdown Tables
          eventsByAdmin.forEach((adminName, adminEvents) {
            final adminEventsCount = adminEvents.length;
            final adminParticipantsCount = adminEvents.fold<int>(0, (sum, e) => sum + e.membersCount);

            content.add(
              pw.Container(
                margin: const pw.EdgeInsets.only(top: 10, bottom: 12),
                child: pw.Table(
                  border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.6),
                  columnWidths: const {
                    0: pw.FlexColumnWidth(3.2),
                    1: pw.FlexColumnWidth(2.3),
                    2: pw.FlexColumnWidth(2),
                    3: pw.FlexColumnWidth(2),
                  },
                  children: [
                    // Row 0: Admin Name & Overview Banner integrated inside the Table itself!
                    pw.TableRow(
                      decoration: pw.BoxDecoration(color: primaryColor),
                      children: [
                        pw.Padding(
                          padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                          child: pw.Text(
                            'ADMIN: ${adminName.toUpperCase()}',
                            style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: PdfColors.white),
                          ),
                        ),
                        pw.Padding(
                          padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                          child: pw.Text(
                            'Events: $adminEventsCount',
                            style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, color: PdfColors.white),
                          ),
                        ),
                        pw.Padding(
                          padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                          child: pw.Text(
                            'Total Participants:',
                            style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, color: PdfColors.white),
                          ),
                        ),
                        pw.Padding(
                          padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                          child: pw.Text(
                            NumberFormat("#,##,###").format(adminParticipantsCount),
                            style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, color: PdfColors.white),
                          ),
                        ),
                      ],
                    ),

                    // Row 1: Column Headings
                    pw.TableRow(
                      decoration: const pw.BoxDecoration(color: PdfColors.grey200),
                      children: [
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(5),
                          child: pw.Text('Event Name', style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
                        ),
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(5),
                          child: pw.Text('Venue / Place', style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
                        ),
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(5),
                          child: pw.Text('Event Date', style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
                        ),
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(5),
                          child: pw.Text('Participants Count', style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, color: primaryColor)),
                        ),
                      ],
                    ),

                    // Row 2+: Event Rows
                    ...adminEvents.map((e) {
                      return pw.TableRow(
                        children: [
                          pw.Padding(
                            padding: const pw.EdgeInsets.all(5),
                            child: pw.Text(cleanPdfText(e.eventName), style: const pw.TextStyle(fontSize: 8.5)),
                          ),
                          pw.Padding(
                            padding: const pw.EdgeInsets.all(5),
                            child: pw.Text(cleanPdfText(e.eventPlace), style: const pw.TextStyle(fontSize: 8.5)),
                          ),
                          pw.Padding(
                            padding: const pw.EdgeInsets.all(5),
                            child: pw.Text(DateFormat('dd MMM yyyy').format(e.eventDate), style: const pw.TextStyle(fontSize: 8.5)),
                          ),
                          pw.Padding(
                            padding: const pw.EdgeInsets.all(5),
                            child: pw.Text(
                              NumberFormat('#,##,###').format(e.membersCount),
                              style: pw.TextStyle(fontSize: 8.5, fontWeight: pw.FontWeight.bold, color: primaryColor),
                            ),
                          ),
                        ],
                      );
                    }),
                  ],
                ),
              ),
            );
          });

          return content;
        },
      ),
    );

    return pdf.save();
  }

  // Generate Donations PDF Report with Breakdown Totals
  static Future<Uint8List> generateDonationsPdfReport({
    required String reportTitle,
    required List<GuestVisit> guests,
  }) async {
    final pdf = pw.Document();
    final primaryColor = PdfColor.fromInt(0xFF0D5C3A);
    final logoImage = await _getLogoImage();

    double totalDonations = 0;
    double shorbuhanaTotal = 0;
    double jamiulFuthuhTotal = 0;

    for (final g in guests) {
      final amt = g.donationAmount;
      final dest = (g.donationTo ?? '').toLowerCase();
      totalDonations += amt;
      if (dest.contains('shorb') || dest.contains('shurb')) {
        shorbuhanaTotal += amt;
      } else if (dest.contains('jami') || dest.contains('jf') || dest.contains('futh')) {
        jamiulFuthuhTotal += amt;
      }
    }

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4.landscape,
        margin: const pw.EdgeInsets.all(32),
        header: (pw.Context context) {
          return pw.Column(
            children: [
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      if (logoImage != null)
                        pw.Image(logoImage, height: 40)
                      else
                        pw.Text(
                          'MARKAZ KNOWLEDGE CITY',
                          style: pw.TextStyle(
                            fontSize: 16,
                            fontWeight: pw.FontWeight.bold,
                            color: primaryColor,
                          ),
                        ),
                      pw.SizedBox(height: 4),
                      pw.Text(
                        reportTitle.toUpperCase(),
                        style: pw.TextStyle(
                          fontSize: 12,
                          fontWeight: pw.FontWeight.bold,
                          color: primaryColor,
                        ),
                      ),
                    ],
                  ),
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.end,
                    children: [
                      pw.Text(
                        'Date: ${DateFormat("dd MMM yyyy").format(DateTime.now())}',
                        style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700),
                      ),
                      pw.Text(
                        'Generated By: Admin System',
                        style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700),
                      ),
                    ],
                  ),
                ],
              ),
              pw.SizedBox(height: 8),
              pw.Divider(color: primaryColor, thickness: 1.5),
              pw.SizedBox(height: 10),
            ],
          );
        },
        footer: (pw.Context context) {
          return pw.Container(
            alignment: pw.Alignment.centerRight,
            margin: const pw.EdgeInsets.only(top: 10),
            child: pw.Text(
              'Page ${context.pageNumber} of ${context.pagesCount}',
              style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey600),
            ),
          );
        },
        build: (pw.Context context) {
          final List<pw.Widget> content = [];

          // Summary Banner Card for Donations
          content.add(
            pw.Container(
              padding: const pw.EdgeInsets.all(10),
              decoration: pw.BoxDecoration(
                color: PdfColor.fromInt(0xFFF0FDF4),
                border: pw.Border.all(color: primaryColor, width: 1),
                borderRadius: pw.BorderRadius.circular(6),
              ),
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceAround,
                children: [
                  pw.Column(
                    children: [
                      pw.Text('Total Donation (Selected Filter)', style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700)),
                      pw.SizedBox(height: 2),
                      pw.Text('Rs. ${NumberFormat("#,##,###").format(totalDonations)}', style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold, color: primaryColor)),
                    ],
                  ),
                  pw.Container(height: 24, width: 1, color: PdfColors.grey300),
                  pw.Column(
                    children: [
                      pw.Text('Total to Shorbuhana', style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700)),
                      pw.SizedBox(height: 2),
                      pw.Text('Rs. ${NumberFormat("#,##,###").format(shorbuhanaTotal)}', style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold, color: primaryColor)),
                    ],
                  ),
                  pw.Container(height: 24, width: 1, color: PdfColors.grey300),
                  pw.Column(
                    children: [
                      pw.Text('Total to Jamiul Futhuh', style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700)),
                      pw.SizedBox(height: 2),
                      pw.Text('Rs. ${NumberFormat("#,##,###").format(jamiulFuthuhTotal)}', style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold, color: primaryColor)),
                    ],
                  ),
                ],
              ),
            ),
          );

          content.add(pw.SizedBox(height: 14));

          // Table of Donation Records
          content.add(
            pw.Table(
              border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.6),
              columnWidths: const {
                0: pw.FlexColumnWidth(2.5),
                1: pw.FlexColumnWidth(2),
                2: pw.FlexColumnWidth(2),
                3: pw.FlexColumnWidth(1.8),
                4: pw.FlexColumnWidth(1.8),
                5: pw.FlexColumnWidth(1.8),
              },
              children: [
                // Header Row
                pw.TableRow(
                  decoration: const pw.BoxDecoration(color: PdfColors.grey200),
                  children: [
                    pw.Padding(padding: const pw.EdgeInsets.all(5), child: pw.Text('Guest Name', style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold))),
                    pw.Padding(padding: const pw.EdgeInsets.all(5), child: pw.Text('Location', style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold))),
                    pw.Padding(padding: const pw.EdgeInsets.all(5), child: pw.Text('Donation To', style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold))),
                    pw.Padding(padding: const pw.EdgeInsets.all(5), child: pw.Text('Amount (Rs.)', style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, color: primaryColor))),
                    pw.Padding(padding: const pw.EdgeInsets.all(5), child: pw.Text('Receipt No', style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold))),
                    pw.Padding(padding: const pw.EdgeInsets.all(5), child: pw.Text('Date', style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold))),
                  ],
                ),
                // Data Rows
                ...guests.map((g) {
                  return pw.TableRow(
                    children: [
                      pw.Padding(padding: const pw.EdgeInsets.all(5), child: pw.Text(cleanPdfText(g.guestName), style: const pw.TextStyle(fontSize: 8.5))),
                      pw.Padding(padding: const pw.EdgeInsets.all(5), child: pw.Text(cleanPdfText(g.place), style: const pw.TextStyle(fontSize: 8.5))),
                      pw.Padding(padding: const pw.EdgeInsets.all(5), child: pw.Text(cleanPdfText(g.donationTo ?? '-'), style: const pw.TextStyle(fontSize: 8.5))),
                      pw.Padding(padding: const pw.EdgeInsets.all(5), child: pw.Text('Rs. ${NumberFormat("#,##,###").format(g.donationAmount)}', style: pw.TextStyle(fontSize: 8.5, fontWeight: pw.FontWeight.bold, color: primaryColor))),
                      pw.Padding(padding: const pw.EdgeInsets.all(5), child: pw.Text(cleanPdfText(g.receiptNo ?? '-'), style: const pw.TextStyle(fontSize: 8.5))),
                      pw.Padding(padding: const pw.EdgeInsets.all(5), child: pw.Text(DateFormat('dd MMM yyyy').format(g.createdAt), style: const pw.TextStyle(fontSize: 8.5))),
                    ],
                  );
                }),
              ],
            ),
          );

          return content;
        },
      ),
    );

    return pdf.save();
  }

  // Generate Outreach Department Executive Summary PDF Report
  static Future<Uint8List> generateOutreachDepartmentPdf({
    required String filterLabel,
    required List<GuestVisit> guests,
    required List<EventModel> events,
    required List<String> selectedAdminNames,
  }) async {
    final pdf = pw.Document();
    final primaryColor = PdfColor.fromInt(0xFF0D5C3A);
    final logoImage = await _getLogoImage();

    // 1. Overall Summaries
    final totalGuests = guests.length;
    final totalDonations = guests.fold(0.0, (sum, g) => sum + g.donationAmount);
    double shorbuhanaTotal = 0.0;
    double jamiulFuthuhTotal = 0.0;
    for (final g in guests) {
      final dest = (g.donationTo ?? '').toLowerCase();
      if (dest.contains('shorb') || dest.contains('shurb')) {
        shorbuhanaTotal += g.donationAmount;
      } else if (dest.contains('jami') || dest.contains('jf') || dest.contains('futh')) {
        jamiulFuthuhTotal += g.donationAmount;
      }
    }

    final totalEvents = events.length;
    final totalAttendees = events.fold(0, (sum, e) => sum + e.membersCount);

    // 2. Group Guests by Handled By Admin
    final Map<String, List<GuestVisit>> guestsByAdmin = {};
    for (final g in guests) {
      final admin = (g.handledBy != null && g.handledBy!.trim().isNotEmpty) ? g.handledBy!.trim() : 'Unassigned';
      if (selectedAdminNames.isNotEmpty && !selectedAdminNames.contains(admin) && admin != 'Unassigned') {
        continue;
      }
      guestsByAdmin.putIfAbsent(admin, () => []).add(g);
    }

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4.landscape,
        margin: const pw.EdgeInsets.all(32),
        header: (pw.Context context) {
          return pw.Column(
            children: [
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      if (logoImage != null)
                        pw.Image(logoImage, height: 44)
                      else
                        pw.Text(
                          'MARKAZ KNOWLEDGE CITY',
                          style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold, color: primaryColor),
                        ),
                      pw.SizedBox(height: 4),
                      pw.Text(
                        'OUTREACH DEPARTMENT REPORT',
                        style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold, color: primaryColor),
                      ),
                      pw.Text(
                        'Selected Filter: $filterLabel',
                        style: pw.TextStyle(fontSize: 9.5, fontWeight: pw.FontWeight.bold, color: PdfColors.grey800),
                      ),
                    ],
                  ),
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.end,
                    children: [
                      pw.Text('Date: ${DateFormat("dd MMM yyyy").format(DateTime.now())}', style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700)),
                      pw.Text('Generated By: Admin System', style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700)),
                    ],
                  ),
                ],
              ),
              pw.SizedBox(height: 8),
              pw.Divider(color: primaryColor, thickness: 1.8),
              pw.SizedBox(height: 10),
            ],
          );
        },
        footer: (pw.Context context) {
          return pw.Container(
            alignment: pw.Alignment.centerRight,
            margin: const pw.EdgeInsets.only(top: 10),
            child: pw.Text(
              'Page ${context.pageNumber} of ${context.pagesCount}',
              style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey600),
            ),
          );
        },
        build: (pw.Context context) {
          final List<pw.Widget> content = [];

          // Overview Dashboard Cards
          content.add(
            pw.Container(
              padding: const pw.EdgeInsets.all(8),
              decoration: pw.BoxDecoration(
                color: PdfColor.fromInt(0xFFF0FDF4),
                border: pw.Border.all(color: primaryColor, width: 1),
                borderRadius: pw.BorderRadius.circular(6),
              ),
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceAround,
                children: [
                  pw.Column(
                    children: [
                      pw.Text('Total Guests', style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700)),
                      pw.SizedBox(height: 2),
                      pw.Text(NumberFormat('#,##,###').format(totalGuests), style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: primaryColor)),
                    ],
                  ),
                  pw.Container(height: 22, width: 1, color: PdfColors.grey300),
                  pw.Column(
                    children: [
                      pw.Text('Total Donation', style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700)),
                      pw.SizedBox(height: 2),
                      pw.Text('Rs. ${NumberFormat('#,##,###').format(totalDonations)}', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: primaryColor)),
                    ],
                  ),
                  pw.Container(height: 22, width: 1, color: PdfColors.grey300),
                  pw.Column(
                    children: [
                      pw.Text('Total to Shorbuhana', style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700)),
                      pw.SizedBox(height: 2),
                      pw.Text('Rs. ${NumberFormat('#,##,###').format(shorbuhanaTotal)}', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: primaryColor)),
                    ],
                  ),
                  pw.Container(height: 22, width: 1, color: PdfColors.grey300),
                  pw.Column(
                    children: [
                      pw.Text('Total to Jamiul Futhuh', style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700)),
                      pw.SizedBox(height: 2),
                      pw.Text('Rs. ${NumberFormat('#,##,###').format(jamiulFuthuhTotal)}', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: primaryColor)),
                    ],
                  ),
                  pw.Container(height: 22, width: 1, color: PdfColors.grey300),
                  pw.Column(
                    children: [
                      pw.Text('Total Events', style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700)),
                      pw.SizedBox(height: 2),
                      pw.Text('$totalEvents', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: primaryColor)),
                    ],
                  ),
                  pw.Container(height: 22, width: 1, color: PdfColors.grey300),
                  pw.Column(
                    children: [
                      pw.Text('Event Attendees', style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700)),
                      pw.SizedBox(height: 2),
                      pw.Text(NumberFormat('#,##,###').format(totalAttendees), style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: primaryColor)),
                    ],
                  ),
                ],
              ),
            ),
          );

          content.add(pw.SizedBox(height: 16));

          // 1. ADMIN PERFORMANCE SUMMARY TABLE
          content.add(
            pw.Text(
              '1. ADMIN PERFORMANCE (GUESTS HANDLED)',
              style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold, color: primaryColor),
            ),
          );
          content.add(pw.SizedBox(height: 6));

          content.add(
            pw.Table(
              border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.6),
              columnWidths: const {
                0: pw.FlexColumnWidth(3.5),
                1: pw.FlexColumnWidth(2.5),
                2: pw.FlexColumnWidth(2.5),
              },
              children: [
                pw.TableRow(
                  decoration: const pw.BoxDecoration(color: PdfColors.grey200),
                  children: [
                    pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text('Admin Name', style: pw.TextStyle(fontSize: 9.5, fontWeight: pw.FontWeight.bold))),
                    pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text('Total Guests Handled', style: pw.TextStyle(fontSize: 9.5, fontWeight: pw.FontWeight.bold, color: primaryColor))),
                    pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text('Total Donations Collected', style: pw.TextStyle(fontSize: 9.5, fontWeight: pw.FontWeight.bold, color: primaryColor))),
                  ],
                ),
                ...guestsByAdmin.entries.map((entry) {
                  final adminName = entry.key;
                  final adminGuestsList = entry.value;
                  final count = adminGuestsList.length;
                  final donationsSum = adminGuestsList.fold(0.0, (s, g) => s + g.donationAmount);

                  return pw.TableRow(
                    children: [
                      pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text(cleanPdfText(adminName), style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold))),
                      pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text(NumberFormat('#,##,###').format(count), style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold))),
                      pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text('Rs. ${NumberFormat('#,##,###').format(donationsSum)}', style: const pw.TextStyle(fontSize: 9))),
                    ],
                  );
                }),
              ],
            ),
          );

          content.add(pw.SizedBox(height: 20));

          // 2. EVENTS PERFORMANCE TABLE
          content.add(
            pw.Text(
              '2. EVENTS PERFORMANCE & ATTENDEES',
              style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold, color: primaryColor),
            ),
          );
          content.add(pw.SizedBox(height: 6));

          content.add(
            pw.Table(
              border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.6),
              columnWidths: const {
                0: pw.FlexColumnWidth(3),
                1: pw.FlexColumnWidth(2),
                2: pw.FlexColumnWidth(2),
                3: pw.FlexColumnWidth(2),
                4: pw.FlexColumnWidth(2.5),
              },
              children: [
                pw.TableRow(
                  decoration: const pw.BoxDecoration(color: PdfColors.grey200),
                  children: [
                    pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text('Event Name', style: pw.TextStyle(fontSize: 9.5, fontWeight: pw.FontWeight.bold))),
                    pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text('Venue / Place', style: pw.TextStyle(fontSize: 9.5, fontWeight: pw.FontWeight.bold))),
                    pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text('Event Date', style: pw.TextStyle(fontSize: 9.5, fontWeight: pw.FontWeight.bold))),
                    pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text('Attendees Count', style: pw.TextStyle(fontSize: 9.5, fontWeight: pw.FontWeight.bold, color: primaryColor))),
                    pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text('Admin Names (Handled By)', style: pw.TextStyle(fontSize: 9.5, fontWeight: pw.FontWeight.bold))),
                  ],
                ),
                ...events.map((e) {
                  return pw.TableRow(
                    children: [
                      pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text(cleanPdfText(e.eventName), style: const pw.TextStyle(fontSize: 8.5))),
                      pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text(cleanPdfText(e.eventPlace), style: const pw.TextStyle(fontSize: 8.5))),
                      pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text(DateFormat('dd MMM yyyy').format(e.eventDate), style: const pw.TextStyle(fontSize: 8.5))),
                      pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text(NumberFormat('#,##,###').format(e.membersCount), style: pw.TextStyle(fontSize: 8.5, fontWeight: pw.FontWeight.bold, color: primaryColor))),
                      pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text(cleanPdfText(e.handledBy), style: const pw.TextStyle(fontSize: 8.5))),
                    ],
                  );
                }),
              ],
            ),
          );

          return content;
        },
      ),
    );

    return pdf.save();
  }
}

pw.Widget _buildPdfRow(String label, String value) {
  return pw.Padding(
    padding: const pw.EdgeInsets.symmetric(vertical: 4),
    child: pw.Row(
      children: [
        pw.SizedBox(
          width: 130,
          child: pw.Text(label, style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
        ),
        pw.Expanded(child: pw.Text(value)),
      ],
    ),
  );
}
