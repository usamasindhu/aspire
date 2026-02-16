import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart' as ffi;
import 'dart:io' show Platform;
import 'package:path/path.dart' as p;
import 'package:intl/intl.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:fl_chart/fl_chart.dart';
import 'firebase_options.dart';

// Expense Categories
const List<String> expenseCategories = [
  'Teacher Salary',
  'Staff',
  'Electricity',
  'Rent',
  'Stationary',
  'Maintenance',
  'Marketing',
  'Tax',
  'Royalty',
  'Other',
];

// Category colors for charts
final Map<String, Color> categoryColors = {
  'Teacher Salary': Colors.blue,
  'Staff': Colors.green,
  'Electricity': Colors.amber,
  'Rent': Colors.purple,
  'Stationary': Colors.orange,
  'Maintenance': Colors.teal,
  'Marketing': Colors.pink,
  'Tax': Colors.red,
  'Royalty': Colors.indigo,
  'Other': Colors.grey,
};

// Global auth state
class AuthService {
  static final AuthService instance = AuthService._init();
  AuthService._init();
  
  User? get currentUser => FirebaseAuth.instance.currentUser;
  String get currentUserEmail => currentUser?.email ?? 'Unknown';
  String get currentUserId => currentUser?.uid ?? '';
  
  Stream<User?> get authStateChanges => FirebaseAuth.instance.authStateChanges();
  
  Future<UserCredential> signIn(String email, String password) async {
    return await FirebaseAuth.instance.signInWithEmailAndPassword(
      email: email,
      password: password,
    );
  }
  
  Future<void> signOut() async {
    await FirebaseAuth.instance.signOut();
  }
}

// Sync Service for Firebase
class SyncService {
  static final SyncService instance = SyncService._init();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  StreamSubscription? _connectivitySubscription;
  bool _isOnline = false;
  bool _isSyncing = false;
  
  // Callbacks for UI updates
  final _syncStatusController = StreamController<SyncStatus>.broadcast();
  Stream<SyncStatus> get syncStatusStream => _syncStatusController.stream;
  
  SyncService._init();
  
  bool get isOnline => _isOnline;
  
  void init() {
    _connectivitySubscription = Connectivity().onConnectivityChanged.listen((results) {
      final wasOnline = _isOnline;
      _isOnline = results.any((r) => r != ConnectivityResult.none);
      
      if (_isOnline && !wasOnline) {
        // Just came online - sync pending data
        syncPendingData();
      }
      _syncStatusController.add(SyncStatus(_isOnline, _isSyncing));
    });
    
    // Check initial connectivity
    Connectivity().checkConnectivity().then((results) {
      _isOnline = results.any((r) => r != ConnectivityResult.none);
      _syncStatusController.add(SyncStatus(_isOnline, _isSyncing));
      if (_isOnline) {
        syncPendingData();
      }
    });
  }
  
  void dispose() {
    _connectivitySubscription?.cancel();
    _syncStatusController.close();
  }
  
  // Sync all pending local data to Firebase
  Future<void> syncPendingData() async {
    if (_isSyncing || !_isOnline) return;
    
    _isSyncing = true;
    _syncStatusController.add(SyncStatus(_isOnline, _isSyncing));
    
    try {
      final db = await DatabaseHelper.instance.database;
      
      // Sync students
      final pendingStudents = await db.query('students', where: 'syncStatus = ?', whereArgs: ['pending']);
      for (var studentMap in pendingStudents) {
        await _syncStudentToFirebase(studentMap);
      }
      
      // Sync deleted students
      final deletedStudents = await db.query('students', where: 'syncStatus = ?', whereArgs: ['deleted']);
      for (var studentMap in deletedStudents) {
        await _deleteStudentFromFirebase(studentMap);
      }
      
      // Sync installments
      final pendingInstallments = await db.query('installments', where: 'syncStatus = ?', whereArgs: ['pending']);
      for (var instMap in pendingInstallments) {
        await _syncInstallmentToFirebase(instMap);
      }
      
      // Sync deleted installments
      final deletedInstallments = await db.query('installments', where: 'syncStatus = ?', whereArgs: ['deleted']);
      for (var instMap in deletedInstallments) {
        await _deleteInstallmentFromFirebase(instMap);
      }
      
      // Sync audit logs
      final pendingLogs = await db.query('audit_logs', where: 'syncStatus = ?', whereArgs: ['pending']);
      for (var logMap in pendingLogs) {
        await _syncLogToFirebase(logMap);
      }
      
      // Sync expenses
      final pendingExpenses = await db.query('expenses', where: 'syncStatus = ?', whereArgs: ['pending']);
      for (var expenseMap in pendingExpenses) {
        await _syncExpenseToFirebase(expenseMap);
      }
      
      // Sync deleted expenses
      final deletedExpenses = await db.query('expenses', where: 'syncStatus = ?', whereArgs: ['deleted']);
      for (var expenseMap in deletedExpenses) {
        await _deleteExpenseFromFirebase(expenseMap);
      }
      
    } catch (e) {
      debugPrint('Sync error: $e');
    } finally {
      _isSyncing = false;
      _syncStatusController.add(SyncStatus(_isOnline, _isSyncing));
    }
  }
  
  Future<void> _syncStudentToFirebase(Map<String, dynamic> studentMap) async {
    try {
      final db = await DatabaseHelper.instance.database;
      String? firebaseId = studentMap['firebaseId'];
      
      final data = {
        'name': studentMap['name'],
        'rollNum': studentMap['rollNum'],
        'fatherName': studentMap['fatherName'],
        'contact': studentMap['contact'],
        'class': studentMap['class'],
        'gender': studentMap['gender'],
        'discipline': studentMap['discipline'],
        'totalPackage': studentMap['totalPackage'],
        'paperFund': studentMap['paperFund'],
        'localId': studentMap['id'],
        'lastModified': FieldValue.serverTimestamp(),
      };
      
      if (firebaseId != null && firebaseId.isNotEmpty) {
        await _firestore.collection('students').doc(firebaseId).update(data);
      } else {
        final docRef = await _firestore.collection('students').add(data);
        firebaseId = docRef.id;
        await db.update('students', {'firebaseId': firebaseId}, where: 'id = ?', whereArgs: [studentMap['id']]);
      }
      
      await db.update('students', {'syncStatus': 'synced'}, where: 'id = ?', whereArgs: [studentMap['id']]);
    } catch (e) {
      debugPrint('Error syncing student: $e');
    }
  }
  
  Future<void> _deleteStudentFromFirebase(Map<String, dynamic> studentMap) async {
    try {
      final db = await DatabaseHelper.instance.database;
      final firebaseId = studentMap['firebaseId'];
      
      if (firebaseId != null && firebaseId.isNotEmpty) {
        await _firestore.collection('students').doc(firebaseId).delete();
        // Also delete related installments from Firebase
        final installments = await _firestore.collection('installments')
            .where('studentFirebaseId', isEqualTo: firebaseId).get();
        for (var doc in installments.docs) {
          await doc.reference.delete();
        }
      }
      
      // Remove from local DB
      await db.delete('installments', where: 'studentId = ?', whereArgs: [studentMap['id']]);
      await db.delete('students', where: 'id = ?', whereArgs: [studentMap['id']]);
    } catch (e) {
      debugPrint('Error deleting student from Firebase: $e');
    }
  }
  
  Future<void> _syncInstallmentToFirebase(Map<String, dynamic> instMap) async {
    try {
      final db = await DatabaseHelper.instance.database;
      String? firebaseId = instMap['firebaseId'];
      
      // Get student's firebaseId
      final students = await db.query('students', where: 'id = ?', whereArgs: [instMap['studentId']]);
      if (students.isEmpty) return;
      final studentFirebaseId = students.first['firebaseId'];
      
      final data = {
        'studentId': instMap['studentId'],
        'studentFirebaseId': studentFirebaseId,
        'amount': instMap['amount'],
        'date': instMap['date'],
        'localId': instMap['id'],
        'lastModified': FieldValue.serverTimestamp(),
      };
      
      if (firebaseId != null && firebaseId.isNotEmpty) {
        await _firestore.collection('installments').doc(firebaseId).update(data);
      } else {
        final docRef = await _firestore.collection('installments').add(data);
        firebaseId = docRef.id;
        await db.update('installments', {'firebaseId': firebaseId}, where: 'id = ?', whereArgs: [instMap['id']]);
      }
      
      await db.update('installments', {'syncStatus': 'synced'}, where: 'id = ?', whereArgs: [instMap['id']]);
    } catch (e) {
      debugPrint('Error syncing installment: $e');
    }
  }
  
  Future<void> _deleteInstallmentFromFirebase(Map<String, dynamic> instMap) async {
    try {
      final db = await DatabaseHelper.instance.database;
      final firebaseId = instMap['firebaseId'];
      
      if (firebaseId != null && firebaseId.isNotEmpty) {
        await _firestore.collection('installments').doc(firebaseId).delete();
      }
      
      await db.delete('installments', where: 'id = ?', whereArgs: [instMap['id']]);
    } catch (e) {
      debugPrint('Error deleting installment from Firebase: $e');
    }
  }
  
  Future<void> _syncLogToFirebase(Map<String, dynamic> logMap) async {
    try {
      final db = await DatabaseHelper.instance.database;
      
      final data = {
        'action': logMap['action'],
        'details': logMap['details'],
        'timestamp': logMap['timestamp'],
        'userEmail': logMap['userEmail'],
        'userId': logMap['userId'],
        'localId': logMap['id'],
      };
      
      final docRef = await _firestore.collection('audit_logs').add(data);
      await db.update('audit_logs', {'firebaseId': docRef.id, 'syncStatus': 'synced'}, where: 'id = ?', whereArgs: [logMap['id']]);
    } catch (e) {
      debugPrint('Error syncing log: $e');
    }
  }
  
  Future<void> _syncExpenseToFirebase(Map<String, dynamic> expenseMap) async {
    try {
      final db = await DatabaseHelper.instance.database;
      String? firebaseId = expenseMap['firebaseId'];
      
      final data = {
        'category': expenseMap['category'],
        'amount': expenseMap['amount'],
        'date': expenseMap['date'],
        'notes': expenseMap['notes'],
        'userEmail': expenseMap['userEmail'],
        'userId': expenseMap['userId'],
        'localId': expenseMap['id'],
        'lastModified': FieldValue.serverTimestamp(),
      };
      
      if (firebaseId != null && firebaseId.isNotEmpty) {
        await _firestore.collection('expenses').doc(firebaseId).update(data);
      } else {
        final docRef = await _firestore.collection('expenses').add(data);
        firebaseId = docRef.id;
        await db.update('expenses', {'firebaseId': firebaseId}, where: 'id = ?', whereArgs: [expenseMap['id']]);
      }
      
      await db.update('expenses', {'syncStatus': 'synced'}, where: 'id = ?', whereArgs: [expenseMap['id']]);
    } catch (e) {
      debugPrint('Error syncing expense: $e');
    }
  }
  
