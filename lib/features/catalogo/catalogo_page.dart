import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../../data/app_database.dart';
import '../../ui/fulltech_widgets.dart';
import 'categorias_page.dart';
import 'producto_detail_page.dart';
import 'producto_form_sheet.dart';

class CatalogoPage extends StatefulWidget {
  const CatalogoPage({super.key});

  static Future<void> openAddForm(BuildContext context) async {
    await showProductoFormSheet(context: context);
  }

  @override
  State<CatalogoPage> createState() => _CatalogoPageState();
}

class _CatalogoPageState extends State<CatalogoPage> {
  final _db = AppDatabase.instance;
  final _searchController = TextEditingController();
  late final StreamSubscription<void> _changesSub;

  bool _loading = true;
  List<Map<String, Object?>> _items = const [];

  bool _categoriasLoading = true;
  List<Map<String, Object?>> _categorias = const [];
  int? _categoriaId;

  @override
  void initState() {
    super.initState();
    _loadCategorias();
    _load();
    _searchController.addListener(_load);
    _changesSub = _db.changes.listen((_) {
      _loadCategorias();
      _load();
    });
  }

  @override
  void dispose() {
    _searchController
      ..removeListener(_load)
      ..dispose();
    _changesSub.cancel();
    super.dispose();
  }

  Future<void> _loadCategorias() async {
    setState(() => _categoriasLoading = true);
    final rows =
        await _db.db.query('categorias', orderBy: 'nombre COLLATE NOCASE');
    if (!mounted) return;
    setState(() {
      _categorias = rows;
      _categoriasLoading = false;
      if (_categoriaId != null &&
          !_categorias.any((c) => (c['id'] as int?) == _categoriaId)) {
        _categoriaId = null;
      }
    });
  }

  Future<void> _load() async {
    setState(() => _loading = true);

    final query = _searchController.text.trim();
    final whereParts = <String>[];
    final whereArgs = <Object?>[];

    if (query.isNotEmpty) {
      whereParts.add('(p.nombre LIKE ? OR p.codigo LIKE ? OR c.nombre LIKE ?)');
      whereArgs.addAll(<Object?>['%$query%', '%$query%', '%$query%']);
    }

    if (_categoriaId != null) {
      whereParts.add('p.categoria_id = ?');
      whereArgs.add(_categoriaId);
    }

    final where = whereParts.isEmpty ? null : whereParts.join(' AND ');

    final rows = await _db.db.rawQuery(
      '''
SELECT p.*, c.nombre AS categoria_nombre
FROM productos p
LEFT JOIN categorias c ON c.id = p.categoria_id
${where == null ? '' : 'WHERE $where'}
ORDER BY p.actualizado_en DESC, p.id DESC
''',
      whereArgs.isEmpty ? null : whereArgs,
    );

    if (!mounted) return;
    setState(() {
      _items = rows;
      _loading = false;
    });
  }

