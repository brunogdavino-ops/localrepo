import 'package:flutter/material.dart';
import '../../services/auth_service.dart';
import '../home/home_entry_page.dart';

class _PremiumTextField extends StatelessWidget {
  final String hintText;
  final bool obscureText;
  final TextEditingController controller;
  final FocusNode focusNode;

  const _PremiumTextField({
    required this.hintText,
    required this.controller,
    required this.focusNode,
    this.obscureText = false,
  });

  @override
    Widget build(BuildContext context) {
      return TextFormField(
        controller: controller,
        focusNode: focusNode,
        keyboardType: obscureText ? TextInputType.visiblePassword : TextInputType.emailAddress,
        obscureText: obscureText,
        style: const TextStyle(color: Colors.white),
        decoration: InputDecoration(
          hintText: hintText,
          hintStyle: const TextStyle(color: Colors.white70),
          filled: true,
          fillColor: const Color(0xFF1B1F2A),
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(
              color: Colors.white.withValues(alpha: 0.15),
              width: 1,
            ),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(
              color: Color(0xFF6D4BC3),
              width: 2,
            ),
          ),
        ),
      );
    }
}

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  late TextEditingController _emailController;
  late TextEditingController _passwordController;
  late FocusNode _emailFocusNode;
  late FocusNode _passwordFocusNode;
  bool _isLoading = false;
  @override
  void initState() {
    super.initState();
    _emailController = TextEditingController();
    _passwordController = TextEditingController();
    _emailFocusNode = FocusNode();
    _passwordFocusNode = FocusNode();
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _emailFocusNode.dispose();
    _passwordFocusNode.dispose();
    super.dispose();
  }

  Future<void> _handleSignIn() async {
    if (_emailController.text.isEmpty || _passwordController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Por favor, preencha todos os campos')),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final authService = AuthService();
      await authService.signIn(
        email: _emailController.text.trim(),
        password: _passwordController.text,
      );

      if (!mounted) return;

      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const HomeEntryPage()),
      );
    } catch (e) {
      if (!mounted) return;

      final message = e is String ? e : 'Erro ao fazer login. Tente novamente.';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF11131A),
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Base gradient background
          Positioned.fill(
            child: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFF1A1624), Color(0xFF141821)],
                ),
              ),
            ),
          ),

          // Subtle radial glow layer
          Positioned.fill(
            child: Container(
              decoration: const BoxDecoration(
                gradient: RadialGradient(
                  center: Alignment(0.2, -0.4),
                  radius: 0.8,
                  colors: [Color(0x2A6D4BC3), Colors.transparent],
                  stops: [0.0, 1.0],
                ),
              ),
            ),
          ),

          // Foreground content: no vertical centering, starts at top
          SafeArea(
            child: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.only(top: 150.0, left: 34.0, right: 34.0, bottom: 24.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.start,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    // Login logo
                    SizedBox(
                      width: 200,
                      child: Image.asset('assets/logo-artezi.png', fit: BoxFit.contain, width: 200),
                    ),
                    const SizedBox(height: 45),

                    // Inputs column constrained to maxWidth 320
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 320),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // Email field
                          _PremiumTextField(
                            hintText: 'Email',
                            obscureText: false,
                            controller: _emailController,
                            focusNode: _emailFocusNode,
                          ),
                          const SizedBox(height: 18),

                          // Password field
                          _PremiumTextField(
                            hintText: 'Senha',
                            obscureText: true,
                            controller: _passwordController,
                            focusNode: _passwordFocusNode,
                          ),
                          const SizedBox(height: 28),

                          // Login button with gradient
                          Container(
                            width: double.infinity,
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                colors: [Color(0xFF6D4BC3), Color(0xFF5A3E8E)],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Material(
                              color: Colors.transparent,
                              child: InkWell(
                                borderRadius: BorderRadius.circular(16),
                                onTap: _isLoading ? null : _handleSignIn,
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 16),
                                  child: Center(
                                    child: _isLoading
                                        ? const SizedBox(
                                            height: 20,
                                            width: 20,
                                            child: CircularProgressIndicator(
                                              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                              strokeWidth: 2,
                                            ),
                                          )
                                        : const Text(
                                            'Entrar',
                                            style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600),
                                          ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