  Future<void> _deleteExpenseFromFirebase(Map<String, dynamic> expenseMap) async {
    try {
      final db = await DatabaseHelper.instance.database;
      final firebaseId = expenseMap['firebaseId'];
      
      if (firebaseId != null && firebaseId.isNotEmpty) {
        await _firestore.collection('expenses').doc(firebaseId).delete();
      }
      
      await db.delete('expenses', where: 'id = ?', whereArgs: [expenseMap['id']]);
    } catch (e) {
      debugPrint('Error deleting expense from Firebase: $e');
    }
  }
  
  // Restore data from Firebase to local DB (for new device)
  Future<bool> restoreFromFirebase() async {
    if (!_isOnline) return false;
    
    try {
      final db = await DatabaseHelper.instance.database;
      
      // Check if local DB is empty
      final localStudents = await db.query('students');
      if (localStudents.isNotEmpty) {
        return false; // Already has data
      }
      
      // Restore students
      final studentsSnapshot = await _firestore.collection('students').get();
      for (var doc in studentsSnapshot.docs) {
        final data = doc.data();
        await db.insert('students', {
          'name': data['name'],
          'rollNum': data['rollNum'],
          'fatherName': data['fatherName'],
          'contact': data['contact'],
          'class': data['class'],
          'gender': data['gender'],
          'discipline': data['discipline'],
          'totalPackage': data['totalPackage'],
          'paperFund': data['paperFund'] ?? 1000,
          'firebaseId': doc.id,
          'syncStatus': 'synced',
        });
      }
      
      // Get updated local students to map firebaseId to localId
      final updatedStudents = await db.query('students');
      final firebaseToLocalId = <String, int>{};
      for (var s in updatedStudents) {
        if (s['firebaseId'] != null) {
          firebaseToLocalId[s['firebaseId'] as String] = s['id'] as int;
        }
      }
      
      // Restore installments
      final installmentsSnapshot = await _firestore.collection('installments').get();
      for (var doc in installmentsSnapshot.docs) {
        final data = doc.data();
        final studentFirebaseId = data['studentFirebaseId'];
        final localStudentId = firebaseToLocalId[studentFirebaseId];
        
        if (localStudentId != null) {
          await db.insert('installments', {
            'studentId': localStudentId,
            'amount': data['amount'],
            'date': data['date'],
            'firebaseId': doc.id,
            'syncStatus': 'synced',
          });
        }
      }
      
      // Restore audit logs
      final logsSnapshot = await _firestore.collection('audit_logs').orderBy('timestamp').get();
      for (var doc in logsSnapshot.docs) {
        final data = doc.data();
        await db.insert('audit_logs', {
          'action': data['action'],
          'details': data['details'],
          'timestamp': data['timestamp'],
          'userEmail': data['userEmail'] ?? 'Unknown',
          'userId': data['userId'] ?? '',
          'firebaseId': doc.id,
          'syncStatus': 'synced',
        });
      }
      
      // Restore expenses
      final expensesSnapshot = await _firestore.collection('expenses').get();
      for (var doc in expensesSnapshot.docs) {
        final data = doc.data();
        await db.insert('expenses', {
          'category': data['category'],
          'amount': data['amount'],
          'date': data['date'],
          'notes': data['notes'],
          'userEmail': data['userEmail'] ?? 'Unknown',
          'userId': data['userId'] ?? '',
          'firebaseId': doc.id,
          'syncStatus': 'synced',
        });
      }
      
      return true;
    } catch (e) {
      debugPrint('Restore error: $e');
      return false;
    }
  }
}

class SyncStatus {
  final bool isOnline;
  final bool isSyncing;
  SyncStatus(this.isOnline, this.isSyncing);
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Initialize sqflite_ffi only on desktop platforms (Windows/Linux/macOS)
  // Android/iOS use regular sqflite which works out of the box
  if (!kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
    ffi.sqfliteFfiInit();
    databaseFactory = ffi.databaseFactoryFfi;
  }
  
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  SyncService.instance.init();
  
  runApp(StudentManagementApp());
}

class StudentManagementApp extends StatelessWidget {
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
class AuthWrapper extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
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

// Login Screen
class LoginScreen extends StatefulWidget {
  @override
  _LoginScreenState createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;
  bool _obscurePassword = true;
  String? _errorMessage;
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF1A237E), Color(0xFF3949AB)],
          ),
        ),
        child: Center(
          child: SingleChildScrollView(
            child: Container(
              width: 420,
              margin: EdgeInsets.all(24),
              padding: EdgeInsets.all(40),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 20, offset: Offset(0, 10))],
              ),
              child: Form(
                key: _formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Color(0xFF1A237E).withOpacity(0.1),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Icon(Icons.school, size: 48, color: Color(0xFF1A237E)),
                    ),
                    SizedBox(height: 24),
                    Text('Student Portal', style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Color(0xFF1A237E))),
                    SizedBox(height: 8),
                    Text('Sign in to continue', style: TextStyle(color: Colors.grey[600], fontSize: 16)),
                    SizedBox(height: 32),
                    
                    if (_errorMessage != null)
                      Container(
                        padding: EdgeInsets.all(12),
                        margin: EdgeInsets.only(bottom: 16),
                        decoration: BoxDecoration(
                          color: Colors.red.shade50,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.red.shade200),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.error_outline, color: Colors.red, size: 20),
                            SizedBox(width: 8),
                            Expanded(child: Text(_errorMessage!, style: TextStyle(color: Colors.red.shade700, fontSize: 14))),
                          ],
                        ),
                      ),
                    
                    TextFormField(
                      controller: _emailController,
                      keyboardType: TextInputType.emailAddress,
                      decoration: InputDecoration(
                        labelText: 'Email',
                        prefixIcon: Icon(Icons.email_outlined),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        filled: true,
                        fillColor: Colors.grey.shade50,
                      ),
                      validator: (value) {
                        if (value?.isEmpty ?? true) return 'Email is required';
                        if (!value!.contains('@')) return 'Enter a valid email';
                        return null;
                      },
                    ),
                    SizedBox(height: 16),
                    
                    TextFormField(
                      controller: _passwordController,
                      obscureText: _obscurePassword,
                      decoration: InputDecoration(
                        labelText: 'Password',
                        prefixIcon: Icon(Icons.lock_outlined),
                        suffixIcon: IconButton(
                          icon: Icon(_obscurePassword ? Icons.visibility_off : Icons.visibility),
                          onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                        ),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        filled: true,
                        fillColor: Colors.grey.shade50,
                      ),
                      validator: (value) {
                        if (value?.isEmpty ?? true) return 'Password is required';
                        if (value!.length < 6) return 'Password must be at least 6 characters';
                        return null;
                      },
                    ),
                    SizedBox(height: 24),
                    
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton(
                        onPressed: _isLoading ? null : _signIn,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Color(0xFF1A237E),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        child: _isLoading
                            ? SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                            : Text('Sign In', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.white)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
  
  Future<void> _signIn() async {
    if (!_formKey.currentState!.validate()) return;
    
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    
    try {
      await AuthService.instance.signIn(
        _emailController.text.trim(),
        _passwordController.text,
      );
      
      // Try to restore data from Firebase for new device
      await SyncService.instance.restoreFromFirebase();
      
    } on FirebaseAuthException catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = _getAuthErrorMessage(e.code);
        });
      }
    } catch (e) {
      print('Auth error: $e');
      if (mounted) {
        setState(() {
          _errorMessage = 'Error: ${e.toString().length > 100 ? e.toString().substring(0, 100) : e.toString()}';
        });
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }
  
  String _getAuthErrorMessage(String code) {
    print('Auth error code: $code');
    switch (code) {
      case 'user-not-found': return 'No user found with this email.';
      case 'wrong-password': return 'Incorrect password.';
      case 'invalid-email': return 'Invalid email address.';
      case 'user-disabled': return 'This account has been disabled.';
      case 'invalid-credential': return 'Invalid email or password.';
      case 'network-request-failed': return 'Network error. Check:\n• Internet connection\n• Firebase Auth enabled in Console\n• Firewall settings';
      case 'too-many-requests': return 'Too many attempts. Try again later.';
      case 'operation-not-allowed': return 'Email/Password sign-in not enabled in Firebase Console.';
      default: return 'Authentication failed ($code).';
    }
  }
}

