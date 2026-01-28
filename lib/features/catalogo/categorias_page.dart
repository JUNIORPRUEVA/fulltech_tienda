import 'package:flutter/material.dart';

import '../../data/app_database.dart';
import '../../ui/fulltech_widgets.dart';

class CategoriasPage extends StatefulWidget {
  const CategoriasPage({super.key});

  @override
  State<CategoriasPage> createState() => _CategoriasPageState();
}

class _CategoriasPageState extends State<CategoriasPage> {
  final _db = AppDatabase.instance;

  bool _loading = true;
  List<Map<String, Object?>> _rows = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final rows =
        await _db.db.query('categorias', orderBy: 'nombre COLLATE NOCASE');
    if (!mounted) return;
    setState(() {
      _rows = rows;
      _loading = false;
    });
  }

  Future<void> _showForm({int? id}) async {
    Map<String, Object?>? existing;
    if (id != null) {
      final rows = await _db.db.query(
        'categorias',
        where: 'id = ?',
        whereArgs: [id],
        limit: 1,
      );
      if (rows.isNotEmpty) existing = rows.first;
    }

    final controller =
        TextEditingController(text: existing?['nombre'] as String? ?? '');

    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(id == null ? 'Nueva categoría' : 'Editar categoría'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Nombre'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Guardar'),
          ),
        ],
      ),
    );

    if (saved != true) return;

    final nombre = controller.text.trim();
    if (nombre.isEmpty) return;

    if (id == null) {
      await _db.db.insert('categorias', {
        'nombre': nombre,
        'creado_en': DateTime.now().millisecondsSinceEpoch,
      });
    } else {
      await _db.db.update(
        'categorias',
        {'nombre': nombre},
        where: 'id = ?',
        whereArgs: [id],
      );
    }

    await _load();
  }

  Future<void> _delete(int id) async {
    final count = await _db.db.rawQuery(
      'SELECT COUNT(*) AS c FROM productos WHERE categoria_id = ?',
      [id],
    );
    final used = (count.first['c'] as int?) ?? 0;

    if (used > 0) {
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('No se puede eliminar'),
          content: Text('Hay $used producto(s) usando esta categoría.'),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Entendido'),
            ),
          ],
        ),
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Eliminar categoría'),
        content: const Text('¿Seguro que deseas eliminar esta categoría?'),
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

    await _db.db.delete('categorias', where: 'id = ?', whereArgs: [id]);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Categorías'),
        actions: [
          IconButton(
            tooltip: 'Agregar',
            onPressed: () => _showForm(),
            icon: const Icon(Icons.add),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : CenteredList(
              child: Column(
                children: [
                  const SizedBox(height: 12),
                  if (_rows.isEmpty)
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Card(
                        child: Padding(
                          padding: const EdgeInsets.all(18),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: const [
                              SizedBox(height: 4),
                              Icon(Icons.inbox_outlined, size: 34),
                              SizedBox(height: 10),
                              Text(
                                'Sin categorías',
                                style: TextStyle(
                                    fontWeight: FontWeight.w900, fontSize: 16),
                              ),
                              SizedBox(height: 6),
                              Text(
                                'Crea una categoría para organizar el catálogo.',
                                textAlign: TextAlign.center,
                                style: TextStyle(color: Colors.black54),
                              ),
                            ],
                          ),
                        ),
                      ),
                    )
                  else
                    ..._rows.map((row) {
                      final id = row['id'] as int;
                      final nombre = (row['nombre'] ?? '') as String;
                      return Padding(
                        padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
                        child: Card(
                          margin: EdgeInsets.zero,
                          child: ListTile(
                            title: Text(nombre),
                            trailing: PopupMenuButton<String>(
                              itemBuilder: (context) => const [
                                PopupMenuItem(
                                    value: 'edit', child: Text('Editar')),
                                PopupMenuItem(
                                    value: 'delete', child: Text('Eliminar')),
                              ],
                              onSelected: (value) async {
                                if (value == 'edit') {
                                  await _showForm(id: id);
                                }
                                if (value == 'delete') {
                                  await _delete(id);
                                }
                              },
                            ),
                          ),
                        ),
                      );
                    }),
                  const SizedBox(height: 24),
                ],
              ),
            ),
    );
  }
}
