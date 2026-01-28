import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:printing/printing.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../data/app_database.dart';
import '../../features/clientes/clientes_page.dart';
import '../../ui/fulltech_widgets.dart';
import 'cotizacion_pdf.dart';
import 'cotizacion_models.dart';

class CotizacionBuilderPage extends StatefulWidget {
  const CotizacionBuilderPage({super.key, this.presupuestoId});

  final int? presupuestoId;

  @override
  State<CotizacionBuilderPage> createState() => _CotizacionBuilderPageState();
}

class _CatalogTab extends StatelessWidget {
  const _CatalogTab({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 0),
      child: child,
    );
  }
}

class _CotizacionBuilderPageState extends State<CotizacionBuilderPage> {
  final _db = AppDatabase.instance;

  int? _clienteId;
  static const String _moneda = 'RD\$';

  bool _itbisActivo = true;
  double _itbisTasa = 0.18;

  double _descuentoGlobal = 0.0;

  List<CotizacionLinea> _lines = [];

  String? _pdfCacheKey;
  String? _pdfCacheTitle;
  Uint8List? _pdfCacheBytes;

  String _search = '';
  int? _categoriaIdFilter;

  bool _loadingExisting = false;

  @override
  void initState() {
    super.initState();
    final id = widget.presupuestoId;
    if (id != null) {
      _loadingExisting = true;
      _loadExistingPresupuesto(id);
    }
  }

  Future<void> _loadExistingPresupuesto(int id) async {
    try {
      final presupuesto = await _db.findById('presupuestos', id);
      if (presupuesto == null) {
        if (!mounted) return;
        setState(() => _loadingExisting = false);
        return;
      }

      final itemRows = await _db.db.query(
        'presupuesto_items',
        where: 'presupuesto_id = ?',
        whereArgs: [id],
        orderBy: 'id ASC',
      );

      final loadedLines = <CotizacionLinea>[];
      for (final r in itemRows) {
        final line = CotizacionLinea(
          productoId: r['producto_id'] as int?,
          codigo: (r['codigo'] as String?) ?? '',
          nombre: (r['nombre'] as String?) ?? '',
          precio: (r['precio'] as num?)?.toDouble() ?? 0.0,
          cantidad: (r['cantidad'] as num?)?.toDouble() ?? 0.0,
        );
        line.descuento = (r['descuento'] as num?)?.toDouble() ?? 0.0;
        loadedLines.add(line);
      }

      if (!mounted) return;
      setState(() {
        _clienteId = presupuesto['cliente_id'] as int?;
        _itbisActivo = ((presupuesto['itbis_activo'] as int?) ?? 0) == 1;
        _itbisTasa = (presupuesto['itbis_tasa'] as num?)?.toDouble() ?? 0.18;
        _descuentoGlobal =
            (presupuesto['descuento_global'] as num?)?.toDouble() ?? 0.0;
        _lines = loadedLines;

        _pdfCacheKey = null;
        _pdfCacheTitle = null;
        _pdfCacheBytes = null;
        _loadingExisting = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingExisting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loadingExisting) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Presupuesto'),
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    final width = MediaQuery.sizeOf(context).width;
    final isWide = width >= 900;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Presupuesto'),
        actions: [
          IconButton(
            tooltip: 'Limpiar',
            onPressed: _lines.isEmpty
                ? null
                : () {
                    setState(() {
                      _lines = [];
                      _descuentoGlobal = 0;
                      _itbisActivo = true;
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
                        child: _buildQuotePane(),
                      ),
                    ],
                  )
                : DefaultTabController(
                    length: 2,
                    child: Column(
                      children: [
                        const Card(
                          margin: EdgeInsets.zero,
                          child: TabBar(
                            tabs: [
                              Tab(text: 'Catálogo'),
                              Tab(text: 'Presupuesto'),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                        Expanded(
                          child: TabBarView(
                            children: [
                              _CatalogTab(child: _buildCatalogPane()),
                              _CatalogTab(child: _buildQuotePane()),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
          ),
        ),
      ),
    );
  }

  double _rightPaneWidth(double screenWidth) {
    final desired = screenWidth * 0.25;
    return desired.clamp(320.0, 420.0);
  }

  Widget _buildCatalogPane() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Card(
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.search),
                      hintText: 'Buscar producto…',
                    ),
                    onChanged: (v) => setState(() => _search = v.trim()),
                  ),
                ),
                const SizedBox(width: 10),
                IconButton.filledTonal(
                  tooltip: _categoriaIdFilter == null
                      ? 'Filtrar por categoría'
                      : 'Categoría filtrada • Toca para cambiar',
                  onPressed: _openCategoriaFilter,
                  icon: Icon(
                    Icons.category_outlined,
                    color: _categoriaIdFilter == null
                        ? null
                        : Theme.of(context).colorScheme.primary,
                  ),
                ),
                if (_categoriaIdFilter != null) ...[
                  const SizedBox(width: 6),
                  IconButton.filledTonal(
                    tooltip: 'Quitar filtro de categoría',
                    onPressed: () => setState(() => _categoriaIdFilter = null),
                    icon: const Icon(Icons.clear),
                  ),
                ],
                const SizedBox(width: 10),
                FilledButton.tonalIcon(
                  onPressed: _addManualItem,
                  icon: const Icon(Icons.add),
                  label: const Text('Manual'),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Expanded(
          child: FutureBuilder<List<Map<String, Object?>>>(
            future: _queryProductos(),
            builder: (context, snapshot) {
              final items = snapshot.data ?? const <Map<String, Object?>>[];
              if (snapshot.connectionState != ConnectionState.done) {
                return const Center(child: CircularProgressIndicator());
              }
              if (items.isEmpty) {
                return const _EmptyBox(
                  title: 'Catálogo vacío',
                  subtitle:
                      'Crea productos en Catálogo para cotizar más rápido.',
                );
              }

              return LayoutBuilder(
                builder: (context, constraints) {
                  final crossAxisCount = constraints.maxWidth >= 900
                      ? 5
                      : constraints.maxWidth >= 700
                          ? 4
                          : constraints.maxWidth >= 520
                              ? 3
                              : 2;

                  return GridView.builder(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: crossAxisCount,
                      crossAxisSpacing: 10,
                      mainAxisSpacing: 10,
                      childAspectRatio: 0.92,
                    ),
                    itemCount: items.length,
                    itemBuilder: (context, i) {
                      final r = items[i];
                      final id = r['id'] as int;
                      final nombre = (r['nombre'] ?? '') as String;
                      final codigo = (r['codigo'] ?? '') as String;
                      final precio = (r['precio'] as num?)?.toDouble() ?? 0.0;
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
                            precio: precio,
                          );
                        },
                      );
                    },
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildQuotePane() {
    final subtotal = _lines.fold<double>(0.0, (s, l) => s + l.subtotal);
    final descuentoLineas = _lines.fold<double>(0.0, (s, l) => s + l.descuento);
    final descuentoGlobal =
        _descuentoGlobal.clamp(0.0, subtotal - descuentoLineas);

    final base = (subtotal - descuentoLineas - descuentoGlobal)
        .clamp(0.0, double.infinity);
    final itbis = _itbisActivo ? base * _itbisTasa : 0.0;
    final total = base + itbis;

    Future<Map<String, Object?>?> loadCliente() async {
      final id = _clienteId;
      if (id == null) return null;
      final rows = await _db.db
          .query('clientes', where: 'id = ?', whereArgs: [id], limit: 1);
      return rows.isEmpty ? null : rows.first;
    }

    final header = _ClienteHeader(
      db: _db,
      clienteId: _clienteId,
      onClienteChanged: (v) => setState(() => _clienteId = v),
      onAddCliente: () async {
        await ClientesPage.openAddForm(context);
        if (!mounted) return;
        setState(() {});
      },
    );

    final resumen = FutureBuilder<Map<String, Object?>?>(
      future: loadCliente(),
      builder: (context, snapshot) {
        final clienteNombre = _clienteId == null
            ? 'Consumidor final'
            : ((snapshot.data?['nombre'] as String?) ?? 'Cliente');
        final totalText = _money(total, _moneda);
        return Card(
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Resumen',
                        style: TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 15,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        clienteNombre,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Total: $totalText',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.primary,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );

    final linesCard = Card(
      margin: EdgeInsets.zero,
      child: _lines.isEmpty
          ? const Padding(
              padding: EdgeInsets.all(16),
              child: Text('Agrega productos desde el catálogo o manual.'),
            )
          : ListView.separated(
              padding: const EdgeInsets.all(12),
              itemCount: _lines.length,
              separatorBuilder: (_, __) => const Divider(height: 18),
              itemBuilder: (context, i) {
                final line = _lines[i];
                return _QuoteLineTile(
                  moneda: _moneda,
                  line: line,
                  onAdd: () => setState(() => line.cantidad += 1),
                  onRemove: () {
                    setState(() {
                      line.cantidad -= 1;
                      if (line.cantidad <= 0) _lines.removeAt(i);
                    });
                  },
                  onEditCantidad: () => _editLineCantidad(line),
                  onDelete: () => setState(() => _lines.removeAt(i)),
                  onDoubleTapDiscount: () => _editLineDiscount(line),
                );
              },
            ),
    );

    final totalsCard = Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Totales',
                    style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15),
                  ),
                ),
                Switch(
                  value: _itbisActivo,
                  onChanged: (v) => setState(() => _itbisActivo = v),
                ),
              ],
            ),
            const SizedBox(height: 6),
            _TotalRow(label: 'Subtotal', value: _money(subtotal, _moneda)),
            _TotalRow(
              label: 'Descuento líneas',
              value: '- ${_money(descuentoLineas, _moneda)}',
            ),
            GestureDetector(
              onDoubleTap: _editGlobalDiscount,
              child: _TotalRow(
                label: 'Descuento total (doble click)',
                value: '- ${_money(descuentoGlobal, _moneda)}',
              ),
            ),
            _TotalRow(
              label: 'ITBIS (${(_itbisTasa * 100).toStringAsFixed(0)}%)',
              value: _itbisActivo ? _money(itbis, _moneda) : '—',
            ),
            const Divider(height: 18),
            _TotalRow(
              label: 'Total',
              value: _money(total, _moneda),
              bold: true,
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed:
                  _lines.isEmpty ? null : () => _cotizar(total, itbis, base),
              icon: const Icon(Icons.picture_as_pdf_outlined),
              label: const Text('Cotizar (PDF)'),
            ),
            const SizedBox(height: 8),
            FilledButton.tonalIcon(
              onPressed:
                  _lines.isEmpty ? null : () => _shareToWhatsAppQuick(total),
              icon: const Icon(Icons.chat_outlined),
              label: const Text('Enviar por WhatsApp'),
            ),
          ],
        ),
      ),
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final tightHeight = constraints.maxHeight < 520;
        if (tightHeight) {
          return ListView(
            children: [
              header,
              const SizedBox(height: 12),
              resumen,
              const SizedBox(height: 12),
              Card(
                margin: EdgeInsets.zero,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: _lines.isEmpty
                      ? const Text(
                          'Agrega productos desde el catálogo o manual.')
                      : ListView.separated(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: _lines.length,
                          separatorBuilder: (_, __) =>
                              const Divider(height: 18),
                          itemBuilder: (context, i) {
                            final line = _lines[i];
                            return _QuoteLineTile(
                              moneda: _moneda,
                              line: line,
                              onAdd: () => setState(() => line.cantidad += 1),
                              onRemove: () {
                                setState(() {
                                  line.cantidad -= 1;
                                  if (line.cantidad <= 0) _lines.removeAt(i);
                                });
                              },
                              onEditCantidad: () => _editLineCantidad(line),
                              onDelete: () =>
                                  setState(() => _lines.removeAt(i)),
                              onDoubleTapDiscount: () =>
                                  _editLineDiscount(line),
                            );
                          },
                        ),
                ),
              ),
              const SizedBox(height: 12),
              totalsCard,
            ],
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            header,
            const SizedBox(height: 12),
            resumen,
            const SizedBox(height: 12),
            Expanded(child: linesCard),
            const SizedBox(height: 12),
            totalsCard,
          ],
        );
      },
    );
  }

  Future<Map<String, Object?>?> _loadSelectedCliente() async {
    final id = _clienteId;
    if (id == null) return null;
    final rows = await _db.db
        .query('clientes', where: 'id = ?', whereArgs: [id], limit: 1);
    return rows.isEmpty ? null : rows.first;
  }

  Future<({String title, Uint8List bytes})> _buildPdfBytes(
      double total, double itbis, double base) async {
    final key = _pdfKey();
    if (_pdfCacheKey == key &&
        _pdfCacheTitle != null &&
        _pdfCacheBytes != null) {
      return (title: _pdfCacheTitle!, bytes: _pdfCacheBytes!);
    }

    final now = DateTime.now().millisecondsSinceEpoch;

    final existingId = widget.presupuestoId;
    late final int presupuestoId;

    if (existingId != null) {
      presupuestoId = existingId;
      final existing = await _db.findById('presupuestos', existingId);
      final existingCodigo = (existing?['codigo'] as String?)?.trim();
      await _db.update(
        'presupuestos',
        {
          'cliente_id': _clienteId,
          'codigo': (existingCodigo == null || existingCodigo.isEmpty)
              ? _newCodigo()
              : existingCodigo,
          'total': total,
          'moneda': _moneda,
          'estado': 'Borrador',
          'notas': (existing?['notas'] as String?) ?? 'Cotización editada.',
          'itbis_activo': _itbisActivo ? 1 : 0,
          'itbis_tasa': _itbisTasa,
          'descuento_global': _descuentoGlobal,
        },
        id: existingId,
      );

      await _db.db.delete(
        'presupuesto_items',
        where: 'presupuesto_id = ?',
        whereArgs: [existingId],
      );
    } else {
      presupuestoId = await _db.insert('presupuestos', {
        'cliente_id': _clienteId,
        'codigo': _newCodigo(),
        'total': total,
        'moneda': _moneda,
        'estado': 'Borrador',
        'notas': 'Cotización generada desde el catálogo.',
        'itbis_activo': _itbisActivo ? 1 : 0,
        'itbis_tasa': _itbisTasa,
        'descuento_global': _descuentoGlobal,
        'creado_en': now,
      });
    }

    for (final line in _lines) {
      await _db.insert('presupuesto_items', {
        'presupuesto_id': presupuestoId,
        'producto_id': line.productoId,
        'codigo': line.codigo.isEmpty ? null : line.codigo,
        'nombre': line.nombre,
        'precio': line.precio,
        'cantidad': line.cantidad,
        'descuento': line.descuento,
        'creado_en': now,
      });
    }

    final cliente = await _loadSelectedCliente();

    final existing = await _db.findById('presupuestos', presupuestoId);
    final codigoDb = (existing?['codigo'] as String?)?.trim();
    final displayCodigo =
        (codigoDb == null || codigoDb.isEmpty) ? 'P$presupuestoId' : codigoDb;

    final empresa = await _db.getEmpresaConfig();
    final empresaNombre = ((empresa?['nombre'] as String?) ?? '').trim();
    final empresaRnc = ((empresa?['rnc'] as String?) ?? '').trim();
    final empresaTel = ((empresa?['telefono'] as String?) ?? '').trim();
    final empresaEmail = ((empresa?['email'] as String?) ?? '').trim();
    final empresaDir = ((empresa?['direccion'] as String?) ?? '').trim();
    final empresaWeb = ((empresa?['web'] as String?) ?? '').trim();
    final logoPath = ((empresa?['logo_path'] as String?) ?? '').trim();

    Uint8List? logoBytes;
    if (logoPath.isNotEmpty) {
      final f = File(logoPath);
      if (await f.exists()) logoBytes = await f.readAsBytes();
    }

    final pdfBytes = await buildCotizacionPdf(
      clienteNombre: (cliente?['nombre'] as String?) ?? 'Consumidor final',
      clienteTelefono: (cliente?['telefono'] as String?) ?? '',
      moneda: _moneda,
      itbisActivo: _itbisActivo,
      itbisTasa: _itbisTasa,
      descuentoGlobal: _descuentoGlobal,
      empresaNombre: empresaNombre,
      empresaRnc: empresaRnc,
      empresaTelefono: empresaTel,
      empresaEmail: empresaEmail,
      empresaDireccion: empresaDir,
      empresaWeb: empresaWeb,
      logoBytes: logoBytes,
      lines: _lines,
      fecha: DateTime.now(),
      codigo: displayCodigo,
    );

    final title = 'Cotización $displayCodigo';
    _pdfCacheKey = key;
    _pdfCacheTitle = title;
    _pdfCacheBytes = pdfBytes;
    return (title: title, bytes: pdfBytes);
  }

  String _pdfKey() {
    final buf = StringBuffer();
    buf.write('c:${_clienteId ?? 0};');
    buf.write(
        'itbis:${_itbisActivo ? 1 : 0};tasa:${_itbisTasa.toStringAsFixed(6)};');
    buf.write('dg:${_descuentoGlobal.toStringAsFixed(2)};');
    for (final l in _lines) {
      buf
        ..write('|')
        ..write(l.productoId ?? 0)
        ..write('~')
        ..write(l.codigo)
        ..write('~')
        ..write(l.nombre)
        ..write('~')
        ..write(l.precio.toStringAsFixed(4))
        ..write('~')
        ..write(l.cantidad.toStringAsFixed(4))
        ..write('~')
        ..write(l.descuento.toStringAsFixed(4));
    }
    return buf.toString();
  }

  Future<void> _previewPdf(double total, double itbis, double base) async {
    final res = await _buildPdfBytes(total, itbis, base);
    if (!mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            CotizacionPdfPreviewPage(title: res.title, pdfBytes: res.bytes),
      ),
    );
  }

