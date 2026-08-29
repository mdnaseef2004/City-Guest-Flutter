import 'dart:async';
import 'dart:math' as math;
import 'package:file_picker/file_picker.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../config/constants.dart';
import '../../core/responsive_layout.dart';
import '../../core/utils.dart';
import '../../models/guest_visit.dart';
import '../../models/profile.dart';
import '../../providers/auth_provider.dart';
import '../../services/export_service.dart';
import '../../services/guest_service.dart';
import '../../services/supabase_service.dart';
import '../../services/thank_you_message_service.dart';

class DashboardView extends StatefulWidget {
  const DashboardView({super.key});

  @override
  State<DashboardView> createState() => _DashboardViewState();
}

class _DashboardViewState extends State<DashboardView> {
  bool _isLoading = true;
  Map<String, dynamic> _stats = {};
  List<GuestVisit> _todayGuestsList = [];
  RealtimeChannel? _subscription;
  Timer? _autoRefreshTimer;

  // Performance Section State (0: Sub Admin, 1: Super Admin, 2: All Admins)
  int _selectedPerfTab = 0; 
  String _dateFilter = 'all'; // all, week, month, custom
  DateTime? _customStartDate;
  DateTime? _customEndDate;

  // Event Graph State (all, today, yesterday, month, custom)
  String _eventDateFilter = 'all';
  DateTime? _eventCustomStartDate;
  DateTime? _eventCustomEndDate;

  final List<Color> _pieColors = const [
    Color(0xFF059669),
    Color(0xFF10B981),
    Color(0xFF34D399),
    Color(0xFF0D9488),
    Color(0xFF6EE7B7),
    Color(0xFF047857),
    Color(0xFF6366F1),
    Color(0xFF8B5CF6),
  ];

  List<Map<String, dynamic>> _cachedFilteredGuests = [];
  List<Map<String, dynamic>> _cachedFilteredEvents = [];
  List<Map<String, dynamic>> _cachedAdminPerformance = [];

  @override
  void initState() {
    super.initState();
    _loadStats();
    _subscribeRealtime();
    _autoRefreshTimer = Timer.periodic(const Duration(seconds: 15), (_) => _loadStatsSilent());
  }

  @override
  void dispose() {
    _autoRefreshTimer?.cancel();
    if (_subscription != null) {
      SupabaseService.client.removeChannel(_subscription!);
    }
    super.dispose();
  }

