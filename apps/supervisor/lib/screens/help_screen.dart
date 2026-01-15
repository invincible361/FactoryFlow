import 'package:flutter/material.dart';

class HelpScreen extends StatelessWidget {
  final bool isDarkMode;

  const HelpScreen({super.key, required this.isDarkMode});

  @override
  Widget build(BuildContext context) {
    final Color backgroundColor = isDarkMode
        ? const Color(0xFF121212)
        : Colors.white;
    final Color textColor = isDarkMode ? Colors.white : Colors.black87;
    final Color secondaryTextColor = isDarkMode
        ? Colors.white70
        : Colors.black54;

    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: AppBar(
        title: Text(
          'How to Use',
          style: TextStyle(color: textColor, fontWeight: FontWeight.bold),
        ),
        backgroundColor: backgroundColor,
        elevation: 0,
        iconTheme: IconThemeData(color: textColor),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSectionHeader('Supervisor Guide', textColor),
            const SizedBox(height: 10),
            Text(
              'Welcome to the Supervisor App. This guide will help you understand the key features available to you.',
              style: TextStyle(color: secondaryTextColor, fontSize: 16),
            ),
            const SizedBox(height: 24),
            _buildFeatureCard(
              'Worker Dashboard',
              'View real-time status of all workers. Green indicates active, and red for work abandonment.',
              Icons.dashboard_outlined,
              Colors.blue,
              isDarkMode,
            ),
            _buildFeatureCard(
              'Work Assignment',
              'Assign specific items, machines, and operations to workers. Click on a worker to see assignment options.',
              Icons.assignment_ind_outlined,
              Colors.orange,
              isDarkMode,
            ),
            _buildFeatureCard(
              'Production Verification',
              'Review and verify production logs submitted by workers. Ensure quality and quantity standards are met.',
              Icons.verified_outlined,
              Colors.green,
              isDarkMode,
            ),
            _buildFeatureCard(
              'Attendance Tracking',
              'Monitor worker attendance and current shift status. See who is clocked in and where they are located.',
              Icons.calendar_today_outlined,
              Colors.purple,
              isDarkMode,
            ),
            _buildFeatureCard(
              'Real-time Notifications',
              'Receive instant alerts when a worker leaves the factory premises or completes an operation.',
              Icons.notifications_active_outlined,
              Colors.red,
              isDarkMode,
            ),

            const SizedBox(height: 30),
            _buildSectionHeader('Need Help?', textColor),
            const SizedBox(height: 10),
            Text(
              'If you encounter any issues or have questions, please contact your system administrator or refer to the technical documentation.',
              style: TextStyle(
                color: secondaryTextColor,
                fontSize: 14,
                fontStyle: FontStyle.italic,
              ),
            ),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title, Color textColor) {
    return Text(
      title,
      style: TextStyle(
        color: textColor,
        fontSize: 22,
        fontWeight: FontWeight.bold,
      ),
    );
  }

  Widget _buildFeatureCard(
    String title,
    String description,
    IconData icon,
    Color color,
    bool isDarkMode,
  ) {
    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDarkMode ? Colors.grey[900] : Colors.white,
        borderRadius: BorderRadius.circular(15),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 5),
          ),
        ],
        border: Border.all(
          color: isDarkMode
              ? Colors.white10
              : Colors.black.withValues(alpha: 0.05),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color, size: 28),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: isDarkMode ? Colors.white : Colors.black87,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  description,
                  style: TextStyle(
                    color: isDarkMode ? Colors.white70 : Colors.black54,
                    fontSize: 14,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
