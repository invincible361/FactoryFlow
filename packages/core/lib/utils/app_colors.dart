import 'package:flutter/material.dart';

class AppColors {
  // Dark Theme Colors
  static const Color darkBackground = Color(0xFF171821);
  static const Color darkCard = Color(0xFF21222D);
  static const Color darkAccent = Color(0xFFA9DFD8);
  static const Color darkText = Colors.white;
  static const Color darkSecondaryText = Colors.white70;
  static const Color darkBorder = Color(0x1AFFFFFF);

  // Light Theme Colors
  static const Color lightBackground = Color(0xFFF5F5F5);
  static const Color lightCard = Color(0xFFFFFFFF);
  static const Color lightAccent = Color(0xFF2E8B57);
  static const Color lightText = Colors.black;
  static const Color lightSecondaryText = Color(0xB3000000);
  static const Color lightBorder = Color(0x1F000000);

  static Color getBackground(bool isDarkMode) => isDarkMode ? darkBackground : lightBackground;
  static Color getCard(bool isDarkMode) => isDarkMode ? darkCard : lightCard;
  static Color getAccent(bool isDarkMode) => isDarkMode ? darkAccent : lightAccent;
  static Color getText(bool isDarkMode) => isDarkMode ? darkText : lightText;
  static Color getSecondaryText(bool isDarkMode) => isDarkMode ? darkSecondaryText : lightSecondaryText;
  static Color getBorder(bool isDarkMode) => isDarkMode ? darkBorder : lightBorder;
}
