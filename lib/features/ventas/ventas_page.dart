import 'package:flutter/material.dart';

import '../../data/app_database.dart';
import '../../data/auth_service.dart';
import '../../ui/fulltech_widgets.dart';
import 'venta_builder_page.dart';

class VentasPage extends StatelessWidget {
  const VentasPage({super.key});

  static Future<void> openAddForm(BuildContext context) {
    return Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const VentaBuilderPage()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return CenteredList(
      child: StreamBuilder<void>(
        stream: AppDatabase.instance.changes,
        builder: (context, _) {
          return FutureBuilder(
            future: _loadDashboard(),
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const Center(child: CircularProgressIndicator());
              }

              final data = snapshot.data;
              if (data == null) {
                return const _EmptyState(
                  title: 'Sin datos',
                  subtitle: 'No se pudo cargar el dashboard de ventas.',
                );
              }

              final rows = data.rows;

              return ListView.separated(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
                itemCount: (rows.isEmpty ? 2 : rows.length + 1),
                separatorBuilder: (_, __) => const SizedBox(height: 12),
                itemBuilder: (context, i) {
                  if (i == 0) {
                    return _VentasDashboardCard(data: data);
                  }

                  if (rows.isEmpty) {
                    return const _EmptyState(
                      title: 'Sin ventas en este período',
                      subtitle:
                          'Usa Agregar para registrar una venta y avanzar hacia tu meta.',
                    );
                  }

                  final r = rows[i - 1];
                  final codigo = (r['codigo'] as String?) ?? '—';
                  final total = (r['total'] as num?)?.toDouble() ?? 0;
                  final puntos = (r['puntos'] as num?)?.toDouble() ?? 0;
                  final comision = (puntos * 0.10).clamp(0.0, double.infinity);
                  final moneda = (r['moneda'] as String?) ?? 'USD';
                  final clienteNombre =
                      (r['cliente_nombre'] as String?)?.trim();
                  return FullTechCard(
                    icon: Icons.point_of_sale_outlined,
                    title: 'Venta $codigo',
                    subtitle: [
                      if (clienteNombre != null && clienteNombre.isNotEmpty)
                        'Cliente: $clienteNombre'
                      else
                        'Cliente: —',
                      'Puntos: ${puntos.toStringAsFixed(2)} • Comisión: ${comision.toStringAsFixed(2)}',
                    ].join('\n'),
                    trailing: '$moneda ${total.toStringAsFixed(2)}',
                    badge: 'Venta',
                    onTap: () => _openActions(context, r),
                  );
                },
              );
            },
          );
        },
      ),
    );
  }

  Future<_VentasDashboardData> _loadDashboard() async {
    final userId = AuthService.instance.currentUserId;
    if (userId == null) return _VentasDashboardData.empty();

    final now = DateTime.now();
    final range = _currentQuincenaRange(now);
    final startMs = range.start.millisecondsSinceEpoch;
    final endMs = range.end.millisecondsSinceEpoch;

    final user = await AuthService.instance.currentUser();
    final metaRaw = (user?['meta_quincenal'] as num?)?.toDouble() ?? 0.0;
    final meta = metaRaw;

    // Siempre muestra el dashboard del usuario actual.
    // (Aunque sea Admin, aquí la intención es ver su propio progreso.)
    const whereUser = 'WHERE v.usuario_id = ?';
    final argsUser = <Object?>[userId];

    final rows = await AppDatabase.instance.db.rawQuery(
      '''
SELECT v.*, c.nombre AS cliente_nombre
FROM ventas v
LEFT JOIN clientes c ON c.id = v.cliente_id
$whereUser
  ${whereUser.isEmpty ? 'WHERE' : 'AND'} v.creado_en >= ?
  AND v.creado_en < ?
ORDER BY v.creado_en DESC, v.id DESC
''',
      [...argsUser, startMs, endMs],
    );

    final sums = await AppDatabase.instance.db.rawQuery(
      '''
SELECT
  COUNT(*) AS ventas_count,
  COALESCE(SUM(v.total), 0) AS total_sum,
  COALESCE(SUM(v.puntos), 0) AS puntos_sum
FROM ventas v
$whereUser
  ${whereUser.isEmpty ? 'WHERE' : 'AND'} v.creado_en >= ?
  AND v.creado_en < ?
''',
      [...argsUser, startMs, endMs],
    );

    final s0 = sums.isNotEmpty ? sums.first : const <String, Object?>{};
    final ventasCount = (s0['ventas_count'] as int?) ?? 0;
    final totalSum = (s0['total_sum'] as num?)?.toDouble() ?? 0.0;
    final puntosSum = (s0['puntos_sum'] as num?)?.toDouble() ?? 0.0;

    final topClientes = await AppDatabase.instance.db.rawQuery(
      '''
SELECT
  v.cliente_id AS cliente_id,
  COALESCE(c.nombre, '—') AS cliente_nombre,
  COUNT(*) AS ventas_count,
  COALESCE(SUM(v.total), 0) AS total_sum,
  COALESCE(SUM(v.puntos), 0) AS puntos_sum
FROM ventas v
LEFT JOIN clientes c ON c.id = v.cliente_id
$whereUser
  ${whereUser.isEmpty ? 'WHERE' : 'AND'} v.creado_en >= ?
  AND v.creado_en < ?
GROUP BY v.cliente_id
ORDER BY puntos_sum DESC
LIMIT 5
''',
      [...argsUser, startMs, endMs],
    );

    return _VentasDashboardData(
      start: range.start,
      end: range.end,
      meta: meta,
      ventasCount: ventasCount,
      totalSum: totalSum,
      puntosSum: puntosSum,
      topClientes: topClientes,
      rows: rows,
    );
  }

  Future<void> _openActions(BuildContext context, Map<String, Object?> row) {
    return showFullTechFormSheet<void>(
      context: context,
      child: _VentaActionsSheet(row: row),
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

class _VentaActionsSheet extends StatelessWidget {
  const _VentaActionsSheet({required this.row});

  final Map<String, Object?> row;

  @override
  Widget build(BuildContext context) {
    final codigo = (row['codigo'] as String?) ?? '—';
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FullTechSheetHeader(
            title: 'Venta $codigo', subtitle: 'Acciones rápidas'),
        const SizedBox(height: 12),
        FilledButton.tonalIcon(
          onPressed: () async {
            final id = (row['id'] as int?) ?? 0;
            await AppDatabase.instance.delete('ventas', id: id);
            if (context.mounted) Navigator.of(context).pop();
          },
          icon: const Icon(Icons.delete_outline),
          label: const Text('Eliminar'),
        ),
      ],
    );
  }
}

