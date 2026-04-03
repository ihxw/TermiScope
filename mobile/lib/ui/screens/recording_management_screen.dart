import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'dart:async';
import 'dart:convert';

import 'package:mobile/l10n/app_localizations.dart';
import '../../providers/recording_provider.dart';
import '../../models/recording.dart';
import 'package:xterm/xterm.dart';
import '../../core/api_client.dart';
import 'package:flutter/cupertino.dart';

class RecordingManagementScreen extends StatefulWidget {
  const RecordingManagementScreen({super.key});

  @override
  State<RecordingManagementScreen> createState() => _RecordingManagementScreenState();
}

class _RecordingManagementScreenState extends State<RecordingManagementScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Provider.of<RecordingProvider>(context, listen: false).fetchRecordings();
    });
  }

  @override
  Widget build(BuildContext context) {
    final recordingProvider = Provider.of<RecordingProvider>(context);
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.recordings),
      ),
      body: recordingProvider.isLoading
          ? const Center(child: CircularProgressIndicator())
          : recordingProvider.error != null
              ? Center(child: Text(recordingProvider.error!))
              : _buildRecordingList(recordingProvider, l10n),
    );
  }

  // Player state
  Terminal? _playerTerminal;
  Timer? _playTimer;
  List<List<dynamic>> _recordingData = [];
  bool _isPlaying = false;
  double _currentTime = 0.0;
  double _totalTime = 0.0;


  Widget _buildRecordingList(RecordingProvider recordingProvider, AppLocalizations l10n) {
    if (recordingProvider.recordings.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.video_camera_back, size: 64, color: Colors.grey),
            const SizedBox(height: 16),
            Text(
              'No recordings found',
              style: const TextStyle(fontSize: 16, color: Colors.grey),
            ),
            const SizedBox(height: 16),
            Text(
              'You have not recorded any terminal sessions yet.',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 14, color: Colors.grey),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () => recordingProvider.refreshRecordings(),
      child: ListView.builder(
        itemCount: recordingProvider.recordings.length,
        itemBuilder: (context, index) {
          final recording = recordingProvider.recordings[index];
          return Card(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: ListTile(
              leading: CircleAvatar(
                child: Icon(Icons.play_circle),
              ),
              title: Text(recording.name),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${recording.hostName} • ${recording.userName}',
                    style: const TextStyle(fontSize: 12),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${_formatDuration(recording.duration)} • ${_formatDateTime(recording.startTime)}',
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ],
              ),
              trailing: PopupMenuButton(
                onSelected: (value) {
                  if (value == 'play') {
                    _playRecording(context, recordingProvider, recording);
                  } else if (value == 'delete') {
                    _confirmDeleteRecording(context, recordingProvider, recording);
                  }
                },
                itemBuilder: (context) => [
                  PopupMenuItem(
                    value: 'play',
                    child: Row(
                      children: [
                        const Icon(Icons.play_arrow, size: 18),
                        const SizedBox(width: 8),
                        Text('Play'),
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
            ),
          );
        },
      ),
    );
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    String twoDigitMinutes = twoDigits(duration.inMinutes.remainder(60));
    String twoDigitSeconds = twoDigits(duration.inSeconds.remainder(60));
    return "${twoDigits(duration.inHours)}:$twoDigitMinutes:$twoDigitSeconds";
  }

  String _formatDateTime(DateTime dateTime) {
    return '${dateTime.year}-${dateTime.month.toString().padLeft(2, '0')}-${dateTime.day.toString().padLeft(2, '0')} '
           '${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}';
  }

  Future<void> _playRecording(BuildContext context, RecordingProvider recordingProvider, Recording recording) async {
    try {
      final streamPath = await recordingProvider.getRecordingStreamUrl(recording.id);

      // Fetch plain text data via ApiClient
      final resp = await ApiClient.instance.getPlain(streamPath);
      final body = resp.data as String;

      final lines = LineSplitter.split(body).where((l) => l.trim().isNotEmpty);
      _recordingData = [];
      for (final line in lines) {
        try {
          final parsed = jsonDecode(line) as List<dynamic>;
          _recordingData.add(parsed);
        } catch (e) {
          // ignore malformed lines
        }
      }

      _totalTime = recording.duration.inSeconds.toDouble();
      _currentTime = 0.0;

      // Show player dialog
      _showPlayerDialog(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error playing recording: $e')),
        );
      }
    }
  }

  void _showPlayerDialog(BuildContext context) {
    _playerTerminal = Terminal();

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            void startPlayback() {
              _isPlaying = true;
              final startTs = DateTime.now().millisecondsSinceEpoch - (_currentTime * 1000).toInt();
              _playTimer?.cancel();
              int dataIndex = 0;
              // Fast-forward to current position
              while (dataIndex < _recordingData.length && (_recordingData[dataIndex][0] as num).toDouble() <= _currentTime) {
                dataIndex++;
              }

              _playTimer = Timer.periodic(const Duration(milliseconds: 100), (_) {
                final elapsed = (DateTime.now().millisecondsSinceEpoch - startTs) / 1000.0;
                _currentTime = elapsed.clamp(0.0, _totalTime);
                // write data until elapsed
                while (dataIndex < _recordingData.length && (_recordingData[dataIndex][0] as num).toDouble() <= elapsed) {
                  final data = _recordingData[dataIndex];
                  if (data.length >= 3) {
                    final chunk = data[2] as String;
                    _playerTerminal?.write(chunk);
                  }
                  dataIndex++;
                }

                if (elapsed >= _totalTime || dataIndex >= _recordingData.length) {
                  _stopPlayback();
                }
                setState(() {});
              });
            }

            void _stopPlayback() {
              _isPlaying = false;
              _playTimer?.cancel();
              _playTimer = null;
            }

            return AlertDialog(
              contentPadding: const EdgeInsets.all(12),
              content: SizedBox(
                width: double.maxFinite,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      height: 320,
                      child: Container(
                        color: Colors.black,
                        child: TerminalView(_playerTerminal!),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        IconButton(
                          icon: Icon(_isPlaying ? Icons.pause : Icons.play_arrow),
                          onPressed: () {
                            if (_isPlaying) {
                              _stopPlayback();
                            } else {
                              startPlayback();
                            }
                            setState(() {});
                          },
                        ),
                        Expanded(
                          child: Slider(
                            value: _currentTime,
                            min: 0,
                            max: _totalTime <= 0 ? 1 : _totalTime,
                            onChanged: (v) {
                              _currentTime = v;
                              // clear terminal and repaint up to position
                              _playerTerminal?.clear();
                              _playerTerminal?.write('\x1b[H\x1b[2J');
                              // replay up to currentTime synchronously
                              for (final entry in _recordingData) {
                                final ts = (entry[0] as num).toDouble();
                                if (ts <= _currentTime) {
                                  if (entry.length >= 3) {
                                    _playerTerminal?.write(entry[2] as String);
                                  }
                                } else {
                                  break;
                                }
                              }
                              setState(() {});
                            },
                          ),
                        ),
                        SizedBox(
                          width: 100,
                          child: Text('${_formatDurationSeconds(_currentTime.toInt())} / ${_formatDurationSeconds(_totalTime.toInt())}', textAlign: TextAlign.right),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    _stopPlayback();
                    _playerTerminal?.dispose();
                    Navigator.of(context).pop();
                  },
                  child: Text(AppLocalizations.of(context)!.close),
                ),
              ],
            );
          },
        );
      },
    ).then((_) {
      _stopPlayback();
      _playerTerminal?.dispose();
      _playerTerminal = null;
    });
  }

  String _formatDurationSeconds(int seconds) {
    final h = seconds ~/ 3600;
    final m = (seconds % 3600) ~/ 60;
    final s = seconds % 60;
    final parts = [h, m, s].map((v) => v.toString().padLeft(2, '0')).toList();
    if (h == 0) return '${parts[1]}:${parts[2]}';
    return '${parts[0]}:${parts[1]}:${parts[2]}';
  }

  Future<void> _confirmDeleteRecording(BuildContext context, RecordingProvider recordingProvider, Recording recording) async {
    final l10n = AppLocalizations.of(context)!;

    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.confirmDelete),
        content: Text('Are you sure you want to delete recording "${recording.name}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l10n.cancel),
          ),
          TextButton(
            onPressed: () async {
              await recordingProvider.deleteRecording(recording.id);
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