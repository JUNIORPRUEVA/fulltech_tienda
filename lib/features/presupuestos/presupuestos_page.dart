import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:printing/printing.dart';

import '../../data/app_database.dart';
import '../../ui/fulltech_widgets.dart';
import 'cotizacion_builder_page.dart';
import 'cotizacion_models.dart';
import 'cotizacion_pdf.dart';

class PresupuestosPage extends StatelessWidget {
  const PresupuestosPage({super.key});

  static Future<void> openAddForm(BuildContext context) {
    return Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const CotizacionBuilderPage()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return CenteredList(
      child: StreamBuilder<void>(
        stream: AppDatabase.instance.changes,
        builder: (context, _) {
          return FutureBuilder<List<Map<String, Object?>>>(
            future: AppDatabase.instance.db.rawQuery(
              'SELECT p.*, c.nombre AS cliente_nombre '
              'FROM presupuestos p '
              'LEFT JOIN clientes c ON c.id = p.cliente_id '
              'ORDER BY p.creado_en DESC',
            ),
            builder: (context, snapshot) {
              final rows = snapshot.data ?? const <Map<String, Object?>>[];
              if (snapshot.connectionState != ConnectionState.done) {
                return const Center(child: CircularProgressIndicator());
              }
              if (rows.isEmpty) {
                return const _EmptyState(
                  title: 'Sin presupuestos',
                  subtitle: 'Crea un presupuesto para tus clientes.',
                );
              }

              return ListView.separated(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
                itemCount: rows.length,
                separatorBuilder: (_, __) => const SizedBox(height: 12),
                itemBuilder: (context, i) {
                  final r = rows[i];
                  final codigo = (r['codigo'] as String?) ?? '—';
                  final estado = (r['estado'] as String?) ?? 'Borrador';
                  final total = (r['total'] as num?)?.toDouble() ?? 0;
                  final clienteNombre =
                      ((r['cliente_nombre'] as String?) ?? '').trim().isEmpty
                          ? 'Consumidor final'
                          : (r['cliente_nombre'] as String);
                  final notas = (r['notas'] as String?)?.trim() ?? '';

                  final subtitle = notas.isEmpty
                      ? 'Cliente: $clienteNombre · Estado: $estado'
                      : 'Cliente: $clienteNombre · $notas';

                  final colorScheme = Theme.of(context).colorScheme;
                  final id = (r['id'] as int?) ?? 0;

                  return Card(
                    margin: EdgeInsets.zero,
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 6),
                      leading: Container(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          color: colorScheme.primary.withAlpha(31),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(Icons.request_quote_outlined,
                            color: colorScheme.primary),
                      ),
                      title: Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Presupuesto $codigo',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  fontWeight: FontWeight.w800, fontSize: 16),
                            ),
                          ),
                          const SizedBox(width: 8),
                          _BadgeChip(text: estado),
                        ],
                      ),
                      subtitle: Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 13, color: Colors.black54),
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            _formatMoney(total),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontWeight: FontWeight.w800, fontSize: 14),
                          ),
                          const SizedBox(width: 6),
                          IconButton(
                            tooltip: 'Editar',
                            onPressed: id <= 0
                                ? null
                                : () async {
                                    await Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) => CotizacionBuilderPage(
                                            presupuestoId: id),
                                      ),
                                    );
                                  },
                            icon: const Icon(Icons.edit_outlined),
                          ),
                        ],
                      ),
                      onTap: () => _openActions(context, r),
                    ),
                  );
                },
              );
            },
          );
        },
      ),
    );
  }

  Future<void> _openActions(BuildContext context, Map<String, Object?> row) {
    return showFullTechFormSheet<void>(
      context: context,
      child: _PresupuestoActionsSheet(row: row),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.title, required this.subtitle});

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

class _BadgeChip extends StatelessWidget {
  const _BadgeChip({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: colorScheme.primary.withAlpha(20),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: colorScheme.primary,
          fontWeight: FontWeight.w800,
          fontSize: 12,
        ),
      ),
    );
  }
}

class _PresupuestoActionsSheet extends StatelessWidget {
  const _PresupuestoActionsSheet({required this.row});

  final Map<String, Object?> row;

