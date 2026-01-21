
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'dart:io' show Platform;
import 'package:path/path.dart' as p;
import 'package:intl/intl.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Only initialize sqflite_ffi on desktop platforms (not web)
  if (!kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }
  
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  runApp(StudentManagementApp());
}

class StudentManagementApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Student Management System',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(primarySwatch: Colors.indigo, scaffoldBackgroundColor: Color(0xFFF5F7FA), fontFamily: 'Roboto'),
      home: MainScreen(),
    );
  }
}

// Database Helper
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

    return await openDatabase(dbFile, version: 1, onCreate: _createDB);
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
        paperFund REAL NOT NULL DEFAULT 1000
      )
    ''');

    await db.execute('''
      CREATE TABLE installments (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        studentId INTEGER NOT NULL,
        amount REAL NOT NULL,
        date TEXT NOT NULL,
        FOREIGN KEY (studentId) REFERENCES students (id) ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE TABLE audit_logs (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        action TEXT NOT NULL,
        details TEXT NOT NULL,
        timestamp TEXT NOT NULL
      )
    ''');
  }

  Future<int> insertStudent(Student student) async {
    final db = await database;
    final id = await db.insert('students', student.toMap());
    await addLog('CREATE', 'Added student: ${student.name} (${student.rollNum})');
    return id;
  }

  Future<List<Student>> getStudents() async {
    final db = await database;
    final result = await db.query('students');
    return result.map((json) => Student.fromMap(json)).toList();
  }

  Future<int> updateStudent(Student student) async {
    final db = await database;
    await addLog('UPDATE', 'Updated student: ${student.name} (${student.rollNum})');
    return db.update('students', student.toMap(), where: 'id = ?', whereArgs: [student.id]);
  }

  Future<int> deleteStudent(int id) async {
    final db = await database;
    final student = await db.query('students', where: 'id = ?', whereArgs: [id]);
    if (student.isNotEmpty) {
      await addLog('DELETE', 'Deleted student: ${student.first['name']} (${student.first['rollNum']})');
    }
    await db.delete('installments', where: 'studentId = ?', whereArgs: [id]);
    return db.delete('students', where: 'id = ?', whereArgs: [id]);
  }

  Future<int> addInstallment(Installment installment) async {
    final db = await database;
    final id = await db.insert('installments', installment.toMap());
    await addLog('PAYMENT', 'Installment added: ${installment.amount} PKR');
    return id;
  }

  Future<List<Installment>> getInstallments(int studentId) async {
    final db = await database;
    final result = await db.query('installments', where: 'studentId = ?', whereArgs: [studentId]);
    return result.map((json) => Installment.fromMap(json)).toList();
  }

  Future<int> deleteInstallment(int id) async {
    final db = await database;
    return db.delete('installments', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> addLog(String action, String details) async {
    final db = await database;
    await db.insert('audit_logs', {'action': action, 'details': details, 'timestamp': DateTime.now().toIso8601String()});
  }

  Future<List<Map<String, dynamic>>> getLogs() async {
    final db = await database;
    return db.query('audit_logs', orderBy: 'id DESC', limit: 100);
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
    );
  }
}

class Installment {
  int? id;
  int studentId;
  double amount;
  String date;

  Installment({this.id, required this.studentId, required this.amount, required this.date});

  Map<String, dynamic> toMap() {
    return {'id': id, 'studentId': studentId, 'amount': amount, 'date': date};
  }

  factory Installment.fromMap(Map<String, dynamic> map) {
    return Installment(id: map['id'], studentId: map['studentId'], amount: map['amount'], date: map['date']);
  }
}

// Main Screen
class MainScreen extends StatefulWidget {
  @override
  _MainScreenState createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _selectedIndex = 0;
  final dbHelper = DatabaseHelper.instance;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Row(
        children: [
          // Sidebar
          Container(
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
                      Text('Student Portal', style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),
                      SizedBox(height: 4),
                      Text('Management System', style: TextStyle(color: Colors.indigo.shade300, fontSize: 14)),
                    ],
                  ),
                ),
                SizedBox(height: 20),
                _buildMenuItem(0, Icons.dashboard, 'Dashboard'),
                _buildMenuItem(1, Icons.people, 'Students'),
                _buildMenuItem(2, Icons.history, 'Audit Logs'),
              ],
            ),
          ),
          // Main Content
          Expanded(child: _getPage(_selectedIndex)),
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
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    students = await dbHelper.getStudents();
    for (var student in students) {
      installmentsMap[student.id.toString()] = await dbHelper.getInstallments(student.id!);
    }
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

    return SingleChildScrollView(
      padding: EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Dashboard', style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: Colors.grey[800])),
          SizedBox(height: 24),

          // Summary Cards
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
    await dbHelper.deleteInstallment(inst.id!);
    await dbHelper.addLog('DELETE', 'Deleted installment of ${inst.amount} PKR for ${student.name}');
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

// Audit Logs Page
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
      default:
        icon = Icons.info;
        color = Colors.grey;
    }

    final timestamp = DateTime.parse(log['timestamp']);
    final formattedTime = DateFormat('dd MMM yyyy, hh:mm a').format(timestamp);

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
                Text(formattedTime, style: TextStyle(fontSize: 12, color: Colors.grey[600])),
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