  Future<void> _deleteProducto(int id) async {
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

    final row = await _db.db.query(
      'productos',
      columns: ['imagen_path', 'imagen_url'],
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (row.isNotEmpty) {
      final imagePath = row.first['imagen_path'] as String?;
      final imageUrl = row.first['imagen_url'] as String?;
      if (imagePath != null && imagePath.isNotEmpty) {
        try {
          final f = File(imagePath);
          if (await f.exists()) await f.delete();
        } catch (_) {
          // Ignorar si no se puede borrar.
        }
      }

      // Limpia referencia remota local (la nube se limpia por sync delete).
      if (imageUrl != null && imageUrl.isNotEmpty) {
        try {
          await _db.db.update(
            'productos',
            {'imagen_url': null},
            where: 'id = ?',
            whereArgs: [id],
          );
        } catch (_) {}
      }
    }

    await _db.db.delete('productos', where: 'id = ?', whereArgs: [id]);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    return CenteredList(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final w = constraints.maxWidth;
                final categoryWidth = (w * 0.38).clamp(150.0, 260.0);

                final compactPadding = EdgeInsets.symmetric(
                  horizontal: w < 420 ? 10 : 12,
                  vertical: 12,
                );

                return Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _searchController,
                        decoration: InputDecoration(
                          isDense: true,
                          contentPadding: compactPadding,
                          prefixIcon: const Icon(Icons.search),
                          hintText: 'Buscar…',
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    SizedBox(
                      width: categoryWidth,
                      child: DropdownButtonFormField<int>(
                        value: (_categoriaId != null &&
                                _categorias.any(
                                  (c) => (c['id'] as int?) == _categoriaId,
                                ))
                            ? _categoriaId
                            : null,
                        decoration: InputDecoration(
                          isDense: true,
                          contentPadding: compactPadding,
                          labelText: 'Categoría',
                          prefixIcon: const Icon(Icons.filter_alt_outlined),
                          suffixIcon: _categoriasLoading
                              ? const Padding(
                                  padding: EdgeInsets.all(12),
                                  child: SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  ),
                                )
                              : null,
                        ),
                        items: [
                          const DropdownMenuItem<int>(
                            value: null,
                            child: Text('Todas'),
                          ),
                          ..._categorias.map(
                            (c) => DropdownMenuItem<int>(
                              value: c['id'] as int,
                              child: Text((c['nombre'] ?? '') as String),
                            ),
                          ),
                        ],
                        onChanged: (v) async {
                          setState(() => _categoriaId = v);
                          await _load();
                        },
                      ),
                    ),
                    const SizedBox(width: 10),
                    IconButton.filledTonal(
                      tooltip: 'Limpiar filtro',
                      onPressed: _categoriaId == null
                          ? null
                          : () async {
                              setState(() => _categoriaId = null);
                              await _load();
                            },
                      style: IconButton.styleFrom(
                        minimumSize: const Size(44, 44),
                      ),
                      icon: const Icon(Icons.filter_alt_off_outlined),
                    ),
                    const SizedBox(width: 8),
                    IconButton.filledTonal(
                      tooltip: 'Categorías',
                      onPressed: () async {
                        await Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const CategoriasPage(),
                          ),
                        );
                        await _loadCategorias();
                        await _load();
                      },
                      style: IconButton.styleFrom(
                        minimumSize: const Size(44, 44),
                      ),
                      icon: const Icon(Icons.category_outlined),
                    ),
                  ],
                );
              },
            ),
          ),
          const SizedBox(height: 8),
          if (_loading)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_items.isEmpty)
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
                        'Sin productos',
                        style: TextStyle(
                            fontWeight: FontWeight.w900, fontSize: 16),
                      ),
                      SizedBox(height: 6),
                      Text(
                        'Usa el botón + para agregar tu primer producto.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.black54),
                      ),
                    ],
                  ),
                ),
              ),
            )
          else
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final w = constraints.maxWidth;
                  final crossAxisCount = w >= 1100
                      ? 5
                      : w >= 900
                          ? 4
                          : w >= 680
                              ? 3
                              : 2;

                  return GridView.builder(
                    padding: const EdgeInsets.fromLTRB(12, 6, 12, 92),
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: crossAxisCount,
                      crossAxisSpacing: 8,
                      mainAxisSpacing: 8,
                      // Más compacto (menos alto) en móvil.
                      childAspectRatio: 0.96,
                    ),
                    itemCount: _items.length,
                    itemBuilder: (context, index) {
                      final row = _items[index];
                      final id = row['id'] as int;
                      final codigo = (row['codigo'] ?? '') as String;
                      final nombre = (row['nombre'] ?? '') as String;
                      final categoriaNombre =
                          (row['categoria_nombre'] ?? '') as String;
                      final precio = (row['precio'] as num?)?.toDouble() ?? 0.0;
                      final costo = (row['costo'] as num?)?.toDouble() ?? 0.0;
                      final imagenPath = row['imagen_path'] as String?;
                      final imagenUrl = row['imagen_url'] as String?;

                      return _ProductoGridCard(
                        nombre: nombre,
                        codigo: codigo,
                        categoriaNombre: categoriaNombre,
                        precio: precio,
                        costo: costo,
                        imagenPath: imagenPath,
                        imagenUrl: imagenUrl,
                        onTap: () async {
                          await Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) =>
                                  ProductoDetailPage(productoId: id),
                            ),
                          );
                          await _load();
                        },
                        onEdit: () async {
                          await showProductoFormSheet(
                            context: context,
                            productoId: id,
                          );
                          await _load();
                        },
                        onDelete: () => _deleteProducto(id),
                      );
                    },
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}

