import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:mobile/l10n/app_localizations.dart';
import 'package:file_picker/file_picker.dart';
import '../../providers/sftp_provider.dart';
import '../../providers/host_provider.dart';
import '../../models/sftp_file.dart';
import '../../models/ssh_host.dart';

class FileTransferScreen extends StatefulWidget {
  const FileTransferScreen({super.key});

  @override
  State<FileTransferScreen> createState() => _FileTransferScreenState();
}

class _FileTransferScreenState extends State<FileTransferScreen> {
  String? _selectedHostId;
  final TextEditingController _pathController = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Provider.of<HostProvider>(context, listen: false).fetchHosts();
    });
  }

  @override
  void dispose() {
    _pathController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final sftpProvider = Provider.of<SftpProvider>(context);
    final hostProvider = Provider.of<HostProvider>(context);
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      appBar: AppBar(
        title: Text('File Transfer'),
        actions: [
          PopupMenuButton(
            onSelected: (value) {
              if (value == 'createDir') {
                _showCreateDirectoryDialog(context);
              } else if (value == 'createFile') {
                _showCreateFileDialog(context);
              }
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 'createDir',
                child: Row(
                  children: [
                    const Icon(Icons.create_new_folder, size: 18),
                    const SizedBox(width: 8),
                    Text('New Folder'),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'createFile',
                child: Row(
                  children: [
                    const Icon(Icons.note_add, size: 18),
                    const SizedBox(width: 8),
                    Text('New File'),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          // Host selection
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: DropdownButtonFormField<SSHHost>(
              initialValue: _selectedHostId != null
                  ? hostProvider.hosts.firstWhere(
                      (h) => h.id.toString() == _selectedHostId,
                      orElse: () => hostProvider.hosts.first,
                    )
                  : null,
              hint: Text('Select Host'),
              items: hostProvider.hosts.map((host) {
                return DropdownMenuItem(
                  value: host,
                  child: Text('${host.name} (${host.hostname})'),
                );
              }).toList(),
              onChanged: (SSHHost? host) {
                if (host != null) {
                  setState(() {
                    _selectedHostId = host.id.toString();
                  });
                  sftpProvider.browseDirectory(_selectedHostId!, '/');
                }
              },
              decoration: InputDecoration(
                labelText: 'Host',
                border: const OutlineInputBorder(),
              ),
            ),
          ),
          // Path navigation
          if (sftpProvider.currentDirectory != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_upward),
                    onPressed: sftpProvider.currentDirectory!.currentPath != '/'
                        ? () => sftpProvider.navigateUp()
                        : null,
                  ),
                  Expanded(
                    child: TextField(
                      controller: _pathController
                        ..text = sftpProvider.currentDirectory!.currentPath,
                      onSubmitted: (path) => sftpProvider.browseDirectory(
                        sftpProvider.currentHostId!,
                        path,
                      ),
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        labelText: 'Path',
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.refresh),
                    onPressed: () => sftpProvider.refreshDirectory(),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 16),
          // File list
          Expanded(
            child: sftpProvider.isLoading
                ? const Center(child: CircularProgressIndicator())
                : sftpProvider.error != null
                    ? Center(child: Text(sftpProvider.error!))
                    : sftpProvider.currentDirectory == null
                        ? Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(Icons.folder_open, size: 64, color: Colors.grey),
                                const SizedBox(height: 16),
                                Text(
                                  'Select a host to browse files',
                                  style: const TextStyle(fontSize: 16, color: Colors.grey),
                                ),
                              ],
                            ),
                          )
                        : _buildFileList(sftpProvider, l10n),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _uploadFile,
        tooltip: 'Upload File',
        child: const Icon(Icons.upload_file),
      ),
    );
  }

  Widget _buildFileList(SftpProvider sftpProvider, AppLocalizations l10n) {
    final directory = sftpProvider.currentDirectory!;
    final files = directory.files;

    return RefreshIndicator(
      onRefresh: () => sftpProvider.refreshDirectory(),
      child: ListView.builder(
        itemCount: files.length,
        itemBuilder: (context, index) {
          final file = files[index];
          return Card(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: ListTile(
              leading: CircleAvatar(
                child: Icon(
                  file.isDirectory ? Icons.folder : Icons.insert_drive_file,
                  color: file.isDirectory ? Colors.orange : Colors.blue,
                ),
              ),
              title: Text(file.name),
              subtitle: Text(
                '${_formatFileSize(file.size)} • ${_formatDateTime(file.modifiedTime)}',
              ),
              trailing: PopupMenuButton(
                onSelected: (value) {
                  if (value == 'download') {
                    _downloadFile(sftpProvider, file.path);
                  } else if (value == 'rename') {
                    _showRenameDialog(context, file);
                  } else if (value == 'delete') {
                    _confirmDeleteFile(context, sftpProvider, file);
                  }
                },
                itemBuilder: (context) => [
                  PopupMenuItem(
                    value: 'download',
                    child: Row(
                      children: [
                        const Icon(Icons.download, size: 18),
                        const SizedBox(width: 8),
                        Text('Download'),
                      ],
                    ),
                  ),
                  PopupMenuItem(
                    value: 'rename',
                    child: Row(
                      children: [
                        const Icon(Icons.edit, size: 18),
                        const SizedBox(width: 8),
                        Text('Rename'),
                      ],
                    ),
                  ),
                  PopupMenuItem(
                    value: 'delete',
                    child: Row(
                      children: [
                        const Icon(Icons.delete, size: 18),
                        const SizedBox(width: 8),
                        Text(l10n.delete),
                      ],
                    ),
                  ),
                ],
              ),
              onTap: file.isDirectory
                  ? () => sftpProvider.navigateToSubdirectory(file.name)
                  : null,
            ),
          );
        },
      ),
    );
  }

  String _formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  String _formatDateTime(DateTime dateTime) {
    return '${dateTime.year}-${dateTime.month.toString().padLeft(2, '0')}-${dateTime.day.toString().padLeft(2, '0')} '
           '${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}';
  }

  Future<void> _uploadFile() async {
    final sftpProvider = Provider.of<SftpProvider>(context, listen: false);
    if (sftpProvider.currentHostId == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Please select a host first')),
        );
      }
      return;
    }

    final result = await FilePicker.platform.pickFiles();
    if (result != null && result.files.single.bytes != null) {
      final fileName = result.files.single.name;
      final fileBytes = result.files.single.bytes!;
      
      // Construct the full path
      String fullPath = sftpProvider.currentDirectory!.currentPath;
      if (!fullPath.endsWith('/')) {
        fullPath += '/';
      }
      fullPath += fileName;

      final success = await sftpProvider.uploadFile(fullPath, fileBytes);
      if (success && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$fileName uploaded successfully!')),
        );
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to upload $fileName')),
        );
      }
    }
  }

  Future<void> _downloadFile(SftpProvider sftpProvider, String filePath) async {
    final fileData = await sftpProvider.downloadFile(filePath);
    if (fileData != null && mounted) {
      // In a real implementation, we would save the file to device
      // For now, we'll just show a snackbar
      final fileName = filePath.split('/').last;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$fileName downloaded successfully!')),
      );
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to download file')),
      );
    }
  }

  Future<void> _showRenameDialog(BuildContext context, SftpFile file) async {
    final sftpProvider = Provider.of<SftpProvider>(context, listen: false);
    final newNameController = TextEditingController(text: file.name);

    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Rename ${file.isDirectory ? 'Folder' : 'File'}'),
        content: TextField(
          controller: newNameController,
          decoration: const InputDecoration(labelText: 'New Name'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(AppLocalizations.of(context)!.cancel),
          ),
          ElevatedButton(
            onPressed: () async {
              final newPath = file.path.substring(0, file.path.lastIndexOf('/') + 1) + newNameController.text;
              final success = await sftpProvider.renamePath(file.path, newPath);
              if (success && mounted) {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Renamed successfully!')),
                );
              } else if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Failed to rename')),
                );
              }
            },
            child: Text('Rename'),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmDeleteFile(BuildContext context, SftpProvider sftpProvider, SftpFile file) async {
    final l10n = AppLocalizations.of(context)!;

    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.confirmDelete),
        content: Text('Are you sure you want to delete "${file.name}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l10n.cancel),
          ),
          TextButton(
            onPressed: () async {
              final success = await sftpProvider.deletePath(file.path);
              if (success && mounted) {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Deleted successfully!')),
                );
              } else if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Failed to delete')),
                );
              }
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: Text(l10n.delete),
          ),
        ],
      ),
    );
  }

  Future<void> _showCreateDirectoryDialog(BuildContext context) async {
    final sftpProvider = Provider.of<SftpProvider>(context, listen: false);
    final controller = TextEditingController();

    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Create New Folder'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(labelText: 'Folder Name'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(AppLocalizations.of(context)!.cancel),
          ),
          ElevatedButton(
            onPressed: () async {
              if (controller.text.isNotEmpty) {
                String newPath = sftpProvider.currentDirectory!.currentPath;
                if (!newPath.endsWith('/')) {
                  newPath += '/';
                }
                newPath += controller.text;

                final success = await sftpProvider.createDirectory(newPath);
                if (success && mounted) {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Folder created successfully!')),
                  );
                } else if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Failed to create folder')),
                  );
                }
              }
            },
            child: Text('Create'),
          ),
        ],
      ),
    );
  }

  Future<void> _showCreateFileDialog(BuildContext context) async {
    final sftpProvider = Provider.of<SftpProvider>(context, listen: false);
    final controller = TextEditingController();

    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Create New File'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(labelText: 'File Name'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(AppLocalizations.of(context)!.cancel),
          ),
          ElevatedButton(
            onPressed: () async {
              if (controller.text.isNotEmpty) {
                String newPath = sftpProvider.currentDirectory!.currentPath;
                if (!newPath.endsWith('/')) {
                  newPath += '/';
                }
                newPath += controller.text;

                final success = await sftpProvider.createFile(newPath);
                if (success && mounted) {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('File created successfully!')),
                  );
                } else if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Failed to create file')),
                  );
                }
              }
            },
            child: Text('Create'),
          ),
        ],
      ),
    );
  }
}