import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_state.dart';
import '../utils/translation.dart';

class UserManagementScreen extends StatefulWidget {
  const UserManagementScreen({super.key});

  @override
  State<UserManagementScreen> createState() => _UserManagementScreenState();
}

class _UserManagementScreenState extends State<UserManagementScreen> {
  List<Map<String, dynamic>> _users = [];
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadUsers();
  }

  Future<void> _loadUsers() async {
    setState(() => _isLoading = true);
    final state = context.read<AppState>();
    final data = await state.getUsers();
    setState(() {
      _users = data;
      _isLoading = false;
    });
  }

  void _showAddEditUserDialog([Map<String, dynamic>? user]) {
    final isEdit = user != null;
    final usernameController = TextEditingController(text: isEdit ? user['username'] : '');
    final passwordController = TextEditingController();
    final displayNameController = TextEditingController(text: isEdit ? user['display_name'] : '');
    final emailController = TextEditingController(text: isEdit ? user['email'] : '');
    String role = isEdit ? (user['role'] ?? 'user') : 'user';

    showDialog(
      context: context,
      builder: (ctx) {
        final state = Provider.of<AppState>(context, listen: false);
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Text(isEdit
                  ? Translation.getText(state.locale, 'user.editUser')
                  : Translation.getText(state.locale, 'user.addUser')),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: usernameController,
                      enabled: !isEdit,
                      decoration: InputDecoration(
                        labelText: Translation.getText(state.locale, 'user.username'),
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (!isEdit) ...[
                      TextField(
                        controller: passwordController,
                        obscureText: true,
                        decoration: InputDecoration(
                          labelText: Translation.getText(state.locale, 'auth.password'),
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                    TextField(
                      controller: displayNameController,
                      decoration: InputDecoration(
                        labelText: Translation.getText(state.locale, 'user.displayName'),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: emailController,
                      decoration: InputDecoration(
                        labelText: Translation.getText(state.locale, 'user.email'),
                      ),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      value: role,
                      decoration: InputDecoration(
                        labelText: Translation.getText(state.locale, 'user.role'),
                      ),
                      items: [
                        DropdownMenuItem(
                          value: 'admin',
                          child: Text(Translation.getText(state.locale, 'user.admin')),
                        ),
                        DropdownMenuItem(
                          value: 'user',
                          child: Text(Translation.getText(state.locale, 'user.user')),
                        ),
                      ],
                      onChanged: (val) {
                        if (val != null) {
                          setDialogState(() => role = val);
                        }
                      },
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: Text(Translation.getText(state.locale, 'common.cancel')),
                ),
                ElevatedButton(
                  onPressed: () async {
                    final username = usernameController.text.trim();
                    final password = passwordController.text.trim();
                    final displayName = displayNameController.text.trim();
                    final email = emailController.text.trim();

                    if (username.isEmpty || (!isEdit && password.isEmpty)) return;

                    Navigator.pop(ctx);
                    final userData = {
                      'username': username,
                      if (!isEdit) 'password': password,
                      'display_name': displayName,
                      'email': email,
                      'role': role,
                    };

                    bool success;
                    if (isEdit) {
                      success = await state.updateUser(user['id'] as int, userData);
                    } else {
                      success = await state.createUser(userData);
                    }

                    if (success) {
                      _loadUsers();
                    }
                  },
                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFF5C35)),
                  child: Text(Translation.getText(state.locale, 'common.confirm')),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _confirmDelete(Map<String, dynamic> user) {
    showDialog(
      context: context,
      builder: (ctx) {
        final state = Provider.of<AppState>(context, listen: false);
        return AlertDialog(
          title: Text(Translation.getText(state.locale, 'common.confirmDelete')),
          content: Text('${user['username']}?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(Translation.getText(state.locale, 'common.cancel')),
            ),
            ElevatedButton(
              onPressed: () async {
                Navigator.pop(ctx);
                final success = await state.deleteUser(user['id'] as int);
                if (success) {
                  _loadUsers();
                }
              },
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              child: Text(Translation.getText(state.locale, 'common.confirm')),
            ),
          ],
        );
      },
    );
  }

  void _resetPassword(Map<String, dynamic> user) {
    showDialog(
      context: context,
      builder: (ctx) {
        final state = Provider.of<AppState>(context, listen: false);
        return AlertDialog(
          title: Text(Translation.getText(state.locale, 'common.warning')),
          content: Text('Are you sure to reset password for "${user['username']}"?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(Translation.getText(state.locale, 'common.cancel')),
            ),
            ElevatedButton(
              onPressed: () async {
                Navigator.pop(ctx);
                final success = await state.resetUserPassword(user['id'] as int);
                if (success && mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Password reset successful. Check system logs for details.')),
                  );
                }
              },
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFF5C35)),
              child: Text(Translation.getText(state.locale, 'common.confirm')),
            ),
          ],
        );
      },
    );
  }

  void _toggleStatus(Map<String, dynamic> user, bool currentStatus) async {
    final state = context.read<AppState>();
    final success = await state.toggleUserStatus(user['id'] as int, !currentStatus);
    if (success) {
      _loadUsers();
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = Provider.of<AppState>(context);

    return Scaffold(
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            color: Theme.of(context).cardColor,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  Translation.getText(state.locale, 'user.title'),
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                ),
                Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.refresh, size: 20),
                      onPressed: _loadUsers,
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton.icon(
                      onPressed: () => _showAddEditUserDialog(),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFFF5C35),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      ),
                      icon: const Icon(Icons.add, size: 16, color: Colors.black87),
                      label: Text(
                        Translation.getText(state.locale, 'user.addUser'),
                        style: const TextStyle(color: Colors.black87, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _users.isEmpty
                    ? Center(
                        child: Text(
                          Translation.getText(state.locale, 'sftp.emptyFolder'),
                          style: const TextStyle(color: Colors.grey),
                        ),
                      )
                    : ListView.builder(
                        itemCount: _users.length,
                        padding: const EdgeInsets.all(8.0),
                        itemBuilder: (ctx, idx) {
                          final user = _users[idx];
                          final isAdminRole = user['role'] == 'admin';
                          final isActive = user['is_active'] == true || user['status'] == 'active';

                          return Card(
                            margin: const EdgeInsets.symmetric(vertical: 6),
                            child: Padding(
                              padding: const EdgeInsets.all(8.0),
                              child: Row(
                                children: [
                                  CircleAvatar(
                                    backgroundColor: isAdminRole
                                        ? const Color(0xFFFF5C35).withOpacity(0.2)
                                        : Colors.grey.withOpacity(0.2),
                                    child: Icon(
                                      isAdminRole ? Icons.admin_panel_settings : Icons.person,
                                      color: isAdminRole ? const Color(0xFFFF5C35) : Colors.grey,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Text(
                                              user['username'] ?? '',
                                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                                            ),
                                            const SizedBox(width: 8),
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                              decoration: BoxDecoration(
                                                color: isAdminRole
                                                    ? const Color(0xFFFF5C35).withOpacity(0.2)
                                                    : Colors.grey.withOpacity(0.2),
                                                borderRadius: BorderRadius.circular(4),
                                                border: Border.all(
                                                  color: isAdminRole ? const Color(0xFFFF5C35) : Colors.grey,
                                                  width: 0.5,
                                                ),
                                              ),
                                              child: Text(
                                                isAdminRole
                                                    ? Translation.getText(state.locale, 'user.admin')
                                                    : Translation.getText(state.locale, 'user.user'),
                                                style: TextStyle(
                                                  fontSize: 9,
                                                  color: isAdminRole ? const Color(0xFFFF5C35) : Colors.grey,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                        Text(
                                          user['display_name'] ?? '',
                                          style: const TextStyle(fontSize: 11, color: Colors.white70),
                                        ),
                                        Text(
                                          user['email'] ?? '',
                                          style: const TextStyle(fontSize: 10, color: Colors.grey),
                                        ),
                                      ],
                                    ),
                                  ),
                                  // Switch for toggling status
                                  Switch(
                                    value: isActive,
                                    activeColor: const Color(0xFF2ED573),
                                    onChanged: (v) => _toggleStatus(user, isActive),
                                  ),
                                  // Actions dropdown menu
                                  PopupMenuButton<String>(
                                    onSelected: (val) {
                                      if (val == 'edit') {
                                        _showAddEditUserDialog(user);
                                      } else if (val == 'reset') {
                                        _resetPassword(user);
                                      } else if (val == 'delete') {
                                        _confirmDelete(user);
                                      }
                                    },
                                    itemBuilder: (c) => [
                                      PopupMenuItem(
                                        value: 'edit',
                                        child: Row(
                                          children: [
                                            const Icon(Icons.edit, size: 18),
                                            const SizedBox(width: 8),
                                            Text(Translation.getText(state.locale, 'common.edit')),
                                          ],
                                        ),
                                      ),
                                      PopupMenuItem(
                                        value: 'reset',
                                        child: Row(
                                          children: [
                                            const Icon(Icons.lock_reset, size: 18),
                                            const SizedBox(width: 8),
                                            Text(Translation.getText(state.locale, 'user.deleteUser') != 'Delete' ? '閲嶇疆瀵嗙爜' : 'Reset PW'),
                                          ],
                                        ),
                                      ),
                                      PopupMenuItem(
                                        value: 'delete',
                                        child: Row(
                                          children: [
                                            const Icon(Icons.delete, color: Colors.redAccent, size: 18),
                                            const SizedBox(width: 8),
                                            Text(Translation.getText(state.locale, 'common.delete'), style: const TextStyle(color: Colors.redAccent)),
                                          ],
                                        ),
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
        ],
      ),
    );
  }
}