  Future<List<Map<String, Object?>>> _queryProductos() async {
    final whereParts = <String>[];
    final args = <Object?>[];

    final cat = _categoriaIdFilter;
    if (cat != null) {
      whereParts.add('categoria_id = ?');
      args.add(cat);
    }

    if (_search.isNotEmpty) {
      whereParts.add('(nombre LIKE ? OR codigo LIKE ?)');
      args.addAll(['%$_search%', '%$_search%']);
    }

    return _db.db.query(
      'productos',
      where: whereParts.isEmpty ? null : whereParts.join(' AND '),
      whereArgs: args.isEmpty ? null : args,
      orderBy: 'nombre COLLATE NOCASE',
    );
  }

  Future<void> _openCategoriaFilter() async {
    final cats =
        await _db.db.query('categorias', orderBy: 'nombre COLLATE NOCASE');

    int? selected = _categoriaIdFilter;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Filtrar por categoría'),
        content: SizedBox(
          width: 420,
          child: StatefulBuilder(
            builder: (context, setLocal) {
              return ListView(
                shrinkWrap: true,
                children: [
                  RadioListTile<int?>(
                    value: null,
                    groupValue: selected,
                    title: const Text('Todas'),
                    onChanged: (v) => setLocal(() => selected = v),
                  ),
                  const Divider(height: 1),
                  ...cats.map(
                    (c) => RadioListTile<int?>(
                      value: c['id'] as int,
                      groupValue: selected,
                      title: Text((c['nombre'] ?? '') as String),
                      onChanged: (v) => setLocal(() => selected = v),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () {
              selected = null;
              Navigator.pop(context, true);
            },
            child: const Text('Limpiar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Aplicar'),
          ),
        ],
      ),
    );

    if (ok != true) return;
    setState(() => _categoriaIdFilter = selected);
  }

  void _addLineFromCatalog({
    required int productoId,
    required String codigo,
    required String nombre,
    required double precio,
  }) {
    final existing = _lines.where((e) => e.productoId == productoId).toList();
    if (existing.isNotEmpty) {
      setState(() => existing.first.cantidad += 1);
      return;
    }
    setState(() {
      _lines = [
        ..._lines,
        CotizacionLinea(
          productoId: productoId,
          codigo: codigo,
          nombre: nombre,
          precio: precio,
          cantidad: 1,
        ),
      ];
    });
  }

  Future<void> _addManualItem() async {
    final nombre = TextEditingController();
    final precio = TextEditingController();
    final cantidad = TextEditingController(text: '1');

    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Agregar producto manual'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
                controller: nombre,
                decoration: const InputDecoration(labelText: 'Nombre')),
            const SizedBox(height: 10),
            TextField(
              controller: precio,
              decoration: const InputDecoration(labelText: 'Precio'),
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: cantidad,
              decoration: const InputDecoration(labelText: 'Cantidad'),
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Agregar')),
        ],
      ),
    );

    if (ok != true) return;

    final n = nombre.text.trim();
    final p0 = double.tryParse(precio.text.trim()) ?? 0;
    final q0 = double.tryParse(cantidad.text.trim()) ?? 1;
    if (n.isEmpty || p0 <= 0 || q0 <= 0) return;

    setState(() {
      _lines = [
        ..._lines,
        CotizacionLinea(
          productoId: null,
          codigo: '',
          nombre: n,
          precio: p0,
          cantidad: q0,
        ),
      ];
    });
  }

