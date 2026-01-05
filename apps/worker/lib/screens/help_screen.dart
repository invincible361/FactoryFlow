import 'package:flutter/material.dart';
import 'package:factoryflow_core/factoryflow_core.dart';
import '../app_theme.dart';

class HelpScreen extends StatefulWidget {
  const HelpScreen({super.key});

  @override
  State<HelpScreen> createState() => _HelpScreenState();
}

class _HelpScreenState extends State<HelpScreen> {
  @override
  void initState() {
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    final themeController = ThemeController.of(context);
    final isDark = themeController?.isDarkMode ?? false;

    return Container(
      color: isDark ? const Color(0xFF121212) : AppTheme.nearlyWhite,
      child: SafeArea(
        top: false,
        child: Scaffold(
          backgroundColor: isDark
              ? const Color(0xFF121212)
              : AppTheme.nearlyWhite,
          body: Column(
            children: <Widget>[
              Container(
                padding: EdgeInsets.only(
                  top: MediaQuery.of(context).padding.top,
                ),
                child: Padding(
                  padding: const EdgeInsets.only(top: 8.0, left: 52, right: 18),
                  child: Row(
                    children: <Widget>[
                      Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.end,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text(
                              'How to Use',
                              textAlign: TextAlign.left,
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 22,
                                letterSpacing: 0.27,
                                color: isDark
                                    ? Colors.white
                                    : AppTheme.darkerText,
                              ),
                            ),
                            Text(
                              'FactoryFlow Worker Guide',
                              textAlign: TextAlign.left,
                              style: TextStyle(
                                fontWeight: isDark
                                    ? FontWeight.bold
                                    : FontWeight.w400,
                                fontSize: 14,
                                letterSpacing: 0.2,
                                color: isDark ? Colors.white : AppTheme.grey,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(
                        width: 60,
                        height: 60,
                        child: Icon(
                          Icons.help_outline,
                          color: Color(0xFF6C5CE7),
                          size: 40,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  child: Padding(
                    padding: const EdgeInsets.all(18.0),
                    child: Column(
                      children: <Widget>[
                        _buildStepCard(
                          '1',
                          'Location Access',
                          'Ensure your GPS is ON. You must be inside the factory premises to log production.',
                          Icons.location_on,
                          Colors.red[400]!,
                          isDark,
                        ),
                        _buildStepCard(
                          '2',
                          'Select Machine',
                          'Pick your assigned machine and the operation you are about to perform.',
                          Icons.settings,
                          Colors.blue[400]!,
                          isDark,
                        ),
                        _buildStepCard(
                          '3',
                          'Start Production',
                          'Tap the "Start Production" button. The timer will track your working time.',
                          Icons.play_circle_fill,
                          Colors.green[400]!,
                          isDark,
                        ),
                        _buildStepCard(
                          '4',
                          'Follow Guides',
                          'Need help? Tap "Open PDF Guide" to see operation instructions directly in the app.',
                          Icons.picture_as_pdf,
                          Colors.orange[400]!,
                          isDark,
                        ),
                        _buildStepCard(
                          '5',
                          'End & Submit',
                          'Once done, tap "Stop". Enter the total quantity produced and submit.',
                          Icons.check_circle,
                          Colors.teal[400]!,
                          isDark,
                        ),
                        _buildStepCard(
                          '6',
                          'Track Progress',
                          'Check the sidebar to see your attendance, shift details, and daily productivity.',
                          Icons.bar_chart,
                          Color(0xFF6C5CE7),
                          isDark,
                        ),
                        const SizedBox(height: 32),
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: isDark
                                ? const Color(0xFF6C5CE7).withValues(alpha: 0.2)
                                : const Color(
                                    0xFF6C5CE7,
                                  ).withValues(alpha: 0.05),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: const Color(
                                0xFF6C5CE7,
                              ).withValues(alpha: 0.4),
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.info_outline,
                                color: isDark
                                    ? Colors.white
                                    : Color(0xFF6C5CE7),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  'Important: Production cannot be logged if you are outside the geofence area.',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    color: isDark
                                        ? Colors.white
                                        : Color(0xFF6C5CE7),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 24),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStepCard(
    String step,
    String title,
    String desc,
    IconData icon,
    Color color,
    bool isDark,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16.0),
      child: Container(
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1E1E1E) : AppTheme.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: isDark
                  ? Colors.black.withValues(alpha: 0.3)
                  : AppTheme.grey.withValues(alpha: 0.1),
              offset: const Offset(1.1, 1.1),
              blurRadius: 10.0,
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: Text(
                    step,
                    style: TextStyle(
                      color: isDark ? Colors.white : color,
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Row(
                      children: [
                        Icon(icon, size: 18, color: color),
                        const SizedBox(width: 8),
                        Text(
                          title,
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                            color: isDark ? Colors.white : AppTheme.darkText,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      desc,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: isDark
                            ? FontWeight.bold
                            : FontWeight.normal,
                        color: isDark ? Colors.white : AppTheme.grey,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
