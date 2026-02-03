import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../data/services/api_service.dart';
import '../../../data/services/settings_service.dart';
import '../../widgets/app_drawer.dart';
import 'package:mobile/l10n/app_localizations.dart';

class UserListScreen extends StatefulWidget {
  const UserListScreen({super.key});

  @override
  State<UserListScreen> createState() => _UserListScreenState();
}

class _UserListScreenState extends State<UserListScreen> {
  late SettingsService _settingsService;
  List<dynamic> _users = [];
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _settingsService = SettingsService(
      Provider.of<ApiService>(context, listen: false),
    );
    _loadUsers();
  }

  Future<void> _loadUsers() async {
    setState(() => _isLoading = true);
    try {
      final users = await _settingsService.getUsers();
      if (mounted) setState(() => _users = users);
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showUserDialog([Map<String, dynamic>? user]) {
    final isEditing = user != null;
    final usernameCtrl = TextEditingController(text: user?['username']);
    final emailCtrl = TextEditingController(text: user?['email']);
    final passwordCtrl = TextEditingController();
    String role = user?['role'] ?? 'user';
    String status = user?['status'] ?? 'active';

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text(
            isEditing
                ? AppLocalizations.of(context)!.editUser
                : AppLocalizations.of(context)!.addUser,
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: usernameCtrl,
                  decoration: InputDecoration(
                    labelText: AppLocalizations.of(context)!.username,
                  ),
                  enabled: !isEditing,
                ),
                TextField(
                  controller: emailCtrl,
                  decoration: InputDecoration(
                    labelText: AppLocalizations.of(context)!.email,
                  ),
                ),
                TextField(
                  controller: passwordCtrl,
                  obscureText: true,
                  decoration: InputDecoration(
                    labelText: AppLocalizations.of(context)!.password,
                    helperText: isEditing
                        ? AppLocalizations.of(context)!.leaveBlankToKeep
                        : null,
                  ),
                ),
                DropdownButtonFormField<String>(
                  value: role,
                  decoration: InputDecoration(
                    labelText: AppLocalizations.of(context)!.role,
                  ),
                  items: [
                    DropdownMenuItem(
                      value: 'user',
                      child: Text(AppLocalizations.of(context)!.userRole),
                    ),
                    DropdownMenuItem(
                      value: 'admin',
                      child: Text(AppLocalizations.of(context)!.admin),
                    ),
                  ],
                  onChanged: (val) => setState(() => role = val!),
                ),
                if (isEditing)
                  DropdownButtonFormField<String>(
                    value: status,
                    decoration: InputDecoration(
                      labelText: AppLocalizations.of(context)!.status,
                    ),
                    items: [
                      DropdownMenuItem(
                        value: 'active',
                        child: Text(AppLocalizations.of(context)!.active),
                      ),
                      DropdownMenuItem(
                        value: 'disabled',
                        child: Text(AppLocalizations.of(context)!.disabled),
                      ),
                    ],
                    onChanged: (val) => setState(() => status = val!),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(AppLocalizations.of(context)!.cancel),
            ),
            ElevatedButton(
              onPressed: () async {
                final data = {
                  'username': usernameCtrl.text,
                  'email': emailCtrl.text,
                  'role': role,
                  'status': status,
                };
                if (!isEditing || passwordCtrl.text.isNotEmpty) {
                  data['password'] = passwordCtrl.text;
                }

                try {
                  if (isEditing) {
                    await _settingsService.updateUser(user['id'], data);
                  } else {
                    await _settingsService.createUser(data);
                  }
                  if (mounted) {
                    Navigator.pop(context);
                    _loadUsers();
                  }
                } catch (e) {
                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(SnackBar(content: Text('Error: $e')));
                }
              },
              child: Text(AppLocalizations.of(context)!.save),
            ),
          ],
        ),
      ),
    );
  }

  void _deleteUser(int id) async {
    try {
      await _settingsService.deleteUser(id);
      _loadUsers();
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(AppLocalizations.of(context)!.users)),
      drawer: const AppDrawer(),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showUserDialog(),
        child: const Icon(Icons.add),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView.builder(
              itemCount: _users.length,
              itemBuilder: (context, index) {
                final u = _users[index];
                return ListTile(
                  leading: CircleAvatar(
                    child: Text(u['username'][0].toUpperCase()),
                  ),
                  title: Text(u['username']),
                  subtitle: Text('${u['email']} (${u['role']})'),
                  trailing: PopupMenuButton(
                    itemBuilder: (context) => [
                      const PopupMenuItem(
                        value: 'edit',
                        child: Icon(Icons.edit, color: Colors.blue),
                      ),
                      const PopupMenuItem(
                        value: 'delete',
                        child: Icon(Icons.delete, color: Colors.red),
                      ),
                    ],
                    onSelected: (val) {
                      if (val == 'edit') _showUserDialog(u);
                      if (val == 'delete') _deleteUser(u['id']);
                    },
                  ),
                );
              },
            ),
    );
  }
}
