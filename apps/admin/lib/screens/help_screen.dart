import 'package:flutter/material.dart';

class HelpScreen extends StatelessWidget {
  final bool isDarkMode;

  const HelpScreen({super.key, required this.isDarkMode});

  @override
  Widget build(BuildContext context) {
    final Color backgroundColor =
        isDarkMode ? const Color(0xFF121212) : Colors.white;
    final Color textColor = isDarkMode ? Colors.white : Colors.black87;
    final Color secondaryTextColor =
        isDarkMode ? Colors.white70 : Colors.black54;

    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: AppBar(
        title: Text(
          'Admin Guide',
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
            _buildSectionHeader('Administrator Guide', textColor),
            const SizedBox(height: 10),
            Text(
              'As an Administrator, you have full control over the FactoryFlow system. Use this guide to master the admin tools.',
              style: TextStyle(color: secondaryTextColor, fontSize: 16),
            ),
            const SizedBox(height: 24),
            _buildFeatureCard(
              'Global Overview',
              'The main dashboard provides real-time statistics on your entire factory operation, including efficiency and active workers.',
              Icons.analytics_outlined,
              Colors.blue,
              isDarkMode,
            ),
            _buildFeatureCard(
              'Organization Settings',
              'Configure your factory location, geofence radius, and basic information in the Settings tab.',
              Icons.business_outlined,
              Colors.orange,
              isDarkMode,
            ),
            _buildFeatureCard(
              'Worker Management',
              'Add new workers, update profiles, and monitor individual performance metrics and historical logs.',
              Icons.people_alt_outlined,
              Colors.green,
              isDarkMode,
            ),
            _buildFeatureCard(
              'Inventory & Assets',
              'Keep track of all raw materials (Items) and production equipment (Machines) used in your facility.',
              Icons.inventory_2_outlined,
              Colors.purple,
              isDarkMode,
            ),
            _buildFeatureCard(
              'Shift Configuration',
              'Set up shift schedules. The system uses these to automatically detect attendance and manage worker status.',
              Icons.access_time_outlined,
              Colors.red,
              isDarkMode,
            ),
            _buildFeatureCard(
              'Export & Reporting',
              'Generate and export comprehensive production reports to Excel for deep-dive analysis and record-keeping.',
              Icons.description_outlined,
              Colors.teal,
              isDarkMode,
            ),
            _buildFeatureCard(
              'Security & Logs',
              'Monitor system logs, including out-of-bounds alerts and login history, to ensure operational security.',
              Icons.security_outlined,
              Colors.indigo,
              isDarkMode,
            ),
            const SizedBox(height: 30),
            _buildSectionHeader('System Support', textColor),
            const SizedBox(height: 10),
            Text(
              'For technical support or feature requests, please contact the FactoryFlow development team or refer to the enterprise support portal.',
              style: TextStyle(
                  color: secondaryTextColor,
                  fontSize: 14,
                  fontStyle: FontStyle.italic),
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