String _formatMoney(double value) => value.toStringAsFixed(2);

class _ProductoGridCard extends StatelessWidget {
  const _ProductoGridCard({
    required this.nombre,
    required this.codigo,
    required this.categoriaNombre,
    required this.precio,
    required this.costo,
    required this.imagenPath,
    required this.imagenUrl,
    required this.onTap,
    required this.onEdit,
    required this.onDelete,
  });

  final String nombre;
  final String codigo;
  final String categoriaNombre;
  final double precio;
  final double costo;
  final String? imagenPath;
  final String? imagenUrl;
  final VoidCallback onTap;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: _ProductoImageBox(path: imagenPath, url: imagenUrl),
              ),
              const SizedBox(height: 8),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          nombre,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: 13,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          [
                            if (codigo.isNotEmpty) codigo,
                            if (categoriaNombre.isNotEmpty) categoriaNombre,
                          ].join(' • ').isEmpty
                              ? '—'
                              : [
                                  if (codigo.isNotEmpty) codigo,
                                  if (categoriaNombre.isNotEmpty)
                                    categoriaNombre,
                                ].join(' • '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.black54,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                  PopupMenuButton<String>(
                    tooltip: 'Acciones',
                    padding: EdgeInsets.zero,
                    itemBuilder: (context) => const [
                      PopupMenuItem(value: 'edit', child: Text('Editar')),
                      PopupMenuItem(value: 'delete', child: Text('Eliminar')),
                    ],
                    onSelected: (value) {
                      if (value == 'edit') onEdit();
                      if (value == 'delete') onDelete();
                    },
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: _PriceChip(
                      label: 'Costo',
                      value: _formatMoney(costo),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _PriceChip(
                      label: 'Precio',
                      value: _formatMoney(precio),
                      highlight: true,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PriceChip extends StatelessWidget {
  const _PriceChip({
    required this.label,
    required this.value,
    this.highlight = false,
  });

  final String label;
  final String value;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final bg = highlight
        ? colorScheme.primary.withAlpha(18)
        : colorScheme.surfaceContainerHighest;
    final fg = highlight ? colorScheme.primary : Colors.black87;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.black.withAlpha(18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 10,
              color: Colors.black54,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontWeight: FontWeight.w900,
              fontSize: 12,
              color: fg,
            ),
          ),
        ],
      ),
    );
  }
}

class _ProductoImageBox extends StatelessWidget {
  const _ProductoImageBox({required this.path, required this.url});

  final String? path;
  final String? url;

  @override
  Widget build(BuildContext context) {
    final borderRadius = BorderRadius.circular(14);
    final bg = Theme.of(context).colorScheme.surfaceContainerHighest;

    final remote = (url ?? '').trim();
    if (remote.isNotEmpty) {
      return ClipRRect(
        borderRadius: borderRadius,
        child: Image.network(
          remote,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) {
            return Container(
              decoration: BoxDecoration(color: bg, borderRadius: borderRadius),
              child: const Center(
                child: Icon(Icons.broken_image_outlined, size: 30),
              ),
            );
          },
        ),
      );
    }

    if (path == null || path!.trim().isEmpty) {
      return Container(
        decoration: BoxDecoration(color: bg, borderRadius: borderRadius),
        child: const Center(child: Icon(Icons.inventory_2_outlined, size: 30)),
      );
    }

    final file = File(path!);
    return ClipRRect(
      borderRadius: borderRadius,
      child: Image.file(
        file,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) {
          return Container(
            decoration: BoxDecoration(color: bg, borderRadius: borderRadius),
            child: const Center(
              child: Icon(Icons.broken_image_outlined, size: 30),
            ),
          );
        },
      ),
    );
  }
}
