import 'package:flutter/material.dart';
import 'dart:async';
import 'package:factoryflow_core/factoryflow_core.dart';
import 'package:factoryflow_core/services/version_service.dart';
import 'package:factoryflow_core/ui_components/update_dialog.dart';
import 'screens/login_screen.dart';

void main() async {
  try {
    WidgetsFlutterBinding.ensureInitialized();
    await SupabaseService.initialize();
    await NotificationService.initialize();
    await TimeUtils.syncServerTime();
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
        final hour = TimeUtils.nowIst().hour;
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
        home: const Initializer(),
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

class Initializer extends StatefulWidget {
  const Initializer({super.key});

  @override
  State<Initializer> createState() => _InitializerState();
}

class _InitializerState extends State<Initializer> {
  @override
  void initState() {
    super.initState();
    _checkForUpdate();
  }

  Future<void> _checkForUpdate() async {
    // Wait a bit for the app to settle
    await Future.delayed(const Duration(seconds: 2));
    if (!mounted) return;

    final updateInfo = await VersionService.checkForUpdate('supervisor');
    if (updateInfo != null && mounted) {
      showDialog(
        context: context,
        barrierDismissible: !updateInfo['isForceUpdate'],
        builder: (context) => UpdateDialog(
          latestVersion: updateInfo['latestVersion'],
          apkUrl: updateInfo['apkUrl'],
          isForceUpdate: updateInfo['isForceUpdate'],
          releaseNotes: updateInfo['releaseNotes'],
          headers: updateInfo['headers'],
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return const LoginScreen();
  }
}
