import 'package:flutter/material.dart';

import '../../data/cloud_http.dart';

class CloudCustomersPage extends StatefulWidget {
  const CloudCustomersPage({super.key});

  @override
  State<CloudCustomersPage> createState() => _CloudCustomersPageState();
}

class _CloudCustomersPageState extends State<CloudCustomersPage> {
  final _api = CloudHttp();

  Future<List<Map<String, Object?>>> _load() async {
    final resp = await _api.getJson('/customers', query: {'limit': '100', 'offset': '0'});
    final data = resp['data'];
    if (data is! List) return const [];
    return data
        .whereType<Map>()
        .map((e) => e.map((k, v) => MapEntry(k.toString(), v)))
        .map((e) => e.cast<String, Object?>())
        .toList();
  }

  Future<void> _create() async {
    final result = await showModalBottomSheet<_CustomerDraft>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const _CustomerFormSheet(),
    );
    if (result == null) return;

    try {
      await _api.postJson('/customers', {
        'name': result.name,
        'email': result.email?.isEmpty == true ? null : result.email,
        'phone': result.phone?.isEmpty == true ? null : result.phone,
        'address': result.address?.isEmpty == true ? null : result.address,
      });
      if (!mounted) return;
      setState(() {});
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Cliente creado.')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  Future<void> _delete(String id, String name) async {
    try {
      await _api.deleteJson('/customers/$id');
      if (!mounted) return;
      setState(() {});
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Cliente "$name" eliminado.')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Map<String, Object?>>>(
      future: _load(),
      builder: (context, snapshot) {
        final items = snapshot.data ?? const [];
        final loading = snapshot.connectionState != ConnectionState.done;

        return Scaffold(
          body: loading
              ? const Center(child: CircularProgressIndicator())
              : RefreshIndicator(
                  onRefresh: () async => setState(() {}),
                  child: ListView.separated(
                    padding: const EdgeInsets.all(12),
                    itemCount: items.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final c = items[index];
                      final id = (c['id'] ?? '').toString();
                      final name = (c['name'] ?? '').toString();
                      final phone = (c['phone'] ?? '').toString();
                      final email = (c['email'] ?? '').toString();

                      return Card(
                        child: ListTile(
                          title: Text(name.isEmpty ? '(Sin nombre)' : name),
                          subtitle: Text(
                            [
                              if (phone.trim().isNotEmpty) phone,
                              if (email.trim().isNotEmpty) email,
                            ].join(' · '),
                          ),
                          trailing: IconButton(
                            tooltip: 'Eliminar',
                            icon: const Icon(Icons.delete_outline),
                            onPressed: id.isEmpty
                                ? null
                                : () async {
                                    final ok = await showDialog<bool>(
                                      context: context,
                                      builder: (_) => AlertDialog(
                                        title: const Text('Eliminar cliente'),
                                        content: Text('¿Eliminar "$name"?'),
                                        actions: [
                                          TextButton(
                                            onPressed: () => Navigator.pop(context, false),
                                            child: const Text('Cancelar'),
                                          ),
                                          FilledButton(
                                            onPressed: () => Navigator.pop(context, true),
                                            child: const Text('Eliminar'),
                                          ),
                                        ],
                                      ),
                                    );
                                    if (ok == true) {
                                      await _delete(id, name);
                                    }
                                  },
                          ),
                        ),
                      );
                    },
                  ),
                ),
          floatingActionButton: FloatingActionButton(
            onPressed: _create,
            child: const Icon(Icons.person_add_alt_1),
          ),
        );
      },
    );
  }
}

class _CustomerDraft {
  _CustomerDraft({
    required this.name,
    this.email,
    this.phone,
    this.address,
  });

  final String name;
  final String? email;
  final String? phone;
  final String? address;
}

class _CustomerFormSheet extends StatefulWidget {
  const _CustomerFormSheet();

  @override
  State<_CustomerFormSheet> createState() => _CustomerFormSheetState();
}

class _CustomerFormSheetState extends State<_CustomerFormSheet> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _phone = TextEditingController();
  final _address = TextEditingController();

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _phone.dispose();
    _address.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(left: 16, right: 16, top: 16, bottom: bottom + 16),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Nuevo cliente', style: TextStyle(fontWeight: FontWeight.w900)),
            const SizedBox(height: 12),
            TextFormField(
              controller: _name,
              decoration: const InputDecoration(labelText: 'Nombre'),
              validator: (v) => (v == null || v.trim().isEmpty) ? 'Requerido' : null,
            ),
            const SizedBox(height: 10),
            TextFormField(
              controller: _phone,
              decoration: const InputDecoration(labelText: 'Teléfono (opcional)'),
            ),
            const SizedBox(height: 10),
            TextFormField(
              controller: _email,
              decoration: const InputDecoration(labelText: 'Email (opcional)'),
            ),
            const SizedBox(height: 10),
            TextFormField(
              controller: _address,
              decoration: const InputDecoration(labelText: 'Dirección (opcional)'),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () {
                if (!(_formKey.currentState?.validate() ?? false)) return;
                Navigator.pop(
                  context,
                  _CustomerDraft(
                    name: _name.text.trim(),
                    phone: _phone.text.trim(),
                    email: _email.text.trim(),
                    address: _address.text.trim(),
                  ),
                );
              },
              child: const Text('Guardar'),
            ),
          ],
        ),
      ),
    );
  }
}
