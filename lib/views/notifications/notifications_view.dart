import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../config/constants.dart';
import '../../core/utils.dart';
import '../../models/app_notification.dart';
import '../../providers/auth_provider.dart';
import '../../services/notification_service.dart';
import '../../services/supabase_service.dart';
import '../assignments/assignments_view.dart';

class NotificationsView extends StatefulWidget {
  const NotificationsView({super.key});

  @override
  State<NotificationsView> createState() => _NotificationsViewState();
}

class _NotificationsViewState extends State<NotificationsView> {
  bool _isLoading = true;
  List<AppNotification> _notifications = [];

  @override
  void initState() {
    super.initState();
    _loadNotifications();
  }

  Future<void> _loadNotifications() async {
    final user = SupabaseService.currentUser;
    final isSuperAdmin = Provider.of<AuthProvider>(context, listen: false).isSuperAdmin;
    if (user == null) return;

    setState(() => _isLoading = true);
    try {
      final query = SupabaseService.client.from('app_notifications').select('*');
      
      final res = isSuperAdmin
          ? await query.order('created_at', ascending: false).limit(50)
          : await query.eq('user_id', user.id).order('created_at', ascending: false).limit(50);

      final list = (res as List).map((json) => AppNotification.fromJson(json)).toList();
      if (mounted) {
        setState(() {
          _notifications = list;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showAddRemarkDialog(AppNotification item) {
    final remarkController = TextEditingController();
    final superAdminName = Provider.of<AuthProvider>(context, listen: false).profile?.name ?? 'Super Admin';

    final List<String> quickRemarks = [
      '👍 Thank you! Great job!',
      '🌟 Excellent work!',
      '🙏 Thanks for the quick update!',
      '👍 Noted, proceed.',
    ];

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: Row(
                children: [
                  const Icon(Icons.comment_rounded, color: AppColors.primary, size: 24),
                  const SizedBox(width: 10),
                  const Expanded(child: Text('Add Remark / Thank Comment', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16))),
                ],
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Regarding: "${item.title}"', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    Text(item.message, style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                    const SizedBox(height: 14),
                    const Text('Quick Appreciation Comments:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: quickRemarks.map((qr) {
                        return ActionChip(
                          label: Text(qr, style: const TextStyle(fontSize: 11)),
                          onPressed: () => setDialogState(() => remarkController.text = qr),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: remarkController,
                      decoration: const InputDecoration(
                        labelText: 'Super Admin Remark *',
                        hintText: 'e.g. Thanking, great job, well done!',
                      ),
                      maxLines: 2,
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
                ElevatedButton.icon(
                  onPressed: () async {
                    final remark = remarkController.text.trim();
                    if (remark.isEmpty) {
                      AppUtils.showSnackBar(ctx, 'Please enter or select a remark', isError: true);
                      return;
                    }

                    await NotificationService.sendRemarkToSubAdmin(
                      subAdminUserId: item.userId,
                      remarkText: remark,
                      superAdminName: superAdminName,
                      taskName: item.title,
                    );

                    if (mounted) {
                      Navigator.pop(ctx);
                      NotificationService.showNotificationPopup(
                        context,
                        title: 'Remark Sent 💬',
                        message: 'Sent comment "$remark" to Sub Admin.',
                        icon: Icons.mark_chat_read_rounded,
                      );
                      _loadNotifications();
                    }
                  },
                  icon: const Icon(Icons.send_rounded, size: 16),
                  label: const Text('Send Remark'),
                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF059669), foregroundColor: Colors.white),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final isSuperAdmin = Provider.of<AuthProvider>(context).isSuperAdmin;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifications Centre'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadNotifications,
            tooltip: 'Refresh Notifications',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _notifications.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.notifications_off_outlined, size: 64, color: Colors.grey.shade400),
                      const SizedBox(height: 12),
                      const Text(
                        'No notifications found',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.textSecondary),
                      ),
                      const SizedBox(height: 4),
                      const Text('System activities and assignments will appear here.', style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _loadNotifications,
                  child: ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
                    itemCount: _notifications.length,
                    itemBuilder: (context, index) {
                      final item = _notifications[index];
                      final isUrgent = item.type == 'urgent';

                      return Card(
                        elevation: 2,
                        margin: const EdgeInsets.only(bottom: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(12),
                          onTap: () {
                            // If task assignment related, navigate to Assignments
                            if (item.title.contains('Task') ||
                                item.title.contains('Assignment') ||
                                item.title.contains('REMINDER') ||
                                item.title.contains('Accepted') ||
                                item.title.contains('REJECTED')) {
                              Navigator.push(
                                context,
                                MaterialPageRoute(builder: (_) => const AssignmentsView()),
                              );
                            }
                          },
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(10),
                                      decoration: BoxDecoration(
                                        color: (isUrgent ? AppColors.danger : AppColors.primary).withValues(alpha: 0.1),
                                        shape: BoxShape.circle,
                                      ),
                                      child: Icon(
                                        isUrgent ? Icons.error_outline_rounded : Icons.notifications_active_rounded,
                                        color: isUrgent ? AppColors.danger : AppColors.primary,
                                        size: 22,
                                      ),
                                    ),
                                    const SizedBox(width: 14),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                            children: [
                                              Expanded(
                                                child: Text(
                                                  item.title,
                                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                                                ),
                                              ),
                                              Text(
                                                AppUtils.formatDateTime(item.createdAt),
                                                style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            item.message,
                                            style: TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.onSurface, height: 1.3),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                                if (isSuperAdmin) ...[
                                  const SizedBox(height: 10),
                                  Align(
                                    alignment: Alignment.centerRight,
                                    child: OutlinedButton.icon(
                                      onPressed: () => _showAddRemarkDialog(item),
                                      icon: const Icon(Icons.comment_outlined, size: 14),
                                      label: const Text('Add Remark 💬', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                                      style: OutlinedButton.styleFrom(
                                        foregroundColor: const Color(0xFF059669),
                                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
    );
  }
}
