import 'package:aspire/constants/app_constants.dart';
import 'package:aspire/models/expense_model.dart';
import 'package:aspire/models/installment_model.dart';
import 'package:aspire/services/db_helper.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class MonthDetailPage extends StatefulWidget {
  final int year;
  final int month;

  const MonthDetailPage({super.key, required this.year, required this.month});

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
                            // ignore: deprecated_member_use
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
