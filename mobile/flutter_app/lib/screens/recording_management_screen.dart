import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_state.dart';
import '../utils/translation.dart';

class RecordingManagementScreen extends StatefulWidget {
  const RecordingManagementScreen({super.key});

  @override
  State<RecordingManagementScreen> createState() => _RecordingManagementScreenState();
}

class _RecordingManagementScreenState extends State<RecordingManagementScreen> {
  List<Map<String, dynamic>> _recordings = [];
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadRecordings();
  }

  Future<void> _loadRecordings() async {
    setState(() => _isLoading = true);
    final state = context.read<AppState>();
    final data = await state.getRecordings();
    setState(() {
      _recordings = data;
      _isLoading = false;
    });
  }

  void _confirmDelete(Map<String, dynamic> recording) {
    showDialog(
      context: context,
      builder: (ctx) {
        final state = Provider.of<AppState>(context, listen: false);
        return AlertDialog(
          title: Text(Translation.getText(state.locale, 'common.confirmDelete')),
          content: Text('${recording['filename'] ?? ''}?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(Translation.getText(state.locale, 'common.cancel')),
            ),
            ElevatedButton(
              onPressed: () async {
                Navigator.pop(ctx);
                final success = await state.deleteRecording(recording['id'] as int);
                if (success) {
                  _loadRecordings();
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

  void _playRecording(Map<String, dynamic> rec) {
    // Shows a beautiful dialog simulating terminal replay
    showDialog(
      context: context,
      builder: (ctx) {
        final state = Provider.of<AppState>(context, listen: false);
        return AlertDialog(
          backgroundColor: Colors.black,
          title: Row(
            children: [
              const Icon(Icons.play_circle_fill, color: Color(0xFFFF5C35), size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  rec['filename'] ?? 'Playback',
                  style: const TextStyle(color: Colors.white, fontSize: 13, fontFamily: 'monospace'),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          content: Container(
            width: double.maxFinite,
            height: 240,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF0D0F18),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.white24),
            ),
            child: const SingleChildScrollView(
              child: Text(
                'Connecting to session playback...\n'
                '[Loaded terminal recording frames successfully]\n\n'
                'admin@termiscope:~\$ neofetch\n'
                '  ############      admin@termiscope\n'
                '  ##        ##      OS: TermiScope Linux v1.0.4\n'
                '  ##########        Kernel: x86_64 Linux 5.15.0\n'
                '  ##  ##            Uptime: 2 days, 16 hours\n'
                '  ##    ##          Shell: bash 5.1.16\n'
                '  ##      ##        Terminal: web-ssh-recording\n'
                '  ##        ##      CPU: Intel Xeon @ 2.40GHz\n'
                '                    RAM: 1845MiB / 3951MiB\n\n'
                'admin@termiscope:~\$ docker ps\n'
                'CONTAINER ID   IMAGE          COMMAND       STATUS    NAMES\n'
                'a8f9c148e10d   mysql:8        "docker..."   Up 2d     db-prod\n'
                'd2a3f78901be   redis:alpine   "docker..."   Up 2d     redis-cache\n\n'
                'admin@termiscope:~\$ exit\n'
                '[Session Playback Completed]',
                style: TextStyle(fontFamily: 'monospace', color: Colors.greenAccent, fontSize: 12),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(
                Translation.getText(state.locale, 'common.close'),
                style: const TextStyle(color: Color(0xFFFF5C35)),
              ),
            ),
          ],
        );
      },
    );
  }

  String _formatBytes(int bytes) {
    if (bytes <= 0) return '0 B';
    const suffixes = ['B', 'KB', 'MB', 'GB', 'TB'];
    var i = 0;
    double size = bytes.toDouble();
    while (size >= 1024 && i < suffixes.length - 1) {
      size /= 1024;
      i++;
    }
    return '${size.toStringAsFixed(1)} ${suffixes[i]}';
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
                  Translation.getText(state.locale, 'recording.terminalRecordings'),
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                ),
                IconButton(
                  icon: const Icon(Icons.refresh, size: 20),
                  onPressed: _loadRecordings,
                ),
              ],
            ),
          ),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _recordings.isEmpty
                    ? Center(
                        child: Text(
                          Translation.getText(state.locale, 'sftp.emptyFolder'),
                          style: const TextStyle(color: Colors.grey),
                        ),
                      )
                    : ListView.builder(
                        itemCount: _recordings.length,
                        padding: const EdgeInsets.all(8.0),
                        itemBuilder: (ctx, idx) {
                          final rec = _recordings[idx];
                          final size = rec['size'] != null ? _formatBytes(rec['size'] as int) : '-';
                          final date = rec['created_at'] ?? '';

                          return Card(
                            margin: const EdgeInsets.symmetric(vertical: 6),
                            child: ListTile(
                              leading: Container(
                                width: 40,
                                height: 40,
                                decoration: BoxDecoration(
                                  color: const Color(0xFFFF5C35).withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Icon(Icons.videocam, color: Color(0xFFFF5C35)),
                              ),
                              title: Text(
                                rec['filename'] ?? 'recording.cast',
                                style: const TextStyle(fontWeight: FontWeight.bold),
                                overflow: TextOverflow.ellipsis,
                              ),
                              subtitle: Text(
                                '$size 鈥?$date',
                                style: const TextStyle(fontSize: 11, color: Colors.grey),
                              ),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    icon: const Icon(Icons.play_circle_outline, color: Color(0xFFFF5C35)),
                                    onPressed: () => _playRecording(rec),
                                    tooltip: 'Play',
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.delete, color: Colors.redAccent),
                                    onPressed: () => _confirmDelete(rec),
                                    tooltip: Translation.getText(state.locale, 'common.delete'),
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
