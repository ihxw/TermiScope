import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:mobile/l10n/app_localizations.dart';
import '../../providers/terminal_provider.dart';
import '../../providers/host_provider.dart';
import '../widgets/app_drawer.dart';
import 'terminal_screen.dart';

class TerminalListScreen extends StatefulWidget {
  const TerminalListScreen({super.key});

  @override
  State<TerminalListScreen> createState() => _TerminalListScreenState();
}

class _TerminalListScreenState extends State<TerminalListScreen> {
  int? _selectedHostId;
  bool _recordingEnabled = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Provider.of<HostProvider>(context, listen: false).fetchHosts();
    });
  }

  @override
  void dispose() {
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.terminal),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(56),
          child: _buildToolbar(context, l10n),
        ),
      ),
      drawer: const AppDrawer(),
      body: Consumer<TerminalProvider>(
        builder: (context, terminalProvider, child) {
          if (terminalProvider.sessions.isEmpty) {
            return _buildEmptyState(context, l10n);
          }

          // Use IndexedStack instead of TabBarView to avoid TabController issues
          final activeIndex = terminalProvider.activeSessionId == null
              ? 0
              : terminalProvider.sessions
                    .indexWhere((s) => s.id == terminalProvider.activeSessionId)
                    .clamp(0, terminalProvider.sessions.length - 1);

          return Column(
            children: [
              // Tab chips for navigation
              if (terminalProvider.sessions.isNotEmpty)
                Container(
                  padding: const EdgeInsets.all(8),
                  color: Colors.grey.shade100,
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: terminalProvider.sessions.asMap().entries.map((
                        entry,
                      ) {
                        final idx = entry.key;
                        final session = entry.value;
                        final isActive = idx == activeIndex;

                        return Padding(
                          padding: const EdgeInsets.only(right: 4),
                          child: ChoiceChip(
                            label: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (session.record)
                                  const Padding(
                                    padding: EdgeInsets.only(right: 4),
                                    child: Icon(
                                      Icons.fiber_manual_record,
                                      size: 8,
                                      color: Colors.red,
                                    ),
                                  ),
                                Text(session.name),
                                const SizedBox(width: 4),
                                InkWell(
                                  onTap: () {
                                    terminalProvider.removeSession(session.id);
                                  },
                                  child: const Icon(Icons.close, size: 16),
                                ),
                              ],
                            ),
                            selected: isActive,
                            onSelected: (selected) {
                              if (selected) {
                                terminalProvider.setActiveSession(session.id);
                              }
                            },
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ),

              // Terminal screens
              Expanded(
                child: IndexedStack(
                  index: activeIndex,
                  children: terminalProvider.sessions.map((session) {
                    return TerminalScreen(
                      hostId: session.hostId,
                      title: session.name,
                    );
                  }).toList(),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildToolbar(BuildContext context, AppLocalizations l10n) {
    return Consumer<HostProvider>(
      builder: (context, hostProvider, child) {
        final terminalProvider = Provider.of<TerminalProvider>(
          context,
          listen: false,
        );

        // Filter out monitor_only hosts
        final availableHosts = hostProvider.hosts
            .where((h) => h.hostType != 'monitor_only')
            .toList();

        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                // Host selector dropdown
                SizedBox(
                  width: 200,
                  child: DropdownButtonFormField<int>(
                    value: _selectedHostId,
                    decoration: InputDecoration(
                      labelText: l10n.terminalSelectHost,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      border: const OutlineInputBorder(),
                      isDense: true,
                    ),
                    items: availableHosts.map((host) {
                      return DropdownMenuItem<int>(
                        value: host.id,
                        child: Text(
                          '${host.name} (${host.host}:${host.port})',
                          overflow: TextOverflow.ellipsis,
                        ),
                      );
                    }).toList(),
                    onChanged: (hostId) {
                      if (hostId != null) {
                        final host = availableHosts.firstWhere(
                          (h) => h.id == hostId,
                        );
                        _handleConnectHost(terminalProvider, host);
                        setState(() => _selectedHostId = null);
                      }
                    },
                  ),
                ),
                const SizedBox(width: 8),

                // Quick connect button
                ElevatedButton.icon(
                  onPressed: () {
                    // TODO: Implement quick connect dialog
                    ScaffoldMessenger.of(
                      context,
                    ).showSnackBar(SnackBar(content: Text(l10n.comingSoon)));
                  },
                  icon: const Icon(Icons.bolt, size: 18),
                  label: Text(l10n.terminalQuickConnect),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                  ),
                ),
                const SizedBox(width: 8),

                // Recording toggle
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey.shade300),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.videocam,
                        size: 16,
                        color: _recordingEnabled ? Colors.red : Colors.grey,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        l10n.terminalRecordSession,
                        style: const TextStyle(fontSize: 12),
                      ),
                      const SizedBox(width: 4),
                      Switch(
                        value: _recordingEnabled,
                        onChanged: (val) {
                          setState(() => _recordingEnabled = val);
                        },
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                    ],
                  ),
                ),

                const SizedBox(width: 8),

                // Tab list (for closing tabs)
                if (terminalProvider.sessions.isNotEmpty)
                  ...terminalProvider.sessions.map((session) {
                    final isActive =
                        terminalProvider.activeSessionId == session.id;
                    return Padding(
                      padding: const EdgeInsets.only(right: 4),
                      child: Chip(
                        label: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (session.record)
                              const Padding(
                                padding: EdgeInsets.only(right: 4),
                                child: Icon(
                                  Icons.fiber_manual_record,
                                  size: 8,
                                  color: Colors.red,
                                ),
                              ),
                            Text(session.name),
                          ],
                        ),
                        backgroundColor: isActive
                            ? Theme.of(context).primaryColor.withOpacity(0.2)
                            : null,
                        deleteIcon: const Icon(Icons.close, size: 16),
                        onDeleted: () {
                          terminalProvider.removeSession(session.id);
                        },
                      ),
                    );
                  }).toList(),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildEmptyState(BuildContext context, AppLocalizations l10n) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.terminal, size: 80, color: Colors.grey.shade400),
          const SizedBox(height: 16),
          Text(
            l10n.terminalNoActive,
            style: TextStyle(fontSize: 16, color: Colors.grey.shade700),
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: () {
              // User should select from dropdown
            },
            icon: const Icon(Icons.add),
            label: Text(l10n.terminalConnectToHost),
          ),
        ],
      ),
    );
  }

  void _handleConnectHost(TerminalProvider terminalProvider, host) {
    // Check if already has a session
    final existing = terminalProvider.findSessionByHostId(host.id);
    if (existing != null) {
      // Switch to existing session
      terminalProvider.setActiveSession(existing.id);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Switched to existing session for ${host.name}'),
          duration: const Duration(seconds: 2),
        ),
      );
    } else {
      // Create new session
      terminalProvider.addSession(
        hostId: host.id,
        name: host.name,
        record: _recordingEnabled,
      );
    }
  }
}
