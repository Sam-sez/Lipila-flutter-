import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../state/auth_provider.dart';
import '../theme/lipila_theme.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _numberController = TextEditingController();
  final _nameController = TextEditingController();
  bool _isAgent = false;
  bool _busy = false;
  String? _error;

  Future<void> _submit() async {
    final number = _numberController.text.trim();
    if (!RegExp(r'^0\d{9}$').hasMatch(number)) {
      setState(() => _error = 'Enter a 10-digit number starting with 0 (e.g. 0977123456).');
      return;
    }
    setState(() { _busy = true; _error = null; });
    final auth = context.read<AuthProvider>();
    try {
      // Recognize returning users by number alone — no password in this
      // prototype, so sign-in and sign-up are the same form.
      final recognized = await auth.loginExisting(number);
      if (recognized) return;

      if (_nameController.text.trim().isEmpty) {
        setState(() { _error = 'First time here — tell us your name too.'; _busy = false; });
        return;
      }
      await auth.createAccount(
        mobileNumber: number, legalName: _nameController.text.trim(), isAgent: _isAgent,
      );
    } catch (e) {
      setState(() => _error = 'Something went wrong — try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Lipila', style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: LipilaColors.espresso)),
                const SizedBox(height: 4),
                const Text('Scan, confirm, done.', style: TextStyle(color: Colors.grey)),
                const SizedBox(height: 28),
                TextField(
                  controller: _numberController,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(labelText: 'Mobile number (e.g. 0977123456)'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _nameController,
                  decoration: const InputDecoration(labelText: 'Your name (only needed the first time)'),
                ),
                const SizedBox(height: 8),
                CheckboxListTile(
                  value: _isAgent,
                  onChanged: (v) => setState(() => _isAgent = v ?? false),
                  title: const Text("I'm registering as a MoMo agent"),
                  controlAffinity: ListTileControlAffinity.leading,
                  contentPadding: EdgeInsets.zero,
                ),
                if (_error != null) ...[
                  const SizedBox(height: 4),
                  Text(_error!, style: const TextStyle(color: LipilaColors.danger, fontSize: 13)),
                ],
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _busy ? null : _submit,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: LipilaColors.ember, padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: Text(_busy ? 'One moment…' : 'Continue', style: const TextStyle(color: Colors.white)),
                  ),
                ),
                const SizedBox(height: 20),
                const Text(
                  "Already used Lipila? Just enter your number — we'll recognize you, "
                  "no password needed. This is a prototype identity, not a bank login.",
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