// Database Helper with sync support
class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();
  static Database? _database;

  DatabaseHelper._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('students.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final dbFile = p.join(dbPath, filePath);

    return await openDatabase(dbFile, version: 3, onCreate: _createDB, onUpgrade: _upgradeDB);
  }

  Future _createDB(Database db, int version) async {
    await db.execute('''
      CREATE TABLE students (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        rollNum TEXT NOT NULL UNIQUE,
        fatherName TEXT NOT NULL,
        contact TEXT NOT NULL,
        class TEXT NOT NULL,
        gender TEXT NOT NULL,
        discipline TEXT NOT NULL,
        totalPackage REAL NOT NULL,
        paperFund REAL NOT NULL DEFAULT 1000,
        firebaseId TEXT,
        syncStatus TEXT DEFAULT 'pending'
      )
    ''');

    await db.execute('''
      CREATE TABLE installments (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        studentId INTEGER NOT NULL,
        amount REAL NOT NULL,
        date TEXT NOT NULL,
        firebaseId TEXT,
        syncStatus TEXT DEFAULT 'pending',
        FOREIGN KEY (studentId) REFERENCES students (id) ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE TABLE audit_logs (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        action TEXT NOT NULL,
        details TEXT NOT NULL,
        timestamp TEXT NOT NULL,
        userEmail TEXT NOT NULL,
        userId TEXT NOT NULL,
        firebaseId TEXT,
        syncStatus TEXT DEFAULT 'pending'
      )
    ''');

    await db.execute('''
      CREATE TABLE expenses (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        category TEXT NOT NULL,
        amount REAL NOT NULL,
        date TEXT NOT NULL,
        notes TEXT,
        userEmail TEXT NOT NULL,
        userId TEXT NOT NULL,
        firebaseId TEXT,
        syncStatus TEXT DEFAULT 'pending'
      )
    ''');
  }

  Future _upgradeDB(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      // Add new columns for sync
      try { await db.execute('ALTER TABLE students ADD COLUMN firebaseId TEXT'); } catch (_) {}
      try { await db.execute('ALTER TABLE students ADD COLUMN syncStatus TEXT DEFAULT "pending"'); } catch (_) {}
      try { await db.execute('ALTER TABLE installments ADD COLUMN firebaseId TEXT'); } catch (_) {}
      try { await db.execute('ALTER TABLE installments ADD COLUMN syncStatus TEXT DEFAULT "pending"'); } catch (_) {}
      try { await db.execute('ALTER TABLE audit_logs ADD COLUMN firebaseId TEXT'); } catch (_) {}
      try { await db.execute('ALTER TABLE audit_logs ADD COLUMN syncStatus TEXT DEFAULT "pending"'); } catch (_) {}
      try { await db.execute('ALTER TABLE audit_logs ADD COLUMN userEmail TEXT DEFAULT "Unknown"'); } catch (_) {}
      try { await db.execute('ALTER TABLE audit_logs ADD COLUMN userId TEXT DEFAULT ""'); } catch (_) {}
    }
    if (oldVersion < 3) {
      // Add expenses table
      try {
        await db.execute('''
          CREATE TABLE expenses (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            category TEXT NOT NULL,
            amount REAL NOT NULL,
            date TEXT NOT NULL,
            notes TEXT,
            userEmail TEXT NOT NULL,
            userId TEXT NOT NULL,
            firebaseId TEXT,
            syncStatus TEXT DEFAULT 'pending'
          )
        ''');
      } catch (_) {}
    }
  }

  Future<int> insertStudent(Student student) async {
    final db = await database;
    final id = await db.insert('students', {...student.toMap(), 'syncStatus': 'pending'});
    await addLog('CREATE', 'Added student: ${student.name} (${student.rollNum})');
    
    // Try to sync immediately if online
    SyncService.instance.syncPendingData();
    return id;
  }

  Future<List<Student>> getStudents() async {
    final db = await database;
    final result = await db.query('students', where: 'syncStatus != ?', whereArgs: ['deleted']);
    return result.map((json) => Student.fromMap(json)).toList();
  }

  Future<int> updateStudent(Student student) async {
    final db = await database;
    await addLog('UPDATE', 'Updated student: ${student.name} (${student.rollNum})');
    final result = db.update('students', {...student.toMap(), 'syncStatus': 'pending'}, where: 'id = ?', whereArgs: [student.id]);
    
    SyncService.instance.syncPendingData();
    return result;
  }

  Future<int> deleteStudent(int id) async {
    final db = await database;
    final student = await db.query('students', where: 'id = ?', whereArgs: [id]);
    if (student.isNotEmpty) {
      await addLog('DELETE', 'Deleted student: ${student.first['name']} (${student.first['rollNum']})');
    }
    
    // Mark as deleted for sync
    await db.update('students', {'syncStatus': 'deleted'}, where: 'id = ?', whereArgs: [id]);
    await db.update('installments', {'syncStatus': 'deleted'}, where: 'studentId = ?', whereArgs: [id]);
    
    SyncService.instance.syncPendingData();
    return 1;
  }

  Future<int> addInstallment(Installment installment) async {
    final db = await database;
    final id = await db.insert('installments', {...installment.toMap(), 'syncStatus': 'pending'});
    
    // Get student name for log
    final student = await db.query('students', where: 'id = ?', whereArgs: [installment.studentId]);
    final studentName = student.isNotEmpty ? student.first['name'] : 'Unknown';
    await addLog('PAYMENT', 'Installment of ${installment.amount} PKR added for $studentName');
    
    SyncService.instance.syncPendingData();
    return id;
  }

  Future<List<Installment>> getInstallments(int studentId) async {
    final db = await database;
    final result = await db.query('installments', where: 'studentId = ? AND syncStatus != ?', whereArgs: [studentId, 'deleted']);
    return result.map((json) => Installment.fromMap(json)).toList();
  }

  Future<int> deleteInstallment(int id, String studentName, double amount) async {
    final db = await database;
    
    // Mark as deleted for sync
    await db.update('installments', {'syncStatus': 'deleted'}, where: 'id = ?', whereArgs: [id]);
    await addLog('DELETE', 'Deleted installment of $amount PKR for $studentName');
    
    SyncService.instance.syncPendingData();
    return 1;
  }

  Future<void> addLog(String action, String details) async {
    final db = await database;
    await db.insert('audit_logs', {
      'action': action,
      'details': details,
      'timestamp': DateTime.now().toIso8601String(),
      'userEmail': AuthService.instance.currentUserEmail,
      'userId': AuthService.instance.currentUserId,
      'syncStatus': 'pending',
    });
    
    SyncService.instance.syncPendingData();
  }

  Future<List<Map<String, dynamic>>> getLogs() async {
    final db = await database;
    return db.query('audit_logs', orderBy: 'id DESC', limit: 100);
  }

  // Expense CRUD operations
  Future<int> insertExpense(Expense expense) async {
    final db = await database;
    final id = await db.insert('expenses', {
      ...expense.toMap(),
      'userEmail': AuthService.instance.currentUserEmail,
      'userId': AuthService.instance.currentUserId,
      'syncStatus': 'pending',
    });
    await addLog('EXPENSE', 'Added expense: ${expense.category} - ${expense.amount} PKR');
    SyncService.instance.syncPendingData();
    return id;
  }

  Future<List<Expense>> getExpenses() async {
    final db = await database;
    final result = await db.query('expenses', where: 'syncStatus != ?', whereArgs: ['deleted'], orderBy: 'date DESC');
    return result.map((json) => Expense.fromMap(json)).toList();
  }

  Future<List<Expense>> getExpensesByMonth(int year, int month) async {
    final db = await database;
    final startDate = DateTime(year, month, 1).toIso8601String();
    final endDate = DateTime(year, month + 1, 0, 23, 59, 59).toIso8601String();
    final result = await db.query(
      'expenses',
      where: 'date >= ? AND date <= ? AND syncStatus != ?',
      whereArgs: [startDate, endDate, 'deleted'],
      orderBy: 'date DESC',
    );
    return result.map((json) => Expense.fromMap(json)).toList();
  }

  Future<List<Expense>> getExpensesByYear(int year) async {
    final db = await database;
    final startDate = DateTime(year, 1, 1).toIso8601String();
    final endDate = DateTime(year, 12, 31, 23, 59, 59).toIso8601String();
    final result = await db.query(
      'expenses',
      where: 'date >= ? AND date <= ? AND syncStatus != ?',
      whereArgs: [startDate, endDate, 'deleted'],
      orderBy: 'date DESC',
    );
    return result.map((json) => Expense.fromMap(json)).toList();
  }

  Future<int> updateExpense(Expense expense) async {
    final db = await database;
    await addLog('UPDATE', 'Updated expense: ${expense.category} - ${expense.amount} PKR');
    final result = await db.update('expenses', {...expense.toMap(), 'syncStatus': 'pending'}, where: 'id = ?', whereArgs: [expense.id]);
    SyncService.instance.syncPendingData();
    return result;
  }

  Future<int> deleteExpense(int id, String category, double amount) async {
    final db = await database;
    await db.update('expenses', {'syncStatus': 'deleted'}, where: 'id = ?', whereArgs: [id]);
    await addLog('DELETE', 'Deleted expense: $category - $amount PKR');
    SyncService.instance.syncPendingData();
    return 1;
  }

  // Get all installments for a date range (for reports)
  Future<List<Installment>> getAllInstallmentsByMonth(int year, int month) async {
    final db = await database;
    final startDate = DateTime(year, month, 1).toIso8601String();
    final endDate = DateTime(year, month + 1, 0, 23, 59, 59).toIso8601String();
    final result = await db.query(
      'installments',
      where: 'date >= ? AND date <= ? AND syncStatus != ?',
      whereArgs: [startDate, endDate, 'deleted'],
    );
    return result.map((json) => Installment.fromMap(json)).toList();
  }

  Future<List<Installment>> getAllInstallmentsByYear(int year) async {
    final db = await database;
    final startDate = DateTime(year, 1, 1).toIso8601String();
    final endDate = DateTime(year, 12, 31, 23, 59, 59).toIso8601String();
    final result = await db.query(
      'installments',
      where: 'date >= ? AND date <= ? AND syncStatus != ?',
      whereArgs: [startDate, endDate, 'deleted'],
    );
    return result.map((json) => Installment.fromMap(json)).toList();
  }
}

// Models
class Student {
  int? id;
  String name;
  String rollNum;
  String fatherName;
  String contact;
  String studentClass;
  String gender;
  String discipline;
  double totalPackage;
  double paperFund;
  String? firebaseId;

  Student({
    this.id,
    required this.name,
    required this.rollNum,
    required this.fatherName,
    required this.contact,
    required this.studentClass,
    required this.gender,
    required this.discipline,
    required this.totalPackage,
    this.paperFund = 1000,
    this.firebaseId,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'rollNum': rollNum,
      'fatherName': fatherName,
      'contact': contact,
      'class': studentClass,
      'gender': gender,
      'discipline': discipline,
      'totalPackage': totalPackage,
      'paperFund': paperFund,
      'firebaseId': firebaseId,
    };
  }

  factory Student.fromMap(Map<String, dynamic> map) {
    return Student(
      id: map['id'],
      name: map['name'],
      rollNum: map['rollNum'],
      fatherName: map['fatherName'],
      contact: map['contact'],
      studentClass: map['class'],
      gender: map['gender'],
      discipline: map['discipline'],
      totalPackage: map['totalPackage'],
      paperFund: map['paperFund'] ?? 1000,
      firebaseId: map['firebaseId'],
    );
  }
}

class Installment {
  int? id;
  int studentId;
  double amount;
  String date;
  String? firebaseId;

  Installment({this.id, required this.studentId, required this.amount, required this.date, this.firebaseId});

  Map<String, dynamic> toMap() {
    return {'id': id, 'studentId': studentId, 'amount': amount, 'date': date, 'firebaseId': firebaseId};
  }

  factory Installment.fromMap(Map<String, dynamic> map) {
    return Installment(id: map['id'], studentId: map['studentId'], amount: map['amount'], date: map['date'], firebaseId: map['firebaseId']);
  }
}

class Expense {
  int? id;
  String category;
  double amount;
  String date;
  String? notes;
  String? firebaseId;
  String? userEmail;
  String? userId;

  Expense({
    this.id,
    required this.category,
    required this.amount,
    required this.date,
    this.notes,
    this.firebaseId,
    this.userEmail,
    this.userId,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'category': category,
      'amount': amount,
      'date': date,
      'notes': notes,
      'firebaseId': firebaseId,
    };
  }

  factory Expense.fromMap(Map<String, dynamic> map) {
    return Expense(
      id: map['id'],
      category: map['category'],
      amount: map['amount'],
      date: map['date'],
      notes: map['notes'],
      firebaseId: map['firebaseId'],
      userEmail: map['userEmail'],
      userId: map['userId'],
    );
  }
}

