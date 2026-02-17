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

    if (mounted) {
      setState(() => _checkedRememberMe = true);
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

        if (snapshot.hasData) {
          return MainScreen();
        }

        return LoginScreen();
      },
    );
  }
}
