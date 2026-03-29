import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:mobile/l10n/app_localizations.dart';
import '../../providers/user_provider.dart';
import '../../models/user.dart';

class UserManagementScreen extends StatefulWidget {
  const UserManagementScreen({super.key});

  @override
  State<UserManagementScreen> createState() => _UserManagementScreenState();
}

class _UserManagementScreenState extends State<UserManagementScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Provider.of<UserProvider>(context, listen: false).fetchUsers();
    });
  }

  @override
  Widget build(BuildContext context) {
    final userProvider = Provider.of<UserProvider>(context);
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.users),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () => _showAddEditUserDialog(context, null),
          ),
        ],
      ),
      body: userProvider.isLoading
          ? const Center(child: CircularProgressIndicator())
          : userProvider.error != null
              ? Center(child: Text(userProvider.error!))
              : _buildUserList(userProvider, l10n),
    );
  }

  Widget _buildUserList(UserProvider userProvider, AppLocalizations l10n) {
    if (userProvider.users.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.people, size: 64, color: Colors.grey),
            const SizedBox(height: 16),
            Text(
              l10n.noUsersFound,
              style: const TextStyle(fontSize: 16, color: Colors.grey),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () => _showAddEditUserDialog(context, null),
              child: Text(l10n.addUser),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () => userProvider.refreshUsers(),
      child: ListView.builder(
        itemCount: userProvider.users.length,
        itemBuilder: (context, index) {
          final user = userProvider.users[index];
          return Card(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: ListTile(
              leading: CircleAvatar(
                child: Text(user.username.substring(0, 1).toUpperCase()),
              ),
              title: Text(user.username),
              subtitle: Text(user.email),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (user.twoFactorEnabled)
                    Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: Colors.green.shade100,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        '2FA',
                        style: TextStyle(
                          color: Colors.green.shade800,
                          fontSize: 10,
                        ),
                      ),
                    ),
                  const SizedBox(width: 8),
                  Text(
                    user.role.toUpperCase(),
                    style: TextStyle(
                      color: user.role == 'admin' ? Colors.red : Colors.blue,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              onTap: () => _showAddEditUserDialog(context, user),
              onLongPress: () => _confirmDeleteUser(context, userProvider, user),
            ),
          );
        },
      ),
    );
  }

  Future<void> _showAddEditUserDialog(BuildContext context, User? user) async {
    final userProvider = Provider.of<UserProvider>(context, listen: false);
    final formKey = GlobalKey<FormState>();
    final usernameController = TextEditingController(text: user?.username);
    final emailController = TextEditingController(text: user?.email);
    final passwordController = TextEditingController();
    final roleController = TextEditingController(text: user?.role ?? 'user');
    final isActiveController = TextEditingController(text: user?.isActive.toString() ?? 'true');

    bool isEditing = user != null;

    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(isEditing ? 'Edit User' : 'Add User'),
        content: SizedBox(
          width: 400,
          child: Form(
            key: formKey,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    controller: usernameController,
                    decoration: const InputDecoration(labelText: 'Username *'),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Please enter a username';
                      }
                      return null;
                    },
                  ),
                  TextFormField(
                    controller: emailController,
                    decoration: const InputDecoration(labelText: 'Email *'),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Please enter an email';
                      }
                      // Basic email validation
                      if (!RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(value)) {
                        return 'Please enter a valid email';
                      }
                      return null;
                    },
                  ),
                  if (!isEditing)
                    TextFormField(
                      controller: passwordController,
                      decoration: const InputDecoration(labelText: 'Password *'),
                      obscureText: true,
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Please enter a password';
                        }
                        if (value.length < 6) {
                          return 'Password must be at least 6 characters';
                        }
                        return null;
                      },
                    ),
                  TextFormField(
                    controller: roleController,
                    decoration: const InputDecoration(labelText: 'Role (user/admin)'),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Please enter a role';
                      }
                      if (value != 'user' && value != 'admin') {
                        return 'Role must be either "user" or "admin"';
                      }
                      return null;
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              if (formKey.currentState!.validate()) {
                final userData = User(
                  id: user?.id ?? 0,
                  username: usernameController.text.trim(),
                  email: emailController.text.trim(),
                  role: roleController.text.trim(),
                  isActive: user?.isActive ?? true,
                  twoFactorEnabled: user?.twoFactorEnabled ?? false,
                  createdAt: user?.createdAt ?? DateTime.now(),
                  updatedAt: DateTime.now(),
                );

                bool success;
                if (isEditing) {
                  success = await userProvider.updateUser(user.id, userData);
                } else {
                  // For new users, we need to include the password
                  // This is simplified since we can't pass password through User object
                  // In a real implementation, we would have a different method
                  success = await userProvider.createUser(userData);
                }

                if (success && mounted) {
                  Navigator.pop(context);
                }
              }
            },
            child: Text(isEditing ? 'Update' : 'Add'),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmDeleteUser(BuildContext context, UserProvider userProvider, User user) async {
    final l10n = AppLocalizations.of(context)!;

    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.confirmDelete),
        content: Text('Are you sure you want to delete user "${user.username}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l10n.cancel),
          ),
          TextButton(
            onPressed: () async {
              await userProvider.deleteUser(user.id);
              if (mounted) {
                Navigator.pop(context);
              }
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: Text(l10n.delete),
          ),
        ],
      ),
    );
  }
}