import 'package:aspire/models/student_model.dart';
import 'package:aspire/services/db_helper.dart';
import 'package:flutter/material.dart';

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

