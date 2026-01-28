import 'package:flutter/material.dart';

import '../../data/cloud_http.dart';

class CloudSalesPage extends StatefulWidget {
  const CloudSalesPage({super.key});

  @override
  State<CloudSalesPage> createState() => _CloudSalesPageState();
}

class _CloudSalesPageState extends State<CloudSalesPage> {
  final _api = CloudHttp();

  Future<List<Map<String, Object?>>> _load() async {
    final resp = await _api.getJson('/sales', query: {'limit': '100', 'offset': '0'});
    final data = resp['data'];
    if (data is! List) return const [];
    return data
        .whereType<Map>()
        .map((e) => e.map((k, v) => MapEntry(k.toString(), v)))
        .map((e) => e.cast<String, Object?>())
        .toList();
  }

  Future<void> _create() async {
    final result = await showModalBottomSheet<_SaleDraft>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const _SaleFormSheet(),
    );
    if (result == null) return;

    try {
      await _api.postJson('/sales', {
        'customerId': null,
        'total': result.total,
        'note': result.note?.isEmpty == true ? null : result.note,
      });
      if (!mounted) return;
      setState(() {});
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Venta creada.')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  Future<void> _delete(String id) async {
    try {
      await _api.deleteJson('/sales/$id');
      if (!mounted) return;
      setState(() {});
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Venta eliminada.')));
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
                      final s = items[index];
                      final id = (s['id'] ?? '').toString();
                      final total = (s['total'] ?? '').toString();
                      final saleAt = (s['saleAt'] ?? '').toString();
                      final note = (s['note'] ?? '').toString();

                      return Card(
                        child: ListTile(
                          title: Text('Total: $total'),
                          subtitle: Text(
                            [
                              if (saleAt.trim().isNotEmpty) saleAt,
                              if (note.trim().isNotEmpty) note,
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
                                        title: const Text('Eliminar venta'),
                                        content: const Text('¿Eliminar esta venta?'),
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
                                      await _delete(id);
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
            child: const Icon(Icons.add),
          ),
        );
      },
    );
  }
}

class _SaleDraft {
  _SaleDraft({required this.total, this.note});

  final String total;
  final String? note;
}

class _SaleFormSheet extends StatefulWidget {
  const _SaleFormSheet();

  @override
  State<_SaleFormSheet> createState() => _SaleFormSheetState();
}

class _SaleFormSheetState extends State<_SaleFormSheet> {
  final _formKey = GlobalKey<FormState>();
  final _total = TextEditingController(text: '0');
  final _note = TextEditingController();

  @override
  void dispose() {
    _total.dispose();
    _note.dispose();
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
            const Text('Nueva venta', style: TextStyle(fontWeight: FontWeight.w900)),
            const SizedBox(height: 12),
            TextFormField(
              controller: _total,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Total'),
              validator: (v) => (v == null || v.trim().isEmpty) ? 'Requerido' : null,
            ),
            const SizedBox(height: 10),
            TextFormField(
              controller: _note,
              decoration: const InputDecoration(labelText: 'Nota (opcional)'),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () {
                if (!(_formKey.currentState?.validate() ?? false)) return;
                Navigator.pop(
                  context,
                  _SaleDraft(
                    total: _total.text.trim(),
                    note: _note.text.trim(),
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
