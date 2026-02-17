import 'package:aspire/main.dart';
import 'package:aspire/services/auth_service.dart';
import 'package:aspire/services/db_helper.dart';
import 'package:aspire/services/sync_service.dart';
import 'package:aspire/views/audit_log_screen.dart';
import 'package:aspire/views/dashboard_screen.dart';
import 'package:aspire/views/expense_screen.dart';
import 'package:aspire/views/report_screen.dart';
import 'package:aspire/views/student_screen.dart';
import 'package:flutter/material.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  _MainScreenState createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _selectedIndex = 0;
  bool _sidebarVisible = true;
  final dbHelper = DatabaseHelper.instance;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Row(
        children: [
          // Sidebar
          AnimatedContainer(
            duration: Duration(milliseconds: 200),
            width: _sidebarVisible ? 260 : 0,
            child: _sidebarVisible ? Container(
              width: 260,
              decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFF1A237E), Color(0xFF283593)])),
              child: Column(
                children: [
                  Container(
                    padding: EdgeInsets.all(24),
                    decoration: BoxDecoration(border: Border(bottom: BorderSide(color: Colors.indigo.shade700))),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(child: Text('Student Portal', style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold))),
                            // Sync status indicator
                            StreamBuilder<SyncStatus>(
                              stream: SyncService.instance.syncStatusStream,
                              builder: (context, snapshot) {
                                final status = snapshot.data;
                                final isOnline = status?.isOnline ?? false;
                                final isSyncing = status?.isSyncing ?? false;
                                
                                return Tooltip(
                                  message: isSyncing ? 'Syncing...' : (isOnline ? 'Online' : 'Offline'),
                                  child: Container(
                                    padding: EdgeInsets.all(6),
                                    decoration: BoxDecoration(
                                      // ignore: deprecated_member_use
                                      color: isOnline ? Colors.green.withOpacity(0.2) : Colors.orange.withOpacity(0.2),
                                      borderRadius: BorderRadius.circular(20),
                                    ),
                                    child: isSyncing
                                        ? SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                        : Icon(isOnline ? Icons.cloud_done : Icons.cloud_off, color: isOnline ? Colors.green.shade300 : Colors.orange.shade300, size: 16),
                                  ),
                                );
                              },
                            ),
                          ],
                        ),
                        SizedBox(height: 4),
                        Text('Management System', style: TextStyle(color: Colors.indigo.shade300, fontSize: 14)),
                        SizedBox(height: 8),
                        // Current user
                        Container(
                          padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            // ignore: deprecated_member_use
                            color: Colors.white.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.person, color: Colors.white70, size: 14),
                              SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  AuthService.instance.currentUserEmail,
                                  style: TextStyle(color: Colors.white70, fontSize: 12),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(height: 20),
                  _buildMenuItem(0, Icons.dashboard, 'Dashboard'),
                  _buildMenuItem(1, Icons.people, 'Students'),
                  _buildMenuItem(2, Icons.receipt_long, 'Expenses'),
                  _buildMenuItem(3, Icons.analytics, 'Reports'),
                  _buildMenuItem(4, Icons.history, 'Audit Logs'),
                  Spacer(),
                  // Logout button
                  Padding(
                    padding: EdgeInsets.all(16),
                    child: SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: () async {
                          await AuthService.instance.signOut();
                        },
                        icon: Icon(Icons.logout, size: 18),
                        label: Text('Sign Out'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.red.shade400,
                          foregroundColor: Colors.white,
                          padding: EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ) : null,
          ),
          // Main Content
          Expanded(
            child: Column(
              children: [
                // Top bar with menu toggle
                Container(
                  padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  color: Colors.white,
                  child: Row(
                    children: [
                      IconButton(
                        icon: Icon(_sidebarVisible ? Icons.menu_open : Icons.menu, color: Color(0xFF1A237E)),
                        onPressed: () => setState(() => _sidebarVisible = !_sidebarVisible),
                        tooltip: _sidebarVisible ? 'Hide sidebar' : 'Show sidebar',
                      ),
                      if (!_sidebarVisible) ...[
                        SizedBox(width: 8),
                        Text('Student Portal', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF1A237E))),
                        Spacer(),
                        // Sync indicator when sidebar hidden
                        StreamBuilder<SyncStatus>(
                          stream: SyncService.instance.syncStatusStream,
                          builder: (context, snapshot) {
                            final status = snapshot.data;
                            final isOnline = status?.isOnline ?? false;
                            final isSyncing = status?.isSyncing ?? false;
                            
                            return Container(
                              padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                              decoration: BoxDecoration(
                                color: isOnline ? Colors.green.shade50 : Colors.orange.shade50,
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (isSyncing)
                                    SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.indigo))
                                  else
                                    Icon(isOnline ? Icons.cloud_done : Icons.cloud_off, color: isOnline ? Colors.green : Colors.orange, size: 14),
                                  SizedBox(width: 6),
                                  Text(isSyncing ? 'Syncing' : (isOnline ? 'Online' : 'Offline'), style: TextStyle(fontSize: 12, color: isOnline ? Colors.green.shade700 : Colors.orange.shade700)),
                                ],
                              ),
                            );
                          },
                        ),
                        SizedBox(width: 8),
                      ],
                    ],
                  ),
                ),
                Expanded(child: _getPage(_selectedIndex)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMenuItem(int index, IconData icon, String title) {
    bool isSelected = _selectedIndex == index;
    return InkWell(
      onTap: () => setState(() => _selectedIndex = index),
      child: Container(
        margin: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: isSelected ? Colors.indigo.shade700 : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border(left: BorderSide(color: isSelected ? Colors.amber : Colors.transparent, width: 4)),
        ),
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          child: Row(
            children: [
              Icon(icon, color: Colors.white, size: 22),
              SizedBox(width: 16),
              Text(title, style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _getPage(int index) {
    switch (index) {
      case 0:
        return DashboardPage();
      case 1:
        return StudentsPage();
      case 2:
        return ExpensesPage();
      case 3:
        return ReportsPage();
      case 4:
        return AuditLogsPage();
      default:
        return DashboardPage();
    }
  }
}