// Main Screen with sync status indicator
class MainScreen extends StatefulWidget {
  @override
  _MainScreenState createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _selectedIndex = 0;
  bool _sidebarVisible = true;
  final dbHelper = DatabaseHelper.instance;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Row(
        children: [
          // Sidebar
          AnimatedContainer(
            duration: Duration(milliseconds: 200),
            width: _sidebarVisible ? 260 : 0,
            child: _sidebarVisible ? Container(
              width: 260,
              decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFF1A237E), Color(0xFF283593)])),
              child: Column(
                children: [
                  Container(
                    padding: EdgeInsets.all(24),
                    decoration: BoxDecoration(border: Border(bottom: BorderSide(color: Colors.indigo.shade700))),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(child: Text('Student Portal', style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold))),
                            // Sync status indicator
                            StreamBuilder<SyncStatus>(
                              stream: SyncService.instance.syncStatusStream,
                              builder: (context, snapshot) {
                                final status = snapshot.data;
                                final isOnline = status?.isOnline ?? false;
                                final isSyncing = status?.isSyncing ?? false;
                                
                                return Tooltip(
                                  message: isSyncing ? 'Syncing...' : (isOnline ? 'Online' : 'Offline'),
                                  child: Container(
                                    padding: EdgeInsets.all(6),
                                    decoration: BoxDecoration(
                                      color: isOnline ? Colors.green.withOpacity(0.2) : Colors.orange.withOpacity(0.2),
                                      borderRadius: BorderRadius.circular(20),
                                    ),
                                    child: isSyncing
                                        ? SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                        : Icon(isOnline ? Icons.cloud_done : Icons.cloud_off, color: isOnline ? Colors.green.shade300 : Colors.orange.shade300, size: 16),
                                  ),
                                );
                              },
                            ),
                          ],
                        ),
                        SizedBox(height: 4),
                        Text('Management System', style: TextStyle(color: Colors.indigo.shade300, fontSize: 14)),
                        SizedBox(height: 8),
                        // Current user
                        Container(
                          padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.person, color: Colors.white70, size: 14),
                              SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  AuthService.instance.currentUserEmail,
                                  style: TextStyle(color: Colors.white70, fontSize: 12),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(height: 20),
                  _buildMenuItem(0, Icons.dashboard, 'Dashboard'),
                  _buildMenuItem(1, Icons.people, 'Students'),
                  _buildMenuItem(2, Icons.receipt_long, 'Expenses'),
                  _buildMenuItem(3, Icons.analytics, 'Reports'),
                  _buildMenuItem(4, Icons.history, 'Audit Logs'),
                  Spacer(),
                  // Logout button
                  Padding(
                    padding: EdgeInsets.all(16),
                    child: SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: () async {
                          await AuthService.instance.signOut();
                        },
                        icon: Icon(Icons.logout, size: 18),
                        label: Text('Sign Out'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.red.shade400,
                          foregroundColor: Colors.white,
                          padding: EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ) : null,
          ),
          // Main Content
          Expanded(
            child: Column(
              children: [
                // Top bar with menu toggle
                Container(
                  padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  color: Colors.white,
                  child: Row(
                    children: [
                      IconButton(
                        icon: Icon(_sidebarVisible ? Icons.menu_open : Icons.menu, color: Color(0xFF1A237E)),
                        onPressed: () => setState(() => _sidebarVisible = !_sidebarVisible),
                        tooltip: _sidebarVisible ? 'Hide sidebar' : 'Show sidebar',
                      ),
                      if (!_sidebarVisible) ...[
                        SizedBox(width: 8),
                        Text('Student Portal', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF1A237E))),
                        Spacer(),
                        // Sync indicator when sidebar hidden
                        StreamBuilder<SyncStatus>(
                          stream: SyncService.instance.syncStatusStream,
                          builder: (context, snapshot) {
                            final status = snapshot.data;
                            final isOnline = status?.isOnline ?? false;
                            final isSyncing = status?.isSyncing ?? false;
                            
                            return Container(
                              padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                              decoration: BoxDecoration(
                                color: isOnline ? Colors.green.shade50 : Colors.orange.shade50,
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (isSyncing)
                                    SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.indigo))
                                  else
                                    Icon(isOnline ? Icons.cloud_done : Icons.cloud_off, color: isOnline ? Colors.green : Colors.orange, size: 14),
                                  SizedBox(width: 6),
                                  Text(isSyncing ? 'Syncing' : (isOnline ? 'Online' : 'Offline'), style: TextStyle(fontSize: 12, color: isOnline ? Colors.green.shade700 : Colors.orange.shade700)),
                                ],
                              ),
                            );
                          },
                        ),
                        SizedBox(width: 8),
                      ],
                    ],
                  ),
                ),
                Expanded(child: _getPage(_selectedIndex)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMenuItem(int index, IconData icon, String title) {
    bool isSelected = _selectedIndex == index;
    return InkWell(
      onTap: () => setState(() => _selectedIndex = index),
      child: Container(
        margin: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: isSelected ? Colors.indigo.shade700 : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border(left: BorderSide(color: isSelected ? Colors.amber : Colors.transparent, width: 4)),
        ),
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          child: Row(
            children: [
              Icon(icon, color: Colors.white, size: 22),
              SizedBox(width: 16),
              Text(title, style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _getPage(int index) {
    switch (index) {
      case 0:
        return DashboardPage();
      case 1:
        return StudentsPage();
      case 2:
        return ExpensesPage();
      case 3:
        return ReportsPage();
      case 4:
        return AuditLogsPage();
      default:
        return DashboardPage();
    }
  }
}

// Dashboard Page
class DashboardPage extends StatefulWidget {
  @override
  _DashboardPageState createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  final dbHelper = DatabaseHelper.instance;
  List<Student> students = [];
  Map<String, List<Installment>> installmentsMap = {};
  List<Expense> expensesYTD = [];
  List<Expense> expensesThisMonth = [];
  List<Installment> installmentsThisMonth = [];
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final now = DateTime.now();
    students = await dbHelper.getStudents();
    for (var student in students) {
      installmentsMap[student.id.toString()] = await dbHelper.getInstallments(student.id!);
    }
    expensesYTD = await dbHelper.getExpensesByYear(now.year);
    expensesThisMonth = await dbHelper.getExpensesByMonth(now.year, now.month);
    installmentsThisMonth = await dbHelper.getAllInstallmentsByMonth(now.year, now.month);
    setState(() => isLoading = false);
  }

  Map<String, dynamic> _getStats() {
    Map<String, dynamic> stats = {
      '11th_Boys': {'count': 0, 'collected': 0.0, 'pending': 0.0, 'totalPackage': 0.0},
      '11th_Girls': {'count': 0, 'collected': 0.0, 'pending': 0.0, 'totalPackage': 0.0},
      '12th_Boys': {'count': 0, 'collected': 0.0, 'pending': 0.0, 'totalPackage': 0.0},
      '12th_Girls': {'count': 0, 'collected': 0.0, 'pending': 0.0, 'totalPackage': 0.0},
    };

    for (var student in students) {
      String key = '${student.studentClass}_${student.gender}';
      stats[key]['count']++;
      stats[key]['totalPackage'] += student.totalPackage;

      double collected = 0;
      if (installmentsMap.containsKey(student.id.toString())) {
        collected = installmentsMap[student.id.toString()]!.fold(0, (sum, inst) => sum + inst.amount);
      }

      stats[key]['collected'] += collected;
      stats[key]['pending'] += (student.totalPackage - collected);
    }

    return stats;
  }

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return Center(child: CircularProgressIndicator());
    }

    final stats = _getStats();
    final total11th = stats['11th_Boys']['count'] + stats['11th_Girls']['count'];
    final total12th = stats['12th_Boys']['count'] + stats['12th_Girls']['count'];
    final totalCollected = stats.values.fold(0.0, (sum, s) => sum + s['collected']);
    final totalPending = stats.values.fold(0.0, (sum, s) => sum + s['pending']);
    final totalPackage = stats.values.fold(0.0, (sum, s) => sum + s['totalPackage']);
    
    // Expense calculations
    final totalExpensesYTD = expensesYTD.fold(0.0, (sum, e) => sum + e.amount);
    final totalExpensesThisMonth = expensesThisMonth.fold(0.0, (sum, e) => sum + e.amount);
    final collectedThisMonth = installmentsThisMonth.fold(0.0, (sum, i) => sum + i.amount);
    final profitThisMonth = collectedThisMonth - totalExpensesThisMonth;
    final monthName = DateFormat('MMMM').format(DateTime.now());

    return SingleChildScrollView(
      padding: EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Dashboard', style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: Colors.grey[800])),
          SizedBox(height: 24),

          // Summary Cards - Row 1 (Students)
          Row(
            children: [
              Expanded(child: _buildStatCard('11th Year Students', total11th.toString(), Icons.school, Colors.blue)),
              SizedBox(width: 16),
              Expanded(child: _buildStatCard('12th Year Students', total12th.toString(), Icons.school, Colors.green)),
              SizedBox(width: 16),
              Expanded(child: _buildStatCard('Total Package', '${totalPackage.toStringAsFixed(0)} PKR', Icons.inventory, Colors.purple)),
              SizedBox(width: 16),
              Expanded(child: _buildStatCard('Total Collected', '${totalCollected.toStringAsFixed(0)} PKR', Icons.account_balance_wallet, Colors.teal)),
              SizedBox(width: 16),
              Expanded(child: _buildStatCard('Total Pending', '${totalPending.toStringAsFixed(0)} PKR', Icons.pending_actions, Colors.orange)),
            ],
          ),
          
          SizedBox(height: 16),
          
          // Summary Cards - Row 2 (Expenses)
          Row(
            children: [
              Expanded(child: _buildStatCard('Expenses YTD', '${totalExpensesYTD.toStringAsFixed(0)} PKR', Icons.receipt_long, Colors.red)),
              SizedBox(width: 16),
              Expanded(child: _buildStatCard('$monthName Expenses', '${totalExpensesThisMonth.toStringAsFixed(0)} PKR', Icons.calendar_month, Colors.deepOrange)),
              SizedBox(width: 16),
              Expanded(child: _buildStatCard('$monthName Collections', '${collectedThisMonth.toStringAsFixed(0)} PKR', Icons.payments, Colors.cyan)),
              SizedBox(width: 16),
              Expanded(child: _buildStatCard('$monthName Profit/Loss', '${profitThisMonth >= 0 ? '+' : ''}${profitThisMonth.toStringAsFixed(0)} PKR', Icons.trending_up, profitThisMonth >= 0 ? Colors.green : Colors.red)),
            ],
          ),

          SizedBox(height: 32),
          Text('Class-wise Statistics', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.grey[800])),
          SizedBox(height: 16),

          // Class Cards Grid
          GridView.count(
            shrinkWrap: true,
            physics: NeverScrollableScrollPhysics(),
            crossAxisCount: 2,
            mainAxisSpacing: 16,
            crossAxisSpacing: 16,
            childAspectRatio: 2,
            children: [
              _buildClassCard('11th', 'Boys', stats['11th_Boys']),
              _buildClassCard('11th', 'Girls', stats['11th_Girls']),
              _buildClassCard('12th', 'Boys', stats['12th_Boys']),
              _buildClassCard('12th', 'Girls', stats['12th_Girls']),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatCard(String title, String value, IconData icon, Color color) {
    return Container(
      padding: EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 8, offset: Offset(0, 4))],
        border: Border(left: BorderSide(color: color, width: 4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [Expanded(child: Text(title, style: TextStyle(color: Colors.grey[600], fontSize: 14, fontWeight: FontWeight.w500))), Icon(icon, color: color.withOpacity(0.3), size: 36)],
          ),
          SizedBox(height: 12),
          Text(value, style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: color)),
        ],
      ),
    );
  }

  Widget _buildClassCard(String classYear, String gender, Map<String, dynamic> data) {
    double collected = data['collected'];
    double pending = data['pending'];
    double totalPackage = data['totalPackage'];
    int count = data['count'];
    double psa = count > 0 ? (totalPackage / count) : 0;
    double total = collected + pending;
    double percentage = total > 0 ? (collected / total * 100) : 0;

    return Container(
      padding: EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [Colors.white, Colors.grey.shade50], begin: Alignment.topLeft, end: Alignment.bottomRight),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 6, offset: Offset(0, 3))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [Text('$classYear - $gender', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.grey[800])), Icon(Icons.people, color: Colors.indigo, size: 24)],
          ),
          SizedBox(height: 16),
          _buildInfoRow('Students', count.toString(), Colors.grey[800]!),
          _buildInfoRow('Total Package', '${totalPackage.toStringAsFixed(0)} PKR', Colors.indigo),
          _buildInfoRow('PSA', '${psa.toStringAsFixed(0)} PKR', Colors.purple),
          _buildInfoRow('Collected', '${collected.toStringAsFixed(0)} PKR', Colors.green),
          _buildInfoRow('Pending', '${pending.toStringAsFixed(0)} PKR', Colors.red),
          SizedBox(height: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Collection Rate', style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                  Text('${percentage.toStringAsFixed(1)}%', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.indigo)),
                ],
              ),
              SizedBox(height: 4),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(value: percentage / 100, backgroundColor: Colors.grey[300], valueColor: AlwaysStoppedAnimation<Color>(Colors.indigo), minHeight: 8),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value, Color valueColor) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [Text(label, style: TextStyle(color: Colors.grey[600], fontSize: 13)), Text(value, style: TextStyle(fontWeight: FontWeight.bold, color: valueColor, fontSize: 13))],
      ),
    );
  }
}

