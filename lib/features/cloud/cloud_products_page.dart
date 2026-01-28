import 'package:flutter/material.dart';

import '../../data/cloud_http.dart';

class CloudProductsPage extends StatefulWidget {
  const CloudProductsPage({super.key});

  @override
  State<CloudProductsPage> createState() => _CloudProductsPageState();
}

class _CloudProductsPageState extends State<CloudProductsPage> {
  final _api = CloudHttp();

  Future<List<Map<String, Object?>>> _load() async {
    final resp = await _api.getJson('/products', query: {'limit': '100', 'offset': '0'});
    final data = resp['data'];
    if (data is! List) return const [];
    return data
        .whereType<Map>()
        .map((e) => e.map((k, v) => MapEntry(k.toString(), v)))
        .map((e) => e.cast<String, Object?>())
        .toList();
  }

  Future<void> _createProduct() async {
    final result = await showModalBottomSheet<_ProductDraft>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const _ProductFormSheet(),
    );

    if (result == null) return;

    try {
      await _api.postJson('/products', {
        'name': result.name,
        'sku': result.sku?.isEmpty == true ? null : result.sku,
        'price': result.price,
        'stock': result.stock,
      });
      if (!mounted) return;
      setState(() {});
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Producto creado.')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  Future<void> _delete(String id) async {
    try {
      await _api.deleteJson('/products/$id');
      if (!mounted) return;
      setState(() {});
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Producto eliminado.')));
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
                      final p = items[index];
                      final id = (p['id'] ?? '').toString();
                      final name = (p['name'] ?? '').toString();
                      final sku = (p['sku'] ?? '').toString();
                      final price = (p['price'] ?? '').toString();
                      final stock = (p['stock'] ?? '').toString();

                      return Card(
                        child: ListTile(
                          title: Text(name.isEmpty ? '(Sin nombre)' : name),
                          subtitle: Text(
                            [
                              if (sku.trim().isNotEmpty) 'SKU: $sku',
                              'Precio: $price',
                              'Stock: $stock',
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
                                        title: const Text('Eliminar producto'),
                                        content: Text('¿Eliminar "$name"?'),
                                        actions: [
                                          TextButton(
                                            onPressed: () =>
                                                Navigator.pop(context, false),
                                            child: const Text('Cancelar'),
                                          ),
                                          FilledButton(
                                            onPressed: () =>
                                                Navigator.pop(context, true),
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
            onPressed: _createProduct,
            child: const Icon(Icons.add),
          ),
        );
      },
    );
  }
}

class _ProductDraft {
  _ProductDraft({
    required this.name,
    required this.price,
    required this.stock,
    this.sku,
  });

  final String name;
  final String? sku;
  final String price;
  final String stock;
}

class _ProductFormSheet extends StatefulWidget {
  const _ProductFormSheet();

  @override
  State<_ProductFormSheet> createState() => _ProductFormSheetState();
}

class _ProductFormSheetState extends State<_ProductFormSheet> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _sku = TextEditingController();
  final _price = TextEditingController(text: '0');
  final _stock = TextEditingController(text: '0');

  @override
  void dispose() {
    _name.dispose();
    _sku.dispose();
    _price.dispose();
    _stock.dispose();
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
            const Text('Nuevo producto', style: TextStyle(fontWeight: FontWeight.w900)),
            const SizedBox(height: 12),
            TextFormField(
              controller: _name,
              decoration: const InputDecoration(labelText: 'Nombre'),
              validator: (v) => (v == null || v.trim().isEmpty) ? 'Requerido' : null,
            ),
            const SizedBox(height: 10),
            TextFormField(
              controller: _sku,
              decoration: const InputDecoration(labelText: 'SKU (opcional)'),
            ),
            const SizedBox(height: 10),
            TextFormField(
              controller: _price,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Precio'),
              validator: (v) => (v == null || v.trim().isEmpty) ? 'Requerido' : null,
            ),
            const SizedBox(height: 10),
            TextFormField(
              controller: _stock,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Stock'),
              validator: (v) => (v == null || v.trim().isEmpty) ? 'Requerido' : null,
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () {
                if (!(_formKey.currentState?.validate() ?? false)) return;
                Navigator.pop(
                  context,
                  _ProductDraft(
                    name: _name.text.trim(),
                    sku: _sku.text.trim(),
                    price: _price.text.trim(),
                    stock: _stock.text.trim(),
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
