import 'dart:io';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:couchbase_lite_p2p/couchbase_lite_p2p.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'screens/login_screen.dart';
import 'screens/work_orders_screen.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const Tele2FieldApp());
}

class Tele2FieldApp extends StatelessWidget {
  const Tele2FieldApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Tele2 Field',
      theme: tele2Theme,
      darkTheme: tele2DarkTheme,
      themeMode: ThemeMode.dark,
      home: const AuthGate(),
      debugShowCheckedModeBanner: false,
    );
  }
}

/// Checks for existing session before showing login or main app
class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  String? _technicianId;
  String? _technicianName;
  bool _checkingSession = true;

  @override
  void initState() {
    super.initState();
    _checkSession();
  }

  Future<void> _checkSession() async {
    final prefs = await SharedPreferences.getInstance();
    final id = prefs.getString('technician_id');
    final name = prefs.getString('technician_name');
    setState(() {
      _technicianId = id;
      _technicianName = name;
      _checkingSession = false;
    });
  }

  void _onLogin(String id, String name) {
    setState(() {
      _technicianId = id;
      _technicianName = name;
    });
  }

  Future<void> _onLogout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('technician_id');
    await prefs.remove('technician_name');
    setState(() {
      _technicianId = null;
      _technicianName = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_checkingSession) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (_technicianId == null) {
      return LoginScreen(onLogin: _onLogin);
    }

    return AppShell(
      technicianId: _technicianId!,
      technicianName: _technicianName ?? _technicianId!,
      onLogout: _onLogout,
    );
  }
}

class AppShell extends StatefulWidget {
  final String technicianId;
  final String technicianName;
  final VoidCallback onLogout;

  const AppShell({
    super.key,
    required this.technicianId,
    required this.technicianName,
    required this.onLogout,
  });

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  final _db = CouchbaseLiteP2p();
  bool _isOnline = true;
  String _syncStatus = 'Stopped';
  int _pendingChanges = 0;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    await [
      Permission.location,
      Permission.bluetooth,
      Permission.bluetoothScan,
      Permission.bluetoothAdvertise,
      Permission.bluetoothConnect,
      Permission.nearbyWifiDevices,
      Permission.camera,
      Permission.microphone,
    ].request();

    await _db.seedDemoData();
    _startSync();

    Connectivity().onConnectivityChanged.listen((results) {
      final online = results.any((r) => r != ConnectivityResult.none);
      if (mounted) setState(() => _isOnline = online);
    });

    _db.onSyncGatewayStatusChanged.listen((status) {
      if (mounted) {
        final newStatus = status['status'] as String? ?? 'Unknown';
        final wasBusy = _syncStatus == 'Busy';

        setState(() {
          _syncStatus = newStatus;
          _pendingChanges = (status['total'] as int? ?? 0) -
              (status['completed'] as int? ?? 0);
        });

        // Show confirmation when sync completes
        if (wasBusy && newStatus == 'Idle') {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Row(
                children: [
                  Icon(Icons.cloud_done, color: Colors.white, size: 18),
                  SizedBox(width: 8),
                  Text('Successfully synced',
                      style: TextStyle(fontWeight: FontWeight.w600)),
                ],
              ),
              backgroundColor: Colors.green,
              duration: const Duration(seconds: 2),
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
          );
        }
      }
    });
  }

  Future<void> _startSync() async {
    try {
      String url = 'ws://192.168.86.142:4984/main';
      if (Platform.isAndroid) {
        url = 'ws://10.0.2.2:4984/main';
      }
      await _db.startSyncGatewayReplication(url);
    } catch (e) {
      debugPrint("Failed to start sync: $e");
    }
  }

  @override
  void dispose() {
    _db.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary,
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Text(
                'Tele2',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                  fontSize: 18,
                ),
              ),
            ),
            const SizedBox(width: 8),
            const Text('Field'),
          ],
        ),
        actions: [
          // Sync status
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  _isOnline ? Icons.cloud_done : Icons.cloud_off,
                  color: _isOnline ? Colors.green : Colors.orange,
                  size: 18,
                ),
                const SizedBox(width: 4),
                Text(
                  _syncStatus,
                  style: TextStyle(fontSize: 11, color: _getSyncColor()),
                ),
              ],
            ),
          ),
          // Profile menu
          PopupMenuButton<String>(
            icon: CircleAvatar(
              radius: 16,
              backgroundColor: tele2Purple,
              child: Text(
                widget.technicianName[0].toUpperCase(),
                style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 14),
              ),
            ),
            onSelected: (value) {
              if (value == 'logout') widget.onLogout();
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                enabled: false,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(widget.technicianName,
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                    Text(widget.technicianId,
                        style:
                            TextStyle(fontSize: 12, color: Colors.grey[500])),
                  ],
                ),
              ),
              const PopupMenuDivider(),
              const PopupMenuItem(
                value: 'logout',
                child: Row(
                  children: [
                    Icon(Icons.logout, size: 18),
                    SizedBox(width: 8),
                    Text('Sign Out'),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          // Offline banner
          if (!_isOnline)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              color: Colors.orange.withValues(alpha: 0.15),
              child: Row(
                children: [
                  const Icon(Icons.cloud_off, size: 16, color: Colors.orange),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'You\'re offline. All changes are saved locally and will sync automatically.',
                      style: TextStyle(fontSize: 12, color: Colors.orange),
                    ),
                  ),
                ],
              ),
            ),
          // Syncing banner
          if (_isOnline && _syncStatus == 'Busy' && _pendingChanges > 0)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              color: tele2Purple.withValues(alpha: 0.15),
              child: Row(
                children: [
                  const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: tele2LightPurple),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Syncing changes...',
                    style: TextStyle(fontSize: 12, color: tele2LightPurple),
                  ),
                ],
              ),
            ),
          // Main content
          Expanded(
            child: WorkOrdersScreen(
              db: _db,
              technicianId: widget.technicianId,
              isOnline: _isOnline,
            ),
          ),
        ],
      ),
    );
  }

  Color _getSyncColor() {
    switch (_syncStatus) {
      case 'Idle':
        return Colors.green;
      case 'Busy':
        return Colors.blue;
      case 'Connecting':
        return Colors.orange;
      case 'Offline':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }
}