  void _subscribeRealtime() {
    final channelName = 'public:guest_visits_${DateTime.now().millisecondsSinceEpoch}';
    _subscription = SupabaseService.client
        .channel(channelName)
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'guest_visits',
          callback: (payload) => _loadStatsSilent(),
        )
        .subscribe();
  }

  Future<void> _loadStats() async {
    final isSuperAdmin = Provider.of<AuthProvider>(context, listen: false).isSuperAdmin;
    final results = await Future.wait<dynamic>(<Future<dynamic>>[
      GuestService.getDashboardStats(isSuperAdmin),
      GuestService.getTodayGuests(isSuperAdmin),
    ]);
    
    if (mounted) {
      setState(() {
        _stats = results[0] as Map<String, dynamic>;
        _todayGuestsList = results[1] as List<GuestVisit>;
        _isLoading = false;
        _updateCachedCalculations();
      });
    }
  }

  Future<void> _loadStatsSilent() async {
    if (!mounted) return;
    final isSuperAdmin = Provider.of<AuthProvider>(context, listen: false).isSuperAdmin;
    final results = await Future.wait<dynamic>(<Future<dynamic>>[
      GuestService.getDashboardStats(isSuperAdmin),
      GuestService.getTodayGuests(isSuperAdmin),
    ]);
    
    if (mounted) {
      final stats = results[0] as Map<String, dynamic>;
      final todayList = results[1] as List<GuestVisit>;
      if (stats.toString() != _stats.toString() || todayList.length != _todayGuestsList.length) {
        setState(() {
          _stats = stats;
          _todayGuestsList = todayList;
          _updateCachedCalculations();
        });
      }
    }
  }

  void _updateCachedCalculations() {
    _cachedFilteredGuests = _calculateFilteredGuests();
    _cachedFilteredEvents = _calculateFilteredEvents();
    _cachedAdminPerformance = _calculateAdminPerformanceList();
  }

  List<Map<String, dynamic>> _getFilteredGuests() => _cachedFilteredGuests;
  List<Map<String, dynamic>> _getFilteredEvents() => _cachedFilteredEvents;
  List<Map<String, dynamic>> _calculateAdminPerformance() => _cachedAdminPerformance;

  // Filter raw guests based on selected time period dropdown
  List<Map<String, dynamic>> _calculateFilteredGuests() {
    final List<Map<String, dynamic>> raw = List<Map<String, dynamic>>.from(_stats['rawGuests'] ?? []);
    if (_dateFilter == 'all') return raw;

    final now = DateTime.now();
    if (_dateFilter == 'week') {
      final startOfWeek = now.subtract(Duration(days: now.weekday - 1));
      final weekStart = DateTime(startOfWeek.year, startOfWeek.month, startOfWeek.day);
      return raw.where((x) {
        final dt = DateTime.tryParse(x['created_at']?.toString() ?? '')?.toLocal();
        return dt != null && dt.isAfter(weekStart.subtract(const Duration(seconds: 1)));
      }).toList();
    }

    if (_dateFilter == 'month') {
      final monthStart = DateTime(now.year, now.month, 1);
      return raw.where((x) {
        final dt = DateTime.tryParse(x['created_at']?.toString() ?? '')?.toLocal();
        return dt != null && dt.isAfter(monthStart.subtract(const Duration(seconds: 1)));
      }).toList();
    }

    if (_dateFilter == 'custom') {
      if (_customStartDate == null || _customEndDate == null) return raw;
      final start = DateTime(_customStartDate!.year, _customStartDate!.month, _customStartDate!.day);
      final end = DateTime(_customEndDate!.year, _customEndDate!.month, _customEndDate!.day, 23, 59, 59);
      return raw.where((x) {
        final dt = DateTime.tryParse(x['created_at']?.toString() ?? '')?.toLocal();
        return dt != null && dt.isAfter(start.subtract(const Duration(seconds: 1))) && dt.isBefore(end.add(const Duration(seconds: 1)));
      }).toList();
    }

    return raw;
  }

  // Filter raw events based on selected event date filter
  List<Map<String, dynamic>> _calculateFilteredEvents() {
    final List<Map<String, dynamic>> raw = List<Map<String, dynamic>>.from(_stats['rawEvents'] ?? []);
    if (_eventDateFilter == 'all') return raw;

    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    final yesterdayStart = todayStart.subtract(const Duration(days: 1));
    final yesterdayEnd = DateTime(yesterdayStart.year, yesterdayStart.month, yesterdayStart.day, 23, 59, 59);

    if (_eventDateFilter == 'today') {
      return raw.where((x) {
        final dt = DateTime.tryParse(x['event_date']?.toString() ?? x['created_at']?.toString() ?? '')?.toLocal();
        return dt != null && dt.year == now.year && dt.month == now.month && dt.day == now.day;
      }).toList();
    }

    if (_eventDateFilter == 'yesterday') {
      return raw.where((x) {
        final dt = DateTime.tryParse(x['event_date']?.toString() ?? x['created_at']?.toString() ?? '')?.toLocal();
        return dt != null && dt.isAfter(yesterdayStart.subtract(const Duration(seconds: 1))) && dt.isBefore(yesterdayEnd.add(const Duration(seconds: 1)));
      }).toList();
    }

    if (_eventDateFilter == 'month') {
      final monthStart = DateTime(now.year, now.month, 1);
      return raw.where((x) {
        final dt = DateTime.tryParse(x['event_date']?.toString() ?? x['created_at']?.toString() ?? '')?.toLocal();
        return dt != null && dt.isAfter(monthStart.subtract(const Duration(seconds: 1)));
      }).toList();
    }

    if (_eventDateFilter == 'custom') {
      if (_eventCustomStartDate == null || _eventCustomEndDate == null) return raw;
      final start = DateTime(_eventCustomStartDate!.year, _eventCustomStartDate!.month, _eventCustomStartDate!.day);
      final end = DateTime(_eventCustomEndDate!.year, _eventCustomEndDate!.month, _eventCustomEndDate!.day, 23, 59, 59);
      return raw.where((x) {
        final dt = DateTime.tryParse(x['event_date']?.toString() ?? x['created_at']?.toString() ?? '')?.toLocal();
        return dt != null && dt.isAfter(start.subtract(const Duration(seconds: 1))) && dt.isBefore(end.add(const Duration(seconds: 1)));
      }).toList();
    }

    return raw;
  }

  // Calculate local admin performance for Sub Admin (0), Super Admin (1), or All Admins (2)
  List<Map<String, dynamic>> _calculateAdminPerformanceList() {
    final List<Map<String, dynamic>> filteredGuests = _cachedFilteredGuests;
    final List<Map<String, dynamic>> allUsers = List<Map<String, dynamic>>.from(_stats['allUsers'] ?? []);

    List<Map<String, dynamic>> roleUsers = [];
    if (_selectedPerfTab == 0) {
      roleUsers = allUsers.where((u) => u['role'] == 'sub_admin').toList();
    } else if (_selectedPerfTab == 1) {
      roleUsers = allUsers.where((u) => u['role'] == 'super_admin').toList();
    } else {
      roleUsers = allUsers; // All Admins
    }

    List<Map<String, dynamic>> perfList = [];

    for (final u in roleUsers) {
      final String uid = u['id'].toString();
      final String name = u['name'] ?? 'User';
      final String role = u['role'] ?? 'sub_admin';
      final String? profilePic = u['profile_picture']?.toString();

      final userVisits = filteredGuests.where((r) => r['created_by'] == uid).toList();
      userVisits.sort((a, b) => (b['created_at'] ?? '').compareTo(a['created_at'] ?? ''));

      final double userDonations = userVisits.fold(0.0, (s, r) => s + ((r['donation_amount'] ?? 0) as num).toDouble());
      final String? lastEntry = userVisits.isNotEmpty ? userVisits.first['created_at']?.toString() : null;

      perfList.add({
        'name': name,
        'role': role == 'super_admin' ? 'Super Admin' : 'Sub Admin',
        'profile_picture': profilePic,
        'totalEntries': userVisits.length,
        'totalDonations': userDonations,
        'lastEntry': lastEntry,
      });
    }

    perfList.sort((a, b) => (b['totalEntries'] as int).compareTo(a['totalEntries'] as int));
    return perfList;
  }

  bool _isSuperAdminUser(Profile? profile) {
    if (profile == null) return false;
    return profile.isSuperAdmin;
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = Provider.of<AuthProvider>(context);
    final profile = authProvider.profile;
    final isDesktop = ResponsiveLayout.isDesktop(context);
    final currentMonthName = DateFormat('MMMM yyyy').format(DateTime.now());
    final todayFormatted = DateFormat('dd MMMM yyyy').format(DateTime.now());
    final monthlyGuestsCount = _stats['monthlyGuestsCount'] ?? 0;
    final List<Map<String, dynamic>> recentPhotos = List<Map<String, dynamic>>.from(_stats['recentPhotos'] ?? []);
    final List<Map<String, dynamic>> guestsByPlace = List<Map<String, dynamic>>.from(_stats['guestsByPlace'] ?? []);
    final List<Map<String, dynamic>> guestsByPurpose = List<Map<String, dynamic>>.from(_stats['guestsByPurpose'] ?? []);
    final isSuperAdmin = _isSuperAdminUser(profile);
    final hasAdminProfilePic = profile?.profilePicture != null && profile!.profilePicture!.trim().isNotEmpty;

    return Scaffold(
      appBar: isDesktop
          ? AppBar(
              title: Text(
                'Dashboard Analytics',
                style: GoogleFonts.poppins(
                  fontWeight: FontWeight.w900,
                  fontSize: 22,
                  letterSpacing: 0.5,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
              actions: [
                IconButton(
                  icon: const Icon(Icons.settings_outlined),
                  onPressed: () => _showProfileSettingsModal(context, authProvider),
                  tooltip: 'Profile Settings',
                ),
                IconButton(
                  icon: const Icon(Icons.refresh),
                  onPressed: _loadStats,
                  tooltip: 'Refresh Stats',
                ),
              ],
            )
          : null,
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadStats,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final isMobile = constraints.maxWidth < 600;

                  return SingleChildScrollView(
                    physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
                    padding: EdgeInsets.fromLTRB(
                      isMobile ? 14 : 24,
                      isMobile ? 14 : 24,
                      isMobile ? 14 : 24,
                      isMobile ? 100 : 24,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Welcome Banner with Admin Profile Picture & Profile Settings Option Button (Mobile Responsive)
                        LayoutBuilder(
                          builder: (context, cardConstraints) {
                            final isCardMobile = cardConstraints.maxWidth < 600;

                            if (isCardMobile) {
                              return Container(
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
                                    Row(
                                      children: [
                                        CircleAvatar(
                                          radius: 24,
                                          backgroundColor: const Color(0xFF10B981),
                                          backgroundImage: hasAdminProfilePic ? NetworkImage(profile.profilePicture!) : null,
                                          child: !hasAdminProfilePic
                                              ? Text(
                                                  profile?.name.isNotEmpty == true ? profile!.name[0].toUpperCase() : 'U',
                                                  style: const TextStyle(fontSize: 20, color: Colors.white, fontWeight: FontWeight.bold),
                                                )
                                              : null,
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                'Welcome back, ${profile?.name ?? 'User'}!',
                                                style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w900, color: Colors.white),
                                                maxLines: 2,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                              const SizedBox(height: 2),
                                              Text(
                                                'Role: ${profile?.isSuperAdmin == true ? "Super Administrator" : "Sub Administrator"}',
                                                style: const TextStyle(color: Color(0xFFA7F3D0), fontWeight: FontWeight.w500, fontSize: 12),
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 14),
                                    SizedBox(
                                      width: double.infinity,
                                      child: ElevatedButton.icon(
                                        onPressed: () => _showProfileSettingsModal(context, authProvider),
                                        icon: const Icon(Icons.manage_accounts, size: 18, color: Colors.white),
                                        label: const Text('Profile Settings', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: const Color(0xFF10B981),
                                          foregroundColor: Colors.white,
                                          elevation: 2,
                                          padding: const EdgeInsets.symmetric(vertical: 10),
                                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            }

                            return Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(20),
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
                              child: Row(
                                children: [
                                  CircleAvatar(
                                    radius: 26,
                                    backgroundColor: const Color(0xFF10B981),
                                    backgroundImage: hasAdminProfilePic ? NetworkImage(profile.profilePicture!) : null,
                                    child: !hasAdminProfilePic
                                        ? Text(
                                            profile?.name.isNotEmpty == true ? profile!.name[0].toUpperCase() : 'U',
                                            style: const TextStyle(fontSize: 22, color: Colors.white, fontWeight: FontWeight.bold),
                                          )
                                        : null,
                                  ),
                                  const SizedBox(width: 16),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'Welcome back, ${profile?.name ?? 'User'}!',
                                          style: GoogleFonts.poppins(fontSize: 21, fontWeight: FontWeight.w900, color: Colors.white),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          'Role: ${profile?.isSuperAdmin == true ? "Super Administrator" : "Sub Administrator"}',
                                          style: const TextStyle(color: Color(0xFFA7F3D0), fontWeight: FontWeight.w500, fontSize: 13),
                                        ),
                                      ],
                                    ),
                                  ),
                                  ElevatedButton.icon(
                                    onPressed: () => _showProfileSettingsModal(context, authProvider),
                                    icon: const Icon(Icons.manage_accounts, size: 18, color: Colors.white),
                                    label: const Text('Profile Settings', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: const Color(0xFF10B981),
                                      foregroundColor: Colors.white,
                                      elevation: 2,
                                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                        const SizedBox(height: 20),

                        // Grid Stats Cards (2-by-2 on mobile, 4-by-1 on desktop)
                        LayoutBuilder(
                          builder: (context, gridConstraints) {
                            int crossAxisCount = gridConstraints.maxWidth > 900 ? 4 : 2;
                            double aspectRatio = gridConstraints.maxWidth < 600 ? 1.35 : (gridConstraints.maxWidth < 900 ? 1.7 : 1.8);

                            return GridView.count(
                              crossAxisCount: crossAxisCount,
                              crossAxisSpacing: 10,
                              mainAxisSpacing: 10,
                              childAspectRatio: aspectRatio,
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                          children: [
                            _buildStatCard(
                              title: 'Total Guests',
                              value: '${_stats['totalGuests'] ?? 0}',
                              subtitle: isSuperAdmin ? 'All time records' : 'Your total guests recorded',
                              icon: Icons.groups_outlined,
                              color: AppColors.primary,
                            ),
                            _buildStatCard(
                              title: "Today's Guests",
                              value: '${_stats['todayGuests'] ?? _todayGuestsList.length}',
                              subtitle: isSuperAdmin ? 'Today ($todayFormatted)' : 'Your guests recorded today ($todayFormatted)',
                              icon: Icons.today_outlined,
                              color: AppColors.accent,
                            ),
                            _buildStatCard(
                              title: 'Total Donations',
                              value: AppUtils.formatCurrency(_stats['totalDonations'] ?? 0),
                              subtitle: isSuperAdmin ? 'All guests donation sum' : 'Your total donations collected',
                              icon: Icons.account_balance_wallet_outlined,
                              color: AppColors.warning,
                            ),
                            _buildStatCard(
                              title: 'Monthly Donations',
                              value: AppUtils.formatCurrency(_stats['monthlyDonations'] ?? 0),
                              subtitle: isSuperAdmin ? 'Month of $currentMonthName ($monthlyGuestsCount guests)' : 'Your donations collected this month',
                              icon: Icons.calendar_month_outlined,
                              color: Colors.purple,
                            ),
                          ],
                        );
                      },
                    ),

                    const SizedBox(height: 24),

                    // Super Admin Only Analytics Sections (Photos, Charts Grid, Event Analytics & Leaderboards)
                    if (isSuperAdmin) ...[
                      // Recent Guest Photos Horizontal Avatar List
                      if (recentPhotos.isNotEmpty) _buildRecentPhotosSection(recentPhotos),

                      if (recentPhotos.isNotEmpty) const SizedBox(height: 24),

                      // Analytics Charts Grid (Guests by Place & Guests by Purpose)
                      if (guestsByPlace.isNotEmpty || guestsByPurpose.isNotEmpty)
                        _buildAnalyticsChartsGrid(guestsByPlace, guestsByPurpose),

                      if (guestsByPlace.isNotEmpty || guestsByPurpose.isNotEmpty) const SizedBox(height: 28),

                      // Event Analytics Graph Section
                      _buildEventAnalyticsGraph(),

                      const SizedBox(height: 28),

                      // Performance Analytics Section (CHARTS, 3 ROLE TABS, DATE FILTERS, EXPORT & LEADERBOARD)
                      _buildPerformanceSection(),

                      const SizedBox(height: 28),
                    ],

                    // Dedicated Today's Guests Section Card
                    Card(
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            LayoutBuilder(
                              builder: (context, headerConstraints) {
                                final isHeaderMobile = headerConstraints.maxWidth < 500;
                                if (isHeaderMobile) {
                                  return Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Container(
                                            padding: const EdgeInsets.all(8),
                                            decoration: BoxDecoration(
                                              color: AppColors.primary.withValues(alpha: 0.1),
                                              borderRadius: BorderRadius.circular(8),
                                            ),
                                            child: const Icon(Icons.people_alt_outlined, color: AppColors.primary, size: 20),
                                          ),
                                          const SizedBox(width: 10),
                                          Expanded(
                                            child: Text(
                                              isSuperAdmin ? "Today's Guests ($todayFormatted)" : "Your Today's Guests ($todayFormatted)",
                                              style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 8),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                        decoration: BoxDecoration(
                                          color: AppColors.primary.withValues(alpha: 0.1),
                                          borderRadius: BorderRadius.circular(20),
                                        ),
                                        child: Text(
                                          isSuperAdmin ? '${_todayGuestsList.length} Guests Today' : '${_todayGuestsList.length} Guests Recorded by You Today',
                                          style: const TextStyle(
                                            color: AppColors.primary,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 12,
                                          ),
                                        ),
                                      ),
                                    ],
                                  );
                                }
                                return Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Row(
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.all(8),
                                          decoration: BoxDecoration(
                                            color: AppColors.primary.withValues(alpha: 0.1),
                                            borderRadius: BorderRadius.circular(8),
                                          ),
                                          child: const Icon(Icons.people_alt_outlined, color: AppColors.primary, size: 20),
                                        ),
                                        const SizedBox(width: 12),
                                        Text(
                                          isSuperAdmin ? "Today's Guests ($todayFormatted)" : "Your Today's Guests ($todayFormatted)",
                                          style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                                        ),
                                      ],
                                    ),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: AppColors.primary.withValues(alpha: 0.1),
                                        borderRadius: BorderRadius.circular(20),
                                      ),
                                      child: Text(
                                        isSuperAdmin ? '${_todayGuestsList.length} Guests Today' : '${_todayGuestsList.length} Guests Recorded by You Today',
                                        style: const TextStyle(
                                          color: AppColors.primary,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ),
                                  ],
                                );
                              },
                            ),
                            const SizedBox(height: 16),
                            const Divider(height: 1),

                            if (_todayGuestsList.isEmpty)
                              Container(
                                padding: const EdgeInsets.symmetric(vertical: 32),
                                alignment: Alignment.center,
                                child: const Column(
                                  children: [
                                    Icon(Icons.event_available_outlined, size: 40, color: AppColors.textSecondary),
                                    SizedBox(height: 8),
                                    Text(
                                      'No guest visits recorded today yet.',
                                      style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
                                    ),
                                  ],
                                ),
                              )
                            else
                              ListView.separated(
                                shrinkWrap: true,
                                physics: const NeverScrollableScrollPhysics(),
                                itemCount: _todayGuestsList.length,
                                separatorBuilder: (context, index) => const Divider(height: 1),
                                itemBuilder: (context, index) {
                                  final guest = _todayGuestsList[index];
                                  final timeStr = DateFormat('hh:mm a').format(guest.createdAt.toLocal());
                                  final handledStr = (guest.handledBy != null && guest.handledBy!.isNotEmpty)
                                      ? " • Handled by: ${guest.handledBy}"
                                      : "";

                                  return ListTile(
                                    onTap: () => ThankYouMessageService.showThankYouDialog(
                                      context,
                                      guestName: guest.guestName,
                                      phoneNumber: guest.phoneNumber,
                                    ),
                                    contentPadding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                                    leading: CircleAvatar(
                                      backgroundColor: AppColors.primary.withValues(alpha: 0.1),
                                      child: Text(
                                        guest.guestName.isNotEmpty ? guest.guestName[0].toUpperCase() : 'G',
                                        style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold),
                                      ),
                                    ),
                                    title: Text(
                                      guest.guestName,
                                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                                    ),
                                    subtitle: Text(
                                      '${guest.place} • ${guest.purpose}$handledStr',
                                      style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                                    ),
                                    trailing: Column(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      crossAxisAlignment: CrossAxisAlignment.end,
                                      children: [
                                        if (guest.donationAmount > 0)
                                          Text(
                                            AppUtils.formatCurrency(guest.donationAmount),
                                            style: TextStyle(
                                              color: Colors.green.shade700,
                                              fontWeight: FontWeight.bold,
                                              fontSize: 13,
                                            ),
                                          ),
                                        Text(
                                          timeStr,
                                          style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
                                        ),
                                      ],
                                    ),
                                  );
                                },
                              ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
    );
  }

  // Profile Settings Modal Dialog with Direct Photo File Picker / Upload (Vibrant Colorful Design)
  void _showProfileSettingsModal(BuildContext context, AuthProvider authProvider) {
    final profile = authProvider.profile;
    final nameController = TextEditingController(text: profile?.name ?? '');
    final photoUrlController = TextEditingController(text: profile?.profilePicture ?? '');
    final dobController = TextEditingController(text: profile?.dateOfBirth ?? '');
    final phoneController = TextEditingController(text: profile?.phoneNumber ?? '');

    bool isUploadingPhoto = false;
    bool isSaving = false;

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            final hasPic = photoUrlController.text.trim().isNotEmpty;

            return Dialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              clipBehavior: Clip.antiAlias,
              child: Container(
                width: 480,
                color: const Color(0xFFF8FAFC),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Colorful Header Banner
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          colors: [Color(0xFF4F46E5), Color(0xFF059669)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Row(
                            children: [
                              Icon(Icons.manage_accounts, color: Colors.white, size: 24),
                              SizedBox(width: 10),
                              Text(
                                'Admin Profile Settings',
                                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
                              ),
                            ],
                          ),
                          IconButton(
                            icon: const Icon(Icons.close, color: Colors.white),
                            onPressed: () => Navigator.pop(context),
                          ),
                        ],
                      ),
                    ),

                    SingleChildScrollView(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        children: [
                          // Colorful Avatar Ring
                          Container(
                            padding: const EdgeInsets.all(4),
                            decoration: const BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: LinearGradient(
                                colors: [Color(0xFF6366F1), Color(0xFF10B981), Color(0xFFEC4899)],
                              ),
                            ),
                            child: Stack(
                              alignment: Alignment.center,
                              children: [
                                CircleAvatar(
                                  radius: 46,
                                  backgroundColor: Colors.white,
                                  backgroundImage: hasPic ? NetworkImage(photoUrlController.text.trim()) : null,
                                  child: !hasPic
                                      ? Text(
                                          nameController.text.isNotEmpty ? nameController.text[0].toUpperCase() : 'A',
                                          style: const TextStyle(fontSize: 34, fontWeight: FontWeight.bold, color: Color(0xFF4F46E5)),
                                        )
                                      : null,
                                ),
                                if (isUploadingPhoto)
                                  const CircleAvatar(
                                    radius: 46,
                                    backgroundColor: Colors.black45,
                                    child: CircularProgressIndicator(color: Colors.white),
                                  ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 14),

                          // Upload Photo Button (Vibrant Emerald)
                          ElevatedButton.icon(
                            onPressed: isUploadingPhoto
                                ? null
                                : () async {
                                    final result = await FilePicker.platform.pickFiles(type: FileType.image);
                                    if (result != null && result.files.single.bytes != null) {
                                      setModalState(() => isUploadingPhoto = true);
                                      try {
                                        final user = SupabaseService.currentUser;
                                        if (user != null) {
                                          final publicUrl = await SupabaseService.uploadProfilePicture(result.files.single.bytes!, user.id);
                                          photoUrlController.text = publicUrl;
                                          setModalState(() {});
                                        }
                                      } catch (e) {
                                        if (mounted) AppUtils.showSnackBar(context, 'Error uploading photo: $e', isError: true);
                                      } finally {
                                        setModalState(() => isUploadingPhoto = false);
                                      }
                                    }
                                  },
                            icon: const Icon(Icons.cloud_upload_rounded, size: 18, color: Colors.white),
                            label: Text(isUploadingPhoto ? 'Uploading Photo...' : 'Upload Photo', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF059669),
                              elevation: 2,
                              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                            ),
                          ),
                          const SizedBox(height: 20),

                          // Colorful Input 1: Admin Name (Indigo Accent)
                          TextField(
                            controller: nameController,
                            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Theme.of(context).colorScheme.onSurface),
                            decoration: InputDecoration(
                              labelText: 'Admin Name',
                              labelStyle: const TextStyle(color: Color(0xFF4F46E5), fontWeight: FontWeight.w600),
                              prefixIcon: const Icon(Icons.person, color: Color(0xFF4F46E5)),
                              filled: true,
                              fillColor: Theme.of(context).brightness == Brightness.dark ? const Color(0xFF1E293B) : const Color(0xFFEEF2FF),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                                borderSide: BorderSide(color: Theme.of(context).brightness == Brightness.dark ? const Color(0xFF334155) : const Color(0xFFC7D2FE), width: 1.2),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                                borderSide: const BorderSide(color: Color(0xFF4F46E5), width: 1.8),
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),

                          // Colorful Input 2: Date of Birth / Age (Rose Accent)
                          TextField(
                            controller: dobController,
                            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Theme.of(context).colorScheme.onSurface),
                            decoration: InputDecoration(
                              labelText: 'Date of Birth / Age (YYYY-MM-DD)',
                              labelStyle: const TextStyle(color: Color(0xFFDB2777), fontWeight: FontWeight.w600),
                              prefixIcon: const Icon(Icons.cake_rounded, color: Color(0xFFDB2777)),
                              filled: true,
                              fillColor: Theme.of(context).brightness == Brightness.dark ? const Color(0xFF1E293B) : const Color(0xFFFCE7F3),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                                borderSide: BorderSide(color: Theme.of(context).brightness == Brightness.dark ? const Color(0xFF334155) : const Color(0xFFFBCFE8), width: 1.2),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                                borderSide: const BorderSide(color: Color(0xFFDB2777), width: 1.8),
                              ),
                              suffixIcon: IconButton(
                                icon: const Icon(Icons.calendar_month_rounded, color: Color(0xFFDB2777)),
                                onPressed: () async {
                                  final picked = await showDatePicker(
                                    context: context,
                                    initialDate: DateTime(1995),
                                    firstDate: DateTime(1940),
                                    lastDate: DateTime.now(),
                                  );
                                  if (picked != null) {
                                    dobController.text = DateFormat('yyyy-MM-dd').format(picked);
                                    setModalState(() {});
                                  }
                                },
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),

                          // Colorful Input 3: Phone Number (Emerald Accent)
                          TextField(
                            controller: phoneController,
                            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Theme.of(context).colorScheme.onSurface),
                            decoration: InputDecoration(
                              labelText: 'Phone Number',
                              labelStyle: const TextStyle(color: Color(0xFF059669), fontWeight: FontWeight.w600),
                              prefixIcon: const Icon(Icons.phone_rounded, color: Color(0xFF059669)),
                              filled: true,
                              fillColor: const Color(0xFFECFDF5),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                                borderSide: const BorderSide(color: Color(0xFFA7F3D0), width: 1.2),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                                borderSide: const BorderSide(color: Color(0xFF059669), width: 1.8),
                              ),
                            ),
                            keyboardType: TextInputType.phone,
                          ),
                          const SizedBox(height: 24),

                          // Action Buttons Bar
                          Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              OutlinedButton(
                                onPressed: isSaving ? null : () => Navigator.pop(context),
                                style: OutlinedButton.styleFrom(
                                  side: const BorderSide(color: Colors.grey),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                                ),
                                child: const Text('Cancel', style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold)),
                              ),
                              const SizedBox(width: 12),
                              ElevatedButton.icon(
                                onPressed: isSaving
                                    ? null
                                    : () async {
                                        setModalState(() => isSaving = true);
                                        try {
                                          await authProvider.updateProfile(
                                            name: nameController.text,
                                            profilePicture: photoUrlController.text,
                                            dateOfBirth: dobController.text,
                                            phoneNumber: phoneController.text,
                                          );
                                          if (mounted) {
                                            Navigator.pop(context);
                                            AppUtils.showSnackBar(context, 'Profile settings successfully saved!');
                                            _loadStats();
                                          }
                                        } catch (e) {
                                          if (mounted) {
                                            AppUtils.showSnackBar(context, 'Error updating profile: $e', isError: true);
                                          }
                                        } finally {
                                          if (mounted) setModalState(() => isSaving = false);
                                        }
                                      },
                                icon: isSaving
                                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                    : const Icon(Icons.save_rounded, color: Colors.white),
                                label: Text(isSaving ? 'Saving...' : 'Save Profile', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF4F46E5),
                                  foregroundColor: Colors.white,
                                  elevation: 3,
                                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  // Recent Guest Photos Section with "View All Photos" Button
  Widget _buildRecentPhotosSection(List<Map<String, dynamic>> recentPhotos) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Recent Guest Photos',
                  style: GoogleFonts.poppins(fontWeight: FontWeight.w900, fontSize: 17, color: Theme.of(context).colorScheme.onSurface),
                ),
                TextButton.icon(
                  onPressed: () => _showAllPhotosGalleryDialog(recentPhotos),
                  icon: const Icon(Icons.collections_outlined, size: 16),
                  label: const Text('View All Photos', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.primary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 110,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: recentPhotos.length,
                itemBuilder: (context, index) {
                  final guest = recentPhotos[index];
                  final photoUrl = guest['photo_url']?.toString() ?? '';
                  final name = guest['guest_name']?.toString() ?? 'Guest';

                  return GestureDetector(
                    onTap: () => _showGuestDetailsModal(guest),
                    child: Container(
                      width: 84,
                      margin: const EdgeInsets.only(right: 16),
                      child: Column(
                        children: [
                          Container(
                            width: 68,
                            height: 68,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(color: AppColors.primary, width: 2.5),
                            ),
                            child: ClipOval(
                              child: Image.network(
                                photoUrl,
                                fit: BoxFit.cover,
                                cacheWidth: 200,
                                cacheHeight: 200,
                                errorBuilder: (context, error, stackTrace) => Container(
                                  color: AppColors.primary.withValues(alpha: 0.1),
                                  child: const Icon(Icons.person, color: AppColors.primary),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  // View All Photos Responsive Gallery Modal Dialog
  void _showAllPhotosGalleryDialog(List<Map<String, dynamic>> photos) {
    showDialog(
      context: context,
      builder: (context) {
        String searchQuery = '';
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final filteredPhotos = photos.where((p) {
              final name = p['guest_name']?.toString().toLowerCase() ?? '';
              final place = p['place']?.toString().toLowerCase() ?? '';
              final q = searchQuery.toLowerCase().trim();
              return q.isEmpty || name.contains(q) || place.contains(q);
            }).toList();

            return Dialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              insetPadding: const EdgeInsets.all(20),
              child: Container(
                width: 900,
                height: 650,
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Row(
                            children: [
                              const Icon(Icons.photo_library_outlined, color: AppColors.primary, size: 22),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Guest Photo Gallery (${filteredPhotos.length} Photos)',
                                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () => Navigator.pop(context),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // Search Input
                    TextField(
                      decoration: InputDecoration(
                        hintText: 'Search guests by name or place...',
                        prefixIcon: const Icon(Icons.search, size: 20),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      onChanged: (val) => setDialogState(() => searchQuery = val),
                    ),
                    const SizedBox(height: 20),

                    // Photo Grid View
                    Expanded(
                      child: filteredPhotos.isEmpty
                          ? const Center(
                              child: Text('No photos matching search.', style: TextStyle(color: AppColors.textSecondary)),
                            )
                          : GridView.builder(
                              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                                maxCrossAxisExtent: 140,
                                mainAxisSpacing: 16,
                                crossAxisSpacing: 16,
                                childAspectRatio: 0.8,
                              ),
                              itemCount: filteredPhotos.length,
                              itemBuilder: (context, index) {
                                final guest = filteredPhotos[index];
                                final photoUrl = guest['photo_url']?.toString() ?? '';
                                final name = guest['guest_name']?.toString() ?? 'Guest';
                                final place = guest['place']?.toString() ?? '';

                                return GestureDetector(
                                  onTap: () {
                                    Navigator.pop(context);
                                    _showGuestDetailsModal(guest);
                                  },
                                  child: Card(
                                    elevation: 2,
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                    child: Column(
                                      children: [
                                        Expanded(
                                          child: ClipRRect(
                                            borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
                                            child: Image.network(
                                              photoUrl,
                                              width: double.infinity,
                                              fit: BoxFit.cover,
                                              errorBuilder: (context, error, stackTrace) => Container(
                                                color: AppColors.primary.withValues(alpha: 0.1),
                                                child: const Icon(Icons.person, color: AppColors.primary, size: 40),
                                              ),
                                            ),
                                          ),
                                        ),
                                        Padding(
                                          padding: const EdgeInsets.all(8),
                                          child: Column(
                                            children: [
                                              Text(
                                                name,
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                                              ),
                                              if (place.isNotEmpty)
                                                Text(
                                                  place,
                                                  maxLines: 1,
                                                  overflow: TextOverflow.ellipsis,
                                                  style: const TextStyle(fontSize: 10, color: AppColors.textSecondary),
                                                ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  // Event Analytics & Attendance Graph Section
  Widget _buildEventAnalyticsGraph() {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final profile = authProvider.profile;
    if (!_isSuperAdminUser(profile)) return const SizedBox.shrink();

    final List<Map<String, dynamic>> filteredEvents = _getFilteredEvents();

    final Map<String, int> eventPlaceMap = {};
    int totalEventMembers = 0;
    for (final ev in filteredEvents) {
      final String place = ev['event_place']?.toString() ?? ev['event_name']?.toString() ?? 'Main Campus';
      final int count = ((ev['members_count'] ?? 1) as num).toInt();
      totalEventMembers += count;
      eventPlaceMap[place] = (eventPlaceMap[place] ?? 0) + (count > 0 ? count : 1);
    }

    final List<Map<String, dynamic>> eventsGraphData = eventPlaceMap.entries
        .map((e) => {'label': e.key, 'count': e.value})
        .toList()
      ..sort((a, b) => (b['count'] as int).compareTo(a['count'] as int));

    double maxY = 0;
    for (final e in eventsGraphData) {
      final double c = ((e['count'] ?? 0) as num).toDouble();
      if (c > maxY) maxY = c;
    }
    if (maxY == 0) maxY = 10;

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Event Attendance Analytics Graph',
                        style: GoogleFonts.poppins(fontWeight: FontWeight.w900, fontSize: 18, color: Theme.of(context).colorScheme.onSurface),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Total Events: ${filteredEvents.length}  •  Total Event Attendees: $totalEventMembers',
                        style: const TextStyle(color: AppColors.textSecondary, fontSize: 13, fontWeight: FontWeight.w500),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.orange.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.event_note_outlined, color: Colors.orange, size: 22),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Controls Bar: Date Filter Dropdown & Export Buttons
            Wrap(
              spacing: 12,
              runSpacing: 12,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                // Date Filter Dropdown (All Time, Today, Yesterday, This Month, Custom Range)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    border: Border.all(color: AppColors.border),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: _eventDateFilter,
                      items: const [
                        DropdownMenuItem(value: 'all', child: Text('All Time')),
                        DropdownMenuItem(value: 'today', child: Text('Today')),
                        DropdownMenuItem(value: 'yesterday', child: Text('Yesterday')),
                        DropdownMenuItem(value: 'month', child: Text('This Month')),
                        DropdownMenuItem(value: 'custom', child: Text('Custom Range')),
                      ],
                      onChanged: (val) {
                        if (val != null) {
                          setState(() => _eventDateFilter = val);
                          if (val == 'custom') _selectEventCustomDateRange();
                        }
                      },
                    ),
                  ),
                ),

                // Export Actions (EXCEL, CSV, PDF)
                Wrap(
                  spacing: 6,
                  children: [
                    OutlinedButton.icon(
                      onPressed: () => _exportEventsData('Excel', filteredEvents),
                      icon: const Icon(Icons.table_view, size: 16),
                      label: const Text('Excel', style: TextStyle(fontSize: 12)),
                    ),
                    OutlinedButton.icon(
                      onPressed: () => _exportEventsData('CSV', filteredEvents),
                      icon: const Icon(Icons.download, size: 16),
                      label: const Text('CSV', style: TextStyle(fontSize: 12)),
                    ),
                    ElevatedButton.icon(
                      onPressed: () => _exportEventsData('PDF', filteredEvents),
                      icon: const Icon(Icons.picture_as_pdf, size: 16),
                      label: const Text('PDF', style: TextStyle(fontSize: 12)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.orange.shade800,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 20),

            if (eventsGraphData.isEmpty)
              Container(
                padding: const EdgeInsets.symmetric(vertical: 36),
                alignment: Alignment.center,
                child: const Column(
                  children: [
                    Icon(Icons.bar_chart_outlined, size: 40, color: AppColors.textSecondary),
                    SizedBox(height: 8),
                    Text('No event attendance records for this date selection.', style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
                  ],
                ),
              )
            else
              LayoutBuilder(
                builder: (context, constraints) {
                  final isMobile = constraints.maxWidth < 600;
                  // On mobile, display ONLY top 3 highest events for maximum clarity
                  final displayData = isMobile ? eventsGraphData.take(3).toList() : eventsGraphData;

                  double localMaxY = 0;
                  for (final e in displayData) {
                    final double c = ((e['count'] ?? 0) as num).toDouble();
                    if (c > localMaxY) localMaxY = c;
                  }
                  if (localMaxY == 0) localMaxY = 10;

                  return SizedBox(
                    height: 230,
                    child: BarChart(
                      BarChartData(
                        alignment: BarChartAlignment.spaceAround,
                        maxY: localMaxY * 1.25,
                        barTouchData: BarTouchData(
                          touchTooltipData: BarTouchTooltipData(
                            getTooltipItem: (group, groupIndex, rod, rodIndex) {
                              final item = displayData[groupIndex];
                              final String label = item['label'] ?? '';
                              final int count = (rod.toY).toInt();
                              return BarTooltipItem(
                                '$label\n$count attendees',
                                const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                              );
                            },
                          ),
                        ),
                        titlesData: FlTitlesData(
                          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                          leftTitles: AxisTitles(
                            sideTitles: SideTitles(
                              showTitles: true,
                              reservedSize: 35,
                              getTitlesWidget: (val, meta) => Text('${val.toInt()}', style: const TextStyle(fontSize: 10)),
                            ),
                          ),
                          bottomTitles: AxisTitles(
                            sideTitles: SideTitles(
                              showTitles: true,
                              reservedSize: 32,
                              getTitlesWidget: (value, meta) {
                                int index = value.toInt();
                                if (index >= 0 && index < displayData.length) {
                                  String label = displayData[index]['label'] ?? '';
                                  return SideTitleWidget(
                                    meta: meta,
                                    space: 6,
                                    child: Text(
                                      label.length > 12 ? '${label.substring(0, 10)}…' : label,
                                      style: TextStyle(
                                        fontSize: isMobile ? 11 : 10,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.orange.shade900,
                                      ),
                                      textAlign: TextAlign.center,
                                    ),
                                  );
                                }
                                return const SizedBox.shrink();
                              },
                            ),
                          ),
                        ),
                        borderData: FlBorderData(show: false),
                        gridData: FlGridData(show: true, drawVerticalLine: false),
                        barGroups: List.generate(displayData.length, (index) {
                          final double count = ((displayData[index]['count'] ?? 0) as num).toDouble();
                          return BarChartGroupData(
                            x: index,
                            barRods: [
                              BarChartRodData(
                                toY: count,
                                color: Colors.orange.shade700,
                                width: isMobile ? 32 : 18,
                                borderRadius: const BorderRadius.only(topLeft: Radius.circular(6), topRight: Radius.circular(6)),
                              ),
                            ],
                          );
                        }),
                      ),
                    ),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _selectEventCustomDateRange() async {
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );

    if (range != null) {
      setState(() {
        _eventCustomStartDate = range.start;
        _eventCustomEndDate = range.end;
      });
    }
  }

  void _exportEventsData(String format, List<Map<String, dynamic>> events) async {
    final headers = ['Event Name', 'Location / Place', 'Attendees', 'Event Date', 'Handled By'];
    final rows = events.map((ev) {
      final String dateRaw = ev['event_date']?.toString() ?? ev['created_at']?.toString() ?? '';
      final String dateStr = dateRaw.isNotEmpty
          ? DateFormat('dd/MM/yyyy').format(DateTime.parse(dateRaw).toLocal())
          : '—';
      return [
        ev['event_name'] ?? 'Event',
        ev['event_place'] ?? 'Main Campus',
        '${ev['members_count'] ?? 1} members',
        dateStr,
        ev['handled_by'] ?? '—',
      ];
    }).toList();

    if (format == 'PDF') {
      await ExportService.exportEventReportPdf(
        reportTitle: 'Event Attendance Analytics Report',
        events: events,
      );
    } else if (format == 'CSV') {
      await ExportService.exportToCSV(
        filename: 'events-analytics',
        headers: headers,
        rows: rows,
      );
    } else if (format == 'Excel') {
      await ExportService.exportToExcel(
        filename: 'events-analytics',
        headers: headers,
        rows: rows,
      );
    }
  }

  // Guest Details Modal Dialog when clicking a photo
  void _showGuestDetailsModal(Map<String, dynamic> guest) {
    showDialog(
      context: context,
      builder: (context) {
        final photoUrl = guest['photo_url']?.toString();
        final name = guest['guest_name']?.toString() ?? 'Guest';
        final occupation = guest['occupation']?.toString();
        final phone = guest['phone_number']?.toString() ?? '—';
        final place = guest['place']?.toString() ?? '';
        final district = guest['district']?.toString() ?? '';
        final locationStr = [place, district].where((s) => s.isNotEmpty).join(', ');
        final purpose = guest['purpose']?.toString() ?? 'Visit';
        final donation = ((guest['donation_amount'] ?? 0) as num).toDouble();
        final handledBy = guest['handled_by']?.toString() ?? '—';
        final remarks = guest['remarks']?.toString();

        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
          contentPadding: const EdgeInsets.all(20),
          content: SizedBox(
            width: 380,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (photoUrl != null && photoUrl.isNotEmpty)
                    CircleAvatar(
                      radius: 46,
                      backgroundImage: NetworkImage(photoUrl),
                    )
                  else
                    const CircleAvatar(
                      radius: 46,
                      backgroundColor: AppColors.primary,
                      child: Icon(Icons.person, size: 46, color: Colors.white),
                    ),
                  const SizedBox(height: 10),
                  Text(
                    name,
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    textAlign: TextAlign.center,
                  ),
                  if (occupation != null && occupation.isNotEmpty)
                    Text(
                      occupation,
                      style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
                      textAlign: TextAlign.center,
                    ),
                  const SizedBox(height: 14),
                  const Divider(),
                  const SizedBox(height: 6),

                  _buildModalDetailRow('Phone', phone),
                  _buildModalDetailRow('Location', locationStr.isNotEmpty ? locationStr : '—'),
                  _buildModalDetailRow('Purpose', purpose),
                  _buildModalDetailRow('Donation', AppUtils.formatCurrency(donation), isSuccess: true),
                  _buildModalDetailRow('Handled By', handledBy),
                  if (remarks != null && remarks.isNotEmpty) _buildModalDetailRow('Remarks', remarks),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        );
      },
    );
  }

  Widget _buildModalDetailRow(String label, String value, {bool isSuccess = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 90,
            child: Text(label, style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 13,
                color: isSuccess ? Colors.green.shade700 : Theme.of(context).colorScheme.onSurface,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Analytics Charts Grid (Guests by Place Bar Chart & Guests by Purpose Pie Chart)
  Widget _buildAnalyticsChartsGrid(List<Map<String, dynamic>> places, List<Map<String, dynamic>> purposes) {
    return LayoutBuilder(
      builder: (context, constraints) {
        bool isWide = constraints.maxWidth > 800;
        if (isWide) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: _buildGuestsByPlaceCard(places)),
              const SizedBox(width: 16),
              Expanded(child: _buildGuestsByPurposeCard(purposes)),
            ],
          );
        } else {
          return Column(
            children: [
              _buildGuestsByPlaceCard(places),
              const SizedBox(height: 16),
              _buildGuestsByPurposeCard(purposes),
            ],
          );
        }
      },
    );
  }

  // Guests by Place Bar Chart Card
  Widget _buildGuestsByPlaceCard(List<Map<String, dynamic>> places) {
    double maxY = 0;
    for (final p in places) {
      final double c = ((p['count'] ?? 0) as num).toDouble();
      if (c > maxY) maxY = c;
    }
    if (maxY == 0) maxY = 10;

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Guests by Place', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            LayoutBuilder(
              builder: (context, constraints) {
                final double minWidth = math.max(constraints.maxWidth, places.length * 52.0);
                return SizedBox(
                  height: 230,
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: SizedBox(
                      width: minWidth,
                      child: BarChart(
                        BarChartData(
                          alignment: BarChartAlignment.spaceAround,
                          maxY: maxY * 1.2,
                          titlesData: FlTitlesData(
                            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                            leftTitles: AxisTitles(
                              sideTitles: SideTitles(
                                showTitles: true,
                                reservedSize: 32,
                                getTitlesWidget: (val, meta) => Text('${val.toInt()}', style: const TextStyle(fontSize: 10)),
                              ),
                            ),
                            bottomTitles: AxisTitles(
                              sideTitles: SideTitles(
                                showTitles: true,
                                reservedSize: 36,
                                getTitlesWidget: (value, meta) {
                                  int index = value.toInt();
                                  if (index >= 0 && index < places.length) {
                                    String name = places[index]['place'] ?? '';
                                    String displayName = name.length > 9 ? '${name.substring(0, 8)}…' : name;
                                    return SideTitleWidget(
                                      meta: meta,
                                      space: 4,
                                      child: Transform.rotate(
                                        angle: -0.3,
                                        child: Text(
                                          displayName,
                                          style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: Theme.of(context).colorScheme.onSurface),
                                        ),
                                      ),
                                    );
                                  }
                                  return const SizedBox.shrink();
                                },
                              ),
                            ),
                          ),
                          borderData: FlBorderData(show: false),
                          gridData: FlGridData(show: true, drawVerticalLine: false),
                          barGroups: List.generate(places.length, (index) {
                            final double count = ((places[index]['count'] ?? 0) as num).toDouble();
                            return BarChartGroupData(
                              x: index,
                              barRods: [
                                BarChartRodData(
                                  toY: count,
                                  color: AppColors.accent,
                                  width: 16,
                                  borderRadius: const BorderRadius.only(topLeft: Radius.circular(4), topRight: Radius.circular(4)),
                                ),
                              ],
                            );
                          }),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  // Guests by Purpose Pie / Donut Chart Card
  Widget _buildGuestsByPurposeCard(List<Map<String, dynamic>> purposes) {
    int totalCount = purposes.fold(0, (s, p) => s + ((p['count'] ?? 0) as int));

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Guests by Purpose', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            SizedBox(
              height: 220,
              child: Row(
                children: [
                  Expanded(
                    flex: 6,
                    child: PieChart(
                      PieChartData(
                        sectionsSpace: 2,
                        centerSpaceRadius: 40,
                        sections: List.generate(purposes.length, (index) {
                          final p = purposes[index];
                          final int count = p['count'] ?? 0;
                          final double pct = totalCount > 0 ? (count / totalCount * 100) : 0;
                          final color = _pieColors[index % _pieColors.length];

                          return PieChartSectionData(
                            color: color,
                            value: count.toDouble(),
                            title: '${pct.toStringAsFixed(0)}%',
                            radius: 45,
                            titleStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white),
                          );
                        }),
                      ),
                    ),
                  ),
                  Expanded(
                    flex: 4,
                    child: SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: List.generate(purposes.length, (index) {
                          final p = purposes[index];
                          final String purpose = p['purpose'] ?? 'Purpose';
                          final color = _pieColors[index % _pieColors.length];

                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            child: Row(
                              children: [
                                Container(width: 10, height: 10, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    purpose,
                                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          );
                        }),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Performance Analytics Section (WITH SUB ADMIN, SUPER ADMIN, AND ALL ADMINS OPTIONS + PROFILE PICTURE AVATARS)
  Widget _buildPerformanceSection() {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final profile = authProvider.profile;
    if (!_isSuperAdminUser(profile)) return const SizedBox.shrink();

    final List<Map<String, dynamic>> activeList = _calculateAdminPerformance();

    String roleLabel = 'Sub Admin';
    Color barColor = Colors.purple;

    if (_selectedPerfTab == 1) {
      roleLabel = 'Super Admin';
      barColor = AppColors.primary;
    } else if (_selectedPerfTab == 2) {
      roleLabel = 'Admin';
      barColor = Colors.teal;
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Card(
      color: isDark ? const Color(0xFF1E293B) : const Color(0xFFFFF1F2),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: isDark ? const Color(0xFF334155) : const Color(0xFFFECDD3), width: 1.2),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Section Header & Controls
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Admin Performance Analytics',
                        style: GoogleFonts.poppins(fontWeight: FontWeight.w900, fontSize: 18, color: Theme.of(context).colorScheme.onSurface),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Performance graphs & comparison table for administrators',
                        style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 13),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Controls Bar: 3 Role Tabs (Sub Admin, Super Admin, All Admins), Date Filter & Export Buttons
            Wrap(
              spacing: 12,
              runSpacing: 12,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                // 3 Role Tabs (Horizontal Scroll for Mobile)
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _buildTabButton('👤 Sub Admin', _selectedPerfTab == 0, () {
                          setState(() {
                            _selectedPerfTab = 0;
                            _updateCachedCalculations();
                          });
                        }),
                        _buildTabButton('👑 Super Admin', _selectedPerfTab == 1, () {
                          setState(() {
                            _selectedPerfTab = 1;
                            _updateCachedCalculations();
                          });
                        }),
                        _buildTabButton('📊 All Admins', _selectedPerfTab == 2, () {
                          setState(() {
                            _selectedPerfTab = 2;
                            _updateCachedCalculations();
                          });
                        }),
                      ],
                    ),
                  ),
                ),

                // Date Filter Dropdown
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surface,
                    border: Border.all(color: isDark ? const Color(0xFF334155) : AppColors.border),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: _dateFilter,
                      dropdownColor: Theme.of(context).colorScheme.surface,
                      style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontSize: 13, fontWeight: FontWeight.w500),
                      items: [
                        DropdownMenuItem(value: 'all', child: Text('All Time', style: TextStyle(color: Theme.of(context).colorScheme.onSurface))),
                        DropdownMenuItem(value: 'week', child: Text('This Week', style: TextStyle(color: Theme.of(context).colorScheme.onSurface))),
                        DropdownMenuItem(value: 'month', child: Text('This Month', style: TextStyle(color: Theme.of(context).colorScheme.onSurface))),
                        DropdownMenuItem(value: 'custom', child: Text('Custom Range', style: TextStyle(color: Theme.of(context).colorScheme.onSurface))),
                      ],
                      onChanged: (val) {
                        if (val != null) {
                          setState(() {
                            _dateFilter = val;
                            _updateCachedCalculations();
                          });
                          if (val == 'custom') _selectCustomDateRange();
                        }
                      },
                    ),
                  ),
                ),

                // Export Actions (EXCEL, CSV, PDF WITH CLEAN RS. CURRENCY)
                Wrap(
                  spacing: 6,
                  children: [
                    OutlinedButton.icon(
                      onPressed: () => _exportData('Excel', activeList, roleLabel),
                      icon: const Icon(Icons.table_view, size: 16),
                      label: const Text('Excel', style: TextStyle(fontSize: 12)),
                    ),
                    OutlinedButton.icon(
                      onPressed: () => _exportData('CSV', activeList, roleLabel),
                      icon: const Icon(Icons.download, size: 16),
                      label: const Text('CSV', style: TextStyle(fontSize: 12)),
                    ),
                    ElevatedButton.icon(
                      onPressed: () => _exportData('PDF', activeList, roleLabel),
                      icon: const Icon(Icons.picture_as_pdf, size: 16),
                      label: const Text('PDF', style: TextStyle(fontSize: 12)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red.shade700,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ],
                ),
              ],
            ),

            const SizedBox(height: 24),

            if (activeList.isEmpty)
              Container(
                padding: const EdgeInsets.symmetric(vertical: 40),
                alignment: Alignment.center,
                child: Text('No admin activity data recorded for this selection.', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
              )
            else ...[
              // Side-by-Side Bar Charts Grid
              LayoutBuilder(
                builder: (context, constraints) {
                  bool isWide = constraints.maxWidth > 800;
                  if (isWide) {
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: _buildBarChartCard('Guests Handled – $roleLabel', activeList, isDonation: false, color: barColor)),
                        const SizedBox(width: 16),
                        Expanded(child: _buildBarChartCard('Donations Collected – $roleLabel', activeList, isDonation: true, color: AppColors.accent)),
                      ],
                    );
                  } else {
                    return Column(
                      children: [
                        _buildBarChartCard('Guests Handled – $roleLabel', activeList, isDonation: false, color: barColor),
                        const SizedBox(height: 16),
                        _buildBarChartCard('Donations Collected – $roleLabel', activeList, isDonation: true, color: AppColors.accent),
                      ],
                    );
                  }
                },
              ),

              const SizedBox(height: 24),
              const Divider(),
              const SizedBox(height: 12),

              // Leaderboard Table with Admin Profile Picture Avatars (Horizontal Scroll for Mobile)
              LayoutBuilder(
                builder: (context, tableConstraints) {
                  final double minTableWidth = math.max(tableConstraints.maxWidth, 500.0);

                  return ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: SizedBox(
                        width: minTableWidth,
                        child: Table(
                          border: TableBorder.all(color: isDark ? const Color(0xFF334155) : const Color(0xFFFECDD3), width: 0.8),
                          columnWidths: const {
                            0: FlexColumnWidth(2.2),
                            1: FlexColumnWidth(1.2),
                            2: FlexColumnWidth(1.8),
                            3: FlexColumnWidth(1.4),
                          },
                          children: [
                            TableRow(
                              decoration: BoxDecoration(color: isDark ? const Color(0xFF0F172A) : const Color(0xFFFFE4E6)),
                              children: [
                                Padding(padding: const EdgeInsets.all(12), child: Text('Admin Name', style: TextStyle(fontWeight: FontWeight.bold, color: isDark ? const Color(0xFFF8FAFC) : const Color(0xFF9F1239)))),
                                Padding(padding: const EdgeInsets.all(12), child: Text('Total Entries', style: TextStyle(fontWeight: FontWeight.bold, color: isDark ? const Color(0xFFF8FAFC) : const Color(0xFF9F1239)))),
                                Padding(padding: const EdgeInsets.all(12), child: Text('Total Donations', style: TextStyle(fontWeight: FontWeight.bold, color: isDark ? const Color(0xFFF8FAFC) : const Color(0xFF9F1239)))),
                                Padding(padding: const EdgeInsets.all(12), child: Text('Last Entry', style: TextStyle(fontWeight: FontWeight.bold, color: isDark ? const Color(0xFFF8FAFC) : const Color(0xFF9F1239)))),
                              ],
                            ),
                            ...activeList.map((item) {
                              final String name = item['name'] ?? 'User';
                              final String? profilePic = item['profile_picture']?.toString();
                              final hasPic = profilePic != null && profilePic.trim().isNotEmpty;
                              final String? lastDateRaw = item['lastEntry']?.toString();
                              final String lastDateStr = lastDateRaw != null && lastDateRaw.isNotEmpty
                                  ? DateFormat('dd/MM/yyyy').format(DateTime.parse(lastDateRaw).toLocal())
                                  : '—';

                              return TableRow(
                                children: [
                                  Padding(
                                    padding: const EdgeInsets.all(12),
                                    child: Row(
                                      children: [
                                        CircleAvatar(
                                          radius: 16,
                                          backgroundColor: AppColors.primary.withValues(alpha: 0.1),
                                          backgroundImage: hasPic ? NetworkImage(profilePic) : null,
                                          child: !hasPic
                                              ? Text(
                                                  name.isNotEmpty ? name[0].toUpperCase() : 'A',
                                                  style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold, fontSize: 12),
                                                )
                                              : null,
                                        ),
                                        const SizedBox(width: 10),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(name, style: const TextStyle(fontWeight: FontWeight.w600)),
                                              if (_selectedPerfTab == 2)
                                                Text(item['role'] ?? '', style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Padding(
                                    padding: const EdgeInsets.all(12),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: AppColors.primary.withValues(alpha: 0.1),
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Text(
                                        '${item['totalEntries']}',
                                        textAlign: TextAlign.center,
                                        style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold, fontSize: 13),
                                      ),
                                    ),
                                  ),
                                  Padding(
                                    padding: const EdgeInsets.all(12),
                                    child: Text(
                                      AppUtils.formatCurrency(item['totalDonations'] ?? 0),
                                      style: TextStyle(color: isDark ? const Color(0xFF34D399) : Colors.green.shade700, fontWeight: FontWeight.bold),
                                    ),
                                  ),
                                  Padding(
                                    padding: const EdgeInsets.all(12),
                                    child: Text(
                                      lastDateStr,
                                      style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 12),
                                    ),
                                  ),
                                ],
                              );
                            }),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildTabButton(String label, bool isSelected, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.white : AppColors.textSecondary,
            fontWeight: FontWeight.bold,
            fontSize: 12,
          ),
        ),
      ),
    );
  }

  Future<void> _selectCustomDateRange() async {
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );

    if (range != null) {
      setState(() {
        _customStartDate = range.start;
        _customEndDate = range.end;
      });
    }
  }

  void _exportData(String format, List<Map<String, dynamic>> list, String roleLabel) async {
    final headers = ['$roleLabel Name', 'Total Entries', 'Total Donations (INR)', 'Last Entry'];
    final rows = list.map((item) {
      final String? lastDateRaw = item['lastEntry']?.toString();
      final String lastDateStr = lastDateRaw != null && lastDateRaw.isNotEmpty
          ? DateFormat('dd/MM/yyyy').format(DateTime.parse(lastDateRaw).toLocal())
          : '—';
      return [
        item['name'] ?? '',
        item['totalEntries'] ?? 0,
        AppUtils.formatCurrency(item['totalDonations'] ?? 0),
        lastDateStr,
      ];
    }).toList();

    if (format == 'PDF') {
      await ExportService.exportAdminPerformancePdf(
        reportTitle: '$roleLabel Performance Report',
        rows: list,
        roleLabel: roleLabel,
      );
    } else if (format == 'CSV') {
      await ExportService.exportToCSV(
        filename: '${roleLabel.toLowerCase()}-performance',
        headers: headers,
        rows: rows,
      );
    } else if (format == 'Excel') {
      await ExportService.exportToExcel(
        filename: '${roleLabel.toLowerCase()}-performance',
        headers: headers,
        rows: rows,
      );
    }
  }

  // Interactive Bar Chart Builder using fl_chart
  Widget _buildBarChartCard(String title, List<Map<String, dynamic>> data, {required bool isDonation, required Color color}) {
    double maxY = 0;
    for (final d in data) {
      final double val = isDonation ? ((d['totalDonations'] ?? 0) as num).toDouble() : ((d['totalEntries'] ?? 0) as num).toDouble();
      if (val > maxY) maxY = val;
    }
    if (maxY == 0) maxY = 10;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(isDonation ? Icons.monetization_on_outlined : Icons.bar_chart_outlined, color: color, size: 20),
              const SizedBox(width: 8),
              Text(title, style: TextStyle(fontWeight: FontWeight.bold, color: color, fontSize: 14)),
            ],
          ),
          const SizedBox(height: 20),
          LayoutBuilder(
            builder: (context, chartConstraints) {
              final double minChartWidth = math.max(chartConstraints.maxWidth, data.length * 60.0);

              return SizedBox(
                height: 240,
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: SizedBox(
                    width: minChartWidth,
                    child: BarChart(
                      BarChartData(
                        alignment: BarChartAlignment.spaceAround,
                        maxY: maxY * 1.2,
                        barTouchData: BarTouchData(
                          touchTooltipData: BarTouchTooltipData(
                            getTooltipItem: (group, groupIndex, rod, rodIndex) {
                              final item = data[groupIndex];
                              final String name = item['name'] ?? '';
                              final String valStr = isDonation ? AppUtils.formatCurrency(rod.toY) : '${rod.toY.toInt()} guests';
                              return BarTooltipItem(
                                '$name\n$valStr',
                                const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                              );
                            },
                          ),
                        ),
                        titlesData: FlTitlesData(
                          show: true,
                          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                          leftTitles: AxisTitles(
                            sideTitles: SideTitles(
                              showTitles: true,
                              reservedSize: 45,
                              getTitlesWidget: (value, meta) {
                                if (value == 0) return const SizedBox.shrink();
                                final textColor = Theme.of(context).colorScheme.onSurface;
                                if (isDonation) {
                                  if (value >= 100000) return Text('₹${(value / 100000).toStringAsFixed(1)}L', style: TextStyle(fontSize: 10, color: textColor));
                                  if (value >= 1000) return Text('₹${(value / 1000).toStringAsFixed(0)}k', style: TextStyle(fontSize: 10, color: textColor));
                                  return Text('₹${value.toInt()}', style: TextStyle(fontSize: 10, color: textColor));
                                }
                                return Text('${value.toInt()}', style: TextStyle(fontSize: 10, color: textColor));
                              },
                            ),
                          ),
                          bottomTitles: AxisTitles(
                            sideTitles: SideTitles(
                              showTitles: true,
                              reservedSize: 36,
                              getTitlesWidget: (value, meta) {
                                int index = value.toInt();
                                if (index >= 0 && index < data.length) {
                                  String fullName = data[index]['name'] ?? '';
                                  List<String> parts = fullName.split(' ');
                                  String displayName = parts.length > 1 ? '${parts[0]} ${parts[1][0]}.' : parts[0];
                                  if (displayName.length > 11) displayName = '${displayName.substring(0, 10)}…';

                                  return SideTitleWidget(
                                    meta: meta,
                                    space: 4,
                                    child: Transform.rotate(
                                      angle: -0.3,
                                      child: Text(
                                        displayName,
                                        style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: Theme.of(context).colorScheme.onSurface),
                                      ),
                                    ),
                                  );
                                }
                                return const SizedBox.shrink();
                              },
                            ),
                          ),
                        ),
                        borderData: FlBorderData(show: false),
                        gridData: FlGridData(
                          show: true,
                          drawVerticalLine: false,
                          getDrawingHorizontalLine: (value) => FlLine(color: AppColors.border.withValues(alpha: 0.5), strokeWidth: 1),
                        ),
                        barGroups: List.generate(data.length, (index) {
                          final item = data[index];
                          final double val = isDonation
                              ? ((item['totalDonations'] ?? 0) as num).toDouble()
                              : ((item['totalEntries'] ?? 0) as num).toDouble();

                          return BarChartGroupData(
                            x: index,
                            barRods: [
                              BarChartRodData(
                                toY: val,
                                color: color,
                                width: 18,
                                borderRadius: const BorderRadius.only(
                                  topLeft: Radius.circular(6),
                                  topRight: Radius.circular(6),
                                ),
                              ),
                            ],
                          );
                        }),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildStatCard({
    required String title,
    required String value,
    required String subtitle,
    required IconData icon,
    required Color color,
  }) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(fontSize: 12, color: AppColors.textSecondary, fontWeight: FontWeight.w600),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(icon, size: 18, color: color),
                ),
              ],
            ),
            const SizedBox(height: 6),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                value,
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.onSurface),
              ),
            ),
            const SizedBox(height: 2),
            Text(
              subtitle,
              style: TextStyle(fontSize: 10, color: color, fontWeight: FontWeight.w600),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}
