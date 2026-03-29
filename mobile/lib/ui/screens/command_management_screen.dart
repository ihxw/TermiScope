import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:mobile/l10n/app_localizations.dart';
import '../../providers/command_provider.dart';
import '../../models/command.dart';

class CommandManagementScreen extends StatefulWidget {
  const CommandManagementScreen({super.key});

  @override
  State<CommandManagementScreen> createState() => _CommandManagementScreenState();
}

class _CommandManagementScreenState extends State<CommandManagementScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Provider.of<CommandProvider>(context, listen: false).fetchCommandTemplates();
    });
  }

  @override
  Widget build(BuildContext context) {
    final commandProvider = Provider.of<CommandProvider>(context);
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.commands),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () => _showAddEditCommandDialog(context, null),
          ),
        ],
      ),
      body: commandProvider.isLoading
          ? const Center(child: CircularProgressIndicator())
          : commandProvider.error != null
              ? Center(child: Text(commandProvider.error!))
              : _buildCommandList(commandProvider, l10n),
    );
  }

  Widget _buildCommandList(CommandProvider commandProvider, AppLocalizations l10n) {
    if (commandProvider.commandTemplates.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.code, size: 64, color: Colors.grey),
            const SizedBox(height: 16),
            Text(
              'No commands found',
              style: const TextStyle(fontSize: 16, color: Colors.grey),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () => _showAddEditCommandDialog(context, null),
              child: Text('Add Command'),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () => commandProvider.refreshCommandTemplates(),
      child: ListView.builder(
        itemCount: commandProvider.commandTemplates.length,
        itemBuilder: (context, index) {
          final command = commandProvider.commandTemplates[index];
          return Card(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: ExpansionTile(
              leading: CircleAvatar(
                child: Icon(Icons.code),
              ),
              title: Text(command.name),
              subtitle: Text(command.command),
              children: [
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (command.description.isNotEmpty)
                        Text(
                          command.description,
                          style: const TextStyle(fontSize: 14),
                        ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(
                              color: command.isActive ? Colors.green.shade100 : Colors.red.shade100,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              command.isActive ? 'Active' : 'Inactive',
                              style: TextStyle(
                                color: command.isActive ? Colors.green.shade800 : Colors.red.shade800,
                                fontSize: 12,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            command.category,
                            style: const TextStyle(
                              color: Colors.grey,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton(
                            onPressed: () => _showAddEditCommandDialog(context, command),
                            child: Text(l10n.edit),
                          ),
                          TextButton(
                            onPressed: () => _confirmDeleteCommand(context, commandProvider, command),
                            style: TextButton.styleFrom(foregroundColor: Colors.red),
                            child: Text(l10n.delete),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Future<void> _showAddEditCommandDialog(BuildContext context, CommandTemplate? command) async {
    final commandProvider = Provider.of<CommandProvider>(context, listen: false);
    final formKey = GlobalKey<FormState>();
    final nameController = TextEditingController(text: command?.name);
    final commandController = TextEditingController(text: command?.command);
    final descriptionController = TextEditingController(text: command?.description);
    final categoryController = TextEditingController(text: command?.category);
    final isActiveController = TextEditingController(text: command?.isActive.toString());

    bool isEditing = command != null;

    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(isEditing ? 'Edit Command' : 'Add Command'),
        content: SizedBox(
          width: 500,
          child: Form(
            key: formKey,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    controller: nameController,
                    decoration: InputDecoration(labelText: 'Name'),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Please enter name';
                      }
                      return null;
                    },
                  ),
                  TextFormField(
                    controller: commandController,
                    decoration: InputDecoration(labelText: 'Command'),
                    maxLines: 3,
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Please enter command';
                      }
                      return null;
                    },
                  ),
                  TextFormField(
                    controller: descriptionController,
                    decoration: InputDecoration(labelText: 'Description'),
                    maxLines: 3,
                  ),
                  TextFormField(
                    controller: categoryController,
                    decoration: InputDecoration(labelText: 'Category'),
                  ),
                  SwitchListTile(
                    title: Text('Active'),
                    value: command?.isActive ?? true,
                    onChanged: (value) {},
                  ),
                ],
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              if (formKey.currentState!.validate()) {
                final commandTemplate = CommandTemplate(
                  id: command?.id ?? 0,
                  name: nameController.text.trim(),
                  command: commandController.text.trim(),
                  description: descriptionController.text.trim(),
                  category: categoryController.text.trim(),
                  isActive: command?.isActive ?? true,
                  createdAt: command?.createdAt ?? DateTime.now(),
                  updatedAt: DateTime.now(),
                );

                bool success;
                if (isEditing) {
                  success = await commandProvider.updateCommandTemplate(command.id, commandTemplate);
                } else {
                  success = await commandProvider.createCommandTemplate(commandTemplate);
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

  Future<void> _confirmDeleteCommand(BuildContext context, CommandProvider commandProvider, CommandTemplate command) async {
    final l10n = AppLocalizations.of(context)!;

    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.confirmDelete),
        content: Text('Are you sure you want to delete command "${command.name}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              await commandProvider.deleteCommandTemplate(command.id);
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