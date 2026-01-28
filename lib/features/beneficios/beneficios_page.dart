import 'package:flutter/material.dart';

import '../../data/app_database.dart';
import '../../data/auth_service.dart';
import '../../ui/fulltech_widgets.dart';
import '../../utils/quincena.dart';

class BeneficiosPage extends StatelessWidget {
  const BeneficiosPage({super.key});

  @override
  Widget build(BuildContext context) {
    return CenteredList(
      child: StreamBuilder<void>(
        stream: AppDatabase.instance.changes,
        builder: (context, _) {
          return FutureBuilder<Map<String, Object?>?>(
            future: AuthService.instance.currentUser(),
            builder: (context, snap) {
              if (snap.connectionState != ConnectionState.done) {
                return const Center(child: CircularProgressIndicator());
              }
              final user = snap.data;
              if (user == null) {
                return const _EmptyState(
                  title: 'Sin sesión',
                  subtitle: 'Inicia sesión para ver tus beneficios.',
                );
              }

              return _BeneficiosBody(user: user);
            },
          );
        },
      ),
    );
  }
}

class _BeneficiosBody extends StatefulWidget {
  const _BeneficiosBody({required this.user});

  final Map<String, Object?> user;

  @override
  State<_BeneficiosBody> createState() => _BeneficiosBodyState();
}

