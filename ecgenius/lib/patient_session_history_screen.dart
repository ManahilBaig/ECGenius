import 'package:ecgenius/services/ecg_api_service.dart';
import 'package:ecgenius/session_details_screen.dart';
import 'package:flutter/material.dart';
import 'main_tab_controller.dart';

class PatientSessionHistoryScreen extends StatefulWidget {
  const PatientSessionHistoryScreen({super.key});

  @override
  State<PatientSessionHistoryScreen> createState() =>
      PatientSessionHistoryScreenState();
}

class PatientSessionHistoryScreenState
    extends State<PatientSessionHistoryScreen> {
  final ECGApi _api = ECGApi();
  List<ECGSession> _sessions = [];
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    loadHistory();
  }

  Future<void> loadHistory() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      final sessions = await _api.listSessions();
      if (!mounted) {
        return;
      }
      setState(() {
        _sessions = sessions;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isLoading = false;
        _errorMessage = 'Unable to load sessions: $e';
      });
    }
  }

  Future<void> _deleteSession(int sessionId) async {
    try {
      await _api.deleteSession(sessionId);
      await loadHistory();
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Session deleted')),
      );
    } catch (e) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to delete session: $e')),
      );
    }
  }

  void _startNewSession() {
    final tabController = context.findAncestorStateOfType<MainTabControllerState>();
    if (tabController != null) {
      tabController.switchToTab(0);
    } else {
      // Fallback in case it's not nested
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (context) => const MainTabController(initialIndex: 0)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: null, // Managed by MainTabController
      body: SafeArea(child: _buildBody()),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _startNewSession,
        backgroundColor: const Color(0xFF1E40AF),
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: const Text('New ECG'),
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_errorMessage!, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              ElevatedButton(
                  onPressed: loadHistory, child: const Text('Retry')),
            ],
          ),
        ),
      );
    }
    if (_sessions.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.history, size: 64, color: Colors.grey[400]),
              const SizedBox(height: 16),
              Text(
                'No recorded sessions yet',
                style: TextStyle(color: Colors.grey[700], fontSize: 18),
              ),
              const SizedBox(height: 8),
              Text(
                'Complete an ECG and tap End Session to save it here.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey[500]),
              ),
            ],
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: loadHistory,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 96),
        itemCount: _sessions.length,
        itemBuilder: (context, index) => _sessionTile(_sessions[index]),
      ),
    );
  }

  Widget _sessionTile(ECGSession session) {
    final startedAt = session.startedAt.toLocal();
    final date = startedAt.toString().split(' ').first;
    final time =
        '${startedAt.hour.toString().padLeft(2, '0')}:${startedAt.minute.toString().padLeft(2, '0')}';
    final duration = session.totalDurationSeconds == null
        ? 'Unknown'
        : '${session.totalDurationSeconds!.toStringAsFixed(0)}s';
    final bpmText =
        session.bpm == null ? 'BPM pending' : '${session.bpm!.round()} BPM';
    final symptoms = session.symptoms?.trim();

    return Dismissible(
      key: Key('session_${session.id}'),
      direction: DismissDirection.endToStart,
      confirmDismiss: (_) => _confirmDelete(),
      onDismissed: (_) => _deleteSession(session.id),
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        decoration: BoxDecoration(
          color: Colors.red[600],
          borderRadius: BorderRadius.circular(14),
        ),
        child: const Icon(Icons.delete, color: Colors.white),
      ),
      child: GestureDetector(
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (context) => SessionDetailsScreen(session: session),
            ),
          );
        },
        child: Container(
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 6,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.blue[50],
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(Icons.favorite, color: Colors.blue[700]),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        session.name ?? 'Session ${session.id}',
                        style: const TextStyle(
                            fontSize: 17, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 4),
                      Text('$date at $time',
                          style: TextStyle(color: Colors.grey[600])),
                    ],
                  ),
                ),
                Text(
                  bpmText,
                  style: const TextStyle(
                    color: Color(0xFF1E3A8A),
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _chip(Icons.timer, 'Duration: $duration'),
                _chip(Icons.check_circle_outline, session.status),
              ],
            ),
            if (symptoms != null && symptoms.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                'Symptoms: $symptoms',
                style: TextStyle(color: Colors.grey[700]),
              ),
            ],
          ],
        ),
        ),
      ),
    );
  }

  Widget _chip(IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.blue[50],
        borderRadius: BorderRadius.circular(99),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: const Color(0xFF1E40AF)),
          const SizedBox(width: 4),
          Text(label, style: const TextStyle(fontSize: 12)),
        ],
      ),
    );
  }

  Future<bool?> _confirmDelete() {
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Session'),
        content: const Text('Are you sure you want to delete this session?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }
}
