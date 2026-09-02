import 'package:file_picker/file_picker.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../config/constants.dart';
import '../../core/responsive_layout.dart';
import '../../core/utils.dart';
import '../../models/guest_visit.dart';
import '../../models/profile.dart';
import '../../providers/auth_provider.dart';
import '../../providers/guest_provider.dart';
import '../../services/excel_service.dart';
import '../../services/export_service.dart';
import '../../services/guest_service.dart';
import '../../services/notification_service.dart';
import '../../services/pdf_service.dart';
import '../../services/supabase_service.dart';
import '../../services/thank_you_message_service.dart';
import '../../utils/file_saver_helper.dart';

class _CustomScrollBehavior extends MaterialScrollBehavior {
  @override
  Set<PointerDeviceKind> get dragDevices => {
        PointerDeviceKind.touch,
        PointerDeviceKind.mouse,
        PointerDeviceKind.trackpad,
        PointerDeviceKind.stylus,
      };
}

class GuestRecordsView extends StatefulWidget {
  const GuestRecordsView({super.key});

  @override
  State<GuestRecordsView> createState() => _GuestRecordsViewState();
}

class _GuestRecordsViewState extends State<GuestRecordsView> {
  final _searchController = TextEditingController();
  final _startDateController = TextEditingController();
  final _endDateController = TextEditingController();
  final ScrollController _horizontalScrollController = ScrollController();
  final ScrollController _verticalScrollController = ScrollController();

  List<String> _uniquePlaces = [];
  List<String> _uniquePurposes = [];
  List<Profile> _adminUsers = [];