class _BeneficiosBodyState extends State<_BeneficiosBody> {
  Future<_BeneficiosData> _load() async {
    final id = (widget.user['id'] as int?) ?? 0;
    final sueldo = (widget.user['sueldo_quincenal'] as num?)?.toDouble() ?? 0.0;
    final meta = (widget.user['meta_quincenal'] as num?)?.toDouble() ?? 0.0;

    final q = quincenaFor(DateTime.now());
    final startMs = q.start.millisecondsSinceEpoch;
    final endMs = q.endExclusive.millisecondsSinceEpoch;

    final sums = await AppDatabase.instance.db.rawQuery(
      '''
SELECT
  COALESCE(SUM(v.ganancia), 0) AS ganancia_sum,
  COALESCE(SUM(v.puntos), 0) AS puntos_sum
FROM ventas v
WHERE v.usuario_id = ?
  AND v.creado_en >= ?
  AND v.creado_en < ?
''',
      [id, startMs, endMs],
    );

    final s0 = sums.isNotEmpty ? sums.first : const <String, Object?>{};
    final gananciaSum = (s0['ganancia_sum'] as num?)?.toDouble() ?? 0.0;
    final puntosSum = (s0['puntos_sum'] as num?)?.toDouble() ?? 0.0;

    final eligible = meta > 0 && puntosSum >= meta;
    final comision =
        eligible ? (puntosSum * 0.10).clamp(0.0, double.infinity) : 0.0;

    final ajustesRows = await AppDatabase.instance.db.rawQuery(
      '''
SELECT
  COALESCE(SUM(monto), 0) AS ajustes_sum
FROM nomina_ajustes
WHERE usuario_id = ?
  AND periodo_inicio = ?
  AND periodo_fin = ?
''',
      [id, startMs, endMs],
    );
    final a0 =
        ajustesRows.isNotEmpty ? ajustesRows.first : const <String, Object?>{};
    final ajustesSum = (a0['ajustes_sum'] as num?)?.toDouble() ?? 0.0;

    final ajustesList = await AppDatabase.instance.db.query(
      'nomina_ajustes',
      where: 'usuario_id = ? AND periodo_inicio = ? AND periodo_fin = ?',
      whereArgs: [id, startMs, endMs],
      orderBy: 'creado_en DESC, id DESC',
    );

    final pagos = await AppDatabase.instance.db.query(
      'beneficios_pagos',
      where: 'usuario_id = ?',
      whereArgs: [id],
      orderBy: 'creado_en DESC, id DESC',
    );

    return _BeneficiosData(
      quincena: q,
      sueldoBase: sueldo,
      meta: meta,
      puntos: puntosSum,
      ganancia: gananciaSum,
      comision: comision,
      eligible: eligible,
      ajustesSum: ajustesSum,
      ajustesList: ajustesList,
      pagos: pagos,
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_BeneficiosData>(
      future: _load(),
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        final data = snapshot.data;
        if (data == null) {
          return const _EmptyState(
            title: 'Sin datos',
            subtitle: 'No se pudo cargar tus beneficios.',
          );
        }

        final nombre = (widget.user['nombre'] as String?)?.trim() ?? 'Usuario';

        return ListView(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
          children: [
            Card(
              margin: EdgeInsets.zero,
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Beneficios',
                      style: const TextStyle(
                          fontWeight: FontWeight.w900, fontSize: 16),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      nombre,
                      style: const TextStyle(color: Colors.black54),
                    ),
                    const SizedBox(height: 10),
                    _InfoLine(
                        label: 'Período',
                        value:
                            '${data.quincena.label} • ${fmtDate(data.quincena.start)} → ${fmtDate(data.quincena.endExclusive.subtract(const Duration(days: 1)))}'),
                    _InfoLine(
                        label: 'Pago', value: fmtDate(data.quincena.payDate)),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Card(
              margin: EdgeInsets.zero,
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text('Resumen (quincena)',
                        style: TextStyle(fontWeight: FontWeight.w900)),
                    const SizedBox(height: 10),
                    _InfoLine(
                        label: 'Sueldo base', value: _money(data.sueldoBase)),
                    _InfoLine(
                      label: 'Comisión',
                      value: data.meta <= 0
                          ? '—'
                          : data.eligible
                              ? _money(data.comision)
                              : 'Pendiente de meta',
                    ),
                    _InfoLine(label: 'Ajustes', value: _money(data.ajustesSum)),
                    const Divider(height: 20),
                    _InfoLine(
                      label: 'Total estimado',
                      value: _money(
                          data.sueldoBase + data.comision + data.ajustesSum),
                      bold: true,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Card(
              margin: EdgeInsets.zero,
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text('Progreso de comisión',
                        style: TextStyle(fontWeight: FontWeight.w900)),
                    const SizedBox(height: 10),
                    if (data.meta <= 0) ...[
                      const Text('No tienes meta configurada.',
                          style: TextStyle(color: Colors.black54)),
                    ] else ...[
                      _InfoLine(
                          label: 'Puntos',
                          value: data.puntos.toStringAsFixed(2)),
                      _InfoLine(
                          label: 'Meta', value: data.meta.toStringAsFixed(2)),
                      const SizedBox(height: 6),
                      LinearProgressIndicator(
                        value: (data.puntos / data.meta).clamp(0.0, 1.0),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        data.eligible
                            ? 'Meta alcanzada: comisión aplicada.'
                            : 'Faltan ${(data.meta - data.puntos).clamp(0.0, double.infinity).toStringAsFixed(2)} puntos para activar la comisión.',
                        style: const TextStyle(color: Colors.black54),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Card(
              margin: EdgeInsets.zero,
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text('Ajustes de nómina (quincena)',
                        style: TextStyle(fontWeight: FontWeight.w900)),
                    const SizedBox(height: 10),
                    if (data.ajustesList.isEmpty)
                      const Text('Sin ajustes registrados.',
                          style: TextStyle(color: Colors.black54))
                    else
                      ...data.ajustesList.take(10).map((r) {
                        final tipo = (r['tipo'] as String?) ?? '';
                        final monto = (r['monto'] as num?)?.toDouble() ?? 0.0;
                        final nota = (r['nota'] as String?)?.trim() ?? '';
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Row(
                            children: [
                              Expanded(
                                  child: Text(
                                      nota.isEmpty ? tipo : '$tipo • $nota')),
                              Text(_money(monto),
                                  style: TextStyle(
                                      fontWeight: FontWeight.w800,
                                      color: monto < 0 ? Colors.red : null)),
                            ],
                          ),
                        );
                      }),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Card(
              margin: EdgeInsets.zero,
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text('Pagos',
                        style: TextStyle(fontWeight: FontWeight.w900)),
                    const SizedBox(height: 10),
                    if (data.pagos.isEmpty)
                      const Text('Aún no hay pagos registrados.',
                          style: TextStyle(color: Colors.black54))
                    else
                      ...data.pagos.take(12).map((p) {
                        final inicio = DateTime.fromMillisecondsSinceEpoch(
                            (p['periodo_inicio'] as int?) ?? 0);
                        final finEx = DateTime.fromMillisecondsSinceEpoch(
                            (p['periodo_fin'] as int?) ?? 0);
                        final pay = DateTime.fromMillisecondsSinceEpoch(
                            (p['pago_en'] as int?) ?? 0);
                        final neto = (p['neto'] as num?)?.toDouble() ?? 0.0;
                        final estado = (p['estado'] as String?) ?? 'Pagado';
                        return ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(Icons.payments_outlined),
                          title: Text(
                              '${fmtDate(inicio)} → ${fmtDate(finEx.subtract(const Duration(days: 1)))}'),
                          subtitle: Text('Pago: ${fmtDate(pay)} • $estado'),
                          trailing: Text(_money(neto),
                              style:
                                  const TextStyle(fontWeight: FontWeight.w900)),
                        );
                      }),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _BeneficiosData {
  const _BeneficiosData({
    required this.quincena,
    required this.sueldoBase,
    required this.meta,
    required this.puntos,
    required this.ganancia,
    required this.comision,
    required this.eligible,
    required this.ajustesSum,
    required this.ajustesList,
    required this.pagos,
  });

  final QuincenaInfo quincena;
  final double sueldoBase;
  final double meta;
  final double puntos;
  final double ganancia;
  final double comision;
  final bool eligible;
  final double ajustesSum;
  final List<Map<String, Object?>> ajustesList;
  final List<Map<String, Object?>> pagos;
}

class _InfoLine extends StatelessWidget {
  const _InfoLine(
      {required this.label, required this.value, this.bold = false});

  final String label;
  final String value;
  final bool bold;

  @override
  Widget build(BuildContext context) {
    final style = bold
        ? const TextStyle(fontWeight: FontWeight.w900)
        : const TextStyle(fontWeight: FontWeight.w700, color: Colors.black87);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(
              child:
                  Text(label, style: const TextStyle(color: Colors.black54))),
          Text(value, style: style),
        ],
      ),
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

String _money(double value) {
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