  Future<void> _editLineDiscount(CotizacionLinea line) async {
    final controller =
        TextEditingController(text: line.descuento.toStringAsFixed(2));
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Descuento de línea'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(labelText: 'Monto de descuento'),
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Aplicar')),
        ],
      ),
    );
    if (ok != true) return;

    final d = double.tryParse(controller.text.trim()) ?? 0;
    setState(() => line.descuento = d.clamp(0.0, line.subtotal));
  }

  Future<void> _editLineCantidad(CotizacionLinea line) async {
    final controller = TextEditingController(
      text: line.cantidad.toStringAsFixed(line.cantidad % 1 == 0 ? 0 : 2),
    );

    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cantidad'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(labelText: 'Cantidad (ej: 100)'),
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Aplicar'),
          ),
        ],
      ),
    );

    if (ok != true) return;
    final raw = controller.text.trim().replaceAll(',', '.');
    final q = double.tryParse(raw);
    if (q == null || q <= 0) return;
    setState(() => line.cantidad = q);
  }

  Future<void> _editGlobalDiscount() async {
    final controller =
        TextEditingController(text: _descuentoGlobal.toStringAsFixed(2));
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Descuento total'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(labelText: 'Monto de descuento'),
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Aplicar')),
        ],
      ),
    );
    if (ok != true) return;

    final d = double.tryParse(controller.text.trim()) ?? 0;
    setState(() => _descuentoGlobal = d.clamp(0.0, double.infinity));
  }

  Future<void> _cotizar(double total, double itbis, double base) async {
    await _previewPdf(total, itbis, base);
  }

  Future<void> _shareToWhatsAppQuick(double total) async {
    // WhatsApp no permite adjuntar automáticamente por URL; usamos el share sheet con PDF.
    // También abrimos un mensaje prellenado opcional.
    final msg = Uri.encodeComponent(
        'Hola, te comparto una cotización de FULLTECH. Total: ${_money(total, _moneda)}');
    final uri = Uri.parse('https://wa.me/?text=$msg');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }

    // Si ya hay PDF en pantalla, el usuario puede compartir desde allí.
    // Aquí solo damos guía por UX.
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
          content: Text(
              'Usa “Cotizar (PDF)” y luego “Compartir” para enviarlo por WhatsApp.')),
    );
  }

  String _newCodigo() {
    final now = DateTime.now();
    return 'COT-${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}-${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}';
  }
}

