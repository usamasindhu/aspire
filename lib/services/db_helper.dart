import 'package:aspire/models/expense_model.dart';
import 'package:aspire/models/installment_model.dart';
import 'package:aspire/models/student_model.dart';
import 'package:aspire/services/auth_service.dart';
import 'package:aspire/services/sync_service.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;

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
    String dbPath;
    if (!kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
      final appDir = await getApplicationSupportDirectory();
      dbPath = appDir.path;
    } else {
      dbPath = await getDatabasesPath();
    }
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

