import 'dart:async';
import 'package:aspire/services/auth_service.dart';
import 'package:aspire/services/sync_service.dart';
import 'package:aspire/views/login_screen.dart';
import 'package:aspire/views/main_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart' as ffi;
import 'dart:io' show Platform;
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'firebase_options.dart';
// Sync Service for Firebase
class SyncStatus {
  final bool isOnline;
  final bool isSyncing;
  SyncStatus(this.isOnline, this.isSyncing);
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  if (!kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
    ffi.sqfliteFfiInit();
    databaseFactory = ffi.databaseFactoryFfi;
  }
  
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  SyncService.instance.init();
  
  runApp(StudentManagementApp());
}

class StudentManagementApp extends StatelessWidget {
  const StudentManagementApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Student Management System',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(primarySwatch: Colors.indigo, scaffoldBackgroundColor: Color(0xFFF5F7FA), fontFamily: 'Roboto'),
      home: AuthWrapper(),
    );
  }
}

// Auth Wrapper - Shows login or main screen based on auth state
class AuthWrapper extends StatefulWidget {
  const AuthWrapper({super.key});

  @override
  State<AuthWrapper> createState() => _AuthWrapperState();
}

class _AuthWrapperState extends State<AuthWrapper> {
  bool _checkedRememberMe = false;
  bool _isSyncing = false;
  bool _dataSynced = false;
  User? _previousUser;

  @override
  void initState() {
    super.initState();
    _checkRememberMe();
  }

  Future<void> _checkRememberMe() async {
    final prefs = await SharedPreferences.getInstance();
    final rememberMe = prefs.getBool('remember_me') ?? false;

    if (!rememberMe && FirebaseAuth.instance.currentUser != null) {
      await AuthService.instance.signOut();
    }

    // If user is already logged in (remember me), pull latest data
    if (FirebaseAuth.instance.currentUser != null) {
      await _syncData();
    }

    if (mounted) {
      setState(() => _checkedRememberMe = true);
    }
  }

  Future<void> _syncData() async {
    if (mounted) setState(() => _isSyncing = true);
    await SyncService.instance.restoreFromFirebase();
    if (mounted) {
      setState(() {
        _isSyncing = false;
        _dataSynced = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_checkedRememberMe) {
      return Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return StreamBuilder<User?>(
      stream: AuthService.instance.authStateChanges,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Scaffold(body: Center(child: CircularProgressIndicator()));
        }

        final user = snapshot.data;

        // Detect fresh sign-in: user was null, now logged in
        if (user != null && _previousUser == null && !_dataSynced) {
          _previousUser = user;
          // Schedule sync after build completes to avoid setState during build
          WidgetsBinding.instance.addPostFrameCallback((_) => _syncData());
        }
        _previousUser = user;

        // Show syncing screen while pulling data
        if (_isSyncing && user != null) {
          return Scaffold(
            body: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text(
                    'Syncing data...',
                    style: TextStyle(color: Colors.grey[600], fontSize: 14),
                  ),
                  SizedBox(height: 8),
                  Text(
                    'Fetching your data from the cloud',
                    style: TextStyle(color: Colors.grey[400], fontSize: 12),
                  ),
                ],
              ),
            ),
          );
        }

        if (user != null) {
          // Reset sync flag when user logs out later
          return MainScreen();
        }

        // User logged out — reset state for next sign-in
        _dataSynced = false;
        return LoginScreen();
      },
    );
  }
}
