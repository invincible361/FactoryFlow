import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../utils/app_colors.dart';
import '../services/biometric_service.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

class ModernLoginScreen extends StatefulWidget {
  final String appTitle;
  final String role;
  final String version;
  final bool isLoading;
  final Function(String username, String password, String orgCode) onLogin;
  final bool isDarkMode;
  final String? logoAsset;

  const ModernLoginScreen({
    super.key,
    required this.appTitle,
    required this.role,
    required this.version,
    required this.isLoading,
    required this.onLogin,
    this.isDarkMode = true,
    this.logoAsset,
  });

  @override
  State<ModernLoginScreen> createState() => _ModernLoginScreenState();
}

class _ModernLoginScreenState extends State<ModernLoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _orgCodeController = TextEditingController();
  final _biometricService = BiometricService();
  bool _obscurePassword = true;
  bool _canBiometric = false;
  bool _isBiometricEnabled = false;

  @override
  void initState() {
    super.initState();
    _checkBiometrics();
  }

  Future<void> _checkBiometrics() async {
    if (kIsWeb) return;

    final canAuthenticate = await _biometricService.isBiometricAvailable();
    final isEnabled = await _biometricService.isBiometricsEnabled();

    if (mounted) {
      setState(() {
        _canBiometric = canAuthenticate;
        _isBiometricEnabled = isEnabled;
      });

      // Auto-trigger biometric login if enabled
      if (canAuthenticate && isEnabled) {
        _handleBiometricLogin();
      }
    }
  }

  Future<void> _handleBiometricLogin() async {
    final authenticated = await _biometricService.authenticate();
    if (authenticated) {
      final credentials = await _biometricService.getSavedCredentials();
      if (credentials != null && mounted) {
        _usernameController.text = credentials['username'] ?? '';
        _passwordController.text = credentials['password'] ?? '';
        _orgCodeController.text = credentials['orgCode'] ?? '';

        widget.onLogin(
          _usernameController.text,
          _passwordController.text,
          _orgCodeController.text,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool isDark = widget.isDarkMode;
    final Color backgroundColor = AppColors.getBackground(isDark);
    final Color cardColor = AppColors.getCard(isDark);
    final Color accentColor = AppColors.getAccent(isDark);
    final Color textColor = AppColors.getText(isDark);

    return Scaffold(
      backgroundColor: backgroundColor,
      body: Stack(
        children: [
          // Animated Background
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: isDark
                      ? [
                          const Color(0xFF171821),
                          const Color(0xFF21222D),
                          const Color(0xFF171821),
                        ]
                      : [
                          const Color(0xFFF5F5F5),
                          const Color(0xFFE0E0E0),
                          const Color(0xFFF5F5F5),
                        ],
                ),
              ),
            ),
          ),

          // Floating Shapes for extra flair
          Positioned(
            top: -100,
            right: -100,
            child:
                Container(
                      width: 300,
                      height: 300,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: accentColor.withValues(alpha: 0.05),
                      ),
                    )
                    .animate(onPlay: (controller) => controller.repeat())
                    .scale(duration: 4.seconds, curve: Curves.easeInOut)
                    .then()
                    .scale(duration: 4.seconds, curve: Curves.easeInOut),
          ),

          Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // App Logo / Icon
                  Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: cardColor,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.2),
                              blurRadius: 20,
                              offset: const Offset(0, 10),
                            ),
                          ],
                        ),
                        child: widget.logoAsset != null
                            ? Image.asset(
                                widget.logoAsset!,
                                width: 60,
                                height: 60,
                                fit: BoxFit.contain,
                              )
                            : Icon(
                                Icons.factory_rounded,
                                size: 60,
                                color: accentColor,
                              ),
                      )
                      .animate()
                      .scale(duration: 600.ms, curve: Curves.easeOutBack)
                      .fadeIn(),

                  const SizedBox(height: 24),

                  // App Title & Role
                  Text(
                    widget.appTitle,
                    style: TextStyle(
                      color: textColor,
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.2,
                    ),
                  ).animate().fadeIn(delay: 200.ms).slideY(begin: 0.3),

                  Text(
                    '${widget.role} Access',
                    style: TextStyle(
                      color: accentColor,
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                      letterSpacing: 4,
                    ),
                  ).animate().fadeIn(delay: 400.ms).slideY(begin: 0.3),

                  const SizedBox(height: 48),

                  // Login Form
                  Container(
                    padding: const EdgeInsets.all(32),
                    decoration: BoxDecoration(
                      color: cardColor,
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: AppColors.getBorder(isDark)),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.1),
                          blurRadius: 40,
                          offset: const Offset(0, 20),
                        ),
                      ],
                    ),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _buildTextField(
                            controller: _orgCodeController,
                            label: 'Organization Code',
                            icon: Icons.business_rounded,
                            isDark: isDark,
                          ).animate().fadeIn(delay: 600.ms).slideX(begin: -0.1),

                          const SizedBox(height: 16),

                          _buildTextField(
                            controller: _usernameController,
                            label: 'Username',
                            icon: Icons.person_outline_rounded,
                            isDark: isDark,
                          ).animate().fadeIn(delay: 700.ms).slideX(begin: -0.1),

                          const SizedBox(height: 16),

                          _buildTextField(
                            controller: _passwordController,
                            label: 'Password',
                            icon: Icons.lock_outline_rounded,
                            isDark: isDark,
                            isPassword: true,
                            obscureText: _obscurePassword,
                            onTogglePassword: () {
                              setState(
                                () => _obscurePassword = !_obscurePassword,
                              );
                            },
                          ).animate().fadeIn(delay: 800.ms).slideX(begin: -0.1),

                          if (_canBiometric) ...[
                            const SizedBox(height: 16),
                            Row(
                                  children: [
                                    SizedBox(
                                      height: 24,
                                      width: 24,
                                      child: Checkbox(
                                        value: _isBiometricEnabled,
                                        onChanged: (value) {
                                          setState(() {
                                            _isBiometricEnabled =
                                                value ?? false;
                                          });
                                        },
                                        activeColor: accentColor,
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                            4,
                                          ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Text(
                                      'Enable Biometric Login',
                                      style: TextStyle(
                                        color: AppColors.getSecondaryText(
                                          isDark,
                                        ),
                                        fontSize: 14,
                                      ),
                                    ),
                                  ],
                                )
                                .animate()
                                .fadeIn(delay: 900.ms)
                                .slideX(begin: -0.1),
                          ],

                          const SizedBox(height: 32),

                          // Login Button Row
                          Row(
                                children: [
                                  Expanded(
                                    child: ElevatedButton(
                                      onPressed: widget.isLoading
                                          ? null
                                          : _handleLogin,
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: accentColor,
                                        foregroundColor: isDark
                                            ? Colors.black
                                            : Colors.white,
                                        padding: const EdgeInsets.symmetric(
                                          vertical: 16,
                                        ),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
                                        ),
                                        elevation: 0,
                                      ),
                                      child: widget.isLoading
                                          ? const SizedBox(
                                              height: 20,
                                              width: 20,
                                              child: CircularProgressIndicator(
                                                strokeWidth: 2,
                                                valueColor:
                                                    AlwaysStoppedAnimation(
                                                      Colors.white,
                                                    ),
                                              ),
                                            )
                                          : const Text(
                                              'LOGIN',
                                              style: TextStyle(
                                                fontSize: 16,
                                                fontWeight: FontWeight.bold,
                                                letterSpacing: 2,
                                              ),
                                            ),
                                    ),
                                  ),
                                  if (_canBiometric) ...[
                                    const SizedBox(width: 16),
                                    Container(
                                      decoration: BoxDecoration(
                                        color: cardColor,
                                        borderRadius: BorderRadius.circular(12),
                                        border: Border.all(
                                          color: AppColors.getBorder(isDark),
                                        ),
                                      ),
                                      child: IconButton(
                                        onPressed: _handleBiometricLogin,
                                        icon: Icon(
                                          Icons.fingerprint_rounded,
                                          color: accentColor,
                                          size: 32,
                                        ),
                                        padding: const EdgeInsets.all(12),
                                      ),
                                    ),
                                  ],
                                ],
                              )
                              .animate()
                              .fadeIn(delay: 1000.ms)
                              .scale(begin: const Offset(0.9, 0.9)),
                        ],
                      ),
                    ),
                  ).animate().fadeIn(delay: 500.ms).slideY(begin: 0.1),

                  const SizedBox(height: 24),

                  // Version Info
                  Text(
                    widget.version,
                    style: TextStyle(
                      color: AppColors.getSecondaryText(isDark),
                      fontSize: 12,
                    ),
                  ).animate().fadeIn(delay: 1200.ms),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    required bool isDark,
    bool isPassword = false,
    bool obscureText = false,
    VoidCallback? onTogglePassword,
  }) {
    final Color textColor = AppColors.getText(isDark);
    final Color accentColor = AppColors.getAccent(isDark);

    return TextFormField(
      controller: controller,
      obscureText: obscureText,
      style: TextStyle(color: textColor),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: AppColors.getSecondaryText(isDark)),
        prefixIcon: Icon(icon, color: accentColor.withValues(alpha: 0.7)),
        suffixIcon: isPassword
            ? IconButton(
                icon: Icon(
                  obscureText ? Icons.visibility_off : Icons.visibility,
                  color: AppColors.getSecondaryText(isDark),
                ),
                onPressed: onTogglePassword,
              )
            : null,
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: AppColors.getBorder(isDark)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: accentColor),
        ),
        filled: true,
        fillColor: isDark
            ? Colors.white.withValues(alpha: 0.02)
            : Colors.black.withValues(alpha: 0.02),
      ),
      validator: (value) => value == null || value.isEmpty ? 'Required' : null,
    );
  }

  void _handleLogin() async {
    if (_formKey.currentState!.validate()) {
      final username = _usernameController.text.trim();
      final password = _passwordController.text.trim();
      final orgCode = _orgCodeController.text.trim();

      if (_isBiometricEnabled) {
        await _biometricService.saveCredentials(username, password, orgCode);
        await _biometricService.setBiometricsEnabled(true);
      } else {
        await _biometricService.setBiometricsEnabled(false);
      }

      widget.onLogin(username, password, orgCode);
    }
  }
}
