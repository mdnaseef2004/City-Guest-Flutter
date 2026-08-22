import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../config/constants.dart';
import '../core/responsive_layout.dart';
import '../providers/auth_provider.dart';
import '../providers/theme_provider.dart';
import 'dashboard/dashboard_view.dart';
import 'guests/add_guest_view.dart';
import 'guests/guest_records_view.dart';
import 'assignments/assignments_view.dart';
import 'events/events_view.dart';
import 'reports/reports_view.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/notification_service.dart';
import '../services/supabase_service.dart';
import 'user_management/user_management_view.dart';
import 'notifications/notifications_view.dart';

class MainNavigationShell extends StatefulWidget {
  const MainNavigationShell({super.key});

  @override
  State<MainNavigationShell> createState() => _MainNavigationShellState();
}

class _MainNavigationShellState extends State<MainNavigationShell> {
  int _selectedIndex = 0;
  RealtimeChannel? _notificationChannel;
  StreamSubscription<String?>? _notificationSelectSubscription;

  @override
  void initState() {
    super.initState();
    _listenToNotificationTap();
    _subscribeToNotifications();
  }

  @override
  void dispose() {
    _notificationSelectSubscription?.cancel();
    if (_notificationChannel != null) {
      SupabaseService.client.removeChannel(_notificationChannel!);
    }
    super.dispose();
  }

  void _listenToNotificationTap() {
    _notificationSelectSubscription = NotificationService.selectNotificationStream.stream.listen((payload) {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final navItems = _getNavItems(authProvider.isSuperAdmin);
      final notificationIndex = navItems.indexWhere((item) => item.title == 'Notifications');
      if (notificationIndex != -1 && mounted) {
        setState(() {
          _selectedIndex = notificationIndex;
        });
      }
    });
  }

