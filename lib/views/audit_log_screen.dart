import 'package:aspire/services/db_helper.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class AuditLogsPage extends StatefulWidget {
  const AuditLogsPage({super.key});

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
      case 'EXPENSE':
        icon = Icons.receipt_long;
        color = Colors.deepOrange;
        break;
      default:
        icon = Icons.info;
        color = Colors.grey;
    }

    final timestamp = DateTime.parse(log['timestamp']);
    final formattedTime = DateFormat('dd MMM yyyy, hh:mm a').format(timestamp);
    final userEmail = log['userEmail'] ?? 'Unknown';

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
                Row(
                  children: [
                    Icon(Icons.person, size: 12, color: Colors.grey[500]),
                    SizedBox(width: 4),
                    Text(userEmail, style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                    SizedBox(width: 12),
                    Icon(Icons.access_time, size: 12, color: Colors.grey[500]),
                    SizedBox(width: 4),
                    Text(formattedTime, style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                  ],
                ),
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