class _DateRange {
  const _DateRange({required this.start, required this.end});

  final DateTime start;
  final DateTime end;
}

int _lastDayOfMonth(int year, int month) {
  return DateTime(year, month + 1, 0).day;
}

DateTime _boundaryAt2350(DateTime base, int day) {
  final lastDay = _lastDayOfMonth(base.year, base.month);
  final safeDay = day.clamp(1, lastDay);
  return DateTime(base.year, base.month, safeDay, 23, 50);
}

_DateRange _currentQuincenaRange(DateTime now) {
  final b14 = _boundaryAt2350(now, 14);
  final b29 = _boundaryAt2350(now, 29);

  if (now.isBefore(b14)) {
    final prevMonth = DateTime(now.year, now.month - 1, 15);
    return _DateRange(start: _boundaryAt2350(prevMonth, 29), end: b14);
  }

  if (now.isBefore(b29)) {
    return _DateRange(start: b14, end: b29);
  }

  final nextMonth = DateTime(now.year, now.month + 1, 15);
  return _DateRange(start: b29, end: _boundaryAt2350(nextMonth, 14));
}

String _fmtShortDateTime(DateTime dt) {
  String two(int v) => v.toString().padLeft(2, '0');
  return '${two(dt.day)}/${two(dt.month)} ${two(dt.hour)}:${two(dt.minute)}';
}

class _VentasDashboardData {
  const _VentasDashboardData({
    required this.start,
    required this.end,
    required this.meta,
    required this.ventasCount,
    required this.totalSum,
    required this.puntosSum,
    required this.topClientes,
    required this.rows,
  });

  final DateTime start;
  final DateTime end;
  final double meta;
  final int ventasCount;
  final double totalSum;
  final double puntosSum;
  final List<Map<String, Object?>> topClientes;
  final List<Map<String, Object?>> rows;

  static _VentasDashboardData empty() {
    final now = DateTime.now();
    final range = _currentQuincenaRange(now);
    return _VentasDashboardData(
      start: range.start,
      end: range.end,
      meta: 0,
      ventasCount: 0,
      totalSum: 0,
      puntosSum: 0,
      topClientes: const [],
      rows: const [],
    );
  }
}

class _VentasDashboardCard extends StatelessWidget {
  const _VentasDashboardCard({required this.data});

