import 'package:flutter/material.dart';
import '../models/theme_mode.dart';
import '../utils/app_colors.dart';

class AppSidebar extends StatelessWidget {
  final String userName;
  final String? profileImageUrl;
  final String organizationCode;
  final String? organizationName;
  final bool isDarkMode;
  final AppThemeMode currentThemeMode;
  final Function(AppThemeMode) onThemeModeChanged;
  final VoidCallback onLogout;
  final List<Widget>? additionalItems;

  const AppSidebar({
    super.key,
    required this.userName,
    this.profileImageUrl,
    required this.organizationCode,
    this.organizationName,
    required this.isDarkMode,
    required this.currentThemeMode,
    required this.onThemeModeChanged,
    required this.onLogout,
    this.additionalItems,
  });

  @override
  Widget build(BuildContext context) {
    final Color accentColor = AppColors.getAccent(isDarkMode);
    final Color cardColor = AppColors.getCard(isDarkMode);
    final Color backgroundColor = AppColors.getBackground(isDarkMode);
    final Color textColor = AppColors.getText(isDarkMode);
    final Color secondaryTextColor = AppColors.getSecondaryText(isDarkMode);
    final Color borderColor = AppColors.getBorder(isDarkMode);

    return Drawer(
      backgroundColor: backgroundColor,
      child: Column(
        children: [
          // Header Section
          Container(
            padding: const EdgeInsets.only(top: 60, left: 24, right: 24, bottom: 24),
            decoration: BoxDecoration(
              color: cardColor,
              border: Border(
                bottom: BorderSide(color: borderColor),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 60,
                      height: 60,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: accentColor.withValues(alpha: 0.2), width: 2),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.1),
                            blurRadius: 10,
                            offset: const Offset(0, 5),
                          ),
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(30),
                        child: profileImageUrl != null && profileImageUrl!.isNotEmpty
                            ? Image.network(
                                profileImageUrl!,
                                fit: BoxFit.cover,
                                errorBuilder: (context, error, stackTrace) => 
                                  Icon(Icons.person, size: 30, color: accentColor),
                              )
                            : Icon(Icons.person, size: 30, color: accentColor),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            userName,
                            style: TextStyle(
                              color: textColor,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            organizationName ?? 'Organization: $organizationCode',
                            style: TextStyle(
                              color: secondaryTextColor,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Menu Items
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: 8),
              children: [
                if (additionalItems != null) ...additionalItems!,
                
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Text(
                    'APPEARANCE',
                    style: TextStyle(
                      color: secondaryTextColor,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.2,
                    ),
                  ),
                ),
                _buildThemeToggle(context),
              ],
            ),
          ),

          // Footer / Logout
          Divider(color: borderColor, height: 1),
          ListTile(
            onTap: onLogout,
            leading: const Icon(Icons.logout_rounded, color: Colors.redAccent),
            title: const Text(
              'Logout',
              style: TextStyle(
                color: Colors.redAccent,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _buildThemeToggle(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        decoration: BoxDecoration(
          color: isDarkMode
              ? Colors.white.withValues(alpha: 0.05)
              : Colors.black.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            _themeOption(
              icon: Icons.wb_sunny_rounded,
              label: 'Day Mode',
              isSelected: currentThemeMode == AppThemeMode.day,
              onTap: () => onThemeModeChanged(AppThemeMode.day),
            ),
            _themeOption(
              icon: Icons.nightlight_round,
              label: 'Night Mode',
              isSelected: currentThemeMode == AppThemeMode.night,
              onTap: () => onThemeModeChanged(AppThemeMode.night),
            ),
            _themeOption(
              icon: Icons.settings_brightness_rounded,
              label: 'Auto (Time based)',
              isSelected: currentThemeMode == AppThemeMode.auto,
              onTap: () => onThemeModeChanged(AppThemeMode.auto),
            ),
          ],
        ),
      ),
    );
  }

  Widget _themeOption({
    required IconData icon,
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    final Color accentColor = AppColors.getAccent(isDarkMode);
    
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Icon(
              icon,
              size: 20,
              color: isSelected ? accentColor : AppColors.getSecondaryText(isDarkMode),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  color: isSelected ? accentColor : AppColors.getText(isDarkMode),
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                ),
              ),
            ),
            if (isSelected)
              Icon(Icons.check_circle_rounded, size: 18, color: accentColor),
          ],
        ),
      ),
    );
  }
}
