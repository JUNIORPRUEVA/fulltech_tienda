import 'dart:io';

import 'package:flutter/material.dart';

import '../../data/app_database.dart';
import '../../ui/fulltech_widgets.dart';
import 'producto_form_sheet.dart';

class ProductoDetailPage extends StatefulWidget {
  const ProductoDetailPage({super.key, required this.productoId});

  final int productoId;

  @override
  State<ProductoDetailPage> createState() => _ProductoDetailPageState();
}

class _ProductoDetailPageState extends State<ProductoDetailPage> {
  final _db = AppDatabase.instance;

  bool _loading = true;
  Map<String, Object?>? _row;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);

    final rows = await _db.db.rawQuery(
      '''
SELECT p.*, c.nombre AS categoria_nombre
FROM productos p
LEFT JOIN categorias c ON c.id = p.categoria_id
WHERE p.id = ?
LIMIT 1
''',
      [widget.productoId],
    );

    if (!mounted) return;
    setState(() {
      _row = rows.isEmpty ? null : rows.first;
      _loading = false;
    });
  }

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Eliminar producto'),
        content: const Text('¿Seguro que deseas eliminar este producto?'),
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

    if (confirmed != true) return;

    final imagePath = _row?['imagen_path'] as String?;
    if (imagePath != null && imagePath.isNotEmpty) {
      try {
        final f = File(imagePath);
        if (await f.exists()) await f.delete();
      } catch (_) {}
    }

    await _db.db
        .delete('productos', where: 'id = ?', whereArgs: [widget.productoId]);
    if (!mounted) return;
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final row = _row;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Detalle'),
        actions: [
          IconButton(
            tooltip: 'Editar',
            onPressed: row == null
                ? null
                : () async {
                    await showProductoFormSheet(
                      context: context,
                      productoId: widget.productoId,
                    );
                    await _load();
                  },
            icon: const Icon(Icons.edit_outlined),
          ),
          IconButton(
            tooltip: 'Eliminar',
            onPressed: row == null ? null : _delete,
            icon: const Icon(Icons.delete_outline),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : row == null
              ? const Center(child: Text('Producto no encontrado.'))
              : CenteredList(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Card(
                      margin: EdgeInsets.zero,
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _DetailHeader(row: row),
                            const SizedBox(height: 12),
                            _DetailRow(
                                label: 'Código',
                                value: (row['codigo'] ?? '') as String),
                            _DetailRow(
                                label: 'Nombre',
                                value: (row['nombre'] ?? '') as String),
                            _DetailRow(
                              label: 'Categoría',
                              value: (row['categoria_nombre'] ?? '—') as String,
                            ),
                            _DetailRow(
                              label: 'Precio',
                              value: _formatMoney(
                                  (row['precio'] as num?)?.toDouble()),
                            ),
                            _DetailRow(
                              label: 'Costo',
                              value: _formatMoney(
                                  (row['costo'] as num?)?.toDouble()),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
    );
  }
}

class _DetailHeader extends StatelessWidget {
  const _DetailHeader({required this.row});

  final Map<String, Object?> row;

  @override
  Widget build(BuildContext context) {
    final nombre = (row['nombre'] ?? '') as String;
    final imagenPath = row['imagen_path'] as String?;
    final imagenUrl = row['imagen_url'] as String?;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        _BigThumb(path: imagenPath, url: imagenUrl),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            nombre.isEmpty ? 'Producto' : nombre,
            style: Theme.of(context).textTheme.titleLarge,
          ),
        ),
      ],
    );
  }
}

class _BigThumb extends StatelessWidget {
  const _BigThumb({required this.path, required this.url});

  final String? path;
  final String? url;

  @override
  Widget build(BuildContext context) {
    final borderRadius = BorderRadius.circular(14);

    final remote = (url ?? '').trim();
    if (remote.isNotEmpty) {
      return ClipRRect(
        borderRadius: borderRadius,
        child: Image.network(
          remote,
          width: 84,
          height: 84,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) {
            return Container(
              width: 84,
              height: 84,
              decoration: BoxDecoration(
                borderRadius: borderRadius,
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
              ),
              child: const Icon(Icons.broken_image_outlined, size: 32),
            );
          },
        ),
      );
    }

    if (path == null || path!.isEmpty) {
      return Container(
        width: 84,
        height: 84,
        decoration: BoxDecoration(
          borderRadius: borderRadius,
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
        ),
        child: const Icon(Icons.inventory_2_outlined, size: 32),
      );
    }

    return ClipRRect(
      borderRadius: borderRadius,
      child: Image.file(
        File(path!),
        width: 84,
        height: 84,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) {
          return Container(
            width: 84,
            height: 84,
            decoration: BoxDecoration(
              borderRadius: borderRadius,
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
            ),
            child: const Icon(Icons.broken_image_outlined, size: 32),
          );
        },
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          SizedBox(
            width: 92,
            child: Text(
              label,
              style: Theme.of(context).textTheme.labelLarge,
            ),
          ),
          Expanded(child: Text(value.isEmpty ? '—' : value)),
        ],
      ),
    );
  }
}

String _formatMoney(double? value) {
  final v = value ?? 0.0;
  return v.toStringAsFixed(2);
}