// Students Page
class StudentsPage extends StatefulWidget {
  @override
  _StudentsPageState createState() => _StudentsPageState();
}

class _StudentsPageState extends State<StudentsPage> {
  final dbHelper = DatabaseHelper.instance;
  List<Student> students = [];
  List<Student> filteredStudents = [];
  Map<String, List<Installment>> installmentsMap = {};
  TextEditingController searchController = TextEditingController();
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    students = await dbHelper.getStudents();
    filteredStudents = students;
    for (var student in students) {
      installmentsMap[student.id.toString()] = await dbHelper.getInstallments(student.id!);
    }
    setState(() => isLoading = false);
  }

  void _filterStudents(String query) {
    setState(() {
      filteredStudents =
          students.where((student) {
            return student.name.toLowerCase().contains(query.toLowerCase()) || student.rollNum.toLowerCase().contains(query.toLowerCase());
          }).toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return Center(child: CircularProgressIndicator());
    }

    return Column(
      children: [
        Container(
          padding: EdgeInsets.all(24),
          color: Colors.white,
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: searchController,
                  onChanged: _filterStudents,
                  decoration: InputDecoration(
                    hintText: 'Search by name or roll number...',
                    prefixIcon: Icon(Icons.search),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: Colors.grey.shade300)),
                    filled: true,
                    fillColor: Colors.grey.shade50,
                  ),
                ),
              ),
              SizedBox(width: 16),
              ElevatedButton.icon(
                onPressed: () => _showAddEditDialog(null),
                icon: Icon(Icons.add),
                label: Text('Add Student'),
                style: ElevatedButton.styleFrom(padding: EdgeInsets.symmetric(horizontal: 24, vertical: 16), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: EdgeInsets.all(24),
            itemCount: filteredStudents.length,
            itemBuilder: (context, index) {
              return _buildStudentCard(filteredStudents[index]);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildStudentCard(Student student) {
    List<Installment> installments = installmentsMap[student.id.toString()] ?? [];
    double collected = installments.fold(0, (sum, inst) => sum + inst.amount);
    double pending = student.totalPackage - collected;

    return Card(
      margin: EdgeInsets.only(bottom: 16),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ExpansionTile(
        leading: CircleAvatar(backgroundColor: Colors.indigo, child: Text(student.name[0].toUpperCase(), style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold))),
        title: Text(student.name, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        subtitle: Text('${student.rollNum} • ${student.studentClass} ${student.gender} • ${student.discipline}'),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(icon: Icon(Icons.edit, color: Colors.blue), onPressed: () => _showAddEditDialog(student)),
            IconButton(icon: Icon(Icons.delete, color: Colors.red), onPressed: () => _deleteStudent(student)),
          ],
        ),
        children: [
          Padding(
            padding: EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [Expanded(child: _buildDetailItem('Father Name', student.fatherName)), Expanded(child: _buildDetailItem('Contact', student.contact))]),
                SizedBox(height: 12),
                Row(children: [Expanded(child: _buildDetailItem('Total Package', '${student.totalPackage} PKR')), Expanded(child: _buildDetailItem('Paper Fund', '${student.paperFund} PKR'))]),
                SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(child: _buildDetailItem('Collected', '${collected.toStringAsFixed(0)} PKR', Colors.green)),
                    Expanded(child: _buildDetailItem('Pending', '${pending.toStringAsFixed(0)} PKR', Colors.red)),
                  ],
                ),
                SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Installments (${installments.length})', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    ElevatedButton.icon(
                      onPressed: () => _showAddInstallmentDialog(student),
                      icon: Icon(Icons.add, size: 18),
                      label: Text('Add Payment'),
                      style: ElevatedButton.styleFrom(padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8)),
                    ),
                  ],
                ),
                SizedBox(height: 12),
                if (installments.isEmpty)
                  Center(child: Padding(padding: EdgeInsets.all(16), child: Text('No installments recorded', style: TextStyle(color: Colors.grey))))
                else
                  ...installments.map((inst) => _buildInstallmentItem(inst, student)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailItem(String label, String value, [Color? valueColor]) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(color: Colors.grey[600], fontSize: 12)),
        SizedBox(height: 4),
        Text(value, style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: valueColor ?? Colors.grey[800])),
      ],
    );
  }

  Widget _buildInstallmentItem(Installment inst, Student student) {
    return Container(
      margin: EdgeInsets.only(bottom: 8),
      padding: EdgeInsets.all(12),
      decoration: BoxDecoration(color: Colors.grey.shade50, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.grey.shade200)),
      child: Row(
        children: [
          Icon(Icons.payment, color: Colors.green, size: 20),
          SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${inst.amount} PKR', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                Text(DateFormat('dd MMM yyyy').format(DateTime.parse(inst.date)), style: TextStyle(color: Colors.grey[600], fontSize: 12)),
              ],
            ),
          ),
          IconButton(icon: Icon(Icons.delete_outline, color: Colors.red, size: 20), onPressed: () => _deleteInstallment(inst, student)),
        ],
      ),
    );
  }

  void _showAddEditDialog(Student? student) {
    showDialog(context: context, builder: (context) => AddEditStudentDialog(student: student, onSave: () => _loadData()));
  }

  void _showAddInstallmentDialog(Student student) {
    showDialog(context: context, builder: (context) => AddInstallmentDialog(student: student, onSave: () => _loadData()));
  }

  Future<void> _deleteStudent(Student student) async {
    bool? confirm = await showDialog<bool>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: Text('Delete Student'),
            content: Text('Are you sure you want to delete ${student.name}?'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context, false), child: Text('Cancel')),
              ElevatedButton(onPressed: () => Navigator.pop(context, true), style: ElevatedButton.styleFrom(backgroundColor: Colors.red), child: Text('Delete')),
            ],
          ),
    );

    if (confirm == true) {
      await dbHelper.deleteStudent(student.id!);
      _loadData();
    }
  }

  Future<void> _deleteInstallment(Installment inst, Student student) async {
    await dbHelper.deleteInstallment(inst.id!, student.name, inst.amount);
    _loadData();
  }
}

// Add/Edit Student Dialog
class AddEditStudentDialog extends StatefulWidget {
  final Student? student;
  final VoidCallback onSave;

  AddEditStudentDialog({this.student, required this.onSave});

  @override
  _AddEditStudentDialogState createState() => _AddEditStudentDialogState();
}

