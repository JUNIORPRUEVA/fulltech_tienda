import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../data/app_database.dart';
import '../../data/auth_service.dart';
import '../../features/clientes/clientes_page.dart';
import '../../ui/fulltech_widgets.dart';
import 'venta_pdf.dart';

class VentaBuilderPage extends StatefulWidget {
  const VentaBuilderPage({super.key});

  @override
  State<VentaBuilderPage> createState() => _VentaBuilderPageState();
}

class _VentaBuilderPageState extends State<VentaBuilderPage> {
  final _db = AppDatabase.instance;

  int? _clienteId;
  static const String _moneda = 'RD\$';
  final _notas = TextEditingController();

  final _searchController = TextEditingController();
  final _searchFocus = FocusNode();
  bool _searchOpen = false;

  String _search = '';
  bool _saving = false;

  final List<_VentaLinea> _lines = [];

  @override
  void dispose() {
    _notas.dispose();
    _searchController.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final isWide = width >= 900;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Registrar venta'),
        actions: [
          IconButton(
            tooltip: 'Limpiar',
            onPressed: _lines.isEmpty
                ? null
                : () {
                    setState(() {
                      _lines.clear();
                      _notas.clear();
                      _search = '';
                      _searchController.clear();
                      _searchOpen = false;
                    });
                  },
            icon: const Icon(Icons.delete_sweep_outlined),
          ),
        ],
      ),
      body: SafeArea(
        child: CenteredList(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: isWide
                ? Row(
                    children: [
                      Expanded(child: _buildCatalogPane()),
                      const SizedBox(width: 12),
                      SizedBox(
                        width: _rightPaneWidth(width),
                        child: _buildCheckoutPane(),
                      ),
                    ],
                  )
                : Column(
                    children: [
                      Expanded(child: _buildCatalogPane()),
                      const SizedBox(height: 12),
                      SizedBox(height: 190, child: _buildCheckoutPane()),
                    ],
                  ),
          ),
        ),
      ),
    );
  }

  double _rightPaneWidth(double screenWidth) {
    final desired = screenWidth * 0.28;
    return desired.clamp(320.0, 460.0);
  }

  Widget _buildCatalogPane() {
    return FutureBuilder<List<Map<String, Object?>>>(
      future: _queryProductos(),
      builder: (context, snapshot) {
        final items = snapshot.data ?? const <Map<String, Object?>>[];
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }

        return CustomScrollView(
          slivers: [
            SliverToBoxAdapter(child: _buildCatalogHeaderRow()),
            const SliverToBoxAdapter(child: SizedBox(height: 12)),
            if (items.isEmpty)
              const SliverToBoxAdapter(
                child: _EmptyBox(
                  title: 'Catálogo vacío',
                  subtitle:
                      'Crea productos en Catálogo para vender más rápido.',
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.only(bottom: 8),
                sliver: SliverLayoutBuilder(
                  builder: (context, constraints) {
                    final w = constraints.crossAxisExtent;
                    final crossAxisCount = w >= 1000
                        ? 7
                        : w >= 860
                            ? 6
                            : w >= 720
                                ? 5
                                : w >= 560
                                    ? 4
                                    : w >= 420
                                        ? 3
                                        : 2;

                    return SliverGrid(
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: crossAxisCount,
                        crossAxisSpacing: 8,
                        mainAxisSpacing: 8,
                        childAspectRatio: 0.86,
                      ),
                      delegate: SliverChildBuilderDelegate(
                        (context, i) {
                          final r = items[i];
                          final id = r['id'] as int;
                          final nombre = (r['nombre'] ?? '') as String;
                          final codigo = (r['codigo'] ?? '') as String;
                          final precio =
                              (r['precio'] as num?)?.toDouble() ?? 0.0;
                          final costo = (r['costo'] as num?)?.toDouble() ?? 0.0;
                          final imagenPath = r['imagen_path'] as String?;

                          return _ProductoMiniCard(
                            nombre: nombre,
                            codigo: codigo,
                            precio: precio,
                            moneda: _moneda,
                            imagenPath: imagenPath,
                            onTap: () {
                              _addLineFromCatalog(
                                productoId: id,
                                codigo: codigo,
                                nombre: nombre,
                                precioVenta: precio,
                                costo: costo,
                                imagenPath: imagenPath,
                              );
                            },
                          );
                        },
                        childCount: items.length,
                      ),
                    );
                  },
                ),
              ),
            const SliverToBoxAdapter(child: SizedBox(height: 8)),
            SliverToBoxAdapter(child: _buildCartDetailBelowGrid()),
            const SliverToBoxAdapter(child: SizedBox(height: 12)),
          ],
        );
      },
    );
  }

  Widget _buildCatalogHeaderRow() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 520;
        final hasNotas = _notas.text.trim().isNotEmpty;
        final hasCliente = _clienteId != null;

        return Card(
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Row(
              children: [
                if (_searchOpen)
                  Expanded(
                    child: TextField(
                      controller: _searchController,
                      focusNode: _searchFocus,
                      decoration: InputDecoration(
                        isDense: true,
                        prefixIcon: const Icon(Icons.search),
                        hintText: 'Buscar producto…',
                        suffixIcon: _searchController.text.trim().isNotEmpty
                            ? IconButton(
                                tooltip: 'Limpiar búsqueda',
                                onPressed: () {
                                  _searchController.clear();
                                  setState(() => _search = '');
                                },
                                icon: const Icon(Icons.close),
                              )
                            : IconButton(
                                tooltip: 'Cerrar búsqueda',
                                onPressed: () {
                                  setState(() => _searchOpen = false);
                                },
                                icon: const Icon(Icons.keyboard_arrow_up),
                              ),
                      ),
                      onChanged: (v) => setState(() => _search = v.trim()),
                    ),
                  )
                else
                  IconButton.filledTonal(
                    tooltip: 'Buscar producto',
                    onPressed: () {
                      setState(() {
                        _searchOpen = true;
                        _searchController.text = _search;
                        _searchController.selection =
                            TextSelection.fromPosition(
                          TextPosition(offset: _searchController.text.length),
                        );
                      });
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (mounted) _searchFocus.requestFocus();
                      });
                    },
                    icon: const Icon(Icons.search),
                    visualDensity: VisualDensity.compact,
                  ),
                const SizedBox(width: 8),
                IconButton.filledTonal(
                  tooltip: hasCliente
                      ? 'Cliente seleccionado'
                      : 'Seleccionar cliente',
                  onPressed: _openClientePicker,
                  icon: Icon(
                    hasCliente ? Icons.person : Icons.person_outline,
                  ),
                  visualDensity: VisualDensity.compact,
                ),
                const SizedBox(width: 6),
                IconButton.filledTonal(
                  tooltip: hasNotas ? 'Editar nota' : 'Agregar nota',
                  onPressed: _openNotasEditor,
                  icon: Icon(
                    hasNotas
                        ? Icons.sticky_note_2
                        : Icons.sticky_note_2_outlined,
                  ),
                  visualDensity: VisualDensity.compact,
                ),
                const SizedBox(width: 6),
                IconButton.filledTonal(
                  tooltip: 'Venta manual (fuera del catálogo)',
                  onPressed: _addManualLine,
                  icon: const Icon(Icons.playlist_add_outlined),
                  visualDensity: VisualDensity.compact,
                ),
                const SizedBox(width: 8),
                if (compact)
                  IconButton.filledTonal(
                    tooltip: 'Resumen',
                    onPressed:
                        _lines.isEmpty ? null : () => _showSummary(context),
                    icon: const Icon(Icons.summarize_outlined),
                    visualDensity: VisualDensity.compact,
                  )
                else
                  FilledButton.tonalIcon(
                    onPressed:
                        _lines.isEmpty ? null : () => _showSummary(context),
                    icon: const Icon(Icons.summarize_outlined),
                    label: const Text('Resumen'),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _openNotasEditor() async {
    final ctrl = TextEditingController(text: _notas.text);
    try {
      final ok = await showDialog<bool>(
        context: context,
        builder: (context) {
          return AlertDialog(
            title: const Text('Nota'),
            content: TextField(
              controller: ctrl,
              maxLines: 4,
              decoration: const InputDecoration(
                hintText: 'Escribe una nota para la venta…',
                border: OutlineInputBorder(),
              ),
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
          );
        },
      );

      if (ok != true) return;
      setState(() {
        _notas.text = ctrl.text;
      });
    } finally {
      ctrl.dispose();
    }
  }

  Future<void> _openClientePicker() async {
    int? selected = _clienteId;
    int refreshTick = 0;

    final picked = await showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return SafeArea(
              child: Padding(
                padding: EdgeInsets.only(
                  left: 16,
                  right: 16,
                  top: 8,
                  bottom: 16 + MediaQuery.viewInsetsOf(context).bottom,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        const Expanded(
                          child: Text(
                            'Cliente',
                            style: TextStyle(
                                fontWeight: FontWeight.w900, fontSize: 16),
                          ),
                        ),
                        IconButton(
                          tooltip: 'Cerrar',
                          onPressed: () => Navigator.pop(context),
                          icon: const Icon(Icons.close),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    FutureBuilder<List<Map<String, Object?>>>(
                      future: _db.queryAll(
                        'clientes',
                        orderBy: 'nombre COLLATE NOCASE',
                      ),
                      builder: (context, snapshot) {
                        // Usa refreshTick para forzar rebuild cuando se agrega un cliente.
                        // ignore: unused_local_variable
                        final _ = refreshTick;

                        final clientes =
                            snapshot.data ?? const <Map<String, Object?>>[];
                        if (snapshot.connectionState != ConnectionState.done) {
                          return const Center(
                              child: CircularProgressIndicator());
                        }

                        if (clientes.isEmpty) {
                          return const Text(
                              'No hay clientes. Agrega uno para continuar.');
                        }

                        return DropdownButtonFormField<int>(
                          value: selected,
                          decoration: const InputDecoration(
                            isDense: true,
                            labelText: 'Cliente (obligatorio)',
                            prefixIcon: Icon(Icons.people_alt_outlined),
                            border: OutlineInputBorder(),
                          ),
                          items: clientes
                              .map(
                                (c) => DropdownMenuItem<int>(
                                  value: c['id'] as int,
                                  child: Text((c['nombre'] ?? '') as String),
                                ),
                              )
                              .toList(growable: false),
                          onChanged: (v) => setModalState(() => selected = v),
                        );
                      },
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: FilledButton.tonalIcon(
                            onPressed: () async {
                              await ClientesPage.openAddForm(context);
                              setModalState(() => refreshTick++);
                            },
                            icon: const Icon(Icons.person_add_alt_1_outlined),
                            label: const Text('Agregar'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: selected == null
                                ? null
                                : () => Navigator.pop(context, selected),
                            icon: const Icon(Icons.check_circle_outline),
                            label: const Text('Seleccionar'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );

    if (picked == null) return;
    setState(() => _clienteId = picked);
  }

  Future<void> _addManualLine() async {
    final nombreCtrl = TextEditingController();
    final precioCtrl = TextEditingController();
    final costoCtrl = TextEditingController();
    final qtyCtrl = TextEditingController(text: '1');

    try {
      final ok = await showDialog<bool>(
        context: context,
        builder: (context) {
          return AlertDialog(
            title: const Text('Venta manual'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: nombreCtrl,
                    decoration: const InputDecoration(labelText: 'Nombre'),
                    textCapitalization: TextCapitalization.words,
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: precioCtrl,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(labelText: 'Precio'),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: costoCtrl,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration:
                        const InputDecoration(labelText: 'Costo (opcional)'),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: qtyCtrl,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(labelText: 'Cantidad'),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancelar'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Agregar'),
              ),
            ],
          );
        },
      );

      if (ok != true) return;

      final nombre = nombreCtrl.text.trim();
      final precio =
          double.tryParse(precioCtrl.text.trim().replaceAll(',', '.'));
      final costo =
          double.tryParse(costoCtrl.text.trim().replaceAll(',', '.')) ?? 0.0;
      final qty =
          double.tryParse(qtyCtrl.text.trim().replaceAll(',', '.')) ?? 1.0;

      if (nombre.isEmpty || precio == null || precio <= 0 || qty <= 0) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Datos inválidos.')),
        );
        return;
      }

      setState(() {
        _lines.add(
          _VentaLinea(
            productoId: null,
            codigo: '',
            nombre: nombre,
            cantidad: qty,
            precioBase: precio,
            precioVenta: precio,
            costo: costo,
            imagenPath: null,
          ),
        );
      });
    } finally {
      nombreCtrl.dispose();
      precioCtrl.dispose();
      costoCtrl.dispose();
      qtyCtrl.dispose();
    }
  }

  Widget _buildCartDetailBelowGrid() {
    if (_lines.isEmpty) {
      return const Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Text('Agrega productos desde el catálogo.'),
        ),
      );
    }

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Detalle de venta',
                    style: TextStyle(fontWeight: FontWeight.w900, fontSize: 14),
                  ),
                ),
                Text(
                  '${_lines.length} item(s)',
                  style: const TextStyle(color: Colors.black54),
                ),
              ],
            ),
            const SizedBox(height: 10),
            for (int i = 0; i < _lines.length; i++) ...[
              _VentaLineCompactTile(
                moneda: _moneda,
                line: _lines[i],
                onAdd: () => setState(() => _lines[i].cantidad += 1),
                onRemove: () {
                  setState(() {
                    _lines[i].cantidad -= 1;
                    if (_lines[i].cantidad <= 0) _lines.removeAt(i);
                  });
                },
                onDelete: () => setState(() => _lines.removeAt(i)),
                onEditPrice: () => _editPrice(_lines[i]),
                onEditQty: () => _editQty(_lines[i]),
              ),
              if (i != _lines.length - 1) const Divider(height: 16),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildCheckoutPane() {
    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: FilledButton.icon(
                onPressed: _saving ? null : _save,
                icon: _saving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.save_outlined),
                label: const Text('Guardar venta'),
              ),
            ),
          ),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 12)),
      ],
    );
  }

  Future<List<Map<String, Object?>>> _queryProductos() async {
    final q = _search.trim();
    if (q.isEmpty) {
      return _db.db.query('productos', orderBy: 'actualizado_en DESC, id DESC');
    }
    return _db.db.query(
      'productos',
      where: '(nombre LIKE ? OR codigo LIKE ?)',
      whereArgs: ['%$q%', '%$q%'],
      orderBy: 'actualizado_en DESC, id DESC',
    );
  }

  void _addLineFromCatalog({
    required int productoId,
    required String codigo,
    required String nombre,
    required double precioVenta,
    required double costo,
    required String? imagenPath,
  }) {
    final existingIndex = _lines
        .indexWhere((l) => l.productoId != null && l.productoId == productoId);
    setState(() {
      if (existingIndex >= 0) {
        _lines[existingIndex].cantidad += 1;
      } else {
        _lines.add(
          _VentaLinea(
            productoId: productoId,
            codigo: codigo,
            nombre: nombre,
            cantidad: 1,
            precioBase: precioVenta,
            precioVenta: precioVenta,
            costo: costo,
            imagenPath: imagenPath,
          ),
        );
      }
    });
  }

  Future<void> _editPrice(_VentaLinea line) async {
    final controller =
        TextEditingController(text: line.precioVenta.toStringAsFixed(2));
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Precio de venta'),
          content: TextField(
            controller: controller,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: 'Precio'),
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
        );
      },
    );

    if (ok != true) return;
    final value = double.tryParse(controller.text.trim());
    if (value == null || value <= 0) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Precio inválido.')),
      );
      return;
    }

    setState(() => line.precioVenta = value);
  }

  Future<void> _editQty(_VentaLinea line) async {
    final controller = TextEditingController(text: _qty(line.cantidad));
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Cantidad'),
          content: TextField(
            controller: controller,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: 'Cantidad'),
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
        );
      },
    );

    if (ok != true) return;
    final value = double.tryParse(controller.text.trim());
    if (value == null || value <= 0) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cantidad inválida.')),
      );
      return;
    }

    setState(() => line.cantidad = value);
  }

  double _puntosTotal() => _lines
      .fold<double>(0.0, (s, l) => s + l.puntos)
      .clamp(0.0, double.infinity)
      .toDouble();

  double _totalVenta() => _lines
      .fold<double>(0.0, (s, l) => s + l.total)
      .clamp(0.0, double.infinity)
      .toDouble();

  double _comision(double puntos) =>
      (puntos * 0.10).clamp(0.0, double.infinity).toDouble();

  Future<void> _save() async {
    if (_lines.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Agrega al menos un producto.')),
      );
      return;
    }

    if (_clienteId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Selecciona un cliente (obligatorio).')),
      );
      return;
    }

    final userId = AuthService.instance.currentUserId;
    if (userId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Sin sesión activa.')),
      );
      return;
    }

    setState(() => _saving = true);

    try {
      final now = DateTime.now().millisecondsSinceEpoch;
      final codigo = _autoCode();
      final total = _totalVenta();
      final puntos = _puntosTotal();
      final ganancia = puntos;

      final ventaId = await _db.insert('ventas', {
        'usuario_id': userId,
        'cliente_id': _clienteId,
        'codigo': codigo,
        'total': total,
        'ganancia': ganancia,
        'puntos': puntos,
        'moneda': _moneda,
        'notas': _notas.text.trim().isEmpty ? null : _notas.text.trim(),
        'creado_en': now,
        'actualizado_en': now,
      });

      for (final l in _lines) {
        await _db.insert('venta_items', {
          'venta_id': ventaId,
          'producto_id': l.productoId,
          'codigo': l.codigo.isEmpty ? null : l.codigo,
          'nombre': l.nombre,
          'cantidad': l.cantidad,
          'precio': l.precioVenta,
          'costo': l.costo,
          'creado_en': now,
        });
      }

      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo guardar: $e')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String _autoCode() {
    final dt = DateTime.now();
    final y = dt.year.toString().padLeft(4, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    final hh = dt.hour.toString().padLeft(2, '0');
    final mm = dt.minute.toString().padLeft(2, '0');
    final ss = dt.second.toString().padLeft(2, '0');
    return 'V-$y$m$d-$hh$mm$ss';
  }

  void _showSummary(BuildContext context) {
    final totalVenta = _totalVenta();
    final puntos = _puntosTotal();
    final comision = _comision(puntos);
    final codigo = _autoCode();
    final fecha = DateTime.now();

    bool exporting = false;

    showFullTechFormSheet<void>(
      context: context,
      child: StatefulBuilder(
        builder: (context, setLocal) {
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              FullTechSheetHeader(
                title: 'Resumen',
                subtitle: 'Venta $codigo',
              ),
              const SizedBox(height: 12),
              Card(
                margin: EdgeInsets.zero,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      FutureBuilder<Map<String, Object?>?>(
                        future: _loadClienteRow(),
                        builder: (context, snap) {
                          final c = snap.data;
                          final nombre = (c?['nombre'] as String?)?.trim();
                          final telefono = (c?['telefono'] as String?)?.trim();
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              _InfoLine(
                                label: 'Cliente',
                                value: (nombre == null || nombre.isEmpty)
                                    ? '—'
                                    : nombre,
                              ),
                              if (telefono != null && telefono.isNotEmpty)
                                _InfoLine(label: 'Teléfono', value: telefono),
                              _InfoLine(
                                label: 'Fecha',
                                value:
                                    '${fecha.year.toString().padLeft(4, '0')}-${fecha.month.toString().padLeft(2, '0')}-${fecha.day.toString().padLeft(2, '0')} ${fecha.hour.toString().padLeft(2, '0')}:${fecha.minute.toString().padLeft(2, '0')}',
                              ),
                            ],
                          );
                        },
                      ),
                      const Divider(height: 18),
                      for (final l in _lines) ...[
                        _LineSummaryRow(moneda: _moneda, line: l),
                        const Divider(height: 16),
                      ],
                      const SizedBox(height: 4),
                      _TotalRow(
                        label: 'Total',
                        value: _money(totalVenta, _moneda),
                      ),
                      const SizedBox(height: 6),
                      _TotalRow(
                        label: 'Total puntos',
                        value: _money(puntos, _moneda),
                      ),
                      const SizedBox(height: 6),
                      _TotalRow(
                        label: 'Total comisión (10%)',
                        value: _money(comision, _moneda),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: exporting
                    ? null
                    : () async {
                        setLocal(() => exporting = true);
                        try {
                          final c = await _loadClienteRow();
                          final clienteNombre =
                              ((c?['nombre'] as String?) ?? '').trim();
                          final clienteTelefono =
                              ((c?['telefono'] as String?) ?? '').trim();

                          final empresa = await _db.getEmpresaConfig();
                          final empresaNombre =
                              ((empresa?['nombre'] as String?) ?? '').trim();
                          final empresaRnc =
                              ((empresa?['rnc'] as String?) ?? '').trim();
                          final empresaTel =
                              ((empresa?['telefono'] as String?) ?? '').trim();
                          final empresaEmail =
                              ((empresa?['email'] as String?) ?? '').trim();
                          final empresaDir =
                              ((empresa?['direccion'] as String?) ?? '').trim();
                          final empresaWeb =
                              ((empresa?['web'] as String?) ?? '').trim();
                          final logoPath =
                              ((empresa?['logo_path'] as String?) ?? '').trim();

                          Uint8List? logoBytes;
                          if (logoPath.isNotEmpty) {
                            final f = File(logoPath);
                            if (await f.exists()) {
                              logoBytes = await f.readAsBytes();
                            }
                          }

                          final pdf = await buildVentaPdf(
                            codigo: codigo,
                            fecha: fecha,
                            clienteNombre: clienteNombre,
                            clienteTelefono: clienteTelefono,
                            moneda: _moneda,
                            total: totalVenta,
                            puntos: puntos,
                            comision: comision,
                            empresaNombre: empresaNombre,
                            empresaRnc: empresaRnc,
                            empresaTelefono: empresaTel,
                            empresaEmail: empresaEmail,
                            empresaDireccion: empresaDir,
                            empresaWeb: empresaWeb,
                            logoBytes: logoBytes,
                            lines: _lines
                                .map(
                                  (l) => VentaPdfLinea(
                                    nombre: l.nombre,
                                    cantidad: l.cantidad,
                                    precio: l.precioVenta,
                                    costo: l.costo,
                                  ),
                                )
                                .toList(growable: false),
                          );

                          final path = await _savePdfToDownloads(
                            bytes: pdf,
                            fileName: 'venta_$codigo.pdf',
                          );

                          if (!mounted) return;
                          final result = await OpenFilex.open(path);
                          if (result.type != ResultType.done && mounted) {
                            final msg = result.message.trim();
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(msg.isEmpty
                                    ? 'No se pudo abrir el PDF.'
                                    : msg),
                              ),
                            );
                          }
                        } catch (e) {
                          if (!mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                                content: Text('Error al exportar PDF: $e')),
                          );
                        } finally {
                          if (mounted) setLocal(() => exporting = false);
                        }
                      },
                icon: exporting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.picture_as_pdf_outlined),
                label: const Text('Generar PDF y descargar'),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<Map<String, Object?>?> _loadClienteRow() async {
    final id = _clienteId;
    if (id == null || id <= 0) return null;
    final rows = await _db.db.query(
      'clientes',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first;
  }

  Future<String> _savePdfToDownloads({
    required Uint8List bytes,
    required String fileName,
  }) async {
    final downloads = await getDownloadsDirectory();
    final dir = downloads ?? await getApplicationDocumentsDirectory();
    final path = p.join(dir.path, fileName);
    final file = File(path);
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  }
}

class _VentaLineCompactTile extends StatelessWidget {
  const _VentaLineCompactTile({
    required this.moneda,
    required this.line,
    required this.onAdd,
    required this.onRemove,
    required this.onDelete,
    required this.onEditPrice,
    required this.onEditQty,
  });

  final String moneda;
  final _VentaLinea line;
  final VoidCallback onAdd;
  final VoidCallback onRemove;
  final VoidCallback onDelete;
  final VoidCallback onEditPrice;
  final VoidCallback onEditQty;

  @override
  Widget build(BuildContext context) {
    final meta =
        '(${_qty(line.cantidad)} x ${_money(line.precioVenta, moneda)})';

    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                line.nombre,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 2),
              Wrap(
                spacing: 10,
                children: [
                  InkWell(
                    onTap: onEditQty,
                    borderRadius: BorderRadius.circular(10),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Text(
                        meta,
                        style: const TextStyle(
                            color: Colors.black54, fontSize: 12),
                      ),
                    ),
                  ),
                  InkWell(
                    onTap: onEditPrice,
                    borderRadius: BorderRadius.circular(10),
                    child: const Padding(
                      padding: EdgeInsets.symmetric(vertical: 2),
                      child: Text(
                        'Editar',
                        style: TextStyle(
                          color: Colors.black54,
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(width: 10),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              _money(line.total, moneda),
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 6),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton.filledTonal(
                  onPressed: onRemove,
                  icon: const Icon(Icons.remove),
                  visualDensity: VisualDensity.compact,
                ),
                const SizedBox(width: 6),
                IconButton.filledTonal(
                  onPressed: onAdd,
                  icon: const Icon(Icons.add),
                  visualDensity: VisualDensity.compact,
                ),
                const SizedBox(width: 6),
                IconButton(
                  tooltip: 'Eliminar',
                  onPressed: onDelete,
                  icon: const Icon(Icons.delete_outline),
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
          ],
        ),
      ],
    );
  }
}

class _ProductoMiniCard extends StatelessWidget {
  const _ProductoMiniCard({
    required this.nombre,
    required this.codigo,
    required this.precio,
    required this.moneda,
    required this.imagenPath,
    required this.onTap,
  });

  final String nombre;
  final String codigo;
  final double precio;
  final String moneda;
  final String? imagenPath;
  final VoidCallback onTap;

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
                child: _ImageBox(path: imagenPath),
              ),
              const SizedBox(height: 6),
              Text(
                nombre,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style:
                    const TextStyle(fontWeight: FontWeight.w900, fontSize: 12),
              ),
              if (codigo.trim().isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  codigo,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.black54, fontSize: 11),
                ),
              ],
              const SizedBox(height: 4),
              Text(
                _money(precio, moneda),
                style:
                    const TextStyle(fontWeight: FontWeight.w900, fontSize: 12),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ImageBox extends StatelessWidget {
  const _ImageBox({required this.path});

  final String? path;

  @override
  Widget build(BuildContext context) {
    final borderRadius = BorderRadius.circular(12);

    if (path == null || path!.trim().isEmpty) {
      return Container(
        decoration: BoxDecoration(
          borderRadius: borderRadius,
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
        ),
        child: const Center(child: Icon(Icons.inventory_2_outlined)),
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
            decoration: BoxDecoration(
              borderRadius: borderRadius,
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
            ),
            child: const Center(child: Icon(Icons.broken_image_outlined)),
          );
        },
      ),
    );
  }
}

