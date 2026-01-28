import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../data/app_database.dart';
import '../../ui/fulltech_widgets.dart';

Future<void> showProductoFormSheet({
  required BuildContext context,
  int? productoId,
}) async {
  await showFullTechFormSheet<void>(
    context: context,
    child: _ProductoFormSheet(productoId: productoId),
  );
}

class _ProductoFormSheet extends StatefulWidget {
  const _ProductoFormSheet({this.productoId});

  final int? productoId;

  @override
  State<_ProductoFormSheet> createState() => _ProductoFormSheetState();
}

class _ProductoFormSheetState extends State<_ProductoFormSheet> {
  final _db = AppDatabase.instance;
  final _formKey = GlobalKey<FormState>();

  final _codigo = TextEditingController();
  final _nombre = TextEditingController();
  final _precio = TextEditingController();
  final _costo = TextEditingController();

  bool _loading = true;
  bool _saving = false;
  bool _saved = false;

  List<Map<String, Object?>> _categorias = const [];
  int? _categoriaId;

  String? _imagenPath;
  String? _originalImagenPath;
  String? _imagenUrl;
  String? _originalImagenUrl;
  final List<String> _tempImages = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _codigo.dispose();
    _nombre.dispose();
    _precio.dispose();
    _costo.dispose();

    if (!_saved) {
      for (final path in _tempImages) {
        try {
          final f = File(path);
          if (f.existsSync()) f.deleteSync();
        } catch (_) {}
      }
    }
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);

    final cats = await _db.db.query('categorias', orderBy: 'nombre COLLATE NOCASE');
    final categorias = <Map<String, Object?>>[...cats];

    Map<String, Object?>? existing;
    if (widget.productoId != null) {
      final rows = await _db.db.query(
        'productos',
        where: 'id = ?',
        whereArgs: [widget.productoId],
        limit: 1,
      );
      if (rows.isNotEmpty) existing = rows.first;
    }

    _codigo.text = (existing?['codigo'] as String?) ?? '';
    _nombre.text = (existing?['nombre'] as String?) ?? '';
    _precio.text = (existing?['precio'] as num?)?.toString() ?? '';
    _costo.text = (existing?['costo'] as num?)?.toString() ?? '';

    final existingCategoriaId = existing?['categoria_id'] as int?;
    final categoriaId = existingCategoriaId ?? (categorias.isEmpty ? null : categorias.first['id'] as int);

    final existingImg = existing?['imagen_path'] as String?;
    final existingUrl = existing?['imagen_url'] as String?;

    if (!mounted) return;
    setState(() {
      _categorias = categorias;
      _categoriaId = categoriaId;
      _imagenPath = existingImg;
      _originalImagenPath = existingImg;
      _imagenUrl = existingUrl;
      _originalImagenUrl = existingUrl;
      _loading = false;
    });
  }

  Future<void> _addCategoriaInline() async {
    final controller = TextEditingController();
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Nueva categoría'),
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

    final newId = await _db.db.insert('categorias', {
      'nombre': nombre,
      'creado_en': DateTime.now().millisecondsSinceEpoch,
    });

    final cats = await _db.db.query('categorias', orderBy: 'nombre COLLATE NOCASE');
    if (!mounted) return;
    setState(() {
      _categorias = <Map<String, Object?>>[...cats];
      _categoriaId = newId;
    });
  }

  Future<void> _pickImage() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      allowMultiple: false,
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;

    final picked = result.files.single;
    final sourcePath = picked.path;
    final bytes = picked.bytes;
    if ((sourcePath == null || sourcePath.isEmpty) && bytes == null) return;

    final dir = await getApplicationDocumentsDirectory();
    final imagesDir = Directory(p.join(dir.path, 'fulltech', 'catalogo'));
    if (!await imagesDir.exists()) {
      await imagesDir.create(recursive: true);
    }

    final ext = sourcePath == null || sourcePath.isEmpty
        ? (picked.extension == null ? '' : '.${picked.extension}')
        : p.extension(sourcePath);
    final fileName = 'prod_${DateTime.now().millisecondsSinceEpoch}$ext';
    final destPath = p.join(imagesDir.path, fileName);

    try {
      if (bytes != null) {
        await File(destPath).writeAsBytes(bytes, flush: true);
      } else {
        await File(sourcePath!).copy(destPath);
      }

      final previous = _imagenPath;
      setState(() {
        _imagenPath = destPath;
        _imagenUrl = null;
        _tempImages.add(destPath);
      });

      // Si el usuario selecciona varias veces durante el mismo formulario,
      // limpiamos la imagen temporal anterior para no dejar basura.
      if (previous != null && previous.isNotEmpty && _tempImages.contains(previous)) {
        try {
          final f = File(previous);
          if (await f.exists()) await f.delete();
        } catch (_) {}
        _tempImages.remove(previous);
      }
    } catch (_) {
      // ignore
    }
  }

  Future<void> _removeImage() async {
    final current = _imagenPath;
    setState(() {
      _imagenPath = null;
      _imagenUrl = null;
    });
    if (current != null && current.isNotEmpty && _tempImages.contains(current)) {
      try {
        final f = File(current);
        if (await f.exists()) await f.delete();
      } catch (_) {}
      _tempImages.remove(current);
    }
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _saving = true);

    final now = DateTime.now().millisecondsSinceEpoch;
    final precio = double.tryParse(_precio.text.trim()) ?? 0.0;
    final costo = double.tryParse(_costo.text.trim()) ?? 0.0;
    final codigo = _codigo.text.trim().isEmpty
        ? 'PRD-$now'
        : _codigo.text.trim();

    if (widget.productoId == null) {
      await _db.insert('productos', {
        'categoria_id': _categoriaId,
        'codigo': codigo,
        'nombre': _nombre.text.trim(),
        'precio': precio,
        'costo': costo,
        'imagen_path': _imagenPath,
        'imagen_url': _imagenUrl,
        'creado_en': now,
        'actualizado_en': now,
      });
    } else {
      await _db.update(
        'productos',
        {
          'categoria_id': _categoriaId,
          'codigo': codigo,
          'nombre': _nombre.text.trim(),
          'precio': precio,
          'costo': costo,
          'imagen_path': _imagenPath,
          'imagen_url': _imagenUrl,
          'actualizado_en': now,
        },
        id: widget.productoId!,
      );
    }

    final original = _originalImagenPath;
    final current = _imagenPath;
    if (original != null && original.isNotEmpty && original != current) {
      try {
        final f = File(original);
        if (await f.exists()) await f.delete();
      } catch (_) {}
    }

    // Si el usuario no cambió la imagen, preserva URL original.
    // Si la cambió, _imagenUrl ya quedó en null para re-subir en el próximo sync.
    if (_imagenUrl == null && current == _originalImagenPath) {
      _imagenUrl = _originalImagenUrl;
    }

    _saved = true;
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    final isEdit = widget.productoId != null;

    return Form(
      key: _formKey,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FullTechSheetHeader(
            title: isEdit ? 'Editar producto' : 'Agregar producto',
            subtitle: 'Nombre, costo, precio e imagen',
          ),
          const SizedBox(height: 12),
          Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  _ImagePickerThumb(path: _imagenPath),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        FilledButton.icon(
                          onPressed: _pickImage,
                          icon: const Icon(Icons.image_outlined),
                          label: const Text('Imagen'),
                        ),
                        TextButton.icon(
                          onPressed: _imagenPath == null ? null : _removeImage,
                          icon: const Icon(Icons.delete_outline),
                          label: const Text('Quitar'),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _nombre,
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(
              labelText: 'Nombre',
              prefixIcon: Icon(Icons.inventory_2_outlined),
            ),
            validator: (v) => (v == null || v.trim().isEmpty) ? 'Requerido' : null,
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<int>(
                  value: _categoriaId,
                  decoration: const InputDecoration(
                    labelText: 'Categoría',
                    prefixIcon: Icon(Icons.category_outlined),
                  ),
                  items: _categorias
                      .map(
                        (c) => DropdownMenuItem<int>(
                          value: c['id'] as int,
                          child: Text((c['nombre'] ?? '') as String),
                        ),
                      )
                      .toList(),
                  onChanged: (v) => setState(() => _categoriaId = v),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filledTonal(
                tooltip: 'Nueva categoría',
                onPressed: _addCategoriaInline,
                icon: const Icon(Icons.add),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  controller: _precio,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: 'Precio',
                    prefixIcon: Icon(Icons.sell_outlined),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextFormField(
                  controller: _costo,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  textInputAction: TextInputAction.done,
                  decoration: const InputDecoration(
                    labelText: 'Costo',
                    prefixIcon: Icon(Icons.payments_outlined),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          FilledButton.icon(
            onPressed: _saving ? null : _save,
            icon: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.save_outlined),
            label: const Text('Guardar'),
          ),
        ],
      ),
    );
  }
}

class _ImagePickerThumb extends StatelessWidget {
  const _ImagePickerThumb({required this.path});

  final String? path;

  @override
  Widget build(BuildContext context) {
    final borderRadius = BorderRadius.circular(12);

    if (path == null || path!.isEmpty) {
      return Container(
        width: 64,
        height: 64,
        decoration: BoxDecoration(
          borderRadius: borderRadius,
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
        ),
        child: const Icon(Icons.image_outlined),
      );
    }

    return ClipRRect(
      borderRadius: borderRadius,
      child: Image.file(
        File(path!),
        width: 64,
        height: 64,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) {
          return Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              borderRadius: borderRadius,
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
            ),
            child: const Icon(Icons.broken_image_outlined),
          );
        },
      ),
    );
  }
}