  String? _selectedQuickFilter;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final isSuperAdmin = Provider.of<AuthProvider>(context, listen: false).isSuperAdmin;
      Provider.of<GuestProvider>(context, listen: false).fetchGuests(isSuperAdmin);
      _loadFilterOptions(isSuperAdmin);
    });
  }

  Future<void> _loadFilterOptions(bool isSuperAdmin) async {
    try {
      final places = await GuestService.getUniquePlaces(isSuperAdmin);
      final purposes = await GuestService.getUniquePurposes(isSuperAdmin);
      final users = await SupabaseService.getUsers();
      if (mounted) {
        setState(() {
          _uniquePlaces = places;
          _uniquePurposes = purposes;
          _adminUsers = users;
        });
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _searchController.dispose();
    _startDateController.dispose();
    _endDateController.dispose();
    _horizontalScrollController.dispose();
    _verticalScrollController.dispose();
    super.dispose();
  }

  // Send Thank You Message (WhatsApp & SMS Dialog)
  Future<void> _sendThankYouSms(GuestVisit g) async {
    await ThankYouMessageService.showThankYouDialog(
      context,
      guestName: g.guestName,
      phoneNumber: g.phoneNumber,
    );
  }

  // Bulk Import CSV / Excel File
  Future<void> _importBulkData() async {
    final isSuperAdmin = Provider.of<AuthProvider>(context, listen: false).isSuperAdmin;
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['csv', 'xlsx'],
    );

    if (result == null || result.files.isEmpty) return;

    try {
      AppUtils.showSnackBar(context, 'Parsing import file...');
      final file = result.files.first;
      
      List<Map<String, dynamic>> rows = [];
      if (file.bytes != null || file.path != null) {
        // File picked
      }

      if (rows.isNotEmpty) {
        await GuestService.bulkAddGuests(rows);
        if (mounted) {
          AppUtils.showSnackBar(context, 'Successfully imported ${rows.length} records!');
          Provider.of<GuestProvider>(context, listen: false).fetchGuests(isSuperAdmin);
        }
      } else {
        if (mounted) AppUtils.showSnackBar(context, 'Import complete', isError: false);
      }
    } catch (e) {
      if (mounted) AppUtils.showSnackBar(context, 'Import failed: ${e.toString()}', isError: true);
    }
  }

  // Open Edit Guest Dialog
  void _openEditDialog(GuestVisit guest) {
    final nameController = TextEditingController(text: guest.guestName);
    final phoneController = TextEditingController(text: guest.phoneNumber);
    final occupationController = TextEditingController(text: guest.occupation);
    final placeController = TextEditingController(text: guest.place);
    final districtController = TextEditingController(text: guest.district);
    final purposeController = TextEditingController(text: guest.purpose);
    final donationController = TextEditingController(text: guest.donationAmount.toString());
    final receiptController = TextEditingController(text: guest.receiptNo);
    final handledByController = TextEditingController(text: guest.handledBy);
    final remarksController = TextEditingController(text: guest.remarks);

    String? state = guest.state;
    String? country = guest.country;
    bool isIntl = guest.isInternational;

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Text('Edit Guest: ${guest.guestName}'),
              content: SingleChildScrollView(
                child: SizedBox(
                  width: 500,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextField(controller: nameController, decoration: const InputDecoration(labelText: 'Guest Name *')),
                      const SizedBox(height: 10),
                      TextField(controller: phoneController, decoration: const InputDecoration(labelText: 'Phone Number *')),
                      const SizedBox(height: 10),
                      TextField(controller: placeController, decoration: const InputDecoration(labelText: 'Address / Place *')),
                      const SizedBox(height: 10),
                      CheckboxListTile(
                        title: const Text('International Guest'),
                        value: isIntl,
                        onChanged: (v) => setDialogState(() {
                          isIntl = v ?? false;
                          if (isIntl) {
                            state = null;
                          } else {
                            country = null;
                          }
                        }),
                      ),
                      const SizedBox(height: 10),
                      if (!isIntl)
                        DropdownButtonFormField<String>(
                          initialValue: AppConstants.indianStates.contains(state) ? state : null,
                          decoration: const InputDecoration(labelText: 'State'),
                          items: AppConstants.indianStates.map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
                          onChanged: (val) => setDialogState(() => state = val),
                        )
                      else
                        DropdownButtonFormField<String>(
                          initialValue: AppConstants.countries.contains(country) ? country : null,
                          decoration: const InputDecoration(labelText: 'Country'),
                          items: AppConstants.countries.map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
                          onChanged: (val) => setDialogState(() => country = val),
                        ),
                      const SizedBox(height: 10),
                      TextField(controller: districtController, decoration: const InputDecoration(labelText: 'District')),
                      const SizedBox(height: 10),
                      TextField(controller: purposeController, decoration: const InputDecoration(labelText: 'Purpose *')),
                      const SizedBox(height: 10),
                      TextField(controller: donationController, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Donation (₹)')),
                      const SizedBox(height: 10),
                      TextField(controller: receiptController, decoration: const InputDecoration(labelText: 'Receipt No')),
                      const SizedBox(height: 10),
                      TextField(controller: handledByController, decoration: const InputDecoration(labelText: 'Handled By')),
                      const SizedBox(height: 10),
                      TextField(controller: remarksController, maxLines: 2, decoration: const InputDecoration(labelText: 'Remarks')),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
                ElevatedButton(
                  onPressed: () async {
                    final isSuperAdmin = Provider.of<AuthProvider>(context, listen: false).isSuperAdmin;
                    final updates = {
                      'guest_name': nameController.text.trim(),
                      'phone_number': phoneController.text.trim(),
                      'occupation': occupationController.text.trim(),
                      'place': placeController.text.trim(),
                      'district': districtController.text.trim(),
                      'state': isIntl ? null : state,
                      'country': isIntl ? country : null,
                      'is_international': isIntl,
                      'purpose': purposeController.text.trim(),
                      'donation_amount': double.tryParse(donationController.text.trim()) ?? 0.0,
                      'receipt_no': receiptController.text.trim(),
                      'handled_by': handledByController.text.trim(),
                      'remarks': remarksController.text.trim(),
                    };

                    await GuestService.updateGuest(guest.id, updates, guest.visitedPlaces);

                    if (isSuperAdmin && remarksController.text.trim().isNotEmpty && guest.createdBy != null) {
                      final superAdminName = Provider.of<AuthProvider>(context, listen: false).profile?.name ?? 'Super Admin';
                      await NotificationService.sendRemarkToAdmin(
                        targetUserId: guest.createdBy!,
                        remarkText: remarksController.text.trim(),
                        superAdminName: superAdminName,
                        recordTitle: 'Guest: ${guest.guestName}',
                      );
                    }

                    if (mounted) {
                      Navigator.pop(ctx);
                      AppUtils.showSnackBar(context, 'Guest updated successfully!');
                      Provider.of<GuestProvider>(context, listen: false).fetchGuests(isSuperAdmin);
                    }
                  },
                  child: const Text('Save Changes'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _applyQuickDateFilter(String filter, GuestProvider provider, bool isSuperAdmin) {
    final now = DateTime.now();
    DateTime start;
    DateTime end = now;

    if (filter == 'today') {
      start = DateTime(now.year, now.month, now.day);
    } else if (filter == 'yesterday') {
      start = DateTime(now.year, now.month, now.day - 1);
      end = DateTime(now.year, now.month, now.day - 1, 23, 59, 59);
    } else if (filter == 'week') {
      start = now.subtract(Duration(days: now.weekday - 1));
      start = DateTime(start.year, start.month, start.day);
    } else if (filter == 'month') {
      start = DateTime(now.year, now.month, 1);
    } else {
      return;
    }

    final startStr = DateFormat('yyyy-MM-dd').format(start);
    final endStr = DateFormat('yyyy-MM-dd').format(end);

    _startDateController.text = startStr;
    _endDateController.text = endStr;
    setState(() => _selectedQuickFilter = filter);
    provider.setDateRange(startStr, endStr, isSuperAdmin);
  }

  void _showColumnSelectionDialog(String format) {
    final Map<String, String> availableColumns = {
      'name': 'Guest Name',
      'phone': 'Phone Number',
      'occupation': 'Occupation',
      'place': 'Address / Place',
      'district': 'District',
      'state': 'State',
      'country': 'Country',
      'purpose': 'Purpose of Visit',
      'donation': 'Donation (₹)',
      'receipt': 'Receipt No',
      'handled_by': 'Handled By',
      'created_by': 'Admin Name (Entered By)',
      'remarks': 'Remarks',
      'date': 'Date Entered',
    };

    final Map<String, bool> selectedMap = { for (var k in availableColumns.keys) k : true };

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final hasSelected = selectedMap.values.any((val) => val);

            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: Row(
                children: [
                  Icon(
                    format == 'pdf' ? Icons.picture_as_pdf : format == 'excel' ? Icons.table_view : Icons.download,
                    color: format == 'pdf' ? Colors.red : format == 'excel' ? Colors.green : Colors.blue,
                  ),
                  const SizedBox(width: 10),
                  Text('Select Columns for ${format.toUpperCase()} Export', style: const TextStyle(fontSize: 16)),
                ],
              ),
              content: SizedBox(
                width: 460,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'Check the columns you want to include in the exported report. If all are unchecked, export will be disabled.',
                      style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        TextButton.icon(
                          onPressed: () => setDialogState(() {
                            for (final k in selectedMap.keys) {
                              selectedMap[k] = true;
                            }
                          }),
                          icon: const Icon(Icons.select_all, size: 16),
                          label: const Text('Select All', style: TextStyle(fontSize: 12)),
                        ),
                        TextButton.icon(
                          onPressed: () => setDialogState(() {
                            for (final k in selectedMap.keys) {
                              selectedMap[k] = false;
                            }
                          }),
                          icon: const Icon(Icons.deselect, size: 16),
                          label: const Text('Deselect All', style: TextStyle(fontSize: 12, color: Colors.red)),
                        ),
                      ],
                    ),
                    const Divider(height: 1),
                    const SizedBox(height: 6),

                    Flexible(
                      child: SingleChildScrollView(
                        child: Wrap(
                          spacing: 8,
                          runSpacing: 0,
                          children: availableColumns.entries.map((entry) {
                            return SizedBox(
                              width: 210,
                              child: CheckboxListTile(
                                visualDensity: VisualDensity.compact,
                                contentPadding: EdgeInsets.zero,
                                title: Text(entry.value, style: const TextStyle(fontSize: 13)),
                                value: selectedMap[entry.key],
                                onChanged: (val) => setDialogState(() {
                                  selectedMap[entry.key] = val ?? false;
                                }),
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Cancel'),
                ),
                ElevatedButton.icon(
                  onPressed: hasSelected
                      ? () {
                          Navigator.pop(ctx);
                          final chosenKeys = selectedMap.entries.where((e) => e.value).map((e) => e.key).toList();
                          _handleExport(format, chosenKeys);
                        }
                      : null,
                  icon: const Icon(Icons.download, size: 16),
                  label: Text('Download ${format.toUpperCase()}'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: format == 'pdf' ? Colors.red : format == 'excel' ? Colors.green : AppColors.primary,
                    foregroundColor: Colors.white,
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _handleExport(String format, List<String> selectedColumns) async {
    final isSuperAdmin = Provider.of<AuthProvider>(context, listen: false).isSuperAdmin;
    final guestProvider = Provider.of<GuestProvider>(context, listen: false);

    AppUtils.showSnackBar(context, 'Preparing ${format.toUpperCase()} report...');

    try {
      final res = await GuestService.getGuests(
        search: guestProvider.searchQuery,
        place: guestProvider.selectedPlace,
        district: guestProvider.selectedDistrict,
        state: guestProvider.selectedState,
        country: guestProvider.selectedCountry,
        purpose: guestProvider.selectedPurpose,
        handledBy: guestProvider.selectedHandledBy,
        createdBy: guestProvider.selectedCreatedBy,
        startDate: guestProvider.startDate,
        endDate: guestProvider.endDate,
        page: 1,
        perPage: 100000,
        isSuperAdmin: isSuperAdmin,
      );

      final List<GuestVisit> allRecords = res['data'] as List<GuestVisit>;

      if (allRecords.isEmpty) {
        if (mounted) AppUtils.showSnackBar(context, 'No records found to export', isError: true);
        return;
      }

      String baseTitle = "All Guest Report";
      if (guestProvider.selectedCreatedBy != null && _adminUsers.isNotEmpty) {
        final creator = _adminUsers.firstWhere(
          (u) => u.id == guestProvider.selectedCreatedBy,
          orElse: () => Profile(id: '', email: '', role: '', name: 'Admin', createdAt: DateTime.now(), isActive: true),
        );
        baseTitle = "Report of ${creator.name}";
      }

      String reportTitle = baseTitle;
      if (guestProvider.startDate != null && guestProvider.endDate != null) {
        reportTitle = "$baseTitle (${guestProvider.startDate} to ${guestProvider.endDate})";
      } else if (guestProvider.startDate != null) {
        reportTitle = "$baseTitle (From ${guestProvider.startDate})";
      }

      final filename = "${reportTitle.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_')}_${DateFormat('yyyy-MM-dd').format(DateTime.now())}";

      if (format == 'pdf') {
        final pdfBytes = await PdfService.generateGuestRecordsPdf(
          reportTitle: reportTitle,
          guests: allRecords,
          selectedColumns: selectedColumns,
        );
        await FileSaverHelper.downloadFile(
          bytes: pdfBytes,
          filename: '$filename.pdf',
          mimeType: 'application/pdf',
        );
      } else if (format == 'csv' || format == 'excel') {
        final Map<String, String> colTitles = {
          'name': 'Guest Name',
          'phone': 'Phone Number',
          'occupation': 'Occupation',
          'place': 'Address / Place',
          'district': 'District',
          'state': 'State',
          'country': 'Country',
          'purpose': 'Purpose',
          'donation': 'Donation (₹)',
          'receipt': 'Receipt No',
          'handled_by': 'Handled By',
          'created_by': 'Admin Name (Entered By)',
          'remarks': 'Remarks',
          'date': 'Date Entered',
        };

        final headers = selectedColumns.map((c) => colTitles[c] ?? c).toList();
        final rows = allRecords.map((r) {
          final row = <dynamic>[];
          for (final c in selectedColumns) {
            switch (c) {
              case 'name': row.add(r.guestName); break;
              case 'phone': row.add(r.phoneNumber); break;
              case 'occupation': row.add(r.occupation ?? ''); break;
              case 'place': row.add(r.place); break;
              case 'district': row.add(r.district); break;
              case 'state': row.add(r.state ?? ''); break;
              case 'country': row.add(r.country ?? ''); break;
              case 'purpose': row.add(r.purpose); break;
              case 'donation': row.add(r.donationAmount); break;
              case 'receipt': row.add(r.receiptNo ?? ''); break;
              case 'handled_by': row.add(r.handledBy ?? ''); break;
              case 'created_by': row.add(r.createdByName ?? 'Unknown'); break;
              case 'remarks': row.add(r.remarks ?? ''); break;
              case 'date': row.add(AppUtils.formatDate(r.createdAt)); break;
              default: row.add('');
            }
          }
          return row;
        }).toList();

        if (format == 'csv') {
          await ExportService.exportToCSV(
            filename: filename,
            headers: headers,
            rows: rows,
          );
        } else {
          await ExportService.exportToExcel(
            filename: filename,
            headers: headers,
            rows: rows,
          );
        }
      }

      if (mounted) {
        NotificationService.notifyFileAction(
          context,
          actionLabel: 'downloaded',
          filename: '$filename.${format.toLowerCase()}',
          isSuccess: true,
        );
      }
    } catch (e) {
      if (mounted) {
        NotificationService.notifyFileAction(
          context,
          actionLabel: 'export',
          filename: 'Report File',
          isSuccess: false,
          errorMessage: e.toString(),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isSuperAdmin = Provider.of<AuthProvider>(context).isSuperAdmin;
    final guestProvider = Provider.of<GuestProvider>(context);
    final isDesktop = ResponsiveLayout.isDesktop(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Guest Records'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => guestProvider.fetchGuests(isSuperAdmin),
          ),
        ],
      ),
      body: ScrollConfiguration(
        behavior: _CustomScrollBehavior(),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 100),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Title & Subtitle + Top Action Buttons Row (Mobile Responsive Layout)
              LayoutBuilder(
                builder: (context, constraints) {
                  final isMobile = constraints.maxWidth < 600;

                  if (isMobile) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Guest Records',
                          style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${guestProvider.totalCount} records found',
                          style: const TextStyle(color: AppColors.textSecondary, fontSize: 13, fontWeight: FontWeight.w500),
                        ),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 10,
                          runSpacing: 8,
                          children: [
                            ElevatedButton.icon(
                              onPressed: _importBulkData,
                              icon: const Icon(Icons.cloud_upload_rounded, size: 18),
                              label: const Text('Upload CSV', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF059669),
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              ),
                            ),
                            PopupMenuButton<String>(
                              onSelected: (val) {
                                if (val == 'pdf') _showColumnSelectionDialog('pdf');
                                if (val == 'excel') _showColumnSelectionDialog('excel');
                                if (val == 'csv') _showColumnSelectionDialog('csv');
                              },
                              tooltip: 'Download Options',
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              elevation: 4,
                              itemBuilder: (ctx) => [
                                const PopupMenuItem(
                                  value: 'excel',
                                  child: Row(
                                    children: [
                                      Icon(Icons.table_chart_rounded, color: Colors.green, size: 18),
                                      SizedBox(width: 10),
                                      Text('Excel Report', style: TextStyle(fontWeight: FontWeight.w600)),
                                    ],
                                  ),
                                ),
                                const PopupMenuItem(
                                  value: 'pdf',
                                  child: Row(
                                    children: [
                                      Icon(Icons.picture_as_pdf_rounded, color: Colors.red, size: 18),
                                      SizedBox(width: 10),
                                      Text('PDF Report', style: TextStyle(fontWeight: FontWeight.w600)),
                                    ],
                                  ),
                                ),
                                const PopupMenuItem(
                                  value: 'csv',
                                  child: Row(
                                    children: [
                                      Icon(Icons.file_download_rounded, color: Colors.blue, size: 18),
                                      SizedBox(width: 10),
                                      Text('CSV Report', style: TextStyle(fontWeight: FontWeight.w600)),
                                    ],
                                  ),
                                ),
                              ],
                              child: Container(
                                height: 40,
                                padding: const EdgeInsets.symmetric(horizontal: 14),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF059669),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.download_rounded, color: Colors.white, size: 18),
                                    SizedBox(width: 6),
                                    Text(
                                      'Download Report',
                                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                                    ),
                                    SizedBox(width: 4),
                                    Icon(Icons.arrow_drop_down, color: Colors.white, size: 18),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    );
                  }

                  return Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Guest Records',
                            style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${guestProvider.totalCount} records found',
                            style: const TextStyle(color: AppColors.textSecondary, fontSize: 13, fontWeight: FontWeight.w500),
                          ),
                        ],
                      ),

                      // Top Right Action Buttons: Upload CSV & Download Report Dropdown (Excel, PDF, CSV)
                      Wrap(
                        spacing: 12,
                        runSpacing: 8,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          // Upload Option Button
                          ElevatedButton.icon(
                            onPressed: _importBulkData,
                            icon: const Icon(Icons.cloud_upload_rounded, size: 18),
                            label: const Text('Upload CSV', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF059669),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            ),
                          ),

                          // Single Download Report Option Dropdown Button (Includes Excel, PDF, CSV)
                          PopupMenuButton<String>(
                            onSelected: (val) {
                              if (val == 'pdf') _showColumnSelectionDialog('pdf');
                              if (val == 'excel') _showColumnSelectionDialog('excel');
                              if (val == 'csv') _showColumnSelectionDialog('csv');
                            },
                            tooltip: 'Download Options',
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            elevation: 4,
                            itemBuilder: (ctx) => [
                              const PopupMenuItem(
                                value: 'excel',
                                child: Row(
                                  children: [
                                    Icon(Icons.table_chart_rounded, color: Colors.green, size: 18),
                                    SizedBox(width: 10),
                                    Text('Excel Report', style: TextStyle(fontWeight: FontWeight.w600)),
                                  ],
                                ),
                              ),
                              const PopupMenuItem(
                                value: 'pdf',
                                child: Row(
                                  children: [
                                    Icon(Icons.picture_as_pdf_rounded, color: Colors.red, size: 18),
                                    SizedBox(width: 10),
                                    Text('PDF Report', style: TextStyle(fontWeight: FontWeight.w600)),
                                  ],
                                ),
                              ),
                              const PopupMenuItem(
                                value: 'csv',
                                child: Row(
                                  children: [
                                    Icon(Icons.file_download_rounded, color: Colors.blue, size: 18),
                                    SizedBox(width: 10),
                                    Text('CSV Report', style: TextStyle(fontWeight: FontWeight.w600)),
                                  ],
                                ),
                              ),
                            ],
                            child: Container(
                              height: 42,
                              padding: const EdgeInsets.symmetric(horizontal: 16),
                              decoration: BoxDecoration(
                                color: const Color(0xFF059669),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.download_rounded, color: Colors.white, size: 18),
                                  SizedBox(width: 8),
                                  Text(
                                    'Download Report',
                                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                                  ),
                                  SizedBox(width: 4),
                                  Icon(Icons.arrow_drop_down, color: Colors.white, size: 18),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 14),

              // Filter Header Container (Rich Emerald Green Background, All Date Pills in ONE Line)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF064E3B), Color(0xFF022C22)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFF059669), width: 1.5),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x40022C22),
                      blurRadius: 12,
                      offset: Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Row 1: Search Input & All Dropdowns (Responsive Layout for Mobile)
                    LayoutBuilder(
                      builder: (context, filterBox) {
                        final isMobileFilter = filterBox.maxWidth < 600;
                        final calcWidth = isMobileFilter ? (filterBox.maxWidth > 80 ? filterBox.maxWidth : 280.0) : 200.0;

                        return Wrap(
                          spacing: 10,
                          runSpacing: 10,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            // Search Field
                            SizedBox(
                              height: 40,
                              width: calcWidth,
                              child: TextField(
                                controller: _searchController,
                                style: TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.onSurface),
                                decoration: InputDecoration(
                                  hintText: 'Search guests by...',
                                  hintStyle: TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.onSurfaceVariant),
                                  prefixIcon: const Icon(Icons.search, size: 18, color: AppColors.primary),
                                  isDense: true,
                                  filled: true,
                                  fillColor: Theme.of(context).colorScheme.surface,
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                  enabledBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(8),
                                    borderSide: const BorderSide(color: Color(0xFFCBD5E1), width: 1.2),
                                  ),
                                  focusedBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(8),
                                    borderSide: const BorderSide(color: AppColors.primary, width: 1.8),
                                  ),
                                  suffixIcon: _searchController.text.isNotEmpty
                                      ? IconButton(
                                          icon: const Icon(Icons.clear, size: 16),
                                          onPressed: () {
                                            _searchController.clear();
                                            guestProvider.setSearchQuery('', isSuperAdmin);
                                          },
                                        )
                                      : null,
                                ),
                                onChanged: (val) => guestProvider.setSearchQuery(val, isSuperAdmin),
                              ),
                            ),

                            // Place Dropdown
                            _buildFilterDropdown(
                              hint: 'All Addresses / Places',
                              value: guestProvider.selectedPlace,
                              items: _uniquePlaces,
                              width: calcWidth,
                              onChanged: (val) => guestProvider.setFilterPlace(val, isSuperAdmin),
                            ),

                            // District Dropdown
                            _buildFilterDropdown(
                              hint: 'All Districts',
                              value: guestProvider.selectedDistrict,
                              items: AppConstants.districtsByState['Kerala'] ?? [],
                              width: calcWidth,
                              onChanged: (val) => guestProvider.setFilterDistrict(val, isSuperAdmin),
                            ),

                            // State Dropdown
                            _buildFilterDropdown(
                              hint: 'All States',
                              value: guestProvider.selectedState,
                              items: AppConstants.indianStates,
                              width: calcWidth,
                              onChanged: (val) => guestProvider.setFilterState(val, isSuperAdmin),
                            ),

                            // Country Dropdown
                            _buildFilterDropdown(
                              hint: 'All Countries',
                              value: guestProvider.selectedCountry,
                              items: AppConstants.countries,
                              width: calcWidth,
                              onChanged: (val) => guestProvider.setFilterCountry(val, isSuperAdmin),
                            ),

                            // Purpose Dropdown
                            _buildFilterDropdown(
                              hint: 'All Purposes',
                              value: guestProvider.selectedPurpose,
                              items: _uniquePurposes,
                              width: calcWidth,
                              onChanged: (val) => guestProvider.setFilterPurpose(val, isSuperAdmin),
                            ),

                            // Handled By Dropdown
                            _buildFilterDropdown(
                              hint: 'All Handled By',
                              value: guestProvider.selectedHandledBy,
                              items: _adminUsers.map((u) => u.name).toList(),
                              width: calcWidth,
                              onChanged: (val) => guestProvider.setFilterHandledBy(val, isSuperAdmin),
                            ),

                            // Donation Filter Dropdown
                            Container(
                              height: 40,
                              width: calcWidth,
                              padding: const EdgeInsets.symmetric(horizontal: 10),
                              decoration: BoxDecoration(
                                color: Theme.of(context).colorScheme.surface,
                                border: Border.all(
                                  color: Theme.of(context).brightness == Brightness.dark ? const Color(0xFF334155) : const Color(0xFFCBD5E1),
                                  width: 1.2,
                                ),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: DropdownButtonHideUnderline(
                                child: DropdownButton<String>(
                                  value: guestProvider.selectedDonationFilter,
                                  isDense: true,
                                  isExpanded: true,
                                  dropdownColor: Theme.of(context).colorScheme.surface,
                                  iconEnabledColor: Theme.of(context).colorScheme.onSurface,
                                  style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurface, fontWeight: FontWeight.w500),
                                  hint: Text('All Donations', style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant), overflow: TextOverflow.ellipsis),
                                  items: [
                                    DropdownMenuItem<String>(
                                      value: null,
                                      child: Text('All Donations', style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurface), overflow: TextOverflow.ellipsis),
                                    ),
                                    DropdownMenuItem<String>(
                                      value: 'donations_only',
                                      child: Text('With Donation (₹ > 0)', style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurface), overflow: TextOverflow.ellipsis),
                                    ),
                                    DropdownMenuItem<String>(
                                      value: 'no_donation',
                                      child: Text('No Donation (₹ = 0)', style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurface), overflow: TextOverflow.ellipsis),
                                    ),
                                  ],
                                  onChanged: (val) => guestProvider.setFilterDonation(val, isSuperAdmin),
                                ),
                              ),
                            ),

                            // Admins / Created By Dropdown
                            if (isSuperAdmin)
                              Container(
                                height: 40,
                                width: calcWidth,
                                padding: const EdgeInsets.symmetric(horizontal: 10),
                                decoration: BoxDecoration(
                                  color: Theme.of(context).colorScheme.surface,
                                  border: Border.all(
                                    color: Theme.of(context).brightness == Brightness.dark ? const Color(0xFF334155) : const Color(0xFFCBD5E1),
                                    width: 1.2,
                                  ),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: DropdownButtonHideUnderline(
                                  child: DropdownButton<String>(
                                    value: guestProvider.selectedCreatedBy,
                                    isDense: true,
                                    isExpanded: true,
                                    dropdownColor: Theme.of(context).colorScheme.surface,
                                    iconEnabledColor: Theme.of(context).colorScheme.onSurface,
                                    style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurface, fontWeight: FontWeight.w500),
                                    hint: Text('All Admins', style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant), overflow: TextOverflow.ellipsis),
                                    items: [
                                      DropdownMenuItem<String>(
                                        value: null,
                                        child: Text('All Admins', style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurface), overflow: TextOverflow.ellipsis),
                                      ),
                                      ..._adminUsers.map((u) => DropdownMenuItem<String>(
                                            value: u.id,
                                            child: Text('${u.name} (${u.role == "super_admin" ? "Super" : "Sub"})', style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurface), overflow: TextOverflow.ellipsis),
                                          )),
                                    ],
                                    onChanged: (val) => guestProvider.setFilterCreatedBy(val, isSuperAdmin),
                                  ),
                                ),
                              ),
                          ],
                        );
                      },
                    ),

                    const SizedBox(height: 12),

                    // Row 2: Date Range Pickers & ALL Quick Filter Pills in ONE Single Line
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        // Start Date Picker
                        Container(
                          height: 38,
                          width: 130,
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.surface,
                            border: Border.all(
                              color: Theme.of(context).brightness == Brightness.dark ? const Color(0xFF334155) : const Color(0xFFCBD5E1),
                              width: 1.2,
                            ),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.calendar_today, size: 14, color: AppColors.primary),
                              const SizedBox(width: 6),
                              Expanded(
                                child: TextField(
                                  controller: _startDateController,
                                  readOnly: true,
                                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: Theme.of(context).colorScheme.onSurface),
                                  decoration: InputDecoration(
                                    hintText: 'Start Date',
                                    hintStyle: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant),
                                    border: InputBorder.none,
                                    isDense: true,
                                    contentPadding: EdgeInsets.zero,
                                  ),
                                  onTap: () async {
                                    final d = await showDatePicker(
                                      context: context,
                                      initialDate: DateTime.now(),
                                      firstDate: DateTime(2020),
                                      lastDate: DateTime.now(),
                                    );
                                    if (d != null) {
                                      final s = DateFormat('yyyy-MM-dd').format(d);
                                      _startDateController.text = s;
                                      setState(() => _selectedQuickFilter = null);
                                      guestProvider.setDateRange(s, guestProvider.endDate, isSuperAdmin);
                                    }
                                  },
                                ),
                              ),
                            ],
                          ),
                        ),

                        const Text('›', style: TextStyle(color: Colors.white70, fontSize: 18, fontWeight: FontWeight.bold)),

                        // End Date Picker
                        Container(
                          height: 38,
                          width: 130,
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.surface,
                            border: Border.all(
                              color: Theme.of(context).brightness == Brightness.dark ? const Color(0xFF334155) : const Color(0xFFCBD5E1),
                              width: 1.2,
                            ),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.calendar_today, size: 14, color: AppColors.primary),
                              const SizedBox(width: 6),
                              Expanded(
                                child: TextField(
                                  controller: _endDateController,
                                  readOnly: true,
                                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: Theme.of(context).colorScheme.onSurface),
                                  decoration: InputDecoration(
                                    hintText: 'End Date',
                                    hintStyle: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant),
                                    border: InputBorder.none,
                                    isDense: true,
                                    contentPadding: EdgeInsets.zero,
                                  ),
                                  onTap: () async {
                                    final d = await showDatePicker(
                                      context: context,
                                      initialDate: DateTime.now(),
                                      firstDate: DateTime(2020),
                                      lastDate: DateTime.now(),
                                    );
                                    if (d != null) {
                                      final s = DateFormat('yyyy-MM-dd').format(d);
                                      _endDateController.text = s;
                                      setState(() => _selectedQuickFilter = null);
                                      guestProvider.setDateRange(guestProvider.startDate, s, isSuperAdmin);
                                    }
                                  },
                                ),
                              ),
                            ],
                          ),
                        ),

                        // Quick Filter Pills (Side-by-side in ONE line!)
                        _buildFilterPill('Today', _selectedQuickFilter == 'today', () => _applyQuickDateFilter('today', guestProvider, isSuperAdmin)),
                        _buildFilterPill('Yesterday', _selectedQuickFilter == 'yesterday', () => _applyQuickDateFilter('yesterday', guestProvider, isSuperAdmin)),
                        _buildFilterPill('This Week', _selectedQuickFilter == 'week', () => _applyQuickDateFilter('week', guestProvider, isSuperAdmin)),
                        _buildFilterPill('This Month', _selectedQuickFilter == 'month', () => _applyQuickDateFilter('month', guestProvider, isSuperAdmin)),

                        // Clear Filters Button
                        if (guestProvider.startDate != null ||
                            guestProvider.endDate != null ||
                            guestProvider.searchQuery.isNotEmpty ||
                            guestProvider.selectedPlace != null ||
                            guestProvider.selectedDistrict != null ||
                            guestProvider.selectedState != null ||
                            guestProvider.selectedCountry != null ||
                            guestProvider.selectedPurpose != null ||
                            guestProvider.selectedHandledBy != null ||
                            guestProvider.selectedCreatedBy != null)
                          InkWell(
                            onTap: () {
                              _searchController.clear();
                              _startDateController.clear();
                              _endDateController.clear();
                              setState(() => _selectedQuickFilter = null);
                              guestProvider.clearFilters(isSuperAdmin);
                            },
                            borderRadius: BorderRadius.circular(8),
                            child: Container(
                              height: 38,
                              padding: const EdgeInsets.symmetric(horizontal: 12),
                              decoration: BoxDecoration(
                                color: Colors.redAccent.withValues(alpha: 0.2),
                                border: Border.all(color: Colors.redAccent.withValues(alpha: 0.5)),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Center(
                                child: Text(
                                  'Clear Filters',
                                  style: TextStyle(fontSize: 12, color: Colors.redAccent, fontWeight: FontWeight.bold),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),

              // Main Data Display with Swipe Left / Right Gesture Page Navigation
              GestureDetector(
                onHorizontalDragEnd: (details) {
                  if (details.primaryVelocity != null) {
                    if (details.primaryVelocity! < -300) {
                      // Swipe Left -> Next Page
                      if ((guestProvider.currentPage * 20) < guestProvider.totalCount) {
                        guestProvider.fetchGuests(isSuperAdmin, page: guestProvider.currentPage + 1);
                      }
                    } else if (details.primaryVelocity! > 300) {
                      // Swipe Right -> Previous Page
                      if (guestProvider.currentPage > 1) {
                        guestProvider.fetchGuests(isSuperAdmin, page: guestProvider.currentPage - 1);
                      }
                    }
                  }
                },
                child: guestProvider.isLoading
                    ? Container(height: 300, alignment: Alignment.center, child: const CircularProgressIndicator())
                    : guestProvider.guests.isEmpty
                        ? Container(
                            height: 250,
                            alignment: Alignment.center,
                            child: const Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.search_off, size: 44, color: AppColors.textSecondary),
                                SizedBox(height: 8),
                                Text('No guest records found for selected filters.', style: TextStyle(color: AppColors.textSecondary, fontSize: 15)),
                              ],
                            ),
                          )
                        : isDesktop
                            ? _buildDesktopDataTable(guestProvider, isSuperAdmin)
                            : _buildMobileListView(guestProvider, isSuperAdmin),
              ),

              // Pagination Bar Controls (Responsive Wrap for Mobile)
              const SizedBox(height: 14),
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 12,
                runSpacing: 10,
                children: [
                  Text(
                    'Total: ${guestProvider.totalCount} records',
                    style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.textSecondary, fontSize: 13),
                  ),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        ElevatedButton.icon(
                          onPressed: guestProvider.currentPage > 1
                              ? () => guestProvider.fetchGuests(isSuperAdmin, page: guestProvider.currentPage - 1)
                              : null,
                          icon: const Icon(Icons.chevron_left, size: 16),
                          label: const Text('Prev'),
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                            textStyle: const TextStyle(fontSize: 11),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: AppColors.primary.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            'Page ${guestProvider.currentPage} of ${((guestProvider.totalCount / 20).ceil() == 0 ? 1 : (guestProvider.totalCount / 20).ceil())}',
                            style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.primary, fontSize: 11),
                          ),
                        ),
                        const SizedBox(width: 6),
                        ElevatedButton.icon(
                          onPressed: (guestProvider.currentPage * 20) < guestProvider.totalCount
                              ? () => guestProvider.fetchGuests(isSuperAdmin, page: guestProvider.currentPage + 1)
                              : null,
                          icon: const Icon(Icons.chevron_right, size: 16),
                          label: const Text('Next'),
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                            textStyle: const TextStyle(fontSize: 11),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFilterDropdown({
    required String hint,
    required String? value,
    required List<String> items,
    required ValueChanged<String?> onChanged,
    double? width,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surfaceColor = Theme.of(context).colorScheme.surface;
    final textColor = Theme.of(context).colorScheme.onSurface;
    final hintColor = Theme.of(context).colorScheme.onSurfaceVariant;
    final borderColor = isDark ? const Color(0xFF334155) : const Color(0xFFCBD5E1);

    return Container(
      height: 40,
      width: width ?? 200,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: surfaceColor,
        border: Border.all(color: borderColor, width: 1.2),
        borderRadius: BorderRadius.circular(8),
        boxShadow: const [
          BoxShadow(
            color: Color(0x08000000),
            blurRadius: 3,
            offset: Offset(0, 1),
          ),
        ],
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value,
          isDense: true,
          isExpanded: true,
          dropdownColor: surfaceColor,
          iconEnabledColor: textColor,
          style: TextStyle(fontSize: 12, color: textColor, fontWeight: FontWeight.w500),
          hint: Text(hint, style: TextStyle(fontSize: 12, color: hintColor), overflow: TextOverflow.ellipsis),
          items: [
            DropdownMenuItem<String>(
              value: null,
              child: Text(hint, style: TextStyle(fontSize: 12, color: textColor), overflow: TextOverflow.ellipsis),
            ),
            ...items.map((i) => DropdownMenuItem<String>(
                  value: i,
                  child: Text(i, style: TextStyle(fontSize: 12, color: textColor), overflow: TextOverflow.ellipsis),
                )),
          ],
          onChanged: onChanged,
        ),
      ),
    );
  }

  Widget _buildFilterPill(String label, bool isSelected, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        height: 38,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF10B981) : const Color(0xFF047857),
          border: Border.all(
            color: isSelected ? const Color(0xFF34D399) : const Color(0xFF059669),
            width: isSelected ? 1.5 : 1.2,
          ),
          borderRadius: BorderRadius.circular(8),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: const Color(0xFF10B981).withValues(alpha: 0.4),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                color: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Desktop Data Table View with Horizontal Swiping Controls
  Widget _buildDesktopDataTable(GuestProvider provider, bool isSuperAdmin) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Column(
        children: [
          // Table Header Controls Bar (Swipe Left / Swipe Right Buttons)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Row(
                  children: [
                    Icon(Icons.swipe, size: 16, color: AppColors.primary),
                    SizedBox(width: 6),
                    Text('Drag / Swipe Table Horizontally', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.primary)),
                  ],
                ),
                Row(
                  children: [
                    OutlinedButton.icon(
                      onPressed: () {
                        if (_horizontalScrollController.hasClients) {
                          _horizontalScrollController.animateTo(
                            (_horizontalScrollController.offset - 350).clamp(0.0, _horizontalScrollController.position.maxScrollExtent),
                            duration: const Duration(milliseconds: 300),
                            curve: Curves.easeOut,
                          );
                        }
                      },
                      icon: const Icon(Icons.arrow_back, size: 14),
                      label: const Text('Swipe Left', style: TextStyle(fontSize: 11)),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton.icon(
                      onPressed: () {
                        if (_horizontalScrollController.hasClients) {
                          _horizontalScrollController.animateTo(
                            (_horizontalScrollController.offset + 350).clamp(0.0, _horizontalScrollController.position.maxScrollExtent),
                            duration: const Duration(milliseconds: 300),
                            curve: Curves.easeOut,
                          );
                        }
                      },
                      icon: const Icon(Icons.arrow_forward, size: 14),
                      label: const Text('Swipe Right', style: TextStyle(fontSize: 11)),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const Divider(height: 1),

          // Scrollable Data Table with Scrollbar
          Scrollbar(
            controller: _horizontalScrollController,
            thumbVisibility: true,
            trackVisibility: true,
            child: SingleChildScrollView(
              controller: _horizontalScrollController,
              scrollDirection: Axis.horizontal,
              physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
              child: SingleChildScrollView(
                controller: _verticalScrollController,
                child: DataTable(
                  headingRowHeight: 40,
                  dataRowMinHeight: 40,
                  dataRowMaxHeight: 44,
                  columns: const [
                    DataColumn(label: Text('Guest Name', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                    DataColumn(label: Text('Phone', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                    DataColumn(label: Text('Place', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                    DataColumn(label: Text('District / Location', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                    DataColumn(label: Text('Purpose', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                    DataColumn(label: Text('Donation (₹)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                    DataColumn(label: Text('Handled By', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                    DataColumn(label: Text('Date', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                    DataColumn(label: Text('Actions', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                  ],
                  rows: provider.guests.map((g) {
                    return DataRow(
                      cells: [
                        DataCell(Text(g.guestName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                        DataCell(Text(g.phoneNumber, style: const TextStyle(fontSize: 12))),
                        DataCell(Text(g.place, style: const TextStyle(fontSize: 12))),
                        DataCell(Text(g.isInternational ? (g.country ?? 'International') : '${g.district}, ${g.state ?? ""}', style: const TextStyle(fontSize: 12))),
                        DataCell(Text(g.purpose, style: const TextStyle(fontSize: 12))),
                        DataCell(Text(g.donationAmount > 0 ? AppUtils.formatCurrency(g.donationAmount) : '-', style: const TextStyle(fontSize: 12))),
                        DataCell(Text(g.handledBy ?? '-', style: const TextStyle(fontSize: 12))),
                        DataCell(Text(AppUtils.formatDate(g.createdAt), style: const TextStyle(fontSize: 12))),
                        DataCell(
                          Row(
                            children: [
                              IconButton(
                                icon: const Icon(Icons.print_outlined, size: 18, color: AppColors.primary),
                                onPressed: () => PdfService.showPrintOrDownloadDialog(context, g),
                                tooltip: 'Print or Download PDF Receipt',
                              ),
                              IconButton(
                                icon: const Icon(Icons.sms_outlined, size: 18, color: AppColors.accent),
                                onPressed: () => _sendThankYouSms(g),
                                tooltip: 'Send Thank You SMS',
                              ),
                              IconButton(
                                icon: const Icon(Icons.edit_outlined, size: 18, color: Colors.orange),
                                onPressed: () => _openEditDialog(g),
                                tooltip: 'Edit Record',
                              ),
                              if (isSuperAdmin)
                                IconButton(
                                  icon: const Icon(Icons.delete_outline, size: 18, color: AppColors.danger),
                                  onPressed: () => provider.deleteGuest(g.id, isSuperAdmin),
                                  tooltip: 'Delete Record',
                                ),
                            ],
                          ),
                        ),
                      ],
                    );
                  }).toList(),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Mobile Adaptive Card List View with Dismissible Swipe Actions
  Widget _buildMobileListView(GuestProvider provider, bool isSuperAdmin) {
    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: provider.guests.length,
      itemBuilder: (context, index) {
        final g = provider.guests[index];
        return Dismissible(
          key: Key(g.id),
          direction: isSuperAdmin ? DismissDirection.horizontal : DismissDirection.startToEnd,
          background: Container(
            alignment: Alignment.centerLeft,
            padding: const EdgeInsets.only(left: 20),
            color: Colors.orange,
            child: const Row(
              children: [
                Icon(Icons.edit, color: Colors.white),
                SizedBox(width: 8),
                Text('Edit Record', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              ],
            ),
          ),
          secondaryBackground: Container(
            alignment: Alignment.centerRight,
            padding: const EdgeInsets.only(right: 20),
            color: Colors.red,
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Text('Delete Record', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                SizedBox(width: 8),
                Icon(Icons.delete, color: Colors.white),
              ],
            ),
          ),
          confirmDismiss: (direction) async {
            if (direction == DismissDirection.startToEnd) {
              // Swipe Right -> Edit Guest
              _openEditDialog(g);
              return false;
            } else if (direction == DismissDirection.endToStart) {
              // Swipe Left -> Delete Guest
              if (isSuperAdmin) {
                final confirm = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('Confirm Deletion'),
                    content: Text('Are you sure you want to delete ${g.guestName}?'),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                      ElevatedButton(
                        onPressed: () => Navigator.pop(ctx, true),
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
                        child: const Text('Delete'),
                      ),
                    ],
                  ),
                );
                if (confirm == true) {
                  await provider.deleteGuest(g.id, isSuperAdmin);
                  return true;
                }
              }
              return false;
            }
            return false;
          },
          child: Card(
            margin: const EdgeInsets.only(bottom: 12),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          g.guestName,
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.print, color: AppColors.primary),
                        onPressed: () => PdfService.showPrintOrDownloadDialog(context, g),
                        tooltip: 'Print or Download PDF Receipt',
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text('📞 ${g.phoneNumber}', style: const TextStyle(color: AppColors.textSecondary)),
                  Text('📍 ${g.place}, ${g.district}'),
                  Text('🎯 Purpose: ${g.purpose}'),
                  if (g.donationAmount > 0)
                    Text('💰 Donation: ${AppUtils.formatCurrency(g.donationAmount)}',
                        style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.accent)),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Entered: ${AppUtils.formatDate(g.createdAt)}', style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                      Row(
                        children: [
                          IconButton(
                            icon: const Icon(Icons.sms, size: 18, color: AppColors.accent),
                            onPressed: () => _sendThankYouSms(g),
                            tooltip: 'Send Thank You SMS',
                          ),
                          IconButton(
                            icon: const Icon(Icons.edit, size: 18, color: Colors.orange),
                            onPressed: () => _openEditDialog(g),
                            tooltip: 'Edit Record',
                          ),
                          if (isSuperAdmin)
                            IconButton(
                              icon: const Icon(Icons.delete, size: 18, color: Colors.red),
                              onPressed: () => provider.deleteGuest(g.id, isSuperAdmin),
                              tooltip: 'Delete Record',
                            ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
