import 'package:flutter/material.dart';
import 'package:factoryflow_core/factoryflow_core.dart';
import 'screens/login_screen.dart';

void main() async {
  try {
    WidgetsFlutterBinding.ensureInitialized();
    await SupabaseService.initialize();
    await NotificationService.initialize();
    runApp(const SupervisorApp());
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

class SupervisorApp extends StatelessWidget {
  const SupervisorApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Supervisor App',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF6C5CE7),
          brightness: Brightness.light,
        ),
        scaffoldBackgroundColor: const Color(0xFFF7F7FB),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF6C5CE7),
          foregroundColor: Colors.white,
          elevation: 0,
        ),
      ),
      home: const LoginScreen(),
    );
  }
}
