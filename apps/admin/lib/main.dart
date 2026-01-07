import 'package:flutter/material.dart';
import 'dart:async';
import 'package:factoryflow_core/factoryflow_core.dart';
import 'package:shorebird_code_push/shorebird_code_push.dart';
import 'screens/login_screen.dart';

// Initialize Shorebird
final shorebirdCodePush = ShorebirdCodePush();

void main() async {
  try {
    WidgetsFlutterBinding.ensureInitialized();
    await SupabaseService.initialize();
    await NotificationService.initialize();
    runApp(const AdminApp());
  } catch (e) {
    debugPrint('Initialization error: $e');
    runApp(MaterialApp(
      home: Scaffold(
        body: Center(
          child: Text('Failed to initialize app: $e'),
        ),
      ),
    ));
  }
}

class AdminApp extends StatefulWidget {
  const AdminApp({super.key});

  @override
  State<AdminApp> createState() => _AdminAppState();
}

class _AdminAppState extends State<AdminApp> {
  AppThemeMode _themeMode = AppThemeMode.auto;
  bool _isDarkMode = true;
  late Timer _themeTimer;

  @override
  void initState() {
    super.initState();
    _loadThemeMode();
    _updateThemeBasedOnTime();
    _themeTimer = Timer.periodic(const Duration(minutes: 1), (timer) {
      _updateThemeBasedOnTime();
    });
  }

  @override
  void dispose() {
    _themeTimer.cancel();
    super.dispose();
  }

  Future<void> _loadThemeMode() async {
    final prefs = await SharedPreferences.getInstance();
    final modeIndex = prefs.getInt('theme_mode') ?? AppThemeMode.auto.index;
    if (mounted) {
      setState(() {
        _themeMode = AppThemeMode.values[modeIndex];
        _updateThemeBasedOnTime();
      });
    }
  }

  void _updateThemeBasedOnTime() {
    bool shouldBeDark;
    switch (_themeMode) {
      case AppThemeMode.day:
        shouldBeDark = false;
        break;
      case AppThemeMode.night:
        shouldBeDark = true;
        break;
      case AppThemeMode.auto:
        final hour = DateTime.now().hour;
        shouldBeDark = !(hour >= 6 && hour < 18);
        break;
    }

    if (_isDarkMode != shouldBeDark) {
      setState(() {
        _isDarkMode = shouldBeDark;
      });
    }
  }

  Future<void> _setThemeMode(AppThemeMode mode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('theme_mode', mode.index);
    setState(() {
      _themeMode = mode;
      _updateThemeBasedOnTime();
    });
  }

  @override
  Widget build(BuildContext context) {
    return ThemeController(
      themeMode: _themeMode,
      isDarkMode: _isDarkMode,
      onThemeModeChanged: _setThemeMode,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'Admin App',
        theme: _isDarkMode ? _darkTheme : _lightTheme,
        home: const LoginScreen(),
      ),
    );
  }

  ThemeData get _lightTheme => ThemeData(
        brightness: Brightness.light,
        primaryColor: const Color(0xFF2E8B57),
        scaffoldBackgroundColor: AppColors.lightBackground,
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.white,
          elevation: 0,
          centerTitle: false,
        ),
        cardColor: Colors.white,
        useMaterial3: true,
      );

  ThemeData get _darkTheme => ThemeData(
        brightness: Brightness.dark,
        primaryColor: const Color(0xFFA9DFD8),
        scaffoldBackgroundColor: AppColors.darkBackground,
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF171821),
          elevation: 0,
          centerTitle: false,
        ),
        cardColor: const Color(0xFF21222D),
        useMaterial3: true,
      );
}
