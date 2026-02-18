import 'package:aspire/models/expense_model.dart';
import 'package:aspire/models/installment_model.dart';
import 'package:aspire/models/student_model.dart';
import 'package:aspire/services/auth_service.dart';
import 'package:aspire/services/db_helper.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class DashboardPage extends StatefulWidget {
  final bool sidebarVisible;
  final VoidCallback onToggleSidebar;

  const DashboardPage({
    super.key,
    required this.sidebarVisible,
    required this.onToggleSidebar,
  });

  @override
  _DashboardPageState createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  final dbHelper = DatabaseHelper.instance;
  List<Student> students = [];
  Map<String, List<Installment>> installmentsMap = {};
  List<Expense> expensesYTD = [];
  List<Expense> expensesThisMonth = [];
  List<Installment> installmentsThisMonth = [];
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final now = DateTime.now();
    students = await dbHelper.getStudents();
    for (var student in students) {
      installmentsMap[student.id.toString()] = await dbHelper.getInstallments(student.id!);
    }
    expensesYTD = await dbHelper.getExpensesByYear(now.year);
    expensesThisMonth = await dbHelper.getExpensesByMonth(now.year, now.month);
    installmentsThisMonth = await dbHelper.getAllInstallmentsByMonth(now.year, now.month);
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

  String _getGreeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good Morning';
    if (hour < 15) return 'Good Afternoon';
    if (hour < 18) return 'Good Evening';
    return 'Good Night';
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

    // Expense calculations
    final totalExpensesYTD = expensesYTD.fold(0.0, (sum, e) => sum + e.amount);
    final totalExpensesThisMonth = expensesThisMonth.fold(0.0, (sum, e) => sum + e.amount);
    final collectedThisMonth = installmentsThisMonth.fold(0.0, (sum, i) => sum + i.amount);
    final profitThisMonth = collectedThisMonth - totalExpensesThisMonth;
    final monthName = DateFormat('MMMM').format(DateTime.now());

    final greeting = _getGreeting();
    final userName = AuthService.instance.currentUser?.displayName ??
        AuthService.instance.currentUserEmail.split('@').first;
    final formattedDate = DateFormat('EEEE, MMMM d, yyyy').format(DateTime.now());

    return SingleChildScrollView(
      padding: EdgeInsets.all(10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header with greeting and sign out
          Padding(
            padding: EdgeInsets.all(10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                if (!widget.sidebarVisible) ...[
                  IconButton(
                    onPressed: widget.onToggleSidebar,
                    icon: Icon(Icons.menu, color: Color(0xFF1A237E), size: 24),
                    tooltip: 'Show sidebar',
                  ),
                  SizedBox(width: 8),
                ],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '$greeting, $userName',
                        style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.grey[800]),
                      ),
                      SizedBox(height: 4),
                      Text(
                        formattedDate,
                        style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () async {
                    await AuthService.instance.signOut();
                  },
                  icon: Icon(Icons.logout, color: Colors.red, size: 24),
                  tooltip: 'Sign Out',
                ),
              ],
            ),
          ),
          SizedBox(height: 10),

          // Summary Cards - Row 1 (Students)
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
          
          SizedBox(height: 16),
          
          // Summary Cards - Row 2 (Expenses)
          Row(
            children: [
              Expanded(child: _buildStatCard('Expenses YTD', '${totalExpensesYTD.toStringAsFixed(0)} PKR', Icons.receipt_long, Colors.red)),
              SizedBox(width: 16),
              Expanded(child: _buildStatCard('$monthName Expenses', '${totalExpensesThisMonth.toStringAsFixed(0)} PKR', Icons.calendar_month, Colors.deepOrange)),
              SizedBox(width: 16),
              Expanded(child: _buildStatCard('$monthName Collections', '${collectedThisMonth.toStringAsFixed(0)} PKR', Icons.payments, Colors.cyan)),
              SizedBox(width: 16),
              Expanded(child: _buildStatCard('$monthName Profit/Loss', '${profitThisMonth >= 0 ? '+' : ''}${profitThisMonth.toStringAsFixed(0)} PKR', Icons.trending_up, profitThisMonth >= 0 ? Colors.green : Colors.red)),
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
            childAspectRatio: 1.7,
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
            // ignore: deprecated_member_use
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
        gradient: LinearGradient(colors: [Colors.white, Color(0xFFFAFAFA)], begin: Alignment.topLeft, end: Alignment.bottomRight),
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

