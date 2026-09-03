import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../config/constants.dart';
import '../../core/utils.dart';
import '../../models/guest_visit.dart';
import '../../providers/auth_provider.dart';
import '../../services/excel_service.dart';
import '../../services/guest_service.dart';
import '../../services/pdf_service.dart';

class ReportsView extends StatefulWidget {
  const ReportsView({super.key});

  @override
  State<ReportsView> createState() => _ReportsViewState();
}

class _ReportsViewState extends State<ReportsView> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final ScrollController _hScrollController = ScrollController();
  bool _isLoading = false;
  List<GuestVisit> _reportRows = [];

  // Filter States
  DateTime _dailyDate = DateTime.now();
  DateTime _monthlyDate = DateTime.now();
  DateTimeRange? _customDateRange;
  DateTimeRange? _donationDateRange;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 6, vsync: this);
    _tabController.addListener(_handleTabChange);
    _loadReportData();
  }

  @override
  void dispose() {
    _tabController.removeListener(_handleTabChange);
    _tabController.dispose();
    _hScrollController.dispose();
    super.dispose();
  }

  void _handleTabChange() {
    if (_tabController.indexIsChanging) return;
    _loadReportData();
  }

  Future<void> _loadReportData() async {
    setState(() => _isLoading = true);
    final isSuperAdmin = Provider.of<AuthProvider>(context, listen: false).isSuperAdmin;

    try {
      List<GuestVisit> rows = [];
      final int index = _tabController.index;

      if (index == 0) {
        // Daily
        final dateStr = DateFormat('yyyy-MM-dd').format(_dailyDate);
        rows = await GuestService.getAllGuestsForReports(
          startDate: dateStr,
          endDate: dateStr,
          isSuperAdmin: isSuperAdmin,
        );
      } else if (index == 1) {
        // Monthly
        final startOfMonth = DateTime(_monthlyDate.year, _monthlyDate.month, 1);
        final endOfMonth = DateTime(_monthlyDate.year, _monthlyDate.month + 1, 0);
        rows = await GuestService.getAllGuestsForReports(
          startDate: DateFormat('yyyy-MM-dd').format(startOfMonth),
          endDate: DateFormat('yyyy-MM-dd').format(endOfMonth),
          isSuperAdmin: isSuperAdmin,
        );
      } else if (index == 2) {
        // Custom Range
        final start = _customDateRange?.start != null ? DateFormat('yyyy-MM-dd').format(_customDateRange!.start) : null;
        final end = _customDateRange?.end != null ? DateFormat('yyyy-MM-dd').format(_customDateRange!.end) : null;
        rows = await GuestService.getAllGuestsForReports(
          startDate: start,
          endDate: end,
          isSuperAdmin: isSuperAdmin,
        );
      } else if (index == 3) {
        // Donation
        final start = _donationDateRange?.start != null ? DateFormat('yyyy-MM-dd').format(_donationDateRange!.start) : null;
        final end = _donationDateRange?.end != null ? DateFormat('yyyy-MM-dd').format(_donationDateRange!.end) : null;
        rows = await GuestService.getAllGuestsForReports(
          startDate: start,
          endDate: end,
          onlyDonations: true,
          isSuperAdmin: isSuperAdmin,
        );
        rows.sort((a, b) => b.donationAmount.compareTo(a.donationAmount));
      } else if (index == 4 || index == 5) {
        // Sub Admin / Super Admin (Super Admin view)
        rows = await GuestService.getAllGuestsForReports(isSuperAdmin: true);
      }

      if (mounted) {
        setState(() {
          _reportRows = rows;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // Set Date Range Presets
  void _setPresetDateRange(String preset) {
    final now = DateTime.now();
    DateTimeRange range;

    if (preset == 'Today') {
      range = DateTimeRange(start: now, end: now);
    } else if (preset == 'Yesterday') {
      final yest = now.subtract(const Duration(days: 1));
      range = DateTimeRange(start: yest, end: yest);
    } else if (preset == 'This Week') {
      final startOfWeek = now.subtract(Duration(days: now.weekday - 1));
      range = DateTimeRange(start: startOfWeek, end: now);
    } else if (preset == 'Last Month') {
      final startOfLastMonth = DateTime(now.year, now.month - 1, 1);
      final endOfLastMonth = DateTime(now.year, now.month, 0);
      range = DateTimeRange(start: startOfLastMonth, end: endOfLastMonth);
    } else {
      // This Month
      final startOfMonth = DateTime(now.year, now.month, 1);
      range = DateTimeRange(start: startOfMonth, end: now);
    }

    setState(() {
      if (_tabController.index == 3) {
        _donationDateRange = range;
      } else {
        _customDateRange = range;
      }
    });
    _loadReportData();
  }

  // Calculate Metrics
  double get _totalDonations => _reportRows.fold(0.0, (sum, g) => sum + g.donationAmount);
  double get _highestDonation => _reportRows.isEmpty
      ? 0.0
      : _reportRows.map((g) => g.donationAmount).reduce((a, b) => a > b ? a : b);

  Widget _buildPresetButton(String label) {
    return SizedBox(
      height: 34,
      child: OutlinedButton(
        onPressed: () => _setPresetDateRange(label),
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          minimumSize: Size.zero,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
        ),
        child: Text(label),
      ),
    );
  }

  Widget _buildDatePicker(String label, DateTime? value, Function(DateTime) onSelect) {
    return InkWell(
      onTap: () async {
        final d = await showDatePicker(
          context: context,
          initialDate: value ?? DateTime.now(),
          firstDate: DateTime(2020),
          lastDate: DateTime.now(),
        );
        if (d != null) onSelect(d);
      },
      borderRadius: BorderRadius.circular(8),
      child: Container(
        height: 34,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          border: Border.all(color: AppColors.primary, width: 1.2),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              value != null ? DateFormat('dd MMM yyyy').format(value) : label,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.primary),
            ),
            const SizedBox(width: 4),
            const Icon(Icons.arrow_drop_down, size: 16, color: AppColors.primary),
          ],
        ),
      ),
    );
  }

  Widget _buildExportButton({
    required String label,
    required IconData icon,
    required Color color,
    required VoidCallback onPressed,
  }) {
    return SizedBox(
      height: 34,
      child: ElevatedButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, size: 16),
        label: Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          minimumSize: Size.zero,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isSuperAdmin = Provider.of<AuthProvider>(context).isSuperAdmin;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Reports Center'),
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          labelPadding: const EdgeInsets.symmetric(horizontal: 10),
          indicatorColor: AppColors.primary,
          labelColor: AppColors.primary,
          unselectedLabelColor: AppColors.textSecondary,
          labelStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
          unselectedLabelStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
          tabs: [
            const Tab(height: 36, text: 'Daily'),
            const Tab(height: 36, text: 'Monthly'),
            const Tab(height: 36, text: 'Custom Range'),
            const Tab(height: 36, text: 'Donations'),
            if (isSuperAdmin) const Tab(height: 36, text: 'Sub Admin'),
            if (isSuperAdmin) const Tab(height: 36, text: 'Super Admin'),
          ],
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 100),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Controls Bar: Compact Date Presets & Export Action Buttons
            Card(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    // Quick Date Presets based on selected Tab
                    if (_tabController.index == 0) ...[
                      _buildPresetButton('Today'),
                      _buildPresetButton('Yesterday'),
                    ] else if (_tabController.index == 1) ...[
                      _buildPresetButton('This Month'),
                      _buildPresetButton('Last Month'),
                    ] else if (_tabController.index == 2) ...[
                      _buildDatePicker('Start Date', _customDateRange?.start, (date) {
                        setState(() {
                          _customDateRange = DateTimeRange(start: date, end: _customDateRange?.end ?? date);
                        });
                        _loadReportData();
                      }),
                      const Text('›', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                      _buildDatePicker('End Date', _customDateRange?.end, (date) {
                        setState(() {
                          _customDateRange = DateTimeRange(start: _customDateRange?.start ?? date, end: date);
                        });
                        _loadReportData();
                      }),
                    ] else ...[
                      _buildPresetButton('Today'),
                      _buildPresetButton('Yesterday'),
                      _buildPresetButton('This Week'),
                      _buildPresetButton('This Month'),
                    ],

                    // Export Action Buttons (Compact Sizing)
                    _buildExportButton(
                      label: 'Excel',
                      icon: Icons.table_view_outlined,
                      color: AppColors.accent,
                      onPressed: () async {
                        final path = await ExcelService.exportGuestsToExcel(_reportRows);
                        if (path != null && mounted) AppUtils.showSnackBar(context, 'Exported Excel: $path');
                      },
                    ),
                    _buildExportButton(
                      label: 'PDF',
                      icon: Icons.picture_as_pdf_outlined,
                      color: AppColors.primary,
                      onPressed: () {
                        if (_reportRows.isNotEmpty) PdfService.printReceipt(_reportRows.first);
                      },
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),

            // Summary Metric Cards
            Row(
              children: [
                Expanded(
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Total Donations', style: TextStyle(color: AppColors.textSecondary, fontSize: 14)),
                          const SizedBox(height: 6),
                          Text(
                            AppUtils.formatCurrency(_totalDonations),
                            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: AppColors.primary),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _tabController.index == 3 ? 'Highest Donation' : 'Total Guests',
                            style: const TextStyle(color: AppColors.textSecondary, fontSize: 14),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            _tabController.index == 3
                                ? AppUtils.formatCurrency(_highestDonation)
                                : _reportRows.length.toString(),
                            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: AppColors.accent),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // Report Detailed Table
            _isLoading
                ? const Center(child: Padding(padding: EdgeInsets.all(40), child: CircularProgressIndicator()))
                : _reportRows.isEmpty
                    ? const Center(child: Padding(padding: EdgeInsets.all(40), child: Text('No records found for selected period.')))
                    : Card(
                        child: Scrollbar(
                          controller: _hScrollController,
                          thumbVisibility: true,
                          trackVisibility: true,
                          thickness: 8.0,
                          radius: const Radius.circular(4),
                          child: SingleChildScrollView(
                            controller: _hScrollController,
                            scrollDirection: Axis.horizontal,
                            child: DataTable(
                              columns: const [
                                DataColumn(label: Text('Guest Name', style: TextStyle(fontWeight: FontWeight.bold))),
                                DataColumn(label: Text('Phone', style: TextStyle(fontWeight: FontWeight.bold))),
                                DataColumn(label: Text('Address', style: TextStyle(fontWeight: FontWeight.bold))),
                                DataColumn(label: Text('Location', style: TextStyle(fontWeight: FontWeight.bold))),
                                DataColumn(label: Text('Purpose', style: TextStyle(fontWeight: FontWeight.bold))),
                                DataColumn(label: Text('Donation (₹)', style: TextStyle(fontWeight: FontWeight.bold))),
                                DataColumn(label: Text('Receipt No', style: TextStyle(fontWeight: FontWeight.bold))),
                                DataColumn(label: Text('Handled By', style: TextStyle(fontWeight: FontWeight.bold))),
                                DataColumn(label: Text('Date', style: TextStyle(fontWeight: FontWeight.bold))),
                              ],
                              rows: _reportRows.map((g) {
                                return DataRow(
                                  cells: [
                                    DataCell(Text(g.guestName, style: const TextStyle(fontWeight: FontWeight.bold))),
                                    DataCell(Text(g.phoneNumber)),
                                    DataCell(Text(g.place)),
                                    DataCell(Text(g.isInternational ? (g.country ?? 'Intl') : (g.state ?? g.district))),
                                    DataCell(Text(g.purpose)),
                                    DataCell(Text(g.donationAmount > 0 ? AppUtils.formatCurrency(g.donationAmount) : '-')),
                                    DataCell(Text(g.receiptNo ?? '-')),
                                    DataCell(Text(g.handledBy ?? '-')),
                                    DataCell(Text(AppUtils.formatDate(g.createdAt))),
                                  ],
                                );
                              }).toList(),
                            ),
                          ),
                        ),
                      ),
          ],
        ),
      ),
    );
  }
}
