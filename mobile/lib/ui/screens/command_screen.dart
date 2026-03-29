import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:mobile/l10n/app_localizations.dart';

class CommandScreen extends StatefulWidget {
  const CommandScreen({super.key});

  @override
  State<CommandScreen> createState() => _CommandScreenState();
}

class _CommandScreenState extends State<CommandScreen> {
  // late CommandService _commandService; // Service not implemented yet
  // List<CommandTemplate> _templates = []; // Template not implemented yet
  List<Map<String, dynamic>> _templates = []; // Placeholder for now
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    // _commandService = CommandService(
      //   Provider.of<ApiService>(context, listen: false),
    // ); // Service not implemented yet
    _loadTemplates();
  }

  Future<void> _loadTemplates() async {
    setState(() => _isLoading = true);
    try {
      // final templates = await _commandService.getTemplates(); // Service not implemented yet
      final templates = <Map<String, dynamic>>[]; // Placeholder for now
      if (mounted) setState(() => _templates = templates);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _deleteTemplate(int id) async {
    try {
      // await _commandService.deleteTemplate(id); // Service not implemented yet
      _loadTemplates();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  void _showEditor([Map<String, dynamic>? template]) {
    showDialog(
      context: context,
      builder: (context) => _CommandEditorDialog(
        template: template,
        onSave: (name, command, desc) async {
          try {
            if (template == null) {
              // await _commandService.createTemplate(
              //   CommandTemplate(
              //     name: name,
              //     command: command,
              //     description: desc,
              //   ),
              // ); // Service not implemented yet
            } else {
              // await _commandService.updateTemplate(
              //   template['id'],
              //   CommandTemplate(
              //     id: template['id'],
              //     name: name,
              //     command: command,
              //     description: desc,
              //   ),
              // ); // Service not implemented yet
            }
            if (mounted) Navigator.pop(context);
            _loadTemplates();
          } catch (e) {
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(SnackBar(content: Text('Error: $e')));
          }
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showEditor(),
        child: const Icon(Icons.add),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _templates.isEmpty
          ? const Center(child: Text('No command templates'))
          : ListView.builder(
              itemCount: _templates.length,
              itemBuilder: (context, index) {
                final t = _templates[index];
                return Card(
                  margin: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  child: ListTile(
                    title: Text(
                      t['name'] ?? '',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if ((t['description'] ?? '').isNotEmpty) Text(t['description'] ?? ''),
                        const SizedBox(height: 4),
                        Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: Colors.grey[200],
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            t['command'] ?? '',
                            style: const TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ],
                    ),
                    trailing: PopupMenuButton(
                      itemBuilder: (context) => [
                        const PopupMenuItem(value: 'edit', child: Text('Edit')),
                        const PopupMenuItem(
                          value: 'delete',
                          child: Text(
                            'Delete',
                            style: TextStyle(color: Colors.red),
                          ),
                        ),
                      ],
                      onSelected: (value) {
                        if (value == 'edit') _showEditor(t);
                        if (value == 'delete') _deleteTemplate(t['id']);
                      },
                    ),
                  ),
                );
              },
            ),
    );
  }
}

class _CommandEditorDialog extends StatefulWidget {
  final Map<String, dynamic>? template;
  final Function(String, String, String) onSave;

  const _CommandEditorDialog({this.template, required this.onSave});

  @override
  State<_CommandEditorDialog> createState() => _CommandEditorDialogState();
}

class _CommandEditorDialogState extends State<_CommandEditorDialog> {
  late TextEditingController _nameCtrl;
  late TextEditingController _cmdCtrl;
  late TextEditingController _descCtrl;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.template?['name'] ?? '');
    _cmdCtrl = TextEditingController(text: widget.template?['command'] ?? '');
    _descCtrl = TextEditingController(text: widget.template?['description'] ?? '');
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.template == null ? 'New Command' : 'Edit Command'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _nameCtrl,
              decoration: const InputDecoration(labelText: 'Name'),
            ),
            TextField(
              controller: _cmdCtrl,
              decoration: const InputDecoration(labelText: 'Command'),
              maxLines: 3,
            ),
            TextField(
              controller: _descCtrl,
              decoration: const InputDecoration(labelText: 'Description'),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: () {
            if (_nameCtrl.text.isEmpty || _cmdCtrl.text.isEmpty) return;
            widget.onSave(_nameCtrl.text, _cmdCtrl.text, _descCtrl.text);
          },
          child: const Text('Save'),
        ),
      ],
    );
  }
}
