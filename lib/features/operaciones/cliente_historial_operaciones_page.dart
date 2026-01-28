import 'package:flutter/material.dart';

import 'operaciones_page.dart';

class ClienteHistorialOperacionesPage extends StatelessWidget {
  const ClienteHistorialOperacionesPage(
      {super.key, required this.clienteId, required this.clienteNombre});

  final int clienteId;
  final String clienteNombre;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Historial: $clienteNombre'),
      ),
      body: SafeArea(child: OperacionesPage(initialClienteId: clienteId)),
    );
  }
}
