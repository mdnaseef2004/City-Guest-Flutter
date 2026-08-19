import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../config/constants.dart';
import '../../core/utils.dart';
import '../../models/event_model.dart';
import '../../providers/auth_provider.dart';
import '../../services/event_service.dart';
import '../../services/export_service.dart';
import 'add_event_view.dart';

class EventsView extends StatefulWidget {
  const EventsView({super.key});

  @override
  State<EventsView> createState() => _EventsViewState();
}

class _EventsViewState extends State<EventsView> {
  bool _isLoading = true;
  List<EventModel> _allEvents = [];
  List<EventModel> _filteredEvents = [];

  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _startDateController = TextEditingController();
  final TextEditingController _endDateController = TextEditingController();
  String? _selectedQuickFilter;

  // Available Export Columns
  final List<Map<String, String>> _availableColumns = [
    {'key': 'eventName', 'label': 'Event Name'},
    {'key': 'eventDate', 'label': 'Event Date'},
    {'key': 'eventPlace', 'label': 'Location / Place'},
    {'key': 'membersCount', 'label': 'Attendees / Members'},
    {'key': 'organizedBy', 'label': 'Organized By'},
    {'key': 'handledBy', 'label': 'Handled By'},
    {'key': 'remarks', 'label': 'Remarks'},
  ];

  late Map<String, bool> _selectedExportColumns;

  @override
  void initState() {
    super.initState();
    _selectedExportColumns = {for (var col in _availableColumns) col['key']!: true};
    _loadEvents();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _startDateController.dispose();
    _endDateController.dispose();
    super.dispose();
  }

