import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'state/auth_provider.dart';
import 'screens/login_screen.dart';
import 'screens/app_shell.dart';
import 'theme/lipila_theme.dart';

void main() {
  runApp(const LipilaApp());
}

class LipilaApp extends StatelessWidget {
  const LipilaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => AuthProvider()..restoreSession(),
      child: MaterialApp(
        title: 'Lipila',
        debugShowCheckedModeBanner: false,
        theme: LipilaTheme.light(),
        home: const _AuthGate(),
      ),
    );
  }
}

class _AuthGate extends StatelessWidget {
  const _AuthGate();

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    if (auth.loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return auth.user == null ? const LoginScreen() : const AppShell();
  }
}
