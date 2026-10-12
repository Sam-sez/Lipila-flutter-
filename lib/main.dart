import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'diagnostics/app_log.dart';
import 'state/auth_provider.dart';
import 'screens/login_screen.dart';
import 'screens/app_shell.dart';
import 'theme/lipila_theme.dart';

void main() {
  // ── Build identity ──────────────────────────────────────────────────────
  // BUILD_ID is injected by CI as --dart-define=BUILD_ID=run<N>.
  // Falls back to 'local' so a locally-built APK is distinguishable from CI.
  const buildId = String.fromEnvironment('BUILD_ID', defaultValue: 'local');
  AppLog.buildId = buildId;
  AppLog.buildMode = kReleaseMode ? 'release' : kDebugMode ? 'debug' : 'profile';
  AppLog.init();

  // ── Global error capture ─────────────────────────────────────────────────
  // Three layers so nothing can silently disappear:
  //   1. runZonedGuarded  — catches errors thrown in async code without a handler
  //   2. FlutterError.onError — catches errors in Flutter framework callbacks
  //   3. PlatformDispatcher.onError — catches errors from platform channels

  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    AppLog.add('ERR', 'Flutter: ${details.exceptionAsString()}');
    if (details.stack != null) {
      AppLog.add('ERR', details.stack.toString());
    }
  };

  PlatformDispatcher.instance.onError = (error, stack) {
    AppLog.add('ERR', 'Platform: $error');
    AppLog.add('ERR', stack.toString());
    return true; // handled — don't crash
  };

  runZonedGuarded(
    () => runApp(const LipilaApp()),
    (error, stack) {
      AppLog.add('ERR', 'Zone: $error');
      AppLog.add('ERR', stack.toString());
    },
  );
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