  Future<void> _loadEvents() async {
    final isSuperAdmin = Provider.of<AuthProvider>(context, listen: false).isSuperAdmin;
    setState(() => _isLoading = true);
    try {
      final list = await EventService.getEvents(isSuperAdmin);
      if (mounted) {
        setState(() {
          _allEvents = list;
          _applyFilters();
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _applyFilters() {
    final query = _searchController.text.trim().toLowerCase();
    final startDateStr = _startDateController.text.trim();
    final endDateStr = _endDateController.text.trim();

    DateTime? startDate;
    DateTime? endDate;

    if (startDateStr.isNotEmpty) {
      try {
        startDate = DateTime.parse(startDateStr);
      } catch (_) {}
    }
    if (endDateStr.isNotEmpty) {
      try {
        endDate = DateTime.parse(endDateStr).add(const Duration(days: 1)).subtract(const Duration(milliseconds: 1));
      } catch (_) {}
    }

    setState(() {
      _filteredEvents = _allEvents.where((e) {
        // Search Filter
        if (query.isNotEmpty) {
          final nameMatch = e.eventName.toLowerCase().contains(query);
          final placeMatch = e.eventPlace.toLowerCase().contains(query);
          final orgMatch = e.organizedBy.toLowerCase().contains(query);
          final handledMatch = e.handledBy.toLowerCase().contains(query);
          if (!nameMatch && !placeMatch && !orgMatch && !handledMatch) return false;
        }

        // Date Range Filter
        if (startDate != null && e.eventDate.isBefore(startDate)) return false;
        if (endDate != null && e.eventDate.isAfter(endDate)) return false;

        return true;
      }).toList();
    });
  }

  void _applyQuickDateFilter(String type) {
    final now = DateTime.now();
    setState(() {
      _selectedQuickFilter = type;
      if (type == 'today') {
        final dateStr = DateFormat('yyyy-MM-dd').format(now);
        _startDateController.text = dateStr;
        _endDateController.text = dateStr;
      } else if (type == 'yesterday') {
        final yest = now.subtract(const Duration(days: 1));
        final dateStr = DateFormat('yyyy-MM-dd').format(yest);
        _startDateController.text = dateStr;
        _endDateController.text = dateStr;
      } else if (type == 'month') {
        final startOfMonth = DateTime(now.year, now.month, 1);
        final endOfMonth = DateTime(now.year, now.month + 1, 0);
        _startDateController.text = DateFormat('yyyy-MM-dd').format(startOfMonth);
        _endDateController.text = DateFormat('yyyy-MM-dd').format(endOfMonth);
      }
      _applyFilters();
    });
  }

  void _clearFilters() {
    setState(() {
      _searchController.clear();
      _startDateController.clear();
      _endDateController.clear();
      _selectedQuickFilter = null;
      _applyFilters();
    });
  }

  // Interactive Checkbox Modal for Column Selection
  Future<void> _showEventColumnSelectionDialog(String format) async {
    final tempSelected = Map<String, bool>.from(_selectedExportColumns);

    await showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final activeCount = tempSelected.values.where((v) => v).length;

            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: Row(
                children: [
                  Icon(
                    format == 'pdf'
                        ? Icons.picture_as_pdf_rounded
                        : format == 'excel'
                            ? Icons.table_chart_rounded
                            : Icons.file_download_rounded,
                    color: format == 'pdf'
                        ? Colors.red
                        : format == 'excel'
                            ? Colors.green
                            : Colors.blue,
                  ),
                  const SizedBox(width: 10),
                  Text(
                    'Select Columns for ${format.toUpperCase()}',
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              content: SizedBox(
                width: 400,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        TextButton.icon(
                          onPressed: () {
                            setDialogState(() {
                              for (var key in tempSelected.keys) {
                                tempSelected[key] = true;
                              }
                            });
                          },
                          icon: const Icon(Icons.select_all, size: 16),
                          label: const Text('Select All', style: TextStyle(fontSize: 12)),
                        ),
                        TextButton.icon(
                          onPressed: () {
                            setDialogState(() {
                              for (var key in tempSelected.keys) {
                                tempSelected[key] = false;
                              }
                            });
                          },
                          icon: const Icon(Icons.deselect, size: 16),
                          label: const Text('Deselect All', style: TextStyle(fontSize: 12)),
                        ),
                      ],
                    ),
                    const Divider(),
                    Flexible(
                      child: SingleChildScrollView(
                        child: Column(
                          children: _availableColumns.map((col) {
                            final key = col['key']!;
                            final label = col['label']!;
                            return CheckboxListTile(
                              dense: true,
                              title: Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
                              value: tempSelected[key] ?? false,
                              activeColor: AppColors.primary,
                              onChanged: (val) {
                                setDialogState(() {
                                  tempSelected[key] = val ?? false;
                                });
                              },
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
                ElevatedButton(
                  onPressed: activeCount == 0
                      ? null
                      : () {
                          setState(() {
                            _selectedExportColumns = tempSelected;
                          });
                          Navigator.pop(ctx);
                          if (format == 'pdf') _exportPdf();
                          if (format == 'excel') _exportExcel();
                          if (format == 'csv') _exportCsv();
                        },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                  ),
                  child: Text('Download ${format.toUpperCase()} ($activeCount Columns)'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // Export Handlers
  Future<void> _exportPdf() async {
    final activeKeys = _selectedExportColumns.entries.where((e) => e.value).map((e) => e.key).toList();
    final eventMaps = _filteredEvents.map((e) {
      final map = <String, dynamic>{};
      if (activeKeys.contains('eventName')) map['event_name'] = e.eventName;
      if (activeKeys.contains('eventPlace')) map['event_place'] = e.eventPlace;
      if (activeKeys.contains('membersCount')) map['members_count'] = e.membersCount;
      if (activeKeys.contains('eventDate')) map['event_date'] = DateFormat('yyyy-MM-dd').format(e.eventDate);
      if (activeKeys.contains('handledBy')) map['handled_by'] = e.handledBy;
      return map;
    }).toList();

    await ExportService.exportEventReportPdf(
      reportTitle: 'Event Attendance Analytics Report',
      events: eventMaps,
    );
  }

  Future<void> _exportExcel() async {
    final activeCols = _availableColumns.where((c) => _selectedExportColumns[c['key']] == true).toList();
    final headers = ['#', ...activeCols.map((c) => c['label']!)];

    final rows = _filteredEvents.asMap().entries.map((entry) {
      final idx = entry.key + 1;
      final e = entry.value;
      final row = <dynamic>[idx];
      for (var col in activeCols) {
        final key = col['key']!;
        if (key == 'eventName') row.add(e.eventName);
        if (key == 'eventDate') row.add(DateFormat('yyyy-MM-dd').format(e.eventDate));
        if (key == 'eventPlace') row.add(e.eventPlace);
        if (key == 'membersCount') row.add(e.membersCount);
        if (key == 'organizedBy') row.add(e.organizedBy);
        if (key == 'handledBy') row.add(e.handledBy);
        if (key == 'remarks') row.add(e.remarks ?? '');
      }
      return row;
    }).toList();

    await ExportService.exportToExcel(
      filename: 'Event_Records.xlsx',
      headers: headers,
      rows: rows,
    );
  }

  Future<void> _exportCsv() async {
    final activeCols = _availableColumns.where((c) => _selectedExportColumns[c['key']] == true).toList();
    final headers = ['#', ...activeCols.map((c) => c['label']!)];

    final rows = _filteredEvents.asMap().entries.map((entry) {
      final idx = entry.key + 1;
      final e = entry.value;
      final row = <dynamic>[idx];
      for (var col in activeCols) {
        final key = col['key']!;
        if (key == 'eventName') row.add(e.eventName);
        if (key == 'eventDate') row.add(DateFormat('yyyy-MM-dd').format(e.eventDate));
        if (key == 'eventPlace') row.add(e.eventPlace);
        if (key == 'membersCount') row.add(e.membersCount);
        if (key == 'organizedBy') row.add(e.organizedBy);
        if (key == 'handledBy') row.add(e.handledBy);
        if (key == 'remarks') row.add(e.remarks ?? '');
      }
      return row;
    }).toList();

    await ExportService.exportToCSV(
      filename: 'Event_Records.csv',
      headers: headers,
      rows: rows,
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

  @override
  Widget build(BuildContext context) {
    final totalEvents = _filteredEvents.length;
    final totalAttendees = _filteredEvents.fold<int>(0, (sum, e) => sum + e.membersCount);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Event Records'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _loadEvents),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          await Navigator.push(context, MaterialPageRoute(builder: (_) => const AddEventView()));
          _loadEvents();
        },
        icon: const Icon(Icons.add),
        label: const Text('Add Event'),
        backgroundColor: AppColors.primary,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadEvents,
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Filter Header Container (Rich Emerald Green Background, Full Width to Right Edge)
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
                          const Text(
                            'Event Attendance Analytics Graph',
                            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Total Events: $totalEvents  •  Total Event Attendees: $totalAttendees',
                            style: const TextStyle(fontSize: 13, color: Color(0xFFA7F3D0), fontWeight: FontWeight.w500),
                          ),
                          const SizedBox(height: 14),

                          // Row 1: Search Field (Full width on mobile, side-by-side with Download button on desktop)
                          LayoutBuilder(
                            builder: (context, constraints) {
                              final isNarrow = constraints.maxWidth < 600;
                              if (isNarrow) {
                                return _buildBiggerSearchBar();
                              }
                              return Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Expanded(
                                    child: Container(
                                      constraints: const BoxConstraints(maxWidth: 420),
                                      child: _buildBiggerSearchBar(),
                                    ),
                                  ),
                                  const SizedBox(width: 16),
                                  _buildDownloadReportButton(),
                                ],
                              );
                            },
                          ),

                          const SizedBox(height: 12),

                          // Row 2: Date Range Pickers, Quick Filter Pills & Download Button on Mobile
                          LayoutBuilder(
                            builder: (context, constraints) {
                              final isNarrow = constraints.maxWidth < 600;

                              return Wrap(
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
                                      color: Colors.white,
                                      border: Border.all(color: const Color(0xFFCBD5E1), width: 1.2),
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
                                            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
                                            decoration: const InputDecoration(
                                              hintText: 'Start Date',
                                              hintStyle: TextStyle(fontSize: 11, color: AppColors.textSecondary),
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
                                                _startDateController.text = DateFormat('yyyy-MM-dd').format(d);
                                                setState(() => _selectedQuickFilter = null);
                                                _applyFilters();
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
                                      color: Colors.white,
                                      border: Border.all(color: const Color(0xFFCBD5E1), width: 1.2),
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
                                            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
                                            decoration: const InputDecoration(
                                              hintText: 'End Date',
                                              hintStyle: TextStyle(fontSize: 11, color: AppColors.textSecondary),
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
                                                _endDateController.text = DateFormat('yyyy-MM-dd').format(d);
                                                setState(() => _selectedQuickFilter = null);
                                                _applyFilters();
                                              }
                                            },
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),

                                  // Quick Filter Pills (Side-by-side)
                                  _buildFilterPill('Today', _selectedQuickFilter == 'today', () => _applyQuickDateFilter('today')),
                                  _buildFilterPill('Yesterday', _selectedQuickFilter == 'yesterday', () => _applyQuickDateFilter('yesterday')),
                                  _buildFilterPill('This Month', _selectedQuickFilter == 'month', () => _applyQuickDateFilter('month')),

                                  // Download Report Button (Moved next to Today button on mobile view!)
                                  if (isNarrow) _buildDownloadReportButton(),

                                  // Clear Filters Button
                                  if (_searchController.text.isNotEmpty ||
                                      _startDateController.text.isNotEmpty ||
                                      _endDateController.text.isNotEmpty ||
                                      _selectedQuickFilter != null)
                                    InkWell(
                                      onTap: _clearFilters,
                                      borderRadius: BorderRadius.circular(8),
                                      child: Container(
                                        height: 38,
                                        padding: const EdgeInsets.symmetric(horizontal: 12),
                                        decoration: BoxDecoration(
                                          color: Colors.redAccent.withValues(alpha: 0.2),
                                          border: Border.all(color: Colors.redAccent.withValues(alpha: 0.5)),
                                          borderRadius: BorderRadius.circular(8),
                                        ),
                                        child: const Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(Icons.clear_all, color: Colors.white, size: 16),
                                            SizedBox(width: 4),
                                            Text('Clear', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                                          ],
                                        ),
                                      ),
                                    ),
                                ],
                              );
                            },
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 16),
                    const Text('Event Records', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
                    const SizedBox(height: 10),

                    // Event List Records
                    _filteredEvents.isEmpty
                        ? Container(
                            height: 180,
                            alignment: Alignment.center,
                            child: const Text('No events found for selected period or search.', style: TextStyle(color: AppColors.textSecondary)),
                          )
                        : ListView.builder(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            itemCount: _filteredEvents.length,
                            itemBuilder: (context, index) {
                              final item = _filteredEvents[index];
                              return Card(
                                margin: const EdgeInsets.only(bottom: 10),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                child: ListTile(
                                  leading: const CircleAvatar(
                                    backgroundColor: Color(0xFF10B981),
                                    child: Icon(Icons.event_available_rounded, color: Colors.white, size: 20),
                                  ),
                                  title: Text(item.eventName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                                  subtitle: Text(
                                    'Place: ${item.eventPlace} | Members: ${item.membersCount}\nOrganized by: ${item.organizedBy} | Handled by: ${item.handledBy}',
                                    style: const TextStyle(fontSize: 12),
                                  ),
                                  trailing: Text(
                                    AppUtils.formatDate(item.eventDate),
                                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.textSecondary),
                                  ),
                                ),
                              );
                            },
                          ),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildBiggerSearchBar() {
    return SizedBox(
      height: 42,
      child: TextField(
        controller: _searchController,
        style: const TextStyle(fontSize: 13, color: AppColors.textPrimary),
        decoration: InputDecoration(
          hintText: 'Search events by name, place, handled by...',
          hintStyle: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
          prefixIcon: const Icon(Icons.search, size: 20, color: AppColors.primary),
          isDense: true,
          filled: true,
          fillColor: Colors.white,
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
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
                    _applyFilters();
                  },
                )
              : null,
        ),
        onChanged: (_) => _applyFilters(),
      ),
    );
  }

  Widget _buildDownloadReportButton() {
    return PopupMenuButton<String>(
      onSelected: (format) => _showEventColumnSelectionDialog(format),
      tooltip: 'Download Options',
      offset: const Offset(0, 45),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      itemBuilder: (context) => [
        const PopupMenuItem<String>(
          value: 'excel',
          child: Row(
            children: [
              Icon(Icons.table_chart_rounded, color: Colors.green, size: 18),
              SizedBox(width: 10),
              Text('Excel Spreadsheet (.xlsx)', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
            ],
          ),
        ),
        const PopupMenuDivider(),
        const PopupMenuItem<String>(
          value: 'pdf',
          child: Row(
            children: [
              Icon(Icons.picture_as_pdf_rounded, color: Colors.red, size: 18),
              SizedBox(width: 10),
              Text('PDF Report (.pdf)', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
            ],
          ),
        ),
        const PopupMenuDivider(),
        const PopupMenuItem<String>(
          value: 'csv',
          child: Row(
            children: [
              Icon(Icons.file_download_rounded, color: Colors.blue, size: 18),
              SizedBox(width: 10),
              Text('CSV Data File (.csv)', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      ],
      child: Container(
        height: 42,
        padding: const EdgeInsets.symmetric(horizontal: 18),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF6366F1), Color(0xFF4F46E5)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(8),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF6366F1).withValues(alpha: 0.35),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.download_rounded, color: Colors.white, size: 18),
            SizedBox(width: 8),
            Text('Download Report', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.white)),
            SizedBox(width: 6),
            Icon(Icons.keyboard_arrow_down_rounded, color: Colors.white, size: 18),
          ],
        ),
      ),
    );
  }
}
