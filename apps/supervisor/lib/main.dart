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
    runApp(const SupervisorApp());
  } catch (e) {
    debugPrint('Initialization error: $e');
    runApp(
      MaterialApp(
        home: Scaffold(
          body: Center(child: Text('Failed to initialize app: $e')),
        ),
      ),
    );
  }
}

class SupervisorApp extends StatefulWidget {
  const SupervisorApp({super.key});

  @override
  State<SupervisorApp> createState() => _SupervisorAppState();
}

class _SupervisorAppState extends State<SupervisorApp> {
  AppThemeMode _themeMode = AppThemeMode.auto;
  bool _isDarkMode = false;
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
        title: 'Supervisor App',
        theme: _isDarkMode ? _darkTheme : _lightTheme,
        home: const LoginScreen(),
      ),
    );
  }

  ThemeData get _lightTheme => ThemeData(
    brightness: Brightness.light,
    primarySwatch: Colors.indigo,
    scaffoldBackgroundColor: AppColors.lightBackground,
    useMaterial3: true,
  );

  ThemeData get _darkTheme => ThemeData(
    brightness: Brightness.dark,
    primarySwatch: Colors.deepPurple,
    scaffoldBackgroundColor: AppColors.darkBackground,
    useMaterial3: true,
  );
}
