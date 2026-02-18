import 'package:aspire/models/installment_model.dart';
import 'package:aspire/models/student_model.dart';
import 'package:aspire/services/db_helper.dart';
import 'package:aspire/widgets/addedit_student_dialogue.dart';
import 'package:aspire/views/installment_screen.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class StudentsPage extends StatefulWidget {
  const StudentsPage({super.key});

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
        // Header Bar
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 22),
          decoration: BoxDecoration(
            color: Colors.white,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // Title & subtitle
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Students',
                          style: TextStyle(
                            fontSize: 26,
                            fontWeight: FontWeight.bold,
                            color: const Color(0xFF1A237E),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${filteredStudents.length} of ${students.length} students',
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey[500],
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Add Student button
                  ElevatedButton.icon(
                    onPressed: () => _showAddEditDialog(null),
                    icon: const Icon(Icons.person_add_alt_1, size: 20),
                    label: const Text('Add Student'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF1A237E),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      elevation: 0,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              // Search bar
              TextField(
                controller: searchController,
                onChanged: _filterStudents,
                decoration: InputDecoration(
                  hintText: 'Search by name or roll number...',
                  hintStyle: TextStyle(color: Colors.grey[400], fontSize: 14),
                  prefixIcon: Icon(Icons.search, color: Colors.grey[400]),
                  contentPadding: const EdgeInsets.symmetric(vertical: 14),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(color: Colors.grey.shade300),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(color: Colors.grey.shade300),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: Color(0xFF1A237E), width: 1.5),
                  ),
                  filled: true,
                  fillColor: Colors.grey.shade50,
                ),
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

