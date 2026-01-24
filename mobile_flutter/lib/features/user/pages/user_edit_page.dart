import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/api/user_api.dart';
import '../../../core/models/user.dart';

class UserEditPage extends ConsumerStatefulWidget {
  final User? user;
  const UserEditPage({super.key, this.user});

  @override
  ConsumerState<UserEditPage> createState() => _UserEditPageState();
}

class _UserEditPageState extends ConsumerState<UserEditPage> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _usernameController;
  late TextEditingController _emailController;
  late TextEditingController _displayNameController;
  late TextEditingController _passwordController;
  String _role = 'user';
  String _status = 'active';
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _usernameController =
        TextEditingController(text: widget.user?.username ?? '');
    _emailController = TextEditingController(text: widget.user?.email ?? '');
    _displayNameController =
        TextEditingController(text: widget.user?.displayName ?? '');
    _passwordController = TextEditingController();
    _role = widget.user?.role ?? 'user';
    _status = widget.user?.status ?? 'active';
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _emailController.dispose();
    _displayNameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    final data = {
      'username': _usernameController.text.trim(),
      'email': _emailController.text.trim(),
      'display_name': _displayNameController.text.trim(),
      'role': _role,
      'status': _status,
    };

    if (_passwordController.text.isNotEmpty) {
      data['password'] = _passwordController.text;
    }

    try {
      if (widget.user == null) {
        // Create
        if (_passwordController.text.isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Password is required for new users')),
          );
          setState(() => _isLoading = false);
          return;
        }
        await ref.read(userApiProvider).createUser(data);
      } else {
        // Update
        await ref.read(userApiProvider).updateUser(widget.user!.id, data);
      }

      if (mounted) {
        context.pop();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Saved successfully')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.user != null;
    return Scaffold(
      appBar: AppBar(
        title: Text(isEditing ? 'Edit User' : 'New User'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                controller: _usernameController,
                decoration: const InputDecoration(labelText: 'Username'),
                readOnly:
                    isEditing, // Prevent changing username if editing? Usually allowed, but IDK. Let's allow unless backend forbids.
                // Assuming backend might allow update if ID is used.
                validator: (v) => v?.isNotEmpty == true ? null : 'Required',
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _displayNameController,
                decoration: const InputDecoration(labelText: 'Display Name'),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _emailController,
                decoration: const InputDecoration(labelText: 'Email'),
                keyboardType: TextInputType.emailAddress,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _passwordController,
                decoration: InputDecoration(
                  labelText:
                      isEditing ? 'Password (leave blank to keep)' : 'Password',
                ),
                obscureText: true,
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                value: _role,
                decoration: const InputDecoration(labelText: 'Role'),
                items: const [
                  DropdownMenuItem(value: 'user', child: Text('User')),
                  DropdownMenuItem(value: 'admin', child: Text('Admin')),
                ],
                onChanged: (val) => setState(() => _role = val!),
              ),
              if (isEditing) ...[
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  value: _status,
                  decoration: const InputDecoration(labelText: 'Status'),
                  items: const [
                    DropdownMenuItem(value: 'active', child: Text('Active')),
                    DropdownMenuItem(
                        value: 'disabled', child: Text('Disabled')),
                  ],
                  onChanged: (val) => setState(() => _status = val!),
                ),
              ],
              const SizedBox(height: 32),
              ElevatedButton(
                onPressed: _isLoading ? null : _save,
                child: _isLoading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('Save'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