class _AddEditStudentDialogState extends State<AddEditStudentDialog> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController nameController;
  late TextEditingController rollNumController;
  late TextEditingController fatherNameController;
  late TextEditingController contactController;
  late TextEditingController totalPackageController;
  late TextEditingController paperFundController;

  String selectedClass = '11th';
  String selectedGender = 'Boys';
  String selectedDiscipline = 'Medical';

  @override
  void initState() {
    super.initState();
    nameController = TextEditingController(text: widget.student?.name ?? '');
    rollNumController = TextEditingController(text: widget.student?.rollNum ?? '');
    fatherNameController = TextEditingController(text: widget.student?.fatherName ?? '');
    contactController = TextEditingController(text: widget.student?.contact ?? '');
    totalPackageController = TextEditingController(text: widget.student?.totalPackage.toString() ?? '');
    paperFundController = TextEditingController(text: widget.student?.paperFund.toString() ?? '1000');

    if (widget.student != null) {
      selectedClass = widget.student!.studentClass;
      selectedGender = widget.student!.gender;
      selectedDiscipline = widget.student!.discipline;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        width: 600,
        padding: EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(widget.student == null ? 'Add New Student' : 'Edit Student', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                SizedBox(height: 24),

                TextFormField(
                  controller: nameController,
                  decoration: InputDecoration(labelText: 'Student Name', border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)), prefixIcon: Icon(Icons.person)),
                  validator: (value) => value?.isEmpty ?? true ? 'Required' : null,
                ),
                SizedBox(height: 16),

                TextFormField(
                  controller: rollNumController,
                  decoration: InputDecoration(labelText: 'Roll Number', border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)), prefixIcon: Icon(Icons.badge)),
                  validator: (value) => value?.isEmpty ?? true ? 'Required' : null,
                ),
                SizedBox(height: 16),

                TextFormField(
                  controller: fatherNameController,
                  decoration: InputDecoration(labelText: 'Father Name', border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)), prefixIcon: Icon(Icons.person_outline)),
                  validator: (value) => value?.isEmpty ?? true ? 'Required' : null,
                ),
                SizedBox(height: 16),

                TextFormField(
                  controller: contactController,
                  decoration: InputDecoration(labelText: 'Contact Number', border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)), prefixIcon: Icon(Icons.phone)),
                  validator: (value) => value?.isEmpty ?? true ? 'Required' : null,
                ),
                SizedBox(height: 16),

                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        value: selectedClass,
                        decoration: InputDecoration(labelText: 'Class', border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))),
                        items:
                            ['11th', '12th'].map((String value) {
                              return DropdownMenuItem<String>(value: value, child: Text(value));
                            }).toList(),
                        onChanged: (value) => setState(() => selectedClass = value!),
                      ),
                    ),
                    SizedBox(width: 16),
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        value: selectedGender,
                        decoration: InputDecoration(labelText: 'Gender', border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))),
                        items:
                            ['Boys', 'Girls'].map((String value) {
                              return DropdownMenuItem<String>(value: value, child: Text(value));
                            }).toList(),
                        onChanged: (value) => setState(() => selectedGender = value!),
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 16),

                DropdownButtonFormField<String>(
                  value: selectedDiscipline,
                  decoration: InputDecoration(labelText: 'Discipline', border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))),
                  items:
                      ['Medical', 'ICS', 'FA', 'Engineering'].map((String value) {
                        return DropdownMenuItem<String>(value: value, child: Text(value));
                      }).toList(),
                  onChanged: (value) => setState(() => selectedDiscipline = value!),
                ),
                SizedBox(height: 16),

                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: totalPackageController,
                        decoration: InputDecoration(labelText: 'Total Package (PKR)', border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)), prefixIcon: Icon(Icons.attach_money)),
                        keyboardType: TextInputType.number,
                        validator: (value) {
                          if (value?.isEmpty ?? true) return 'Required';
                          if (double.tryParse(value!) == null) return 'Invalid number';
                          return null;
                        },
                      ),
                    ),
                    SizedBox(width: 16),
                    Expanded(
                      child: TextFormField(
                        controller: paperFundController,
                        decoration: InputDecoration(labelText: 'Paper Fund (PKR)', border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)), prefixIcon: Icon(Icons.description)),
                        keyboardType: TextInputType.number,
                        validator: (value) {
                          if (value?.isEmpty ?? true) return 'Required';
                          if (double.tryParse(value!) == null) return 'Invalid number';
                          return null;
                        },
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 24),

                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(onPressed: () => Navigator.pop(context), child: Text('Cancel')),
                    SizedBox(width: 8),
                    ElevatedButton(onPressed: _saveStudent, style: ElevatedButton.styleFrom(padding: EdgeInsets.symmetric(horizontal: 32, vertical: 12)), child: Text('Save')),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _saveStudent() async {
    if (_formKey.currentState!.validate()) {
      final student = Student(
        id: widget.student?.id,
        name: nameController.text,
        rollNum: rollNumController.text,
        fatherName: fatherNameController.text,
        contact: contactController.text,
        studentClass: selectedClass,
        gender: selectedGender,
        discipline: selectedDiscipline,
        totalPackage: double.parse(totalPackageController.text),
        paperFund: double.parse(paperFundController.text),
        firebaseId: widget.student?.firebaseId,
      );

      if (widget.student == null) {
        await DatabaseHelper.instance.insertStudent(student);
      } else {
        await DatabaseHelper.instance.updateStudent(student);
      }

      widget.onSave();
      Navigator.pop(context);
    }
  }
}

// Add Installment Dialog
class AddInstallmentDialog extends StatefulWidget {
  final Student student;
  final VoidCallback onSave;

  AddInstallmentDialog({required this.student, required this.onSave});

  @override
  _AddInstallmentDialogState createState() => _AddInstallmentDialogState();
}

class _AddInstallmentDialogState extends State<AddInstallmentDialog> {
  final _formKey = GlobalKey<FormState>();
  final amountController = TextEditingController();
  DateTime selectedDate = DateTime.now();

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        width: 400,
        padding: EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Add Installment', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
              SizedBox(height: 8),
              Text('Student: ${widget.student.name}', style: TextStyle(color: Colors.grey[600])),
              SizedBox(height: 24),

              TextFormField(
                controller: amountController,
                decoration: InputDecoration(labelText: 'Amount (PKR)', border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)), prefixIcon: Icon(Icons.payment)),
                keyboardType: TextInputType.number,
                validator: (value) {
                  if (value?.isEmpty ?? true) return 'Required';
                  if (double.tryParse(value!) == null) return 'Invalid amount';
                  return null;
                },
              ),
              SizedBox(height: 16),

              InkWell(
                onTap: () async {
                  final date = await showDatePicker(context: context, initialDate: selectedDate, firstDate: DateTime(2020), lastDate: DateTime(2030));
                  if (date != null) {
                    setState(() => selectedDate = date);
                  }
                },
                child: InputDecorator(
                  decoration: InputDecoration(labelText: 'Payment Date', border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)), prefixIcon: Icon(Icons.calendar_today)),
                  child: Text(DateFormat('dd MMM yyyy').format(selectedDate)),
                ),
              ),
              SizedBox(height: 24),

              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(onPressed: () => Navigator.pop(context), child: Text('Cancel')),
                  SizedBox(width: 8),
                  ElevatedButton(onPressed: _saveInstallment, style: ElevatedButton.styleFrom(padding: EdgeInsets.symmetric(horizontal: 32, vertical: 12)), child: Text('Add Payment')),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _saveInstallment() async {
    if (_formKey.currentState!.validate()) {
      final installment = Installment(studentId: widget.student.id!, amount: double.parse(amountController.text), date: selectedDate.toIso8601String());

      await DatabaseHelper.instance.addInstallment(installment);
      widget.onSave();
      Navigator.pop(context);
    }
  }
}

// Audit Logs Page - now shows user info
class AuditLogsPage extends StatefulWidget {
  @override
  _AuditLogsPageState createState() => _AuditLogsPageState();
}

class _AuditLogsPageState extends State<AuditLogsPage> {
  final dbHelper = DatabaseHelper.instance;
  List<Map<String, dynamic>> logs = [];
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadLogs();
  }

  Future<void> _loadLogs() async {
    logs = await dbHelper.getLogs();
    setState(() => isLoading = false);
  }

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return Center(child: CircularProgressIndicator());
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.all(24),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Audit Logs', style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: Colors.grey[800])),
              Text('${logs.length} entries', style: TextStyle(color: Colors.grey[600])),
            ],
          ),
        ),
        Expanded(
          child:
              logs.isEmpty
                  ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [Icon(Icons.history, size: 64, color: Colors.grey[400]), SizedBox(height: 16), Text('No logs yet', style: TextStyle(color: Colors.grey[600], fontSize: 18))],
                    ),
                  )
                  : ListView.builder(
                    padding: EdgeInsets.symmetric(horizontal: 24),
                    itemCount: logs.length,
                    itemBuilder: (context, index) {
                      final log = logs[index];
                      return _buildLogItem(log);
                    },
                  ),
        ),
      ],
    );
  }

  Widget _buildLogItem(Map<String, dynamic> log) {
    IconData icon;
    Color color;

    switch (log['action']) {
      case 'CREATE':
        icon = Icons.add_circle;
        color = Colors.green;
        break;
      case 'UPDATE':
        icon = Icons.edit;
        color = Colors.blue;
        break;
      case 'DELETE':
        icon = Icons.delete;
        color = Colors.red;
        break;
      case 'PAYMENT':
        icon = Icons.payment;
        color = Colors.teal;
        break;
      case 'EXPENSE':
        icon = Icons.receipt_long;
        color = Colors.deepOrange;
        break;
      default:
        icon = Icons.info;
        color = Colors.grey;
    }

    final timestamp = DateTime.parse(log['timestamp']);
    final formattedTime = DateFormat('dd MMM yyyy, hh:mm a').format(timestamp);
    final userEmail = log['userEmail'] ?? 'Unknown';

    return Container(
      margin: EdgeInsets.only(bottom: 12),
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0, 2))],
        border: Border(left: BorderSide(color: color, width: 4)),
      ),
      child: Row(
        children: [
          Container(padding: EdgeInsets.all(8), decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(8)), child: Icon(icon, color: color, size: 24)),
          SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(log['details'], style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                SizedBox(height: 4),
                Row(
                  children: [
                    Icon(Icons.person, size: 12, color: Colors.grey[500]),
                    SizedBox(width: 4),
                    Text(userEmail, style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                    SizedBox(width: 12),
                    Icon(Icons.access_time, size: 12, color: Colors.grey[500]),
                    SizedBox(width: 4),
                    Text(formattedTime, style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                  ],
                ),
              ],
            ),
          ),
          Container(
            padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(12)),
            child: Text(log['action'], style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// EXPENSES PAGE
// ============================================================================

class ExpensesPage extends StatefulWidget {
  @override
  _ExpensesPageState createState() => _ExpensesPageState();
}

class _ExpensesPageState extends State<ExpensesPage> {
  final dbHelper = DatabaseHelper.instance;
  List<Expense> expenses = [];
  bool isLoading = true;
  String? filterCategory;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    expenses = await dbHelper.getExpenses();
    setState(() => isLoading = false);
  }

  List<Expense> get filteredExpenses {
    if (filterCategory == null) return expenses;
    return expenses.where((e) => e.category == filterCategory).toList();
  }

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return Center(child: CircularProgressIndicator());
    }

    final totalExpenses = expenses.fold(0.0, (sum, e) => sum + e.amount);

    return Column(
      children: [
        // Header
        Container(
          padding: EdgeInsets.all(24),
          color: Colors.white,
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Expenses', style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.grey[800])),
                    SizedBox(height: 4),
                    Text('Total: ${totalExpenses.toStringAsFixed(0)} PKR', style: TextStyle(color: Colors.grey[600], fontSize: 16)),
                  ],
                ),
              ),
              // Filter dropdown
              Container(
                padding: EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey.shade300),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String?>(
                    value: filterCategory,
                    hint: Text('All Categories'),
                    items: [
                      DropdownMenuItem(value: null, child: Text('All Categories')),
                      ...expenseCategories.map((c) => DropdownMenuItem(value: c, child: Text(c))),
                    ],
                    onChanged: (value) => setState(() => filterCategory = value),
                  ),
                ),
              ),
              SizedBox(width: 16),
              ElevatedButton.icon(
                onPressed: () => _showAddEditExpenseDialog(null),
                icon: Icon(Icons.add),
                label: Text('Add Expense'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Color(0xFF1A237E),
                  foregroundColor: Colors.white,
                  padding: EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
              ),
            ],
          ),
        ),
        // Expense List
        Expanded(
          child: filteredExpenses.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.receipt_long, size: 64, color: Colors.grey[400]),
                      SizedBox(height: 16),
                      Text('No expenses recorded', style: TextStyle(color: Colors.grey[600], fontSize: 18)),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: EdgeInsets.all(24),
                  itemCount: filteredExpenses.length,
                  itemBuilder: (context, index) => _buildExpenseCard(filteredExpenses[index]),
                ),
        ),
      ],
    );
  }

  Widget _buildExpenseCard(Expense expense) {
    final color = categoryColors[expense.category] ?? Colors.grey;
    final date = DateTime.parse(expense.date);
    final formattedDate = DateFormat('dd MMM yyyy').format(date);

    return Container(
      margin: EdgeInsets.only(bottom: 12),
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0, 2))],
        border: Border(left: BorderSide(color: color, width: 4)),
      ),
      child: Row(
        children: [
          Container(
            padding: EdgeInsets.all(12),
            decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(12)),
            child: Icon(Icons.receipt, color: color, size: 28),
          ),
          SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(expense.category, style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.grey[800])),
                SizedBox(height: 4),
                Text(formattedDate, style: TextStyle(color: Colors.grey[600], fontSize: 13)),
                if (expense.notes != null && expense.notes!.isNotEmpty) ...[
                  SizedBox(height: 4),
                  Text(expense.notes!, style: TextStyle(color: Colors.grey[500], fontSize: 12, fontStyle: FontStyle.italic)),
                ],
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text('${expense.amount.toStringAsFixed(0)} PKR', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: color)),
              SizedBox(height: 8),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: Icon(Icons.edit, color: Colors.blue, size: 20),
                    onPressed: () => _showAddEditExpenseDialog(expense),
                    tooltip: 'Edit',
                    constraints: BoxConstraints(),
                    padding: EdgeInsets.all(8),
                  ),
                  IconButton(
                    icon: Icon(Icons.delete, color: Colors.red, size: 20),
                    onPressed: () => _deleteExpense(expense),
                    tooltip: 'Delete',
                    constraints: BoxConstraints(),
                    padding: EdgeInsets.all(8),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _showAddEditExpenseDialog(Expense? expense) {
    showDialog(
      context: context,
      builder: (context) => AddEditExpenseDialog(
        expense: expense,
        onSave: () => _loadData(),
      ),
    );
  }

  Future<void> _deleteExpense(Expense expense) async {
    bool? confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete Expense'),
        content: Text('Are you sure you want to delete this ${expense.category} expense of ${expense.amount} PKR?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await dbHelper.deleteExpense(expense.id!, expense.category, expense.amount);
      _loadData();
    }
  }
}