  final _VentasDashboardData data;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final goal = data.meta <= 0 ? 0.0 : data.meta;
    final progress = goal <= 0 ? 0.0 : (data.puntosSum / goal).clamp(0.0, 1.0);
    final comision = (data.puntosSum * 0.10).clamp(0.0, double.infinity);
    final eligible = goal > 0 && data.puntosSum >= goal;

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Dashboard (período actual)',
                        style: TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 15,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${_fmtShortDateTime(data.start)} → ${_fmtShortDateTime(data.end)}',
                        style: const TextStyle(color: Colors.black54),
                      ),
                    ],
                  ),
                ),
                _FunnelProgress(
                  progress: progress,
                  color: colorScheme.primary,
                  background: colorScheme.surfaceContainerHighest,
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                _MetricChip(
                  label: 'Ventas',
                  value: data.ventasCount.toString(),
                  icon: Icons.receipt_long_outlined,
                ),
                _MetricChip(
                  label: 'Total vendido',
                  value: data.totalSum.toStringAsFixed(2),
                  icon: Icons.attach_money_outlined,
                ),
                _MetricChip(
                  label: 'Puntos',
                  value: data.puntosSum.toStringAsFixed(2),
                  icon: Icons.trending_up_outlined,
                  highlight: true,
                ),
                _MetricChip(
                  label: 'Comisión (10%)',
                  value: comision.toStringAsFixed(2),
                  icon: Icons.percent,
                ),
                _MetricChip(
                  label: 'Meta quincenal',
                  value: goal.toStringAsFixed(2),
                  icon: Icons.flag_outlined,
                ),
              ],
            ),
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 10,
                backgroundColor: colorScheme.surfaceContainerHighest,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              goal <= 0
                  ? 'Meta quincenal no configurada.'
                  : 'Progreso: ${(progress * 100).toStringAsFixed(0)}% • ${data.puntosSum.toStringAsFixed(2)} / ${goal.toStringAsFixed(2)} puntos',
              style: const TextStyle(color: Colors.black54),
            ),
            if (goal > 0) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: eligible
                      ? colorScheme.primaryContainer
                      : colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  eligible
                      ? 'Felicidades, acabas de ganar una comisión de ${comision.toStringAsFixed(2)} por llegar a tu meta mínima de ventas. Ya está reflejado en tu mural de pago.'
                      : 'Faltan ${(goal - data.puntosSum).clamp(0.0, double.infinity).toStringAsFixed(2)} puntos para alcanzar tu meta.',
                  style: TextStyle(
                    color: eligible
                        ? colorScheme.onPrimaryContainer
                        : Colors.black87,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
            if (data.topClientes.isNotEmpty) ...[
              const SizedBox(height: 12),
              const Text(
                'Top clientes (por puntos)',
                style: TextStyle(fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 8),
              ...data.topClientes.take(3).map((r) {
                final name = (r['cliente_nombre'] as String?) ?? '—';
                final pts = (r['puntos_sum'] as num?)?.toDouble() ?? 0.0;
                final ventas = (r['ventas_count'] as int?) ?? 0;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                      ),
                      Text(
                        '$ventas venta(s) • ${pts.toStringAsFixed(2)} pts',
                        style: const TextStyle(color: Colors.black54),
                      ),
                    ],
                  ),
                );
              }),
            ],
          ],
        ),
      ),
    );
  }
}

class _MetricChip extends StatelessWidget {
  const _MetricChip({
    required this.label,
    required this.value,
    required this.icon,
    this.highlight = false,
  });

  final String label;
  final String value;
  final IconData icon;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final bg = highlight
        ? colorScheme.primary.withAlpha(18)
        : colorScheme.surfaceContainerHighest;
    final fg = highlight ? colorScheme.primary : Colors.black87;

    return Container(
      constraints: const BoxConstraints(minWidth: 160),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.black.withAlpha(14)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: fg),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 11,
                    color: Colors.black54,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontWeight: FontWeight.w900, color: fg),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FunnelProgress extends StatelessWidget {
  const _FunnelProgress({
    required this.progress,
    required this.color,
    required this.background,
  });

  final double progress;
  final Color color;
  final Color background;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 64,
      height: 84,
      child: CustomPaint(
        painter: _FunnelPainter(
          progress: progress,
          color: color,
          background: background,
        ),
      ),
    );
  }
}

class _FunnelPainter extends CustomPainter {
  const _FunnelPainter({
    required this.progress,
    required this.color,
    required this.background,
  });

  final double progress;
  final Color color;
  final Color background;

  @override
  void paint(Canvas canvas, Size size) {
    final outer = Path()
      ..moveTo(size.width * 0.08, 0)
      ..lineTo(size.width * 0.92, 0)
      ..lineTo(size.width * 0.62, size.height)
      ..lineTo(size.width * 0.38, size.height)
      ..close();

    final outlinePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..color = Colors.black.withAlpha(22);

    final bgPaint = Paint()
      ..style = PaintingStyle.fill
      ..color = background;

    final fillPaint = Paint()
      ..style = PaintingStyle.fill
      ..color = color.withAlpha(200);

    canvas.drawPath(outer, bgPaint);

    final p = progress.clamp(0.0, 1.0);
    if (p > 0) {
      canvas.save();
      final clipRect = Rect.fromLTWH(
        0,
        size.height * (1 - p),
        size.width,
        size.height * p,
      );
      canvas.clipRect(clipRect);
      canvas.drawPath(outer, fillPaint);
      canvas.restore();
    }

    canvas.drawPath(outer, outlinePaint);
  }

  @override
  bool shouldRepaint(covariant _FunnelPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.color != color ||
        oldDelegate.background != background;
  }
}
