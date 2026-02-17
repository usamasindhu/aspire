import 'package:aspire/models/installment_model.dart';
import 'package:aspire/models/student_model.dart';
import 'package:aspire/services/db_helper.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

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
      // ignore: use_build_context_synchronously
      Navigator.pop(context);
    }
  }
}

