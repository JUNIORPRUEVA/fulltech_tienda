import 'package:flutter/material.dart';

import '../../data/auth_service.dart';
import '../../data/cloud_settings.dart';
import '../auth/login_page.dart';

class CloudProfilePage extends StatefulWidget {
  const CloudProfilePage({super.key});

  @override
  State<CloudProfilePage> createState() => _CloudProfilePageState();
}

class _CloudProfilePageState extends State<CloudProfilePage> {
  Future<void> _logout() async {
    await AuthService.instance.logout();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(
        builder: (_) => const LoginPage(initialMessage: 'Sesión cerrada.'),
      ),
      (_) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<CloudSettingsData>(
      future: CloudSettings.load(),
      builder: (context, snapshot) {
        final settings = snapshot.data;

        return Scaffold(
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Cuenta', style: TextStyle(fontWeight: FontWeight.w900)),
                      const SizedBox(height: 8),
                      Text('Email: ${settings?.email ?? ''}'),
                      const SizedBox(height: 6),
                      Text('Servidor: ${settings?.baseUrl ?? ''}'),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: _logout,
                icon: const Icon(Icons.logout),
                label: const Text('Cerrar sesión'),
              ),
            ],
          ),
        );
      },
    );
  }
}
