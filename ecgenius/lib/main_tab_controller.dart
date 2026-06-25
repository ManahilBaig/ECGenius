import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'login_screen.dart';
import 'ecg_screen.dart';
import 'patient_session_history_screen.dart';

class MainTabController extends StatefulWidget {
  final int initialIndex;
  const MainTabController({this.initialIndex = 0, super.key});

  @override
  State<MainTabController> createState() => MainTabControllerState();
}

class MainTabControllerState extends State<MainTabController> with SingleTickerProviderStateMixin {
  late int _currentIndex;
  bool _isEcgRecording = false;

  final GlobalKey<PatientSessionHistoryScreenState> _historyKey = GlobalKey();
  
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat(reverse: true);
    
    _pulseAnimation = Tween<double>(begin: 0.4, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  Future<void> _logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('is_logged_in', false);
    
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (context) => const LoginScreen()),
      (route) => false,
    );
  }

  void setRecordingState(bool isRecording) {
    setState(() {
      _isEcgRecording = isRecording;
    });
  }

  void switchToTab(int index) {
    setState(() {
      _currentIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E40AF),
        foregroundColor: Colors.white,
        elevation: 2,
        title: Text(
          _currentIndex == 0 ? 'ECGenius - Live ECG' : 'ECGenius - Session History',
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 20),
        ),
        actions: [
          if (_currentIndex == 1)
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: 'Refresh History',
              onPressed: () {
                _historyKey.currentState?.loadHistory();
              },
            ),
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Sign Out',
            onPressed: () {
              showDialog(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text('Sign Out'),
                  content: const Text('Are you sure you want to sign out?'),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Cancel'),
                    ),
                    TextButton(
                      onPressed: () {
                        Navigator.of(context).pop();
                        _logout();
                      },
                      style: TextButton.styleFrom(foregroundColor: Colors.red),
                      child: const Text('Sign Out'),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
      body: IndexedStack(
        index: _currentIndex,
        children: [
          ECGScreen(
            autoStart: false,
            onRecordingStateChanged: setRecordingState,
          ),
          PatientSessionHistoryScreen(
            key: _historyKey,
          ),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) {
          setState(() {
            _currentIndex = index;
          });
        },
        selectedItemColor: const Color(0xFF1E40AF),
        unselectedItemColor: Colors.grey[500],
        backgroundColor: Colors.white,
        elevation: 8,
        selectedLabelStyle: const TextStyle(fontWeight: FontWeight.bold),
        items: [
          BottomNavigationBarItem(
            label: 'Live ECG',
            icon: Stack(
              clipBehavior: Clip.none,
              children: [
                const Icon(Icons.favorite),
                if (_isEcgRecording)
                  Positioned(
                    right: -4,
                    top: -4,
                    child: FadeTransition(
                      opacity: _pulseAnimation,
                      child: Container(
                        width: 10,
                        height: 10,
                        decoration: const BoxDecoration(
                          color: Colors.redAccent,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const BottomNavigationBarItem(
            icon: Icon(Icons.history),
            label: 'Session History',
          ),
        ],
      ),
    );
  }
}