// Add/Edit Expense Dialog
class AddEditExpenseDialog extends StatefulWidget {
  final Expense? expense;
  final VoidCallback onSave;

  AddEditExpenseDialog({this.expense, required this.onSave});

  @override
  _AddEditExpenseDialogState createState() => _AddEditExpenseDialogState();
}

class _AddEditExpenseDialogState extends State<AddEditExpenseDialog> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController amountController;
  late TextEditingController notesController;
  String selectedCategory = expenseCategories[0];
  DateTime selectedDate = DateTime.now();

  @override
  void initState() {
    super.initState();
    amountController = TextEditingController(text: widget.expense?.amount.toString() ?? '');
    notesController = TextEditingController(text: widget.expense?.notes ?? '');
    if (widget.expense != null) {
      selectedCategory = widget.expense!.category;
      selectedDate = DateTime.parse(widget.expense!.date);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        width: 450,
        padding: EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.expense == null ? 'Add Expense' : 'Edit Expense',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              ),
              SizedBox(height: 24),

              // Category Dropdown
              DropdownButtonFormField<String>(
                value: selectedCategory,
                decoration: InputDecoration(
                  labelText: 'Category',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  prefixIcon: Icon(Icons.category),
                ),
                items: expenseCategories.map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
                onChanged: (value) => setState(() => selectedCategory = value!),
              ),
              SizedBox(height: 16),

              // Amount
              TextFormField(
                controller: amountController,
                decoration: InputDecoration(
                  labelText: 'Amount (PKR)',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  prefixIcon: Icon(Icons.attach_money),
                ),
                keyboardType: TextInputType.number,
                validator: (value) {
                  if (value?.isEmpty ?? true) return 'Required';
                  if (double.tryParse(value!) == null) return 'Invalid amount';
                  return null;
                },
              ),
              SizedBox(height: 16),

              // Date Picker
              InkWell(
                onTap: () async {
                  final date = await showDatePicker(
                    context: context,
                    initialDate: selectedDate,
                    firstDate: DateTime(2020),
                    lastDate: DateTime(2030),
                  );
                  if (date != null) setState(() => selectedDate = date);
                },
                child: InputDecorator(
                  decoration: InputDecoration(
                    labelText: 'Date',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    prefixIcon: Icon(Icons.calendar_today),
                  ),
                  child: Text(DateFormat('dd MMM yyyy').format(selectedDate)),
                ),
              ),
              SizedBox(height: 16),

              // Notes (optional)
              TextFormField(
                controller: notesController,
                decoration: InputDecoration(
                  labelText: 'Notes (optional)',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  prefixIcon: Icon(Icons.notes),
                ),
                maxLines: 2,
              ),
              SizedBox(height: 24),

              // Buttons
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(onPressed: () => Navigator.pop(context), child: Text('Cancel')),
                  SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: _saveExpense,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Color(0xFF1A237E),
                      foregroundColor: Colors.white,
                      padding: EdgeInsets.symmetric(horizontal: 32, vertical: 12),
                    ),
                    child: Text(widget.expense == null ? 'Add' : 'Save'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _saveExpense() async {
    if (_formKey.currentState!.validate()) {
      final expense = Expense(
        id: widget.expense?.id,
        category: selectedCategory,
        amount: double.parse(amountController.text),
        date: selectedDate.toIso8601String(),
        notes: notesController.text.isEmpty ? null : notesController.text,
        firebaseId: widget.expense?.firebaseId,
      );

      if (widget.expense == null) {
        await DatabaseHelper.instance.insertExpense(expense);
      } else {
        await DatabaseHelper.instance.updateExpense(expense);
      }

      widget.onSave();
      Navigator.pop(context);
    }
  }
}

// ============================================================================
// REPORTS PAGE
// ============================================================================

class ReportsPage extends StatefulWidget {
  @override
  _ReportsPageState createState() => _ReportsPageState();
}

