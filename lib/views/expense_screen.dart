import 'package:aspire/constants/app_constants.dart';
import 'package:aspire/models/expense_model.dart';
import 'package:aspire/services/db_helper.dart';
import 'package:aspire/widgets/addedit_expense_dialogue.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class ExpensesPage extends StatefulWidget {
  const ExpensesPage({super.key});

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

