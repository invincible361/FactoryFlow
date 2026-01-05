import 'package:flutter/material.dart';
import '../models/theme_mode.dart';

class ThemeController extends InheritedWidget {
  final AppThemeMode themeMode;
  final bool isDarkMode;
  final Function(AppThemeMode) onThemeModeChanged;

  const ThemeController({
    super.key,
    required this.themeMode,
    required this.isDarkMode,
    required this.onThemeModeChanged,
    required Widget child,
  }) : super(child: child);

  static ThemeController? of(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<ThemeController>();
  }

  @override
  bool updateShouldNotify(ThemeController oldWidget) {
    return themeMode != oldWidget.themeMode || isDarkMode != oldWidget.isDarkMode;
  }
}