class _ReportsPageState extends State<ReportsPage> {
  final dbHelper = DatabaseHelper.instance;
  int selectedYear = DateTime.now().year;
  Map<int, double> monthlyCollections = {};
  Map<int, double> monthlyExpenses = {};
  List<Expense> yearExpenses = [];
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => isLoading = true);
    
    yearExpenses = await dbHelper.getExpensesByYear(selectedYear);
    
    // Calculate monthly data
    monthlyCollections = {};
    monthlyExpenses = {};
    
    for (int month = 1; month <= 12; month++) {
      final installments = await dbHelper.getAllInstallmentsByMonth(selectedYear, month);
      final expenses = await dbHelper.getExpensesByMonth(selectedYear, month);
      
      monthlyCollections[month] = installments.fold(0.0, (sum, i) => sum + i.amount);
      monthlyExpenses[month] = expenses.fold(0.0, (sum, e) => sum + e.amount);
    }
    
    setState(() => isLoading = false);
  }

  Map<String, double> get categoryBreakdown {
    final breakdown = <String, double>{};
    for (var expense in yearExpenses) {
      breakdown[expense.category] = (breakdown[expense.category] ?? 0) + expense.amount;
    }
    return breakdown;
  }

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return Center(child: CircularProgressIndicator());
    }

    final totalCollections = monthlyCollections.values.fold(0.0, (sum, v) => sum + v);
    final totalExpenses = monthlyExpenses.values.fold(0.0, (sum, v) => sum + v);
    final netProfit = totalCollections - totalExpenses;

    return SingleChildScrollView(
      padding: EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header with year selector
          Row(
            children: [
              Text('Financial Reports', style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: Colors.grey[800])),
              Spacer(),
              Container(
                padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.grey.shade300),
                ),
                child: Row(
                  children: [
                    IconButton(
                      icon: Icon(Icons.chevron_left),
                      onPressed: () {
                        setState(() => selectedYear--);
                        _loadData();
                      },
                    ),
                    Text('$selectedYear', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    IconButton(
                      icon: Icon(Icons.chevron_right),
                      onPressed: selectedYear < DateTime.now().year ? () {
                        setState(() => selectedYear++);
                        _loadData();
                      } : null,
                    ),
                  ],
                ),
              ),
            ],
          ),
          SizedBox(height: 24),

          // Summary Cards
          Row(
            children: [
              Expanded(child: _buildSummaryCard('Total Collections', totalCollections, Icons.account_balance_wallet, Colors.teal)),
              SizedBox(width: 16),
              Expanded(child: _buildSummaryCard('Total Expenses', totalExpenses, Icons.receipt_long, Colors.red)),
              SizedBox(width: 16),
              Expanded(child: _buildSummaryCard('Net Profit/Loss', netProfit, Icons.trending_up, netProfit >= 0 ? Colors.green : Colors.red)),
            ],
          ),
          SizedBox(height: 32),

          // Monthly Calendar Grid
          Text('Monthly Overview', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.grey[800])),
          SizedBox(height: 16),
          _buildMonthlyGrid(),
          SizedBox(height: 32),

          // Category Breakdown and Profit Chart
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: _buildCategoryBreakdown()),
              SizedBox(width: 24),
              Expanded(child: _buildProfitChart()),
            ],
          ),
          SizedBox(height: 32),

          // Top Categories
          _buildTopCategories(),
        ],
      ),
    );
  }

  Widget _buildSummaryCard(String title, double value, IconData icon, Color color) {
    return Container(
      padding: EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 8, offset: Offset(0, 4))],
        border: Border(left: BorderSide(color: color, width: 4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color.withOpacity(0.7), size: 32),
              Spacer(),
            ],
          ),
          SizedBox(height: 12),
          Text(title, style: TextStyle(color: Colors.grey[600], fontSize: 14)),
          SizedBox(height: 4),
          Text(
            '${value >= 0 ? '' : '-'}${value.abs().toStringAsFixed(0)} PKR',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: color),
          ),
        ],
      ),
    );
  }

  Widget _buildMonthlyGrid() {
    final months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

    return GridView.builder(
      shrinkWrap: true,
      physics: NeverScrollableScrollPhysics(),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 4,
        mainAxisSpacing: 16,
        crossAxisSpacing: 16,
        childAspectRatio: 1.5,
      ),
      itemCount: 12,
      itemBuilder: (context, index) {
        final month = index + 1;
        final collected = monthlyCollections[month] ?? 0;
        final expenses = monthlyExpenses[month] ?? 0;
        final profit = collected - expenses;
        final isCurrentMonth = selectedYear == DateTime.now().year && month == DateTime.now().month;

        return InkWell(
          onTap: () => _showMonthDetails(month),
          child: Container(
            padding: EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: isCurrentMonth ? Border.all(color: Color(0xFF1A237E), width: 2) : null,
              boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0, 2))],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(months[index], style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.grey[800])),
                    if (isCurrentMonth)
                      Container(
                        padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(color: Color(0xFF1A237E), borderRadius: BorderRadius.circular(4)),
                        child: Text('NOW', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                      ),
                  ],
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('C: ${collected.toStringAsFixed(0)}', style: TextStyle(fontSize: 12, color: Colors.teal)),
                    Text('E: ${expenses.toStringAsFixed(0)}', style: TextStyle(fontSize: 12, color: Colors.red)),
                  ],
                ),
                Container(
                  padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: profit >= 0 ? Colors.green.shade50 : Colors.red.shade50,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    '${profit >= 0 ? '+' : ''}${profit.toStringAsFixed(0)}',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: profit >= 0 ? Colors.green : Colors.red,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildCategoryBreakdown() {
    final breakdown = categoryBreakdown;
    if (breakdown.isEmpty) {
      return Container(
        padding: EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 4)],
        ),
        child: Column(
          children: [
            Text('Category Breakdown', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            SizedBox(height: 24),
            Icon(Icons.pie_chart_outline, size: 64, color: Colors.grey[400]),
            SizedBox(height: 8),
            Text('No expense data', style: TextStyle(color: Colors.grey[600])),
          ],
        ),
      );
    }

    final total = breakdown.values.fold(0.0, (sum, v) => sum + v);
    final sortedEntries = breakdown.entries.toList()..sort((a, b) => b.value.compareTo(a.value));

    return Container(
      padding: EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 4)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Category Breakdown', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          SizedBox(height: 24),
          SizedBox(
            height: 200,
            child: PieChart(
              PieChartData(
                sectionsSpace: 2,
                centerSpaceRadius: 40,
                sections: sortedEntries.map((entry) {
                  final color = categoryColors[entry.key] ?? Colors.grey;
                  final percentage = (entry.value / total * 100);
                  return PieChartSectionData(
                    color: color,
                    value: entry.value,
                    title: '${percentage.toStringAsFixed(0)}%',
                    radius: 60,
                    titleStyle: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white),
                  );
                }).toList(),
              ),
            ),
          ),
          SizedBox(height: 16),
          ...sortedEntries.take(5).map((entry) {
            final color = categoryColors[entry.key] ?? Colors.grey;
            final percentage = (entry.value / total * 100);
            return Padding(
              padding: EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  Container(width: 12, height: 12, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2))),
                  SizedBox(width: 8),
                  Expanded(child: Text(entry.key, style: TextStyle(fontSize: 13))),
                  Text('${percentage.toStringAsFixed(1)}%', style: TextStyle(fontSize: 13, color: Colors.grey[600])),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildProfitChart() {
    final maxValue = [
      ...monthlyCollections.values,
      ...monthlyExpenses.values,
    ].fold(0.0, (max, v) => v > max ? v : max);

    return Container(
      padding: EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 4)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Monthly Trend', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          SizedBox(height: 8),
          Row(
            children: [
              Container(width: 12, height: 12, color: Colors.teal),
              SizedBox(width: 4),
              Text('Collections', style: TextStyle(fontSize: 12)),
              SizedBox(width: 16),
              Container(width: 12, height: 12, color: Colors.red),
              SizedBox(width: 4),
              Text('Expenses', style: TextStyle(fontSize: 12)),
            ],
          ),
          SizedBox(height: 24),
          SizedBox(
            height: 250,
            child: BarChart(
              BarChartData(
                alignment: BarChartAlignment.spaceAround,
                maxY: maxValue * 1.2,
                barTouchData: BarTouchData(enabled: true),
                titlesData: FlTitlesData(
                  show: true,
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      getTitlesWidget: (value, meta) {
                        final months = ['J', 'F', 'M', 'A', 'M', 'J', 'J', 'A', 'S', 'O', 'N', 'D'];
                        return Text(months[value.toInt()], style: TextStyle(fontSize: 10));
                      },
                    ),
                  ),
                  leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                ),
                borderData: FlBorderData(show: false),
                barGroups: List.generate(12, (index) {
                  final month = index + 1;
                  return BarChartGroupData(
                    x: index,
                    barRods: [
                      BarChartRodData(
                        toY: monthlyCollections[month] ?? 0,
                        color: Colors.teal,
                        width: 8,
                        borderRadius: BorderRadius.circular(2),
                      ),
                      BarChartRodData(
                        toY: monthlyExpenses[month] ?? 0,
                        color: Colors.red,
                        width: 8,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ],
                  );
                }),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTopCategories() {
    final breakdown = categoryBreakdown;
    final sortedEntries = breakdown.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    final total = breakdown.values.fold(0.0, (sum, v) => sum + v);

    return Container(
      padding: EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 4)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Top Expense Categories', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          SizedBox(height: 16),
          if (sortedEntries.isEmpty)
            Center(child: Text('No expense data', style: TextStyle(color: Colors.grey[600])))
          else
            ...sortedEntries.map((entry) {
              final color = categoryColors[entry.key] ?? Colors.grey;
              final percentage = total > 0 ? (entry.value / total * 100) : 0.0;
              return Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: EdgeInsets.all(8),
                          decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
                          child: Icon(Icons.receipt, color: color, size: 20),
                        ),
                        SizedBox(width: 12),
                        Expanded(child: Text(entry.key, style: TextStyle(fontWeight: FontWeight.w500))),
                        Text('${entry.value.toStringAsFixed(0)} PKR', style: TextStyle(fontWeight: FontWeight.bold, color: color)),
                      ],
                    ),
                    SizedBox(height: 8),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: percentage / 100,
                        backgroundColor: Colors.grey[200],
                        valueColor: AlwaysStoppedAnimation<Color>(color),
                        minHeight: 6,
                      ),
                    ),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }

  void _showMonthDetails(int month) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => MonthDetailPage(year: selectedYear, month: month),
      ),
    );
  }
}

// Month Detail Page
class MonthDetailPage extends StatefulWidget {
  final int year;
  final int month;

  MonthDetailPage({required this.year, required this.month});

  @override
  _MonthDetailPageState createState() => _MonthDetailPageState();
}

class _MonthDetailPageState extends State<MonthDetailPage> {
  final dbHelper = DatabaseHelper.instance;
  List<Expense> expenses = [];
  List<Installment> installments = [];
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    expenses = await dbHelper.getExpensesByMonth(widget.year, widget.month);
    installments = await dbHelper.getAllInstallmentsByMonth(widget.year, widget.month);
    setState(() => isLoading = false);
  }

  Map<String, List<Expense>> get expensesByCategory {
    final grouped = <String, List<Expense>>{};
    for (var expense in expenses) {
      grouped.putIfAbsent(expense.category, () => []).add(expense);
    }
    return grouped;
  }

  @override
  Widget build(BuildContext context) {
    final monthName = DateFormat('MMMM yyyy').format(DateTime(widget.year, widget.month));
    final totalCollected = installments.fold(0.0, (sum, i) => sum + i.amount);
    final totalExpenses = expenses.fold(0.0, (sum, e) => sum + e.amount);
    final profit = totalCollected - totalExpenses;

    return Scaffold(
      appBar: AppBar(
        title: Text(monthName),
        backgroundColor: Color(0xFF1A237E),
        foregroundColor: Colors.white,
      ),
      body: isLoading
          ? Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Summary
                  Row(
                    children: [
                      Expanded(child: _buildSummaryCard('Collected', totalCollected, Colors.teal)),
                      SizedBox(width: 16),
                      Expanded(child: _buildSummaryCard('Expenses', totalExpenses, Colors.red)),
                      SizedBox(width: 16),
                      Expanded(child: _buildSummaryCard('Profit/Loss', profit, profit >= 0 ? Colors.green : Colors.red)),
                    ],
                  ),
                  SizedBox(height: 32),

                  // Category breakdown
                  Text('Expenses by Category', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                  SizedBox(height: 16),
                  if (expensesByCategory.isEmpty)
                    Container(
                      padding: EdgeInsets.all(32),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Center(
                        child: Column(
                          children: [
                            Icon(Icons.receipt_long, size: 64, color: Colors.grey[400]),
                            SizedBox(height: 16),
                            Text('No expenses this month', style: TextStyle(color: Colors.grey[600])),
                          ],
                        ),
                      ),
                    )
                  else
                    ...expensesByCategory.entries.map((entry) {
                      final categoryTotal = entry.value.fold(0.0, (sum, e) => sum + e.amount);
                      final color = categoryColors[entry.key] ?? Colors.grey;
                      return Container(
                        margin: EdgeInsets.only(bottom: 12),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 4)],
                        ),
                        child: ExpansionTile(
                          leading: Container(
                            padding: EdgeInsets.all(8),
                            decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
                            child: Icon(Icons.receipt, color: color),
                          ),
                          title: Text(entry.key, style: TextStyle(fontWeight: FontWeight.bold)),
                          subtitle: Text('${entry.value.length} expenses'),
                          trailing: Text('${categoryTotal.toStringAsFixed(0)} PKR', style: TextStyle(fontWeight: FontWeight.bold, color: color)),
                          children: entry.value.map((expense) {
                            final date = DateTime.parse(expense.date);
                            return ListTile(
                              contentPadding: EdgeInsets.symmetric(horizontal: 24),
                              title: Text('${expense.amount.toStringAsFixed(0)} PKR'),
                              subtitle: Text(expense.notes ?? DateFormat('dd MMM').format(date)),
                              trailing: Text(DateFormat('dd MMM').format(date), style: TextStyle(color: Colors.grey[600])),
                            );
                          }).toList(),
                        ),
                      );
                    }),
                ],
              ),
            ),
    );
  }

  Widget _buildSummaryCard(String title, double value, Color color) {
    return Container(
      padding: EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 4)],
        border: Border(left: BorderSide(color: color, width: 4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: TextStyle(color: Colors.grey[600], fontSize: 14)),
          SizedBox(height: 8),
          Text(
            '${value >= 0 ? '' : '-'}${value.abs().toStringAsFixed(0)} PKR',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: color),
          ),
        ],
      ),
    );
  }
}
