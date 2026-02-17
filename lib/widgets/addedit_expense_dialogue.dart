import 'package:aspire/constants/app_constants.dart';
import 'package:aspire/models/expense_model.dart';
import 'package:aspire/services/db_helper.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class AddEditExpenseDialog extends StatefulWidget {
  final Expense? expense;
  final VoidCallback onSave;

  const AddEditExpenseDialog({super.key, this.expense, required this.onSave});

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
                initialValue: selectedCategory,
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
      // ignore: use_build_context_synchronously
      Navigator.pop(context);
    }
  }
}

