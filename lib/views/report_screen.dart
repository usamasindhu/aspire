import 'package:aspire/constants/app_constants.dart';
import 'package:aspire/main.dart';
import 'package:aspire/models/expense_model.dart';
import 'package:aspire/services/db_helper.dart';
import 'package:aspire/views/month_detail_screen.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

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

