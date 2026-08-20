import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../config/constants.dart';
import '../../core/utils.dart';
import '../../models/profile.dart';
import '../../providers/auth_provider.dart';
import '../../services/supabase_service.dart';

class UserManagementView extends StatefulWidget {
  const UserManagementView({super.key});

  @override
  State<UserManagementView> createState() => _UserManagementViewState();
}

class _UserManagementViewState extends State<UserManagementView> {
  bool _isLoading = true;
  List<Profile> _users = [];

  @override
  void initState() {
    super.initState();
    _loadUsers();
  }

  Future<void> _loadUsers() async {
    setState(() => _isLoading = true);
    try {
      final list = await SupabaseService.getUsers();
      if (mounted) {
        setState(() {
          _users = list;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _toggleUserActive(Profile user) async {
    final newStatus = !user.isActive;
    await SupabaseService.updateProfile(user.id, {'is_active': newStatus});
    _loadUsers();
    AppUtils.showSnackBar(context, '${user.name} status updated');
  }

  // Open Create User Dialog (Super Admin)
  void _openCreateUserDialog() {
    final nameController = TextEditingController();
    final emailController = TextEditingController();
    final passwordController = TextEditingController();
    String role = 'sub_admin';

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Add New Sub Admin Account'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(controller: nameController, decoration: const InputDecoration(labelText: 'Full Name *')),
                  const SizedBox(height: 12),
                  TextField(controller: emailController, keyboardType: TextInputType.emailAddress, decoration: const InputDecoration(labelText: 'Email Address *')),
                  const SizedBox(height: 12),
                  TextField(controller: passwordController, obscureText: true, decoration: const InputDecoration(labelText: 'Password *')),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: role,
                    decoration: const InputDecoration(labelText: 'Role'),
                    items: const [
                      DropdownMenuItem(value: 'sub_admin', child: Text('Sub Admin')),
                      DropdownMenuItem(value: 'super_admin', child: Text('Super Admin')),
                    ],
                    onChanged: (val) => setDialogState(() => role = val ?? 'sub_admin'),
                  ),
                ],
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
                ElevatedButton(
                  onPressed: () async {
                    if (nameController.text.trim().isEmpty || emailController.text.trim().isEmpty || passwordController.text.isEmpty) {
                      AppUtils.showSnackBar(ctx, 'All fields are required', isError: true);
                      return;
                    }

                    try {
                      await SupabaseService.createAdminUser(
                        name: nameController.text.trim(),
                        email: emailController.text.trim(),
                        password: passwordController.text,
                        role: role,
                      );

                      if (mounted) {
                        Navigator.pop(ctx);
                        AppUtils.showSnackBar(
                          context,
                          'Admin user account created successfully!',
                          icon: Icons.person_add_alt_1_rounded,
                        );
                        _loadUsers();
                      }
                    } catch (e) {
                      String msg = e.toString();
                      if (msg.contains('Exception:')) {
                        msg = msg.replaceAll('Exception:', '').trim();
                      }
                      if (mounted) AppUtils.showSnackBar(ctx, msg, isError: true);
                    }
                  },
                  child: const Text('Create User'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // Open Edit User Dialog
  void _openEditUserDialog(Profile user) {
    final nameController = TextEditingController(text: user.name);
    String role = user.role;

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Text('Edit User: ${user.name}'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(controller: nameController, decoration: const InputDecoration(labelText: 'Full Name *')),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: role,
                    decoration: const InputDecoration(labelText: 'Role'),
                    items: const [
                      DropdownMenuItem(value: 'sub_admin', child: Text('Sub Admin')),
                      DropdownMenuItem(value: 'super_admin', child: Text('Super Admin')),
                    ],
                    onChanged: (val) => setDialogState(() => role = val ?? 'sub_admin'),
                  ),
                ],
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
                ElevatedButton(
                  onPressed: () async {
                    await SupabaseService.updateProfile(user.id, {
                      'name': nameController.text.trim(),
                      'role': role,
                    });
                    if (mounted) {
                      Navigator.pop(ctx);
                      AppUtils.showSnackBar(
                        context,
                        'User account updated successfully!',
                        icon: Icons.check_circle_rounded,
                      );
                      _loadUsers();
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

  // Delete User Confirmation Modal (Super Admin)
  void _deleteUser(Profile user) {
    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              const Icon(Icons.warning_amber_rounded, color: Colors.red, size: 26),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Delete Account',
                  style: TextStyle(fontWeight: FontWeight.bold, color: Colors.red.shade800),
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Are you sure you want to delete user account "${user.name}" (${user.email})?',
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
              ),
              const SizedBox(height: 10),
              const Text(
                'This action will permanently delete this admin account record.',
                style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            ElevatedButton.icon(
              onPressed: () async {
                try {
                  await SupabaseService.deleteUser(user.id);
                  if (mounted) {
                    Navigator.pop(ctx);
                    AppUtils.showSnackBar(
                      context,
                      'User account "${user.name}" deleted successfully!',
                      isError: true,
                      icon: Icons.delete_sweep_rounded,
                    );
                    _loadUsers();
                  }
                } catch (e) {
                  if (mounted) {
                    Navigator.pop(ctx);
                    AppUtils.showSnackBar(context, 'Failed to delete user: $e', isError: true);
                  }
                }
              },
              icon: const Icon(Icons.delete_forever_rounded, size: 18),
              label: const Text('Delete Account'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red.shade700,
                foregroundColor: Colors.white,
              ),
            ),
          ],
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
        title: const Text('User Management Panel'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _loadUsers),
          const SizedBox(width: 6),
        ],
      ),
      floatingActionButton: isSuperAdmin
          ? Padding(
              padding: const EdgeInsets.only(bottom: 75),
              child: FloatingActionButton.extended(
                onPressed: _openCreateUserDialog,
                icon: const Icon(Icons.person_add),
                label: const Text('Add Sub Admin', style: TextStyle(fontWeight: FontWeight.bold)),
                backgroundColor: AppColors.primary,
              ),
            )
          : null,
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
              itemCount: _users.length,
              itemBuilder: (context, index) {
                final u = _users[index];
                return Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                    side: BorderSide(color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0), width: 1),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            CircleAvatar(
                              radius: 22,
                              backgroundColor: u.isSuperAdmin ? const Color(0xFF059669) : const Color(0xFF4F46E5),
                              child: Text(
                                u.name.isNotEmpty ? u.name[0].toUpperCase() : 'U',
                                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    u.name,
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 15,
                                      color: Theme.of(context).colorScheme.onSurface,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    u.email,
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Switch(
                              value: u.isActive,
                              activeThumbColor: const Color(0xFF059669),
                              onChanged: (val) => _toggleUserActive(u),
                            ),
                          ],
                        ),
                        const Divider(height: 18),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: u.isSuperAdmin
                                    ? const Color(0xFF059669).withValues(alpha: 0.15)
                                    : const Color(0xFF4F46E5).withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                '${u.role.toUpperCase()}  •  ${u.isActive ? "ACTIVE" : "DISABLED"}',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: u.isSuperAdmin ? const Color(0xFF059669) : const Color(0xFF4F46E5),
                                ),
                              ),
                            ),
                            Row(
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.edit_outlined, color: Colors.orange, size: 20),
                                  onPressed: () => _openEditUserDialog(u),
                                  tooltip: 'Edit User',
                                  constraints: const BoxConstraints(),
                                  padding: const EdgeInsets.all(6),
                                ),
                                const SizedBox(width: 8),
                                IconButton(
                                  icon: const Icon(Icons.delete_outline_rounded, color: Colors.red, size: 20),
                                  onPressed: () => _deleteUser(u),
                                  tooltip: 'Delete User Account',
                                  constraints: const BoxConstraints(),
                                  padding: const EdgeInsets.all(6),
                                ),
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
    );
  }
}