  @override
  Widget build(BuildContext context) {
    final codigo = (row['codigo'] as String?) ?? '—';
    final id = (row['id'] as int?) ?? 0;
    final clienteNombre =
        ((row['cliente_nombre'] as String?) ?? '').trim().isEmpty
            ? 'Consumidor final'
            : (row['cliente_nombre'] as String);

    Future<({String title, Uint8List bytes})> buildPdf() async {
      final presupuesto =
          await AppDatabase.instance.findById('presupuestos', id);
      if (presupuesto == null) {
        throw StateError('Presupuesto no encontrado');
      }

      final clienteId = presupuesto['cliente_id'] as int?;
      Map<String, Object?>? cliente;
      if (clienteId != null) {
        cliente = await AppDatabase.instance.findById('clientes', clienteId);
      }

      final creadoEnMs = (presupuesto['creado_en'] as int?) ??
          DateTime.now().millisecondsSinceEpoch;
      final fecha = DateTime.fromMillisecondsSinceEpoch(creadoEnMs);

      final codigoDb = (presupuesto['codigo'] as String?)?.trim();
      final displayCodigo =
          (codigoDb == null || codigoDb.isEmpty) ? 'P$id' : codigoDb;

      final moneda = (presupuesto['moneda'] as String?) ?? 'RD\$';
      final itbisActivo = ((presupuesto['itbis_activo'] as int?) ?? 0) == 1;
      final itbisTasa = (presupuesto['itbis_tasa'] as num?)?.toDouble() ?? 0.18;
      final descuentoGlobal =
          (presupuesto['descuento_global'] as num?)?.toDouble() ?? 0.0;

      final itemRows = await AppDatabase.instance.db.query(
        'presupuesto_items',
        where: 'presupuesto_id = ?',
        whereArgs: [id],
        orderBy: 'id ASC',
      );

      final lines = <CotizacionLinea>[];
      for (final r in itemRows) {
        final line = CotizacionLinea(
          productoId: r['producto_id'] as int?,
          codigo: (r['codigo'] as String?) ?? '',
          nombre: (r['nombre'] as String?) ?? '',
          precio: (r['precio'] as num?)?.toDouble() ?? 0.0,
          cantidad: (r['cantidad'] as num?)?.toDouble() ?? 0.0,
        );
        line.descuento = (r['descuento'] as num?)?.toDouble() ?? 0.0;
        lines.add(line);
      }

      final empresa = await AppDatabase.instance.getEmpresaConfig();
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

      final bytes = await buildCotizacionPdf(
        codigo: displayCodigo,
        fecha: fecha,
        clienteNombre: (cliente?['nombre'] as String?) ?? 'Consumidor final',
        clienteTelefono: (cliente?['telefono'] as String?) ?? '',
        moneda: moneda,
        itbisActivo: itbisActivo,
        itbisTasa: itbisTasa,
        descuentoGlobal: descuentoGlobal,
        empresaNombre: empresaNombre,
        empresaRnc: empresaRnc,
        empresaTelefono: empresaTel,
        empresaEmail: empresaEmail,
        empresaDireccion: empresaDir,
        empresaWeb: empresaWeb,
        logoBytes: logoBytes,
        lines: lines,
      );

      return (title: 'Presupuesto $displayCodigo', bytes: bytes);
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FullTechSheetHeader(
          title: 'Presupuesto $codigo',
          subtitle: 'Cliente: $clienteNombre',
        ),
        const SizedBox(height: 12),
        FilledButton.tonalIcon(
          onPressed: () async {
            final navigator = Navigator.of(context);
            navigator.pop();
            await navigator.push(
              MaterialPageRoute(
                builder: (_) => CotizacionBuilderPage(presupuestoId: id),
              ),
            );
          },
          icon: const Icon(Icons.edit_outlined),
          label: const Text('Editar borrador'),
        ),
        const SizedBox(height: 10),
        FilledButton.tonalIcon(
          onPressed: () async {
            final res = await buildPdf();
            if (!context.mounted) return;
            Navigator.of(context).pop();
            await Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => CotizacionPdfPreviewPage(
                  title: res.title,
                  pdfBytes: res.bytes,
                ),
              ),
            );
          },
          icon: const Icon(Icons.picture_as_pdf_outlined),
          label: const Text('Ver PDF'),
        ),
        const SizedBox(height: 10),
        FilledButton.tonalIcon(
          onPressed: () async {
            final res = await buildPdf();
            await Printing.sharePdf(
                bytes: res.bytes, filename: '${res.title}.pdf');
            if (context.mounted) Navigator.of(context).pop();
          },
          icon: const Icon(Icons.share_outlined),
          label: const Text('Compartir PDF'),
        ),
        const SizedBox(height: 10),
        FilledButton.tonalIcon(
          onPressed: () async {
            final res = await buildPdf();
            final dir = await getApplicationDocumentsDirectory();
            final folder =
                Directory(p.join(dir.path, 'fulltech', 'cotizaciones'));
            if (!await folder.exists()) {
              await folder.create(recursive: true);
            }
            final file = File(p.join(folder.path, '${res.title}.pdf'));
            await file.writeAsBytes(res.bytes, flush: true);
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Guardado en: ${file.path}')),
              );
              Navigator.of(context).pop();
            }
          },
          icon: const Icon(Icons.download_outlined),
          label: const Text('Descargar PDF'),
        ),
        const SizedBox(height: 10),
        FilledButton.tonalIcon(
          onPressed: () async {
            final clientes = await AppDatabase.instance.db.query(
              'clientes',
              orderBy: 'nombre COLLATE NOCASE',
            );

            int? selectedClienteId = (row['cliente_id'] as int?);
            final codigoOriginal = (row['codigo'] as String?)?.trim();
            final controller = TextEditingController(
              text: (codigoOriginal == null || codigoOriginal.isEmpty)
                  ? '${DateTime.now().millisecondsSinceEpoch}'
                  : '$codigoOriginal (copia)',
            );

            final ok = await showDialog<bool>(
              context: context,
              builder: (context) => AlertDialog(
                title: const Text('Duplicar cotización'),
                content: SizedBox(
                  width: 460,
                  child: StatefulBuilder(
                    builder: (context, setLocal) {
                      final ids = clientes.map((c) => c['id'] as int).toSet();
                      final safeValue = (selectedClienteId != null &&
                              ids.contains(selectedClienteId))
                          ? selectedClienteId
                          : null;
                      return Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          DropdownButtonFormField<int>(
                            value: safeValue,
                            items: [
                              const DropdownMenuItem<int>(
                                value: null,
                                child: Text('Consumidor final'),
                              ),
                              ...clientes.map(
                                (c) => DropdownMenuItem<int>(
                                  value: c['id'] as int,
                                  child: Text(
                                      (c['nombre'] as String?) ?? 'Cliente'),
                                ),
                              ),
                            ],
                            onChanged: (v) =>
                                setLocal(() => selectedClienteId = v),
                            decoration: const InputDecoration(
                              labelText: 'Cliente',
                            ),
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: controller,
                            decoration: const InputDecoration(
                              labelText: 'Nombre / código',
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    child: const Text('Cancelar'),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.of(context).pop(true),
                    child: const Text('Duplicar'),
                  ),
                ],
              ),
            );

            if (ok != true) return;

            final now = DateTime.now().millisecondsSinceEpoch;
            final original =
                await AppDatabase.instance.findById('presupuestos', id);
            if (original == null) return;

            final newCodigo = controller.text.trim().isEmpty
                ? 'P$now'
                : controller.text.trim();

            final newPresupuestoId =
                await AppDatabase.instance.insert('presupuestos', {
              'cliente_id': selectedClienteId,
              'codigo': newCodigo,
              'total': (original['total'] as num?)?.toDouble() ?? 0.0,
              'moneda': (original['moneda'] as String?) ?? 'RD\$',
              'estado': 'Borrador',
              'notas': 'Duplicado de ${original['codigo'] ?? 'P$id'}',
              'itbis_activo': (original['itbis_activo'] as int?) ?? 0,
              'itbis_tasa':
                  (original['itbis_tasa'] as num?)?.toDouble() ?? 0.18,
              'descuento_global':
                  (original['descuento_global'] as num?)?.toDouble() ?? 0.0,
              'creado_en': now,
            });

            final itemRows = await AppDatabase.instance.db.query(
              'presupuesto_items',
              where: 'presupuesto_id = ?',
              whereArgs: [id],
              orderBy: 'id ASC',
            );

            for (final it in itemRows) {
              await AppDatabase.instance.insert('presupuesto_items', {
                'presupuesto_id': newPresupuestoId,
                'producto_id': it['producto_id'],
                'codigo': it['codigo'],
                'nombre': it['nombre'],
                'precio': it['precio'],
                'cantidad': it['cantidad'],
                'descuento': it['descuento'],
                'creado_en': now,
              });
            }

            if (!context.mounted) return;
            final navigator = Navigator.of(context);
            navigator.pop();
            ScaffoldMessenger.of(navigator.context).showSnackBar(
              const SnackBar(content: Text('Cotización duplicada.')),
            );
            await navigator.push(
              MaterialPageRoute(
                builder: (_) => CotizacionBuilderPage(
                  presupuestoId: newPresupuestoId,
                ),
              ),
            );
          },
          icon: const Icon(Icons.copy_outlined),
          label: const Text('Duplicar cotización'),
        ),
        const SizedBox(height: 10),
        FilledButton.tonalIcon(
          onPressed: () async {
            // Por ahora abrimos el builder en modo nuevo.
            if (!context.mounted) return;
            Navigator.of(context).pop();
            await Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const CotizacionBuilderPage()),
            );
          },
          icon: const Icon(Icons.add_chart_outlined),
          label: const Text('Nueva cotización'),
        ),
        const SizedBox(height: 10),
        FilledButton.tonalIcon(
          onPressed: () async {
            await AppDatabase.instance.delete('presupuestos', id: id);
            if (context.mounted) Navigator.of(context).pop();
          },
          icon: const Icon(Icons.delete_outline),
          label: const Text('Eliminar'),
        ),
      ],
    );
  }
}

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