class CotizacionPdfPreviewPage extends StatelessWidget {
  const CotizacionPdfPreviewPage(
      {super.key, required this.title, required this.pdfBytes});

  final String title;
  final Uint8List pdfBytes;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: [
          IconButton(
            tooltip: 'Compartir',
            onPressed: () =>
                Printing.sharePdf(bytes: pdfBytes, filename: '$title.pdf'),
            icon: const Icon(Icons.share_outlined),
          ),
          IconButton(
            tooltip: 'Descargar',
            onPressed: () async {
              final dir = await getApplicationDocumentsDirectory();
              final folder =
                  Directory(p.join(dir.path, 'fulltech', 'cotizaciones'));
              if (!await folder.exists()) {
                await folder.create(recursive: true);
              }
              final file = File(p.join(folder.path, '$title.pdf'));
              await file.writeAsBytes(pdfBytes, flush: true);
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Guardado en: ${file.path}')),
                );
              }
            },
            icon: const Icon(Icons.download_outlined),
          ),
        ],
      ),
      body: PdfPreview(
        build: (format) async => pdfBytes,
        canChangeOrientation: false,
        canChangePageFormat: false,
        allowSharing: false,
        allowPrinting: true,
      ),
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
                child: _Thumb(path: imagenPath),
              ),
              const SizedBox(height: 8),
              Text(
                nombre,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style:
                    const TextStyle(fontWeight: FontWeight.w900, fontSize: 12),
              ),
              const SizedBox(height: 4),
              Text(
                _money(precio, moneda),
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 12,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
              if (codigo.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(
                  codigo,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 10, color: Colors.black54),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _Thumb extends StatelessWidget {
  const _Thumb({required this.path});

  final String? path;

  @override
  Widget build(BuildContext context) {
    final borderRadius = BorderRadius.circular(10);

    if (path == null || path!.isEmpty) {
      return Container(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: borderRadius,
        ),
        child: const Center(child: Icon(Icons.inventory_2_outlined)),
      );
    }

    return ClipRRect(
      borderRadius: borderRadius,
      child: Image.file(
        File(path!),
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) {
          return Container(
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: borderRadius,
            ),
            child: const Center(child: Icon(Icons.broken_image_outlined)),
          );
        },
      ),
    );
  }
}

