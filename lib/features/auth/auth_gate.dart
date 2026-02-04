import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';

import '../../data/auth_service.dart';
import '../../data/cloud_api.dart';
import '../../data/cloud_settings.dart';
import '../../ui/shell/fulltech_shell.dart';
import 'login_page.dart';

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  late Future<void> _future;
  static const bool _isFlutterTest = bool.fromEnvironment('FLUTTER_TEST');

  @override
  void initState() {
    super.initState();
    _future = _boot();
  }

  Future<void> _boot() async {
    final settings = await CloudSettings.load();
    if (kDebugMode) {
      debugPrint('[AuthGate] boot baseUrl=${settings.baseUrl}');
    }
    final api = CloudApi();
    if (!_isFlutterTest) {
      final ok =
          await api.ping(baseUrl: settings.baseUrl).catchError((_) => false);
      if (!ok) {
        throw StateError(
            'Sin conexion. Verifica tu internet y que el servidor este activo.');
      }
    }
    await AuthService.instance.loadSession();
  }

  void _retry() {
    setState(() {
      _future = _boot();
    });
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<void>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const _LoadingScreen(message: 'Conectando…');
        }

        if (snapshot.hasError) {
          return _OfflineScreen(
            message: snapshot.error?.toString() ??
                'Sin conexión: necesitas Internet para usar la app.',
            onRetry: _retry,
          );
        }

        if (!AuthService.instance.hasSession) {
          return const LoginPage();
        }

        return const FullTechShell();
      },
    );
  }
}

class _LoadingScreen extends StatelessWidget {
  const _LoadingScreen({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: colorScheme.primary.withAlpha(31),
                borderRadius: BorderRadius.circular(18),
              ),
              child: Icon(Icons.lock_outline, color: colorScheme.primary, size: 28),
            ),
            const SizedBox(height: 14),
            const Text(
              'FULLTECH',
              style: TextStyle(fontWeight: FontWeight.w900, fontSize: 20),
            ),
            const SizedBox(height: 8),
            Text(message),
          ],
        ),
      ),
    );
  }
}

class _OfflineScreen extends StatelessWidget {
  const _OfflineScreen({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: colorScheme.error.withAlpha(25),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Icon(Icons.wifi_off, color: colorScheme.error, size: 28),
              ),
              const SizedBox(height: 14),
              const Text(
                'Sin conexión',
                style: TextStyle(fontWeight: FontWeight.w900, fontSize: 20),
              ),
              const SizedBox(height: 8),
              Text(
                message,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: onRetry,
                child: const Text('Reintentar'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