  void _subscribeToNotifications() {
    final user = SupabaseService.currentUser;
    if (user == null) return;

    final channelName = 'public:app_notifications_${user.id}_${DateTime.now().millisecondsSinceEpoch}';
    _notificationChannel = SupabaseService.client
        .channel(channelName)
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'app_notifications',
          callback: (payload) {
            final record = payload.newRecord;
            final targetUserId = record['user_id']?.toString();
            if (targetUserId == user.id || targetUserId == null) {
              final title = record['title']?.toString() ?? 'New Notification';
              final message = record['message']?.toString() ?? '';
              final type = record['type']?.toString() ?? 'info';

              // Show Android System Tray Notification (sound + vibration + notification bar)
              NotificationService.showSystemNotification(
                title: title,
                message: message,
              );

              if (mounted) {
                NotificationService.showNotificationPopup(
                  context,
                  title: title,
                  message: message,
                  isError: type == 'urgent' || type == 'error',
                  icon: type == 'urgent' ? Icons.warning_amber_rounded : Icons.notifications_active_rounded,
                );
              }
            }
          },
        )
        .subscribe();
  }

  List<NavItem> _getNavItems(bool isSuperAdmin) {
    return [
      NavItem(title: 'Dashboard', icon: Icons.dashboard_outlined, activeIcon: Icons.dashboard),
      NavItem(title: 'Add Guest', icon: Icons.person_add_outlined, activeIcon: Icons.person_add),
      NavItem(title: 'Records', icon: Icons.table_chart_outlined, activeIcon: Icons.table_chart),
      NavItem(title: 'Assignments', icon: Icons.assignment_ind_outlined, activeIcon: Icons.assignment_ind),
      NavItem(title: 'Events', icon: Icons.event_outlined, activeIcon: Icons.event),
      NavItem(title: 'Reports', icon: Icons.assessment_outlined, activeIcon: Icons.assessment),
      if (isSuperAdmin)
        NavItem(title: 'Users', icon: Icons.manage_accounts_outlined, activeIcon: Icons.manage_accounts),
      NavItem(title: 'Notifications', icon: Icons.notifications_outlined, activeIcon: Icons.notifications),
    ];
  }

  Widget _getSelectedView(bool isSuperAdmin) {
    switch (_selectedIndex) {
      case 0:
        return const DashboardView();
      case 1:
        return const AddGuestView();
      case 2:
        return const GuestRecordsView();
      case 3:
        return const AssignmentsView();
      case 4:
        return const EventsView();
      case 5:
        return const ReportsView();
      case 6:
        return isSuperAdmin ? const UserManagementView() : const NotificationsView();
      case 7:
        return const NotificationsView();
      default:
        return const DashboardView();
    }
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = Provider.of<AuthProvider>(context);
    final profile = authProvider.profile;
    final isSuperAdmin = authProvider.isSuperAdmin;
    final navItems = _getNavItems(isSuperAdmin);

    // Ensure _selectedIndex is safely within bounds
    if (_selectedIndex >= navItems.length) {
      _selectedIndex = 0;
    }

    final hasProfilePic = profile?.profilePicture != null && profile!.profilePicture!.trim().isNotEmpty;

    return Scaffold(
      body: ResponsiveLayout(
        // Mobile Layout: Screen View + Forest Emerald Green Navigation Drawer & Liquid Floating Bottom Navigation Bar
        mobile: Scaffold(
          appBar: AppBar(
            backgroundColor: const Color(0xFF064E3B),
            foregroundColor: Colors.white,
            elevation: 2,
            iconTheme: const IconThemeData(color: Colors.white),
            title: Text(
              navItems[_selectedIndex].title,
              style: GoogleFonts.poppins(fontWeight: FontWeight.w900, fontSize: 21, letterSpacing: 0.4, color: Colors.white),
            ),
            actions: [
              // Theme Mode Selector Toggle Button (System / Light / Dark)
              Consumer<ThemeProvider>(
                builder: (context, themeProvider, _) {
                  IconData themeIcon;
                  String themeTooltip;
                  if (themeProvider.themeMode == ThemeMode.dark) {
                    themeIcon = Icons.dark_mode_rounded;
                    themeTooltip = 'Theme: Dark';
                  } else if (themeProvider.themeMode == ThemeMode.light) {
                    themeIcon = Icons.light_mode_rounded;
                    themeTooltip = 'Theme: Light';
                  } else {
                    themeIcon = Icons.brightness_auto_rounded;
                    themeTooltip = 'Theme: System';
                  }
                  return IconButton(
                    icon: Icon(themeIcon, color: Colors.white, size: 22),
                    tooltip: themeTooltip,
                    onPressed: () {
                      if (themeProvider.themeMode == ThemeMode.system) {
                        themeProvider.setThemeMode(ThemeMode.light);
                      } else if (themeProvider.themeMode == ThemeMode.light) {
                        themeProvider.setThemeMode(ThemeMode.dark);
                      } else {
                        themeProvider.setThemeMode(ThemeMode.system);
                      }
                    },
                  );
                },
              ),
              // Top Bar Notification Button
              Stack(
                alignment: Alignment.center,
                children: [
                  IconButton(
                    icon: const Icon(Icons.notifications_outlined, color: Colors.white, size: 24),
                    tooltip: 'Notifications',
                    onPressed: () {
                      final notifIndex = isSuperAdmin ? 7 : 6;
                      setState(() => _selectedIndex = notifIndex);
                    },
                  ),
                  Positioned(
                    top: 10,
                    right: 10,
                    child: Container(
                      width: 8,
                      height: 8,
                      decoration: const BoxDecoration(
                        color: Color(0xFFEF4444),
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 8),
            ],
          ),
          drawer: Drawer(
            child: ListView(
              padding: EdgeInsets.zero,
              children: [
                DrawerHeader(
                  margin: EdgeInsets.zero,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Color(0xFF064E3B), Color(0xFF022C22)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                  ),
                  child: SingleChildScrollView(
                    physics: const NeverScrollableScrollPhysics(),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        // City Guest Logo Container
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.15),
                                blurRadius: 8,
                                offset: const Offset(0, 3),
                              ),
                            ],
                          ),
                          child: Image.asset(
                            'assets/full_mkc_logo.png',
                            height: 38,
                            fit: BoxFit.contain,
                            errorBuilder: (context, error, stackTrace) => const Icon(
                              Icons.apartment_rounded,
                              color: Color(0xFF059669),
                              size: 26,
                            ),
                          ),
                        ),
                        const SizedBox(height: 14),

                        // Prominent Big Profile Avatar with Name & Email
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(2.5),
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                gradient: const LinearGradient(
                                  colors: [Color(0xFF10B981), Color(0xFFA7F3D0)],
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.25),
                                    blurRadius: 6,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                              ),
                              child: CircleAvatar(
                                radius: 28,
                                backgroundColor: Colors.white,
                                backgroundImage: hasProfilePic ? NetworkImage(profile.profilePicture!) : null,
                                child: !hasProfilePic
                                    ? Text(
                                        profile?.name.isNotEmpty == true ? profile!.name[0].toUpperCase() : 'U',
                                        style: const TextStyle(
                                          color: Color(0xFF059669),
                                          fontWeight: FontWeight.w900,
                                          fontSize: 22,
                                        ),
                                      )
                                    : null,
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text(
                                    profile?.name ?? 'User',
                                    style: GoogleFonts.poppins(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 15,
                                      color: Colors.white,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    profile?.email ?? '',
                                    style: GoogleFonts.poppins(
                                      color: const Color(0xFFA7F3D0),
                                      fontSize: 11,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 4),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF10B981).withValues(alpha: 0.25),
                                      borderRadius: BorderRadius.circular(6),
                                      border: Border.all(color: const Color(0xFF10B981), width: 0.8),
                                    ),
                                    child: Text(
                                      isSuperAdmin ? 'Super Admin' : 'Sub Admin',
                                      style: GoogleFonts.poppins(
                                        color: const Color(0xFFA7F3D0),
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                      ),
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
                for (int i = 0; i < navItems.length; i++)
                  Container(
                    margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                    decoration: _selectedIndex == i
                        ? BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [Color(0xFF10B981), Color(0xFF059669)],
                            ),
                            borderRadius: BorderRadius.circular(10),
                            boxShadow: const [
                              BoxShadow(
                                color: Color(0x3010B981),
                                blurRadius: 6,
                                offset: Offset(0, 2),
                              ),
                            ],
                          )
                        : null,
                    child: ListTile(
                      dense: true,
                      leading: Icon(
                        _selectedIndex == i ? navItems[i].activeIcon : navItems[i].icon,
                        color: _selectedIndex == i ? Colors.white : const Color(0xFF10B981),
                      ),
                      title: Text(
                        navItems[i].title,
                        style: TextStyle(
                          fontWeight: _selectedIndex == i ? FontWeight.bold : FontWeight.w500,
                          color: _selectedIndex == i ? Colors.white : Theme.of(context).colorScheme.onSurface,
                        ),
                      ),
                      selected: _selectedIndex == i,
                      onTap: () {
                        Navigator.pop(context);
                        setState(() => _selectedIndex = i);
                      },
                    ),
                  ),
                const Divider(),
                Consumer<ThemeProvider>(
                  builder: (context, themeProvider, _) {
                    String label = 'Theme Mode: System';
                    IconData icon = Icons.brightness_auto_rounded;
                    if (themeProvider.themeMode == ThemeMode.dark) {
                      label = 'Theme Mode: Dark';
                      icon = Icons.dark_mode_rounded;
                    } else if (themeProvider.themeMode == ThemeMode.light) {
                      label = 'Theme Mode: Light';
                      icon = Icons.light_mode_rounded;
                    }
                    return ListTile(
                      dense: true,
                      leading: Icon(icon, color: const Color(0xFF10B981)),
                      title: Text(
                        label,
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                      ),
                      trailing: const Icon(Icons.swap_horiz_rounded, size: 18),
                      onTap: () {
                        if (themeProvider.themeMode == ThemeMode.system) {
                          themeProvider.setThemeMode(ThemeMode.light);
                        } else if (themeProvider.themeMode == ThemeMode.light) {
                          themeProvider.setThemeMode(ThemeMode.dark);
                        } else {
                          themeProvider.setThemeMode(ThemeMode.system);
                        }
                      },
                    );
                  },
                ),
                ListTile(
                  dense: true,
                  leading: const Icon(Icons.logout, color: AppColors.danger),
                  title: const Text('Sign Out', style: TextStyle(color: AppColors.danger, fontWeight: FontWeight.bold)),
                  onTap: () => authProvider.signOut(),
                ),
              ],
            ),
          ),
          extendBody: true,
          body: AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeInCubic,
            transitionBuilder: (Widget child, Animation<double> animation) {
              return FadeTransition(
                opacity: animation,
                child: SlideTransition(
                  position: Tween<Offset>(
                    begin: const Offset(0.0, 0.02),
                    end: Offset.zero,
                  ).animate(animation),
                  child: child,
                ),
              );
            },
            child: KeyedSubtree(
              key: ValueKey<int>(_selectedIndex),
              child: _getSelectedView(isSuperAdmin),
            ),
          ),
          bottomNavigationBar: _buildLiquidBottomNavBar(navItems),
        ),

        // Desktop & Tablet Layout: Sidebar Navigation Panel (Forest Emerald Green Gradient)
        desktop: Row(
          children: [
            Container(
              width: 260,
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFF064E3B), Color(0xFF022C22)],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
                border: Border(
                  right: BorderSide(color: Color(0xFF059669), width: 1),
                ),
              ),
              child: Column(
                children: [
                  // Full Size MKC Logo Header
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
                    alignment: Alignment.center,
                    child: Column(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            boxShadow: const [
                              BoxShadow(
                                color: Color(0x30022C22),
                                blurRadius: 8,
                                offset: Offset(0, 3),
                              ),
                            ],
                          ),
                          child: Image.asset(
                            'assets/full_mkc_logo.png',
                            height: 45,
                            fit: BoxFit.contain,
                            errorBuilder: (context, error, stackTrace) => const Icon(
                              Icons.apartment_rounded,
                              color: Color(0xFF059669),
                              size: 28,
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          AppConstants.appName,
                          style: GoogleFonts.poppins(
                            fontWeight: FontWeight.bold,
                            fontSize: 18,
                            color: Colors.white,
                          ),
                        ),
                        Text(
                          isSuperAdmin ? 'Super Admin' : 'Sub Admin',
                          style: GoogleFonts.poppins(
                            fontSize: 12,
                            color: const Color(0xFFA7F3D0),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Navigation Links List
                  Expanded(
                    child: ListView.builder(
                      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
                      itemCount: navItems.length,
                      itemBuilder: (context, index) {
                        final item = navItems[index];
                        final isSelected = _selectedIndex == index;

                        return Container(
                          margin: const EdgeInsets.only(bottom: 6),
                          decoration: isSelected
                              ? BoxDecoration(
                                  gradient: const LinearGradient(
                                    colors: [Color(0xFF10B981), Color(0xFF059669)],
                                  ),
                                  borderRadius: BorderRadius.circular(12),
                                  boxShadow: const [
                                    BoxShadow(
                                      color: Color(0x4010B981),
                                      blurRadius: 8,
                                      offset: Offset(0, 3),
                                    ),
                                  ],
                                )
                              : null,
                          child: ListTile(
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            leading: Icon(
                              isSelected ? item.activeIcon : item.icon,
                              color: isSelected ? Colors.white : const Color(0xFFA7F3D0),
                            ),
                            title: Text(
                              item.title,
                              style: GoogleFonts.poppins(
                                color: isSelected ? Colors.white : const Color(0xFFA7F3D0),
                                fontWeight: isSelected ? FontWeight.w900 : FontWeight.w700,
                                fontSize: 15,
                                letterSpacing: 0.3,
                              ),
                            ),
                            onTap: () => setState(() => _selectedIndex = index),
                          ),
                        );
                      },
                    ),
                  ),

                  // User Info Footer with Admin Profile Picture
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0x30000000),
                      border: Border(
                        top: BorderSide(color: const Color(0xFF059669).withValues(alpha: 0.3), width: 1),
                      ),
                    ),
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 20,
                          backgroundColor: const Color(0xFF10B981),
                          backgroundImage: hasProfilePic ? NetworkImage(profile.profilePicture!) : null,
                          child: !hasProfilePic
                              ? Text(
                                  profile?.name.isNotEmpty == true ? profile!.name[0].toUpperCase() : 'U',
                                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                                )
                              : null,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                profile?.name ?? 'User',
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.white),
                                overflow: TextOverflow.ellipsis,
                              ),
                              Text(
                                profile?.email ?? '',
                                style: const TextStyle(fontSize: 11, color: Color(0xFFA7F3D0)),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.logout_rounded, size: 20, color: Color(0xFFF87171)),
                          onPressed: () => authProvider.signOut(),
                          tooltip: 'Logout',
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // Main Content Body Area
            Expanded(
              child: _getSelectedView(isSuperAdmin),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLiquidBottomNavBar(List<NavItem> navItems) {
    final mobileIndices = [0, 1, 2, 5];
    final selectedBottomIndex = mobileIndices.indexOf(_selectedIndex);
    final activeIndex = selectedBottomIndex != -1 ? selectedBottomIndex : 0;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      margin: const EdgeInsets.only(left: 20, right: 20, bottom: 18, top: 4),
      height: 60,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(32),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: isDark
                    ? [
                        const Color(0xFF1E293B).withValues(alpha: 0.82),
                        const Color(0xFF0F172A).withValues(alpha: 0.78),
                      ]
                    : [
                        Colors.white.withValues(alpha: 0.82),
                        const Color(0xFFD1FAE5).withValues(alpha: 0.72),
                      ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(32),
              border: Border.all(
                color: isDark
                    ? const Color(0xFF334155).withValues(alpha: 0.8)
                    : const Color(0xFF10B981).withValues(alpha: 0.4),
                width: 1.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: isDark
                      ? const Color(0x60000000)
                      : const Color(0x3510B981),
                  blurRadius: 20,
                  spreadRadius: 2,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
              child: Stack(
                children: [
                  // Smooth Gliding Liquid Indicator Pill Background (Icon-only proportion)
                  AnimatedAlign(
                    duration: const Duration(milliseconds: 320),
                    curve: Curves.easeOutBack,
                    alignment: Alignment(-1.0 + (activeIndex * (2.0 / 3.0)), 0.0),
                    child: FractionallySizedBox(
                      widthFactor: 0.23,
                      heightFactor: 1.0,
                      child: Container(
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFF047857), Color(0xFF065F46)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(24),
                          boxShadow: const [
                            BoxShadow(
                              color: Color(0x50047857),
                              blurRadius: 10,
                              offset: Offset(0, 4),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),

                  // Interactive Pure Icon Layer (No text labels)
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: List.generate(mobileIndices.length, (index) {
                      final isSelected = activeIndex == index;
                      final item = navItems[mobileIndices[index]];

                      return Expanded(
                        child: Tooltip(
                          message: item.title,
                          child: GestureDetector(
                            onTap: () {
                              setState(() {
                                _selectedIndex = mobileIndices[index];
                              });
                            },
                            behavior: HitTestBehavior.opaque,
                            child: Center(
                              child: AnimatedScale(
                                duration: const Duration(milliseconds: 200),
                                scale: isSelected ? 1.15 : 1.0,
                                child: Icon(
                                  isSelected ? item.activeIcon : item.icon,
                                  size: 24,
                                  color: isSelected
                                      ? Colors.white
                                      : (isDark ? const Color(0xFF94A3B8) : const Color(0xFF047857)),
                                ),
                              ),
                            ),
                          ),
                        ),
                      );
                    }),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class NavItem {
  final String title;
  final IconData icon;
  final IconData activeIcon;

  NavItem({required this.title, required this.icon, required this.activeIcon});
}
