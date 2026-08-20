import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../config/constants.dart';
import '../../core/utils.dart';
import '../../models/guest_assignment.dart';
import '../../models/profile.dart';
import '../../providers/auth_provider.dart';
import '../../services/assignment_service.dart';
import '../../services/notification_service.dart';
import '../../services/supabase_service.dart';

class AssignmentsView extends StatefulWidget {
  const AssignmentsView({super.key});

  @override
  State<AssignmentsView> createState() => _AssignmentsViewState();
}

class _AssignmentsViewState extends State<AssignmentsView> {
  bool _isLoading = true;
  List<GuestAssignment> _assignments = [];
  List<Profile> _subAdmins = [];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final isSuperAdmin = authProvider.isSuperAdmin;

    setState(() => _isLoading = true);
    try {
      final list = await AssignmentService.getAssignments(isSuperAdmin);
      if (isSuperAdmin) {
        final users = await SupabaseService.getUsers();
        _subAdmins = users.where((u) => u.role == 'sub_admin').toList();
      }
      if (mounted) {
        setState(() {
          _assignments = list;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showNewAssignmentDialog() {
    final guestNameController = TextEditingController();
    final notesController = TextEditingController();
    String? selectedSubAdminId;
    bool isUrgent = false;

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Assign Guest Task'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: guestNameController,
                      decoration: const InputDecoration(labelText: 'Guest Name *'),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      value: selectedSubAdminId,
                      decoration: const InputDecoration(labelText: 'Assign To (Sub Admin) *'),
                      items: _subAdmins.map((u) {
                        return DropdownMenuItem(value: u.id, child: Text(u.name));
                      }).toList(),
                      onChanged: (val) => setDialogState(() => selectedSubAdminId = val),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: notesController,
                      decoration: const InputDecoration(labelText: 'Notes / Instructions'),
                      maxLines: 2,
                    ),
                    const SizedBox(height: 12),
                    CheckboxListTile(
                      title: const Text('Mark as Urgent 🚨'),
                      value: isUrgent,
                      onChanged: (val) => setDialogState(() => isUrgent = val ?? false),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
                ElevatedButton(
                  onPressed: () async {
                    final taskName = guestNameController.text.trim();
                    final assignedToProfile = _subAdmins.firstWhere(
                      (u) => u.id == selectedSubAdminId,
                      orElse: () => Profile(id: selectedSubAdminId!, name: 'Sub Admin', email: '', role: 'sub_admin', isActive: true, createdAt: DateTime.now()),
                    );

                    await AssignmentService.createAssignment(
                      guestName: taskName,
                      notes: notesController.text.trim(),
                      assignedTo: selectedSubAdminId!,
                      isUrgent: isUrgent,
                    );

                    final creatorName = Provider.of<AuthProvider>(context, listen: false).profile?.name ?? 'Super Admin';

                    if (mounted) {
                      // Show loud popup notification banner with sound
                      NotificationService.showNotificationPopup(
                        context,
                        title: isUrgent ? 'Urgent Assignment Sent 🚨' : 'Task Assigned Successfully!',
                        message: 'Assigned "$taskName" to ${assignedToProfile.name}.',
                        icon: Icons.assignment_ind_rounded,
                      );

                      // Save notification in database for Notification Centre
                      NotificationService.notifyAssignmentCreated(
                        assignedUserId: selectedSubAdminId!,
                        assignmentTitle: taskName,
                        assignedByName: creatorName,
                      );

                      Navigator.pop(ctx);
                      _loadData();
                    }
                  },
                  child: const Text('Assign Task'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // Send Reminder (Super Admin)
  Future<void> _sendReminder(GuestAssignment item) async {
    final creatorName = Provider.of<AuthProvider>(context, listen: false).profile?.name ?? 'Super Admin';
    await AssignmentService.sendReminder(
      assignmentId: item.id,
      guestName: item.guestName,
      assignedTo: item.assignedTo,
      assignedByName: creatorName,
    );

    if (mounted) {
      NotificationService.showNotificationPopup(
        context,
        title: 'Reminder Sent 🔔',
        message: 'Sent reminder to ${item.assignedToName ?? "Sub Admin"} for "${item.guestName}".',
        icon: Icons.notifications_active_rounded,
      );
    }
  }

  // Accept Task Dialog (In Progress or Waiting for Guest)
  void _showAcceptTaskDialog(GuestAssignment item) {
    String subStatus = 'in_progress';

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: Row(
                children: [
                  const Icon(Icons.check_circle_outline_rounded, color: Color(0xFF059669), size: 26),
                  const SizedBox(width: 10),
                  const Expanded(child: Text('Accept Guest Task', style: TextStyle(fontWeight: FontWeight.bold))),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Task for: "${item.guestName}"', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                  const SizedBox(height: 14),
                  const Text('Select initial task status:', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  RadioListTile<String>(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('In Progress ⏳', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                    subtitle: const Text('Currently actively handling this guest request', style: TextStyle(fontSize: 11)),
                    value: 'in_progress',
                    groupValue: subStatus,
                    onChanged: (val) => setDialogState(() => subStatus = val!),
                  ),
                  RadioListTile<String>(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Waiting for Guest 🛋️', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                    subtitle: const Text('Guest has not arrived yet / waiting for arrival', style: TextStyle(fontSize: 11)),
                    value: 'waiting_for_guest',
                    groupValue: subStatus,
                    onChanged: (val) => setDialogState(() => subStatus = val!),
                  ),
                ],
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
                ElevatedButton(
                  onPressed: () async {
                    final adminName = Provider.of<AuthProvider>(context, listen: false).profile?.name ?? 'Admin';
                    await AssignmentService.acceptAssignment(
                      assignmentId: item.id,
                      subStatus: subStatus,
                      guestName: item.guestName,
                      assignedBy: item.assignedBy,
                      subAdminName: adminName,
                    );
                    if (mounted) {
                      Navigator.pop(ctx);
                      NotificationService.showNotificationPopup(
                        context,
                        title: 'Task Accepted!',
                        message: 'Status updated to ${subStatus == "waiting_for_guest" ? "Waiting for Guest" : "In Progress"}.',
                        icon: Icons.check_circle_rounded,
                      );
                      _loadData();
                    }
                  },
                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF059669), foregroundColor: Colors.white),
                  child: const Text('Confirm Accept'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // Reject Task Dialog (Collects Reason)
  void _showRejectTaskDialog(GuestAssignment item) {
    final reasonController = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              const Icon(Icons.cancel_outlined, color: Colors.red, size: 26),
              const SizedBox(width: 10),
              const Expanded(child: Text('Reject Guest Task', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.red))),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Task for: "${item.guestName}"', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
              const SizedBox(height: 12),
              TextField(
                controller: reasonController,
                decoration: const InputDecoration(
                  labelText: 'Reason for Rejection *',
                  hintText: 'e.g. Out of office, assigned to wrong department...',
                ),
                maxLines: 3,
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () async {
                final reason = reasonController.text.trim();
                if (reason.isEmpty) {
                  AppUtils.showSnackBar(ctx, 'Please enter a rejection reason', isError: true);
                  return;
                }

                final adminName = Provider.of<AuthProvider>(context, listen: false).profile?.name ?? 'Admin';
                await AssignmentService.rejectAssignment(
                  assignmentId: item.id,
                  reason: reason,
                  guestName: item.guestName,
                  assignedBy: item.assignedBy,
                  subAdminName: adminName,
                );
                if (mounted) {
                  Navigator.pop(ctx);
                  NotificationService.showNotificationPopup(
                    context,
                    title: 'Task Rejected',
                    message: 'Rejection reason sent to Super Admin.',
                    isError: true,
                    icon: Icons.cancel_rounded,
                  );
                  _loadData();
                }
              },
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red.shade700, foregroundColor: Colors.white),
              child: const Text('Confirm Reject'),
            ),
          ],
        );
      },
    );
  }

  // Save Guest Entry & Complete Assignment Dialog
  void _showSaveGuestAndCompleteDialog(GuestAssignment item) {
    final nameController = TextEditingController(text: item.guestName);
    final phoneController = TextEditingController();
    final occupationController = TextEditingController();
    final placeController = TextEditingController();
    final purposeController = TextEditingController(text: item.notes ?? '');
    final donationController = TextEditingController();
    final receiptController = TextEditingController();
    String? selectedDistrict = 'Kozhikode';
    String? selectedState = 'Kerala';
    String? selectedCountry = 'India';

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: Row(
                children: [
                  const Icon(Icons.task_alt_rounded, color: Color(0xFF059669), size: 26),
                  const SizedBox(width: 10),
                  const Expanded(child: Text('Save Guest Data & Complete', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16))),
                ],
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'Enter guest visit details below. This will save the record into Guest Records and mark the task as completed.',
                      style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
                    ),
                    const SizedBox(height: 14),
                    TextField(controller: nameController, decoration: const InputDecoration(labelText: 'Guest Name *', prefixIcon: Icon(Icons.person))),
                    const SizedBox(height: 10),
                    TextField(controller: phoneController, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'Phone Number', prefixIcon: Icon(Icons.phone))),
                    const SizedBox(height: 10),
                    TextField(controller: occupationController, decoration: const InputDecoration(labelText: 'Occupation', prefixIcon: Icon(Icons.work_outline))),
                    const SizedBox(height: 10),
                    TextField(controller: placeController, decoration: const InputDecoration(labelText: 'Address / Place Name *', prefixIcon: Icon(Icons.location_on_outlined))),
                    const SizedBox(height: 10),
                    DropdownButtonFormField<String>(
                      value: selectedDistrict,
                      decoration: const InputDecoration(labelText: 'District *', prefixIcon: Icon(Icons.map_outlined)),
                      items: (AppConstants.districtsByState['Kerala'] ?? ['Kozhikode']).map((d) => DropdownMenuItem(value: d, child: Text(d))).toList(),
                      onChanged: (val) => setDialogState(() => selectedDistrict = val),
                    ),
                    const SizedBox(height: 10),
                    TextField(controller: purposeController, decoration: const InputDecoration(labelText: 'Purpose of Visit *', prefixIcon: Icon(Icons.flag_outlined))),
                    const SizedBox(height: 10),
                    TextField(controller: donationController, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Donation Amount (₹)', prefixIcon: Icon(Icons.currency_rupee))),
                    const SizedBox(height: 10),
                    TextField(controller: receiptController, decoration: const InputDecoration(labelText: 'Receipt No', prefixIcon: Icon(Icons.receipt_long_outlined))),
                  ],
                ),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
                ElevatedButton.icon(
                  onPressed: () async {
                    final guestName = nameController.text.trim();
                    final place = placeController.text.trim();
                    final purpose = purposeController.text.trim();

                    if (guestName.isEmpty || place.isEmpty || purpose.isEmpty) {
                      AppUtils.showSnackBar(ctx, 'Guest Name, Place, and Purpose are required!', isError: true);
                      return;
                    }

                    final currentUser = SupabaseService.currentUser;
                    final adminName = Provider.of<AuthProvider>(context, listen: false).profile?.name ?? 'Admin';

                    final guestData = {
                      'guest_name': guestName,
                      'phone_number': phoneController.text.trim(),
                      'occupation': occupationController.text.trim(),
                      'place': place,
                      'district': selectedDistrict ?? 'Kozhikode',
                      'state': selectedState ?? 'Kerala',
                      'country': selectedCountry ?? 'India',
                      'purpose': purpose,
                      'donation_amount': double.tryParse(donationController.text.trim()) ?? 0.0,
                      'receipt_no': receiptController.text.trim(),
                      'created_by': currentUser?.id,
                      'handled_by': adminName,
                      'created_at': DateTime.now().toIso8601String(),
                    };

                    await AssignmentService.completeAssignmentWithGuestData(
                      assignmentId: item.id,
                      guestData: guestData,
                      assignedBy: item.assignedBy,
                      adminName: adminName,
                    );

                    if (mounted) {
                      Navigator.pop(ctx);
                      NotificationService.showNotificationPopup(
                        context,
                        title: 'Task Completed & Saved! 🎉',
                        message: 'Guest "$guestName" has been added to Guest Records and task completed.',
                        icon: Icons.check_circle_rounded,
                      );
                      _loadData();
                    }
                  },
                  icon: const Icon(Icons.save_rounded, size: 18),
                  label: const Text('Save & Complete Task'),
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
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Guest Task Assignments'),
        actions: [
          ElevatedButton.icon(
            onPressed: _showNewAssignmentDialog,
            icon: const Icon(Icons.add, size: 16),
            label: const Text('Assign Task', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF059669),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
          ),
          const SizedBox(width: 6),
          IconButton(icon: const Icon(Icons.refresh), onPressed: _loadData),
          const SizedBox(width: 6),
        ],
      ),
      floatingActionButton: Padding(
        padding: const EdgeInsets.only(bottom: 75),
        child: FloatingActionButton.extended(
          onPressed: _showNewAssignmentDialog,
          icon: const Icon(Icons.add),
          label: const Text('New Assignment', style: TextStyle(fontWeight: FontWeight.bold)),
          backgroundColor: AppColors.primary,
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _assignments.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.assignment_ind_outlined, size: 64, color: AppColors.primary),
                        const SizedBox(height: 16),
                        Text(
                          'No guest assignments found.',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Theme.of(context).colorScheme.onSurface,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Assign tasks and follow-ups to admin team members.',
                          style: TextStyle(
                            fontSize: 13,
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 20),
                        ElevatedButton.icon(
                          onPressed: _showNewAssignmentDialog,
                          icon: const Icon(Icons.add, size: 18),
                          label: const Text('Assign New Task', style: TextStyle(fontWeight: FontWeight.bold)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF059669),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _loadData,
                  child: ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
                    itemCount: _assignments.length,
                    itemBuilder: (context, index) {
                      final item = _assignments[index];
                      final isCompleted = item.status == 'completed';
                      final isRejected = item.status == 'rejected';
                      final isWaiting = item.status == 'waiting_for_guest';
                      final isInProgress = item.status == 'in_progress';

                      Color statusColor = Colors.orange;
                      String statusBadgeText = 'PENDING RESPONSE';
                      if (isInProgress) {
                        statusColor = Colors.blue;
                        statusBadgeText = 'IN PROGRESS ⏳';
                      } else if (isWaiting) {
                        statusColor = Colors.purple;
                        statusBadgeText = 'WAITING FOR GUEST 🛋️';
                      } else if (isRejected) {
                        statusColor = Colors.red;
                        statusBadgeText = 'REJECTED ❌';
                      } else if (isCompleted) {
                        statusColor = const Color(0xFF059669);
                        statusBadgeText = 'COMPLETED ✅';
                      }

                      return Card(
                        margin: const EdgeInsets.only(bottom: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                          side: BorderSide(color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0), width: 1),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(14),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Top Row: Guest Name, Urgent Badge, Status Badge
                              Row(
                                children: [
                                  CircleAvatar(
                                    radius: 20,
                                    backgroundColor: item.isUrgent ? AppColors.danger : AppColors.primary,
                                    child: Icon(item.isUrgent ? Icons.warning_amber_rounded : Icons.assignment_ind_rounded, color: Colors.white, size: 20),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Expanded(
                                              child: Text(
                                                item.guestName,
                                                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Theme.of(context).colorScheme.onSurface),
                                              ),
                                            ),
                                            if (item.isUrgent) ...[
                                              const SizedBox(width: 6),
                                              Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                decoration: BoxDecoration(color: Colors.red.shade100, borderRadius: BorderRadius.circular(4)),
                                                child: const Text('URGENT 🚨', style: TextStyle(color: Colors.red, fontSize: 10, fontWeight: FontWeight.bold)),
                                              ),
                                            ],
                                          ],
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          'Assigned To: ${item.assignedToName ?? "Sub Admin"}  •  By: ${item.assignedByName ?? "Super Admin"}',
                                          style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                              if (item.notes != null && item.notes!.isNotEmpty) ...[
                                const SizedBox(height: 10),
                                Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF8FAFC),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text('Notes: ${item.notes}', style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurface)),
                                ),
                              ],

                              if (isRejected && item.rejectionReason != null) ...[
                                const SizedBox(height: 10),
                                Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: Colors.red.withValues(alpha: 0.1),
                                    border: Border.all(color: Colors.red.shade300),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text('Rejection Reason: "${item.rejectionReason}"', style: const TextStyle(fontSize: 12, color: Colors.red, fontWeight: FontWeight.bold)),
                                ),
                              ],

                              const SizedBox(height: 12),
                              const Divider(height: 1),
                              const SizedBox(height: 10),

                              // Bottom Row: Status Badge & Action Controls (Accept, Reject, Reminder, Save & Complete)
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                alignment: WrapAlignment.spaceBetween,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: statusColor.withValues(alpha: 0.15),
                                      borderRadius: BorderRadius.circular(6),
                                      border: Border.all(color: statusColor.withValues(alpha: 0.4)),
                                    ),
                                    child: Text(
                                      statusBadgeText,
                                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: statusColor),
                                    ),
                                  ),
                                  Wrap(
                                    spacing: 6,
                                    runSpacing: 6,
                                    children: [
                                      // Super Admin Reminder Button
                                      if (isSuperAdmin && !isCompleted)
                                        OutlinedButton.icon(
                                          onPressed: () => _sendReminder(item),
                                          icon: const Icon(Icons.notifications_active_outlined, size: 14),
                                          label: const Text('Send Reminder 🔔', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                                          style: OutlinedButton.styleFrom(
                                            foregroundColor: Colors.orange.shade700,
                                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                          ),
                                        ),

                                      // Sub Admin / Admin Response Buttons (Accept, Reject, Save & Complete)
                                      if (!isCompleted && !isRejected) ...[
                                        ElevatedButton.icon(
                                          onPressed: () => _showAcceptTaskDialog(item),
                                          icon: const Icon(Icons.thumb_up_outlined, size: 14),
                                          label: const Text('Accept', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: const Color(0xFF059669),
                                            foregroundColor: Colors.white,
                                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                          ),
                                        ),
                                        OutlinedButton.icon(
                                          onPressed: () => _showRejectTaskDialog(item),
                                          icon: const Icon(Icons.thumb_down_outlined, size: 14),
                                          label: const Text('Reject', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                                          style: OutlinedButton.styleFrom(
                                            foregroundColor: Colors.red,
                                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                          ),
                                        ),
                                        ElevatedButton.icon(
                                          onPressed: () => _showSaveGuestAndCompleteDialog(item),
                                          icon: const Icon(Icons.save_as_rounded, size: 14),
                                          label: const Text('Save & Complete', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: const Color(0xFF4F46E5),
                                            foregroundColor: Colors.white,
                                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
    );
  }
}
