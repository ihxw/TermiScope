import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_state.dart';

class HostEditDialog extends StatefulWidget {
  final Map<String, dynamic>? host;

  const HostEditDialog({super.key, this.host});

  @override
  State<HostEditDialog> createState() => _HostEditDialogState();
}

class _HostEditDialogState extends State<HostEditDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _hostController;
  late final TextEditingController _portController;
  late final TextEditingController _usernameController;
  late final TextEditingController _passwordController;
  bool _monitorEnabled = false;
  String _hostType = 'ssh';

  @override
  void initState() {
    super.initState();
    final host = widget.host;
    _nameController = TextEditingController(text: host?['name'] ?? '');
    _hostController = TextEditingController(text: host?['host'] ?? '');
    _portController = TextEditingController(text: host?['port']?.toString() ?? '22');
    _usernameController = TextEditingController(text: host?['username'] ?? '');
    _passwordController = TextEditingController();
    _monitorEnabled = host?['monitor_enabled'] ?? false;
    _hostType = host?['host_type'] ?? 'ssh';
  }

  @override
  void dispose() {
    _nameController.dispose();
    _hostController.dispose();
    _portController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF2D2D2D),
      title: Text(widget.host == null ? '添加主机' : '编辑主机'),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildTextField(
                '名称',
                _nameController,
                Icons.computer,
                validator: (v) => v?.isEmpty ?? true ? '请输入名称' : null,
              ),
              const SizedBox(height: 12),
              _buildTextField(
                '主机地址',
                _hostController,
                Icons.dns,
                validator: (v) => v?.isEmpty ?? true ? '请输入主机地址' : null,
              ),
              const SizedBox(height: 12),
              _buildTextField(
                '端口',
                _portController,
                Icons.input,
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 12),
              _buildTextField(
                '用户名',
                _usernameController,
                Icons.person,
              ),
              const SizedBox(height: 12),
              _buildTextField(
                '密码',
                _passwordController,
                Icons.lock,
                obscureText: true,
                helperText: widget.host != null ? '留空则不修改' : null,
              ),
              const SizedBox(height: 16),
              const Text('类型', style: TextStyle(color: Colors.grey, fontSize: 12)),
              const SizedBox(height: 8),
              Row(
                children: [
                  _buildTypeChip('SSH', 'ssh'),
                  const SizedBox(width: 8),
                  _buildTypeChip('仅监控', 'monitor_only'),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Checkbox(
                    value: _monitorEnabled,
                    activeColor: const Color(0xFF64D2FF),
                    onChanged: (v) => setState(() => _monitorEnabled = v == true),
                  ),
                  const Text('启用监控', style: TextStyle(color: Colors.white)),
                ],
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        ElevatedButton(
          onPressed: _save,
          style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF64D2FF)),
          child: Text(widget.host == null ? '添加' : '保存'),
        ),
      ],
    );
  }

  Widget _buildTextField(
    String label,
    TextEditingController controller,
    IconData icon, {
    String? helperText,
    bool obscureText = false,
    TextInputType? keyboardType,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      obscureText: obscureText,
      keyboardType: keyboardType,
      validator: validator,
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Colors.grey, fontSize: 12),
        hintText: helperText,
        hintStyle: const TextStyle(color: Colors.grey, fontSize: 11),
        prefixIcon: Icon(icon, color: Colors.grey, size: 20),
        filled: true,
        fillColor: const Color(0xFF1E1E1E),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide.none,
        ),
      ),
      style: const TextStyle(color: Colors.white),
    );
  }

  Widget _buildTypeChip(String label, String type) {
    final isSelected = _hostType == type;
    return FilterChip(
      label: Text(label),
      selected: isSelected,
      backgroundColor: const Color(0xFF1E1E1E),
      selectedColor: const Color(0xFF64D2FF).withOpacity(0.3),
      checkmarkColor: const Color(0xFF64D2FF),
      labelStyle: TextStyle(
        color: isSelected ? const Color(0xFF64D2FF) : Colors.grey,
      ),
      onSelected: (v) => setState(() => _hostType = type),
    );
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;

    final hostData = {
      'name': _nameController.text.trim(),
      'host': _hostController.text.trim(),
      'port': int.tryParse(_portController.text.trim()) ?? 22,
      'username': _usernameController.text.trim(),
      'monitor_enabled': _monitorEnabled,
      'host_type': _hostType,
    };

    if (_passwordController.text.isNotEmpty) {
      hostData['password'] = _passwordController.text;
    }

    if (widget.host == null) {
      // Add new host
      context.read<AppState>().addHost(hostData).then((success) {
        if (success && context.mounted) {
          Navigator.pop(context);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('主机添加成功')),
          );
        } else if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('添加失败')),
          );
        }
      });
    } else {
      // Update existing host
      context.read<AppState>().updateHost(
        widget.host!['id'].toString(),
        hostData,
      ).then((success) {
        if (success && context.mounted) {
          Navigator.pop(context);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('主机更新成功')),
          );
        } else if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('更新失败')),
          );
        }
      });
    }
  }
}
