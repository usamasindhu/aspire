import 'package:aspire/services/db_helper.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

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

  Future<void> _downloadPdfReport() async {
    final pdf = pw.Document();
    final now = DateTime.now();
    final generatedAt = DateFormat('dd MMM yyyy, hh:mm a').format(now);

    const int rowsPerPage = 25;
    final totalPages = (logs.length / rowsPerPage).ceil().clamp(1, 9999);

    for (int page = 0; page < totalPages; page++) {
      final startIdx = page * rowsPerPage;
      final endIdx = (startIdx + rowsPerPage).clamp(0, logs.length);
      final pageLogs = logs.sublist(startIdx, endIdx);

      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(32),
          build: (pw.Context context) {
            return pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                // Header (only on first page)
                if (page == 0) ...[
                  pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.Text(
                            'Audit Log Report',
                            style: pw.TextStyle(
                              fontSize: 24,
                              fontWeight: pw.FontWeight.bold,
                              color: PdfColor.fromHex('#1A237E'),
                            ),
                          ),
                          pw.SizedBox(height: 4),
                          pw.Text(
                            'Generated: $generatedAt',
                            style: pw.TextStyle(fontSize: 10, color: PdfColors.grey600),
                          ),
                        ],
                      ),
                      pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.end,
                        children: [
                          pw.Text(
                            'Aspire Student Portal',
                            style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold, color: PdfColors.grey700),
                          ),
                          pw.SizedBox(height: 2),
                          pw.Text(
                            'Total Entries: ${logs.length}',
                            style: pw.TextStyle(fontSize: 10, color: PdfColors.grey600),
                          ),
                        ],
                      ),
                    ],
                  ),
                  pw.SizedBox(height: 6),
                  pw.Divider(color: PdfColor.fromHex('#1A237E'), thickness: 2),
                  pw.SizedBox(height: 12),
                ],
                // Table
                pw.TableHelper.fromTextArray(
                  headerStyle: pw.TextStyle(
                    fontWeight: pw.FontWeight.bold,
                    fontSize: 9,
                    color: PdfColors.white,
                  ),
                  headerDecoration: pw.BoxDecoration(
                    color: PdfColor.fromHex('#1A237E'),
                  ),
                  headerAlignment: pw.Alignment.centerLeft,
                  cellStyle: const pw.TextStyle(fontSize: 8),
                  cellAlignment: pw.Alignment.centerLeft,
                  cellPadding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 5),
                  headerPadding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                  headers: ['#', 'Action', 'Details', 'User', 'Date & Time'],
                  columnWidths: {
                    0: const pw.FixedColumnWidth(30),
                    1: const pw.FixedColumnWidth(60),
                    2: const pw.FlexColumnWidth(3),
                    3: const pw.FlexColumnWidth(2),
                    4: const pw.FixedColumnWidth(110),
                  },
                  oddRowDecoration: pw.BoxDecoration(
                    color: PdfColor.fromHex('#F5F5F5'),
                  ),
                  data: pageLogs.asMap().entries.map((entry) {
                    final idx = startIdx + entry.key + 1;
                    final log = entry.value;
                    final timestamp = DateTime.parse(log['timestamp']);
                    final formattedTime = DateFormat('dd MMM yyyy, hh:mm a').format(timestamp);
                    final userEmail = log['userEmail'] ?? 'Unknown';
                    return [
                      '$idx',
                      log['action'] ?? '',
                      log['details'] ?? '',
                      userEmail,
                      formattedTime,
                    ];
                  }).toList(),
                ),
                pw.Spacer(),
                // Footer
                pw.Divider(color: PdfColors.grey300),
                pw.SizedBox(height: 4),
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text(
                      'Powered by Aspire',
                      style: pw.TextStyle(fontSize: 8, color: PdfColors.grey500),
                    ),
                    pw.Text(
                      'Page ${page + 1} of $totalPages',
                      style: pw.TextStyle(fontSize: 8, color: PdfColors.grey500),
                    ),
                  ],
                ),
              ],
            );
          },
        ),
      );
    }

    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => pdf.save(),
      name: 'Audit_Log_Report_${DateFormat('yyyyMMdd_HHmm').format(now)}',
    );
  }

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return Center(child: CircularProgressIndicator());
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
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
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Audit Logs',
                      style: TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.bold,
                        color: const Color(0xFF1A237E),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${logs.length} entries',
                      style: TextStyle(fontSize: 14, color: Colors.grey[500]),
                    ),
                  ],
                ),
              ),
              ElevatedButton.icon(
                onPressed: logs.isEmpty ? null : _downloadPdfReport,
                icon: const Icon(Icons.picture_as_pdf, size: 20),
                label: const Text('Download PDF'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1A237E),
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: Colors.grey[300],
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  elevation: 0,
                ),
              ),
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

