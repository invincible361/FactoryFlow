import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/worker.dart';
import 'production_entry_screen.dart';
import 'admin_dashboard_screen.dart';
import '../services/location_service.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final LocationService _locationService = LocationService();
  bool _isLoading = false;

  void _login() async {
    if (_formKey.currentState!.validate()) {
      setState(() {
        _isLoading = true;
      });

      try {
        final username = _usernameController.text;
        final password = _passwordController.text;

        // 1. Check for Admin Login
        if (username == 'admin' && password == 'admin123') {
           Navigator.pushReplacement(
             context,
             MaterialPageRoute(builder: (context) => const AdminDashboardScreen()),
           );
           return;
        }

        // 2. Worker Login Checks
        // Check location first
        final position = await _locationService.getCurrentLocation();
        final isInside = _locationService.isInsideFactory(position);

        if (!mounted) return;

        if (!isInside) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Login denied: You are not at the factory location.'),
              backgroundColor: Colors.red,
            ),
          );
          setState(() {
            _isLoading = false;
          });
          return;
        }

        // Simulate network delay for login
        // await Future.delayed(const Duration(seconds: 1)); // Not needed with real DB
        if (!mounted) return;

        final response = await Supabase.instance.client
            .from('workers')
            .select()
            .eq('username', username)
            .eq('password', password)
            .maybeSingle();

        if (response == null) {
          throw StateError('Invalid username or password');
        }

        final worker = Worker.fromJson(response);

        if (!mounted) return;
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) => ProductionEntryScreen(worker: worker),
          ),
        );
      } catch (e) {
        if (!mounted) return;
        
        String errorMessage = 'An error occurred';
        if (e is StateError) {
          errorMessage = 'Invalid username or password';
        } else {
          errorMessage = e.toString();
        }

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(errorMessage)),
        );
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Adinath Automotive Pvt Ltd')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Logo
              Image.asset(
                'assets/images/logo.png',
                height: 120,
                errorBuilder: (context, error, stackTrace) {
                  return const Icon(Icons.factory, size: 80, color: Colors.blue);
                },
              ),
              const SizedBox(height: 30),
              TextFormField(
                controller: _usernameController,
                decoration: const InputDecoration(labelText: 'Username'),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please enter username';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _passwordController,
                decoration: const InputDecoration(labelText: 'Password'),
                obscureText: true,
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please enter password';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 24),
              if (_isLoading)
                const CircularProgressIndicator()
              else
                ElevatedButton(
                  onPressed: _login,
                  child: const Text('Login'),
                ),
              const SizedBox(height: 16),
              const Text('Hint: worker1 / password1'),
            ],
          ),
        ),
      ),
    );
  }
}
