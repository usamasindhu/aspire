import 'dart:async';

import 'package:aspire/main.dart';
import 'package:aspire/services/db_helper.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';

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

