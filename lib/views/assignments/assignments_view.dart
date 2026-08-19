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

  @override
  Widget build(BuildContext context) {
    final isSuperAdmin = Provider.of<AuthProvider>(context).isSuperAdmin;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Guest Task Assignments'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _loadData),
        ],
      ),
      floatingActionButton: isSuperAdmin
          ? FloatingActionButton.extended(
              onPressed: _showNewAssignmentDialog,
              icon: const Icon(Icons.add),
              label: const Text('New Assignment'),
              backgroundColor: AppColors.primary,
            )
          : null,
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _assignments.isEmpty
              ? const Center(child: Text('No guest assignments found.', style: TextStyle(color: AppColors.textSecondary)))
              : RefreshIndicator(
                  onRefresh: _loadData,
                  child: ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _assignments.length,
                    itemBuilder: (context, index) {
                      final item = _assignments[index];
                      return Card(
                        margin: const EdgeInsets.only(bottom: 12),
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: item.isUrgent ? AppColors.danger : AppColors.primary,
                            child: Icon(item.isUrgent ? Icons.warning : Icons.assignment, color: Colors.white),
                          ),
                          title: Row(
                            children: [
                              Text(item.guestName, style: const TextStyle(fontWeight: FontWeight.bold)),
                              if (item.isUrgent) ...[
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(color: Colors.red.shade100, borderRadius: BorderRadius.circular(4)),
                                  child: const Text('URGENT', style: TextStyle(color: Colors.red, fontSize: 10, fontWeight: FontWeight.bold)),
                                ),
                              ],
                            ],
                          ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (item.notes != null && item.notes!.isNotEmpty) Text('Notes: ${item.notes}'),
                              Text(
                                'Assigned To: ${item.assignedToName ?? "Sub Admin"} | Status: ${item.status.toUpperCase()}',
                                style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                              ),
                            ],
                          ),
                          trailing: DropdownButton<String>(
                            value: item.status,
                            items: const [
                              DropdownMenuItem(value: 'pending', child: Text('Pending')),
                              DropdownMenuItem(value: 'in_progress', child: Text('In Progress')),
                              DropdownMenuItem(value: 'completed', child: Text('Completed')),
                            ],
                            onChanged: (newStatus) async {
                              if (newStatus != null) {
                                await AssignmentService.updateAssignmentStatus(item.id, newStatus);
                                _loadData();
                              }
                            },
                          ),
                        ),
                      );
                    },
                  ),
                ),
    );
  }
}