class _InfoLine extends StatelessWidget {
  const _InfoLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          SizedBox(
            width: 78,
            child: Text(
              label,
              style: const TextStyle(
                fontWeight: FontWeight.w800,
                color: Colors.black54,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
          ),
        ],
      ),
    );
  }
}

class _LineSummaryRow extends StatelessWidget {
  const _LineSummaryRow({required this.moneda, required this.line});

  final String moneda;
  final _VentaLinea line;

  @override
  Widget build(BuildContext context) {
    final comision = (line.puntos * 0.10).clamp(0.0, double.infinity);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                line.nombre,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 2),
              Text(
                '${_qty(line.cantidad)} x ${_money(line.precioVenta, moneda)}',
                style: const TextStyle(color: Colors.black54, fontSize: 12),
              ),
              const SizedBox(height: 2),
              Text(
                'Puntos: ${_money(line.puntos, moneda)} • Comisión: ${_money(comision, moneda)}',
                style: const TextStyle(color: Colors.black54, fontSize: 12),
              ),
            ],
          ),
        ),
        const SizedBox(width: 10),
        Text(
          _money(line.total, moneda),
          style: const TextStyle(fontWeight: FontWeight.w900),
        ),
      ],
    );
  }
}

class _TotalRow extends StatelessWidget {
  const _TotalRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child:
              Text(label, style: const TextStyle(fontWeight: FontWeight.w800)),
        ),
        Text(value, style: const TextStyle(fontWeight: FontWeight.w900)),
      ],
    );
  }
}

class _EmptyBox extends StatelessWidget {
  const _EmptyBox({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.inbox_outlined, size: 34),
              const SizedBox(height: 10),
              Text(title,
                  style: const TextStyle(
                      fontWeight: FontWeight.w900, fontSize: 16)),
              const SizedBox(height: 6),
              Text(subtitle,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.black54)),
            ],
          ),
        ),
      ),
    );
  }
}

class _VentaLinea {
  _VentaLinea({
    required this.productoId,
    required this.codigo,
    required this.nombre,
    required this.cantidad,
    required this.precioBase,
    required this.precioVenta,
    required this.costo,
    required this.imagenPath,
  });

  final int? productoId;
  final String codigo;
  final String nombre;
  final String? imagenPath;

  double cantidad;
  final double precioBase;
  double precioVenta;
  final double costo;

  double get total => (precioVenta * cantidad).clamp(0.0, double.infinity);

  double get puntos {
    final g = (precioVenta - costo) * cantidad;
    return g;
  }
}

String _money(double value, String moneda) =>
    '$moneda ${value.toStringAsFixed(2)}';

String _qty(double value) {
  final isInt = value % 1 == 0;
  return value.toStringAsFixed(isInt ? 0 : 2);
}
