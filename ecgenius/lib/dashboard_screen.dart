import 'package:flutter/material.dart';
import 'dart:async';
import 'package:ecgenius/widgets/ecg_chart.dart';
import 'package:ecgenius/widgets/bpm_card.dart';
import 'package:ecgenius/widgets/bpm_chart.dart';
import 'package:ecgenius/widgets/alert_box.dart';
import 'package:ecgenius/welcome_screen.dart';
import 'package:ecgenius/session_detail_screen.dart';
import 'package:ecgenius/services/ecg_api_service.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen>
    with SingleTickerProviderStateMixin {
  final ECGApi _api = ECGApi();
  int? currentSessionId;
  int bpm = 72;
  bool monitoring = false;
  late TabController _tabController;
  Timer? _bpmTimer;
  bool showWelcome = true;
  String? errorMessage;

  // Patient information
  final String patientName = "alina azam";
  final String accountNumber = "ACC-2024-001234";

  // Patient history data - now loaded from backend
  List<ECGSession> historyData = [];
  bool isLoadingHistory = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadHistory();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _bpmTimer?.cancel();
    super.dispose();
  }

  void _startMonitoring() async {
    try {
      setState(() {
        errorMessage = null;
      });

      // Create a new session
      final session = await _api.createSession(
        name: 'Live Monitoring - ${DateTime.now()}',
        source: 'mock',
      );
      setState(() {
        currentSessionId = session.id;
        monitoring = true;
      });

      // Fetch health status every 2 seconds
      _bpmTimer = Timer.periodic(const Duration(seconds: 2), (_) async {
        try {
          if (currentSessionId != null && mounted) {
            final health = await _api.getHealth(currentSessionId!);
            if (mounted) {
              setState(() {
                bpm = health.bpm.toInt();
              });
            }
          }
        } catch (e) {
          // Continue polling even if one request fails
          print('Error fetching health: $e');
        }
      });
    } catch (e) {
      setState(() {
        errorMessage = 'Failed to start monitoring: $e';
        monitoring = false;
      });
    }
  }

  void _stopMonitoring() {
    setState(() {
      monitoring = false;
    });
    _bpmTimer?.cancel();
    _bpmTimer = null;
  }

  void _onGetStarted() {
    setState(() {
      showWelcome = false;
    });
  }

  void _goBackToWelcome() {
    setState(() {
      showWelcome = true;
      monitoring = false;
      _bpmTimer?.cancel();
      _bpmTimer = null;
    });
  }

  Future<void> _loadHistory() async {
    try {
      setState(() {
        isLoadingHistory = true;
      });
      final sessions = await _api.listSessions();
      setState(() {
        historyData = sessions;
        isLoadingHistory = false;
      });
    } catch (e) {
      setState(() {
        isLoadingHistory = false;
      });
      print('Error loading history: $e');
    }
  }

  Future<void> _deleteSession(int sessionId) async {
    try {
      await _api.deleteSession(sessionId);
      await _loadHistory(); // Reload the list
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Session deleted successfully')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to delete session: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (showWelcome) {
      return Scaffold(body: WelcomeScreen(onGetStarted: _onGetStarted));
    }

    return Scaffold(
      backgroundColor: Colors.grey[50],
      body: SafeArea(
        child: Column(
          children: [
            // Header with Logo and Tabs
            _buildHeader(),
            // Tab Content
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _buildBPMChartTab(),
                  _buildECGChartTab(),
                  _buildHistoryTab(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      color: const Color(0xFF1E40AF),
      child: Column(
        children: [
          // Logo and Title Row
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  // Logo (Heart with ECG waveform)
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.favorite, color: Colors.white, size: 24),
                        SizedBox(width: 4),
                        Icon(Icons.show_chart, color: Colors.white, size: 20),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Text(
                    "ECG Monitoring System",
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(width: 12),
                  // Patient Info
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.person, color: Colors.white, size: 16),
                        const SizedBox(width: 6),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              patientName,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              accountNumber,
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.9),
                                fontSize: 10,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  // Back to Welcome Button
                  IconButton(
                    onPressed: _goBackToWelcome,
                    icon: const Icon(Icons.home, color: Colors.white, size: 20),
                    tooltip: 'Back to Welcome',
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.white.withValues(alpha: 0.2),
                      padding: const EdgeInsets.all(6),
                    ),
                  ),
                ],
              ),
            ),
          ),
          // Tabs
          Container(
            color: const Color(0xFF1E40AF),
            child: TabBar(
              controller: _tabController,
              indicatorColor: Colors.white,
              indicatorWeight: 3,
              labelColor: Colors.white,
              unselectedLabelColor: Colors.white70,
              labelStyle: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),

              tabs: const [
                Tab(text: 'BPM Chart'),
                Tab(text: 'ECG Chart'),
                Tab(text: 'Patient History'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBPMChartTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // BPM Chart
          BPMChart(monitoring: monitoring, bpm: bpm),
          const SizedBox(height: 24),
          // BPM Card
          BPMCard(bpm: bpm),
          const SizedBox(height: 24),
          // Alert Box
          AlertBox(bpm: bpm),
          const SizedBox(height: 24),
          // Control Buttons
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: monitoring ? null : _startMonitoring,
                  icon: const Icon(Icons.play_arrow),
                  label: const Text(
                    "Start Monitoring",
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green[600],
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 2,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: monitoring ? _stopMonitoring : null,
                  icon: const Icon(Icons.stop),
                  label: const Text(
                    "Stop Monitoring",
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red[600],
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 2,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildECGChartTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ECG Chart
          ECGChart(monitoring: monitoring),
          const SizedBox(height: 24),
          // Control Buttons
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: monitoring ? null : _startMonitoring,
                  icon: const Icon(Icons.play_arrow),
                  label: const Text(
                    "Start Monitoring",
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green[600],
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 2,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: monitoring ? _stopMonitoring : null,
                  icon: const Icon(Icons.stop),
                  label: const Text(
                    "Stop Monitoring",
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red[600],
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 2,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          // Status Indicator
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: monitoring ? Colors.green[50] : Colors.grey[200],
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: monitoring ? Colors.green[300]! : Colors.grey[300]!,
                width: 1,
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: monitoring ? Colors.green : Colors.grey,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  monitoring ? "Monitoring Active" : "Monitoring Stopped",
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: monitoring ? Colors.green[900] : Colors.grey[700],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHistoryTab() {
    if (isLoadingHistory) {
      return const Center(child: CircularProgressIndicator());
    }

    if (historyData.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.history, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(
              'No sessions found',
              style: TextStyle(color: Colors.grey[600], fontSize: 18),
            ),
            const SizedBox(height: 8),
            Text(
              'Start monitoring to create your first session',
              style: TextStyle(color: Colors.grey[500], fontSize: 14),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadHistory,
      child: ListView.builder(
        padding: const EdgeInsets.all(24),
        itemCount: historyData.length,
        itemBuilder: (context, index) {
          final session = historyData[index];
          final date = session.startedAt;
          final time = '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
          final duration = session.totalDurationSeconds != null
              ? '${session.totalDurationSeconds!.toStringAsFixed(1)}s'
              : 'Unknown';

          return Dismissible(
            key: Key('session_${session.id}'),
            direction: DismissDirection.endToStart,
            background: Container(
              alignment: Alignment.centerRight,
              padding: const EdgeInsets.only(right: 20),
              decoration: BoxDecoration(
                color: Colors.red[600],
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(
                Icons.delete,
                color: Colors.white,
                size: 28,
              ),
            ),
            confirmDismiss: (direction) async {
              return await showDialog(
                context: context,
                builder: (BuildContext context) {
                  return AlertDialog(
                    title: const Text('Delete Session'),
                    content: const Text('Are you sure you want to delete this session? This action cannot be undone.'),
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
                  );
                },
              );
            },
            onDismissed: (direction) {
              _deleteSession(session.id);
            },
            child: Container(
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: ListTile(
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (context) => SessionDetailScreen(session: session),
                    ),
                  );
                },
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 12,
                ),
                leading: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.blue[100],
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    Icons.favorite,
                    color: Colors.blue[700],
                    size: 24,
                  ),
                ),
                title: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "Session ${session.id}",
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      "${date.toLocal().toString().split(' ')[0]} at $time",
                      style: TextStyle(
                        color: Colors.grey[600],
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.green[100],
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        session.status,
                        style: TextStyle(
                          color: Colors.green[900],
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
                subtitle: Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.timer, size: 14, color: Colors.grey[600]),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              "Duration: $duration",
                              style: TextStyle(color: Colors.grey[600], fontSize: 14),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      if (session.name != null) ...[
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Icon(Icons.label, size: 14, color: Colors.grey[600]),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                session.name!,
                                style: TextStyle(color: Colors.grey[600], fontSize: 14),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
                trailing: Icon(Icons.chevron_right, color: Colors.grey[400]),
              ),
            ),
          );
        },
      ),
    );
  }
}