class _ClienteHeader extends StatelessWidget {
  const _ClienteHeader({
    required this.db,
    required this.clienteId,
    required this.onClienteChanged,
    required this.onAddCliente,
  });

  final AppDatabase db;
  final int? clienteId;
  final ValueChanged<int?> onClienteChanged;
  final VoidCallback onAddCliente;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Detalle',
                style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15)),
            const SizedBox(height: 10),
            FutureBuilder<List<Map<String, Object?>>>(
              future: db.queryAll('clientes', orderBy: 'nombre COLLATE NOCASE'),
              builder: (context, snapshot) {
                final clientes =
                    snapshot.data ?? const <Map<String, Object?>>[];
                final safeClienteId = (clienteId != null &&
                        clientes.any((c) => (c['id'] as int?) == clienteId))
                    ? clienteId
                    : null;
                return Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<int>(
                        value: safeClienteId,
                        decoration: const InputDecoration(
                          labelText: 'Cliente',
                          prefixIcon: Icon(Icons.people_alt_outlined),
                        ),
                        items: [
                          const DropdownMenuItem<int>(
                            value: null,
                            child: Text('Consumidor final'),
                          ),
                          ...clientes.map(
                            (c) => DropdownMenuItem<int>(
                              value: c['id'] as int,
                              child: Text((c['nombre'] ?? '') as String),
                            ),
                          ),
                        ],
                        onChanged: onClienteChanged,
                      ),
                    ),
                    const SizedBox(width: 10),
                    IconButton.filledTonal(
                      tooltip: 'Agregar cliente',
                      onPressed: onAddCliente,
                      icon: const Icon(Icons.person_add_alt_1_outlined),
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Icon(
                  Icons.attach_money_outlined,
                  size: 18,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 8),
                Text(
                  'Moneda: RD\$',
                  style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _QuoteLineTile extends StatelessWidget {
  const _QuoteLineTile({
    required this.moneda,
    required this.line,
    required this.onAdd,
    required this.onRemove,
    required this.onEditCantidad,
    required this.onDelete,
    required this.onDoubleTapDiscount,
  });

  final String moneda;
  final CotizacionLinea line;
  final VoidCallback onAdd;
  final VoidCallback onRemove;
  final VoidCallback onEditCantidad;
  final VoidCallback onDelete;
  final VoidCallback onDoubleTapDiscount;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onDoubleTap: onDoubleTapDiscount,
      child: Row(
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
                const SizedBox(height: 4),
                Text(
                  '${line.cantidad.toStringAsFixed(line.cantidad % 1 == 0 ? 0 : 2)} x ${_money(line.precio, moneda)}',
                  style: const TextStyle(color: Colors.black54, fontSize: 12),
                ),
                if (line.descuento > 0) ...[
                  const SizedBox(height: 4),
                  Text(
                    'Descuento: -${_money(line.descuento, moneda)}',
                    style: TextStyle(
                        color: Theme.of(context).colorScheme.primary,
                        fontSize: 12),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
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
                    tooltip: 'Cambiar cantidad',
                    onPressed: onEditCantidad,
                    icon: const Icon(Icons.calculate_outlined),
                    visualDensity: VisualDensity.compact,
                  ),
                  const SizedBox(width: 6),
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
      ),
    );
  }
}

class _TotalRow extends StatelessWidget {
  const _TotalRow(
      {required this.label, required this.value, this.bold = false});

  final String label;
  final String value;
  final bool bold;

  @override
  Widget build(BuildContext context) {
    final style = bold
        ? const TextStyle(fontWeight: FontWeight.w900, fontSize: 14)
        : const TextStyle(fontWeight: FontWeight.w600, fontSize: 13);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(child: Text(label, style: style)),
          Text(value, style: style),
        ],
      ),
    );
  }
}

class _EmptyBox extends StatelessWidget {
  const _EmptyBox({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.inbox_outlined, size: 34),
            const SizedBox(height: 10),
            Text(title,
                style:
                    const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
            const SizedBox(height: 6),
            Text(subtitle,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.black54)),
          ],
        ),
      ),
    );
  }
}

String _money(double value, String moneda) => _formatMoney(value);

String _formatMoney(double value) {
  final negative = value < 0;
  final v = value.abs();
  final s = v.toStringAsFixed(2);
  final parts = s.split('.');
  final intPart = parts[0];
  final decPart = parts.length > 1 ? parts[1] : '00';

  final b = StringBuffer();
  for (var i = 0; i < intPart.length; i++) {
    final remaining = intPart.length - i;
    b.write(intPart[i]);
    if (remaining > 1 && remaining % 3 == 1) b.write(',');
  }

  final out = '${b.toString()}.$decPart';
  return negative ? '-$out' : out;
}
