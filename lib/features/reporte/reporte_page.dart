import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'dart:convert';

import '../../data/app_database.dart';
import '../../data/auth_service.dart';
import '../../ui/fulltech_widgets.dart';
import '../../utils/daily_motivation.dart';
import '../../utils/report_intelligence.dart';
import '../../utils/weather_service.dart';

class ReportePage extends StatelessWidget {
  const ReportePage({super.key});

  @override
  Widget build(BuildContext context) {
    return CenteredList(
      child: StreamBuilder<void>(
        stream: AppDatabase.instance.changes,
        builder: (context, _) {
          return FutureBuilder<_ReporteData>(
            future: _ReporteData.load(),
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const Center(child: CircularProgressIndicator());
              }
              return _ReporteBody(data: snapshot.data ?? _ReporteData.empty());
            },
          );
        },
      ),
    );
  }
}

class _ReporteBody extends StatelessWidget {
  const _ReporteBody({required this.data});

  final _ReporteData data;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final todayLabel = _fmtDate(data.today);

    final hasMural = (data.infoEspecial ?? '').trim().isNotEmpty ||
        (data.infoGeneral ?? '').trim().isNotEmpty;
    final hasReconocimientos =
        (data.topVendedorNombre ?? '').trim().isNotEmpty ||
            (data.empleadoMesNombre ?? '').trim().isNotEmpty;
    final hasTopVendedores = data.topVendedores.isNotEmpty;
    final hasPendientes = data.pendientesHoy.isNotEmpty;
    final hasInstalacionesEnCurso = data.instalacionesEnCurso.isNotEmpty;

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
      children: [
        Container(
          height: 132,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Colors.black, Colors.white],
              stops: [0.0, 1.0],
            ),
            boxShadow: const [
              BoxShadow(
                color: Color(0x22000000),
                blurRadius: 18,
                offset: Offset(0, 10),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.start,
              children: [
                Text(
                  'Reporte del día',
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 18,
                    color: Colors.white,
                    letterSpacing: 0.2,
                    shadows: [
                      Shadow(
                        color: Color(0x66000000),
                        blurRadius: 10,
                        offset: Offset(0, 3),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  todayLabel,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    shadows: [
                      Shadow(
                        color: Color(0x66000000),
                        blurRadius: 10,
                        offset: Offset(0, 3),
                      ),
                    ],
                  ),
                ),
                const Spacer(),
                Text(
                  'Resumen ejecutivo • FULLTECH',
                  style: TextStyle(
                    color: Colors.black.withValues(alpha: 0.65),
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.2,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        if (hasMural) ...[
          _MuralCard(
            infoEspecial: data.infoEspecial,
            infoGeneral: data.infoGeneral,
          ),
          const SizedBox(height: 12),
        ],
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            _KpiChip(
              icon: Icons.event_available_outlined,
              label: 'Reservas hoy',
              value: data.reservasHoyCount.toString(),
              color: cs.primary,
            ),
            _KpiChip(
              icon: Icons.pending_actions_outlined,
              label: 'Pendientes hoy',
              value: data.pendientesHoyCount.toString(),
              color: cs.tertiary,
            ),
            _KpiChip(
              icon: Icons.home_repair_service_outlined,
              label: 'Instalaciones en curso',
              value: data.instalacionesEnCursoCount.toString(),
              color: cs.secondary,
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (hasReconocimientos) ...[
          Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'Reconocimientos',
                    style: TextStyle(fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 10),
                  if ((data.topVendedorNombre ?? '').trim().isNotEmpty)
                    _InfoLine(
                      icon: Icons.emoji_events_outlined,
                      label: 'Top vendedor (hoy)',
                      value: data.topVendedorNombre!.trim(),
                    ),
                  if ((data.empleadoMesNombre ?? '').trim().isNotEmpty)
                    _InfoLine(
                      icon: Icons.star_outline,
                      label: 'Empleado del mes',
                      value: data.empleadoMesNombre!.trim(),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
        ],
        if (hasTopVendedores) ...[
          Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'Top vendedores (hoy)',
                    style: TextStyle(fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    height: 220,
                    child: _TopVendedoresChart(rows: data.topVendedores),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Ranking por puntos (no se muestra monto).',
                    style: TextStyle(color: cs.onSurfaceVariant),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
        ],
        _AssistantCard(data: data),
        const SizedBox(height: 12),
        if (hasPendientes) ...[
          _OperacionesCard(
            title: 'Servicios pendientes para hoy',
            subtitle: 'Reservas programadas hoy que aún no están finalizadas.',
            emptyText: '',
            rows: data.pendientesHoy,
          ),
          const SizedBox(height: 12),
        ],
        if (hasInstalacionesEnCurso) ...[
          _OperacionesCard(
            title: 'Instalaciones en curso (hoy)',
            subtitle: 'Instalaciones en estado En proceso / Programada.',
            emptyText: '',
            rows: data.instalacionesEnCurso,
          ),
          const SizedBox(height: 12),
        ],
        const _DailyMotivationCard(),
      ],
    );
  }
}

class _MuralCard extends StatelessWidget {
  const _MuralCard({required this.infoEspecial, required this.infoGeneral});

  final String? infoEspecial;
  final String? infoGeneral;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final especial = (infoEspecial ?? '').trim();
    final general = (infoGeneral ?? '').trim();

    if (especial.isEmpty && general.isEmpty) {
      return const SizedBox.shrink();
    }

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Mural', style: TextStyle(fontWeight: FontWeight.w900)),
            const SizedBox(height: 10),
            if (especial.isNotEmpty) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: cs.primaryContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.campaign_outlined, color: cs.onPrimaryContainer),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        especial,
                        style: TextStyle(
                          color: cs.onPrimaryContainer,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            if (general.isNotEmpty) ...[
              if (especial.isNotEmpty) const SizedBox(height: 10),
              Text(general, style: const TextStyle(color: Colors.black87)),
            ],
          ],
        ),
      ),
    );
  }
}

class _OperacionesCard extends StatelessWidget {
  const _OperacionesCard({
    required this.title,
    required this.subtitle,
    required this.emptyText,
    required this.rows,
  });

  final String title;
  final String subtitle;
  final String emptyText;
  final List<_OpRow> rows;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.w900)),
            const SizedBox(height: 6),
            Text(subtitle, style: TextStyle(color: cs.onSurfaceVariant)),
            const SizedBox(height: 10),
            if (rows.isEmpty)
              Text(emptyText, style: TextStyle(color: cs.onSurfaceVariant))
            else
              ...rows.take(8).map((r) {
                final programado = r.programadoEn == null
                    ? '—'
                    : _fmtTime(
                        DateTime.fromMillisecondsSinceEpoch(r.programadoEn!));
                final line = [
                  r.cliente,
                  r.tipoServicio,
                  if (r.tecnico != null && r.tecnico!.trim().isNotEmpty)
                    'Técnico: ${r.tecnico}',
                ].join(' • ');

                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: FullTechCard(
                    icon: Icons.manage_accounts_outlined,
                    title: r.codigo,
                    subtitle: line,
                    trailing: programado,
                    badge: r.estado,
                    onTap: null,
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }
}

class _KpiChip extends StatelessWidget {
  const _KpiChip({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(label, style: TextStyle(color: cs.onSurfaceVariant)),
              const SizedBox(height: 2),
              Text(
                value,
                style: const TextStyle(fontWeight: FontWeight.w900),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _InfoLine extends StatelessWidget {
  const _InfoLine(
      {required this.icon, required this.label, required this.value});

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Icon(icon, size: 18, color: cs.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              style: TextStyle(color: cs.onSurfaceVariant),
            ),
          ),
          const SizedBox(width: 10),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }
}

class _DailyMotivationCard extends StatelessWidget {
  const _DailyMotivationCard();

  static const _brandBlue = Color(0xFF1E3AFF);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Card(
      margin: EdgeInsets.zero,
      color: Colors.white,
      surfaceTintColor: Colors.white,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: _brandBlue.withValues(alpha: 0.18)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: _brandBlue.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(
                Icons.bolt_rounded,
                color: _brandBlue,
                size: 22,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'Motivación del día',
                    style: TextStyle(fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 8),
                  FutureBuilder<String>(
                    future: DailyMotivation.getTodayPhrase(),
                    builder: (context, snapshot) {
                      if (snapshot.connectionState != ConnectionState.done) {
                        return Text(
                          'Cargando…',
                          style: TextStyle(color: cs.onSurfaceVariant),
                        );
                      }

                      final phrase = (snapshot.data ?? '').trim();
                      if (phrase.isEmpty) {
                        return Text(
                          'Enfoque, calidad y seguridad en cada instalación.',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        );
                      }

                      return Text(
                        phrase,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      );
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AssistantCard extends StatelessWidget {
  const _AssistantCard({required this.data});

  static const _brandBlue = Color(0xFF1E3AFF);

  final _ReporteData data;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final now = DateTime.now();

    final scheduleLabel = data.horarioLabel ?? 'Horario no definido';
    final punchLabel = _punchLabel(data);
    final reminder = _punchReminder(data, now);

    final hasLocation = data.ubicacionLat != null && data.ubicacionLon != null;
    final weatherFuture = WeatherService.getCurrent(
      lat: data.ubicacionLat,
      lon: data.ubicacionLon,
    );

    return Card(
      margin: EdgeInsets.zero,
      color: Colors.white,
      surfaceTintColor: Colors.white,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: _brandBlue.withValues(alpha: 0.14)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: _brandBlue.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.support_agent_rounded,
                    color: _brandBlue,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'Asistente FULLTECH',
                    style: TextStyle(fontWeight: FontWeight.w900),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              scheduleLabel,
              style: TextStyle(color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: 8),
            Text(
              punchLabel,
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
            if (reminder != null) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: _brandBlue.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.notification_important_rounded,
                        color: _brandBlue),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        reminder,
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          color: _brandBlue,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 10),
            FutureBuilder<WeatherSnapshot?>(
              future: weatherFuture,
              builder: (context, snapshot) {
                final w = snapshot.data;

                Widget climate = const SizedBox.shrink();
                if (w != null) {
                  final label = w.isCloudy
                      ? 'Clima: Nublado (${w.cloudCover}%)'
                      : 'Clima: Estable (${w.cloudCover}%)';

                  climate = Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Row(
                      children: [
                        Icon(
                          w.isCloudy
                              ? Icons.cloud_rounded
                              : Icons.wb_sunny_rounded,
                          color: w.isCloudy ? cs.tertiary : cs.primary,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          label,
                          style: TextStyle(color: cs.onSurfaceVariant),
                        ),
                      ],
                    ),
                  );
                } else if (hasLocation &&
                    snapshot.connectionState != ConnectionState.done) {
                  climate = Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: cs.primary,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Clima: consultando…',
                          style: TextStyle(color: cs.onSurfaceVariant),
                        ),
                      ],
                    ),
                  );
                }

                final ctx = ReportContext(
                  dateKey: _yyyyMmDd(DateTime.now()),
                  userName: data.currentUserNombre ?? 'Equipo',
                  role: data.currentUserRol ?? '—',
                  isWorkDay: data.isWorkDay,
                  scheduleLabel: data.horarioLabel ?? 'Horario no definido',
                  hasEntrada: data.entradaMs != null,
                  hasSalida: data.salidaMs != null,
                  pendientesHoy: data.pendientesHoyCount,
                  instalacionesEnCurso: data.instalacionesEnCursoCount,
                  isCloudy: w?.isCloudy,
                  adminActiveUsers: data.adminActiveUsers,
                  adminSinEntrada: data.adminSinEntrada,
                  adminSalidaPendiente: data.adminSalidaPendiente,
                  adminSinEntradaSample: data.adminSinEntradaSample,
                  adminSalidaPendienteSample: data.adminSalidaPendienteSample,
                );

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    climate,
                    FutureBuilder<String>(
                      future: ReportIntelligence.getDailyInsight(ctx),
                      builder: (context, snap) {
                        final text = (snap.data ?? '').trim();
                        if (snap.connectionState != ConnectionState.done) {
                          return Text(
                            'Analizando el día…',
                            style: TextStyle(color: cs.onSurfaceVariant),
                          );
                        }
                        return Text(
                          text.isEmpty
                              ? 'Enfoque en calidad: diagnóstico claro, pruebas completas y entrega confirmada.'
                              : text,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        );
                      },
                    ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  String _punchLabel(_ReporteData data) {
    final entrada = data.entradaMs == null
        ? '—'
        : _fmtTime(DateTime.fromMillisecondsSinceEpoch(data.entradaMs!));
    final salida = data.salidaMs == null
        ? '—'
        : _fmtTime(DateTime.fromMillisecondsSinceEpoch(data.salidaMs!));

    if (!data.isWorkDay) {
      return 'Ponche: $entrada / $salida (fuera de horario laboral)';
    }

    if (data.entradaMs == null && data.salidaMs == null) {
      return 'Ponche: sin registros hoy';
    }
    if (data.entradaMs != null && data.salidaMs == null) {
      return 'Ponche: entrada $entrada • salida pendiente';
    }
    return 'Ponche: entrada $entrada • salida $salida';
  }

  String? _punchReminder(_ReporteData data, DateTime now) {
    if (!data.isWorkDay) return null;
    if (data.currentUserId == null) return null;
    final start = data.workStart;
    final end = data.workEnd;
    if (start == null || end == null) return null;

    final minutes = now.hour * 60 + now.minute;
    final startMin = start.hour * 60 + start.minute;
    final endMin = end.hour * 60 + end.minute;

    // Ventana de recordatorio: 60 min antes de entrada hasta 90 min después.
    if (data.entradaMs == null && minutes >= (startMin - 60)) {
      if (minutes <= (startMin + 90)) {
        return 'Recordatorio: registra tu ponche de entrada.';
      }
    }

    // Cerca de salida: 30 min antes hasta 2h después.
    if (data.entradaMs != null && data.salidaMs == null) {
      if (minutes >= (endMin - 30) && minutes <= (endMin + 120)) {
        return 'Recordatorio: registra tu ponche de salida al cerrar jornada.';
      }
    }

    return null;
  }
}

class _TopVendedoresChart extends StatelessWidget {
  const _TopVendedoresChart({required this.rows});

  final List<_SellerRow> rows;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final maxY = rows
        .map((e) => e.puntos)
        .fold<double>(0.0, (m, v) => v > m ? v : m)
        .clamp(1.0, double.infinity);

    return BarChart(
      BarChartData(
        alignment: BarChartAlignment.spaceAround,
        maxY: maxY,
        gridData: FlGridData(show: true, drawVerticalLine: false),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          topTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 34,
              getTitlesWidget: (v, meta) => Text(
                v.toStringAsFixed(0),
                style: const TextStyle(fontSize: 10, color: Colors.black54),
              ),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              getTitlesWidget: (v, meta) {
                final i = v.toInt();
                if (i < 0 || i >= rows.length) return const SizedBox.shrink();
                final name = rows[i].nombre;
                final short = name.split(' ').first;
                return Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    short,
                    style: const TextStyle(fontSize: 10),
                    overflow: TextOverflow.ellipsis,
                  ),
                );
              },
            ),
          ),
        ),
        barGroups: [
          for (var i = 0; i < rows.length; i++)
            BarChartGroupData(
              x: i,
              barRods: [
                BarChartRodData(
                  toY: rows[i].puntos,
                  color: cs.primary,
                  borderRadius: BorderRadius.circular(6),
                  width: 18,
                ),
              ],
            )
        ],
      ),
    );
  }
}

class _SellerRow {
  _SellerRow({required this.nombre, required this.puntos});

  final String nombre;
  final double puntos;
}

class _OpRow {
  _OpRow({
    required this.codigo,
    required this.cliente,
    required this.tipoServicio,
    required this.estado,
    required this.programadoEn,
    required this.tecnico,
  });

  final String codigo;
  final String cliente;
  final String tipoServicio;
  final String estado;
  final int? programadoEn;
  final String? tecnico;
}

class _ReporteData {
  _ReporteData({
    required this.today,
    required this.currentUserNombre,
    required this.currentUserRol,
    required this.infoGeneral,
    required this.infoEspecial,
    required this.empleadoMesNombre,
    required this.topVendedorNombre,
    required this.topVendedores,
    required this.reservasHoyCount,
    required this.pendientesHoyCount,
    required this.instalacionesEnCursoCount,
    required this.pendientesHoy,
    required this.instalacionesEnCurso,
    required this.currentUserId,
    required this.isWorkDay,
    required this.workStart,
    required this.workEnd,
    required this.horarioLabel,
    required this.entradaMs,
    required this.salidaMs,
    required this.ubicacionLat,
    required this.ubicacionLon,
    required this.adminActiveUsers,
    required this.adminSinEntrada,
    required this.adminSalidaPendiente,
    required this.adminSinEntradaSample,
    required this.adminSalidaPendienteSample,
  });

  final DateTime today;
  final String? currentUserNombre;
  final String? currentUserRol;

  final String? infoGeneral;
  final String? infoEspecial;

  final String? empleadoMesNombre;
  final String? topVendedorNombre;

  final List<_SellerRow> topVendedores;

  final int reservasHoyCount;
  final int pendientesHoyCount;
  final int instalacionesEnCursoCount;

  final List<_OpRow> pendientesHoy;
  final List<_OpRow> instalacionesEnCurso;

  final int? currentUserId;

  final bool isWorkDay;
  final TimeOfDay? workStart;
  final TimeOfDay? workEnd;
  final String? horarioLabel;

  final int? entradaMs;
  final int? salidaMs;

  final double? ubicacionLat;
  final double? ubicacionLon;

  // Solo Admin: resumen de ponches del equipo (hoy)
  final int? adminActiveUsers;
  final int? adminSinEntrada;
  final int? adminSalidaPendiente;
  final List<String>? adminSinEntradaSample;
  final List<String>? adminSalidaPendienteSample;

  static _ReporteData empty() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return _ReporteData(
      today: today,
      currentUserNombre: null,
      currentUserRol: null,
      infoGeneral: null,
      infoEspecial: null,
      empleadoMesNombre: null,
      topVendedorNombre: null,
      topVendedores: const [],
      reservasHoyCount: 0,
      pendientesHoyCount: 0,
      instalacionesEnCursoCount: 0,
      pendientesHoy: const [],
      instalacionesEnCurso: const [],
      currentUserId: null,
      isWorkDay: false,
      workStart: null,
      workEnd: null,
      horarioLabel: null,
      entradaMs: null,
      salidaMs: null,
      ubicacionLat: null,
      ubicacionLon: null,
      adminActiveUsers: null,
      adminSinEntrada: null,
      adminSalidaPendiente: null,
      adminSinEntradaSample: null,
      adminSalidaPendienteSample: null,
    );
  }

  static Future<_ReporteData> load() async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final startMs = today.millisecondsSinceEpoch;
    final endMs = today.add(const Duration(days: 1)).millisecondsSinceEpoch;

    // Garantiza que la DB esté inicializada aunque Reporte sea la primera pantalla.
    await AppDatabase.instance.init();

    String? currentUserNombre;
    String? currentUserRol;
    try {
      final user = await AuthService.instance.currentUser();
      currentUserNombre = (user?['nombre'] as String?)?.trim();
      currentUserRol = (user?['rol'] as String?)?.trim();
    } catch (_) {}

    String? infoGeneral;
    String? infoEspecial;
    String? horarioJson;
    double? ubicacionLat;
    double? ubicacionLon;
    try {
      final cfg = await AppDatabase.instance.getEmpresaConfig();
      infoGeneral = (cfg?['info_general'] as String?)?.trim();
      infoEspecial = (cfg?['info_especial'] as String?)?.trim();
      horarioJson = (cfg?['horario_json'] as String?)?.trim();
      ubicacionLat = (cfg?['ubicacion_lat'] as num?)?.toDouble();
      ubicacionLon = (cfg?['ubicacion_lon'] as num?)?.toDouble();
    } catch (_) {}

    final (isWorkDay, start, end, horarioLabel) =
        _computeWorkSchedule(now: now, horarioJson: horarioJson);

    final currentUserId = AuthService.instance.currentUserId;
    final (entradaMs, salidaMs) = await _loadMyPunches(
      userId: currentUserId,
      startMs: startMs,
      endMs: endMs,
    );

    int? adminActiveUsers;
    int? adminSinEntrada;
    int? adminSalidaPendiente;
    List<String>? adminSinEntradaSample;
    List<String>? adminSalidaPendienteSample;

    if (AuthService.isAdminRole(currentUserRol)) {
      try {
        final rows = await _safeRawQuery(
          '''
SELECT
  u.id AS usuario_id,
  COALESCE(u.nombre, '—') AS nombre,
  MAX(CASE WHEN p.tipo = 'LABOR_ENTRADA' THEN 1 ELSE 0 END) AS has_entrada,
  MAX(CASE WHEN p.tipo = 'LABOR_SALIDA' THEN 1 ELSE 0 END) AS has_salida
FROM usuarios u
LEFT JOIN ponches p
  ON p.usuario_id = u.id
  AND p.hora >= ?
  AND p.hora < ?
  AND p.tipo IN ('LABOR_ENTRADA','LABOR_SALIDA')
WHERE COALESCE(u.bloqueado, 0) = 0
  AND LOWER(TRIM(COALESCE(u.rol, ''))) <> 'admin'
GROUP BY u.id, u.nombre
ORDER BY u.nombre ASC
''',
          [startMs, endMs],
        );

        adminActiveUsers = rows.length;
        final sinEntradaNames = <String>[];
        final salidaPendNames = <String>[];

        for (final r in rows) {
          final nombre = (r['nombre'] as String?)?.trim() ?? '—';
          final hasEntrada = (r['has_entrada'] as int?) ?? 0;
          final hasSalida = (r['has_salida'] as int?) ?? 0;

          if (hasEntrada == 0) {
            sinEntradaNames.add(nombre);
          } else if (hasSalida == 0) {
            salidaPendNames.add(nombre);
          }
        }

        adminSinEntrada = sinEntradaNames.length;
        adminSalidaPendiente = salidaPendNames.length;
        adminSinEntradaSample = sinEntradaNames.take(3).toList(growable: false);
        adminSalidaPendienteSample =
            salidaPendNames.take(3).toList(growable: false);
      } catch (_) {
        // No bloquea el reporte.
      }
    }

    String? empleadoMesNombre;
    try {
      final empleadoMesRows = await AppDatabase.instance.db.query(
        'usuarios',
        columns: const ['nombre'],
        where: 'empleado_mes = 1',
        limit: 1,
      );
      empleadoMesNombre = empleadoMesRows.isEmpty
          ? null
          : (empleadoMesRows.first['nombre'] as String?)?.trim();
    } catch (_) {}

    final topVendedoresRows = await _safeRawQuery(
      '''
SELECT
  u.id AS usuario_id,
  COALESCE(u.nombre, '—') AS usuario_nombre,
  COALESCE(SUM(v.puntos), 0) AS puntos_sum
FROM ventas v
LEFT JOIN usuarios u ON u.id = v.usuario_id
WHERE v.creado_en >= ?
  AND v.creado_en < ?
GROUP BY u.id, u.nombre
ORDER BY puntos_sum DESC
LIMIT 5
''',
      [startMs, endMs],
    );

    final topVendedores = topVendedoresRows.map((r) {
      final nombre = (r['usuario_nombre'] as String?) ?? '—';
      final puntos = (r['puntos_sum'] as num?)?.toDouble() ?? 0.0;
      return _SellerRow(nombre: nombre, puntos: puntos);
    }).toList(growable: false);

    final topVendedorNombre =
        topVendedores.isEmpty ? null : topVendedores.first.nombre;

    final opRows = await _safeRawQuery(
      '''
SELECT
  o.codigo AS codigo,
  COALESCE(c.nombre, '—') AS cliente_nombre,
  o.tipo_servicio AS tipo_servicio,
  o.estado AS estado,
  o.programado_en AS programado_en,
  COALESCE(u.nombre, t.nombre, '—') AS tecnico_nombre
FROM operaciones o
LEFT JOIN clientes c ON c.id = o.cliente_id
LEFT JOIN usuarios u ON u.id = o.tecnico_usuario_id
LEFT JOIN tecnicos t ON t.id = o.tecnico_id
WHERE o.programado_en >= ?
  AND o.programado_en < ?
  AND o.estado IN ('Pendiente','Programada','En proceso','Pendiente de pago')
ORDER BY o.programado_en ASC, o.prioridad DESC, o.id DESC
''',
      [startMs, endMs],
    );

    final pendientesHoy = opRows.map((r) {
      return _OpRow(
        codigo: (r['codigo'] as String?) ?? '—',
        cliente: (r['cliente_nombre'] as String?) ?? '—',
        tipoServicio: (r['tipo_servicio'] as String?) ?? '—',
        estado: (r['estado'] as String?) ?? 'Pendiente',
        programadoEn: r['programado_en'] as int?,
        tecnico: (r['tecnico_nombre'] as String?)?.trim(),
      );
    }).toList(growable: false);

    final instalacionesEnCurso = pendientesHoy.where((r) {
      final tipo = r.tipoServicio.toLowerCase();
      if (!tipo.contains('instal')) return false;
      return r.estado == 'En proceso' || r.estado == 'Programada';
    }).toList(growable: false);

    final reservasHoyCount = pendientesHoy.length;
    final pendientesHoyCount = pendientesHoy
        .where((r) => r.estado == 'Pendiente' || r.estado == 'Programada')
        .length;
    final instalacionesEnCursoCount = instalacionesEnCurso.length;

    return _ReporteData(
      today: today,
      currentUserNombre: currentUserNombre,
      currentUserRol: currentUserRol,
      infoGeneral: infoGeneral,
      infoEspecial: infoEspecial,
      empleadoMesNombre: empleadoMesNombre,
      topVendedorNombre: topVendedorNombre,
      topVendedores: topVendedores,
      reservasHoyCount: reservasHoyCount,
      pendientesHoyCount: pendientesHoyCount,
      instalacionesEnCursoCount: instalacionesEnCursoCount,
      pendientesHoy: pendientesHoy,
      instalacionesEnCurso: instalacionesEnCurso,
      currentUserId: currentUserId,
      isWorkDay: isWorkDay,
      workStart: start,
      workEnd: end,
      horarioLabel: horarioLabel,
      entradaMs: entradaMs,
      salidaMs: salidaMs,
      ubicacionLat: ubicacionLat,
      ubicacionLon: ubicacionLon,
      adminActiveUsers: adminActiveUsers,
      adminSinEntrada: adminSinEntrada,
      adminSalidaPendiente: adminSalidaPendiente,
      adminSinEntradaSample: adminSinEntradaSample,
      adminSalidaPendienteSample: adminSalidaPendienteSample,
    );
  }
}

(bool, TimeOfDay?, TimeOfDay?, String?) _computeWorkSchedule({
  required DateTime now,
  required String? horarioJson,
}) {
  final weekday = now.weekday; // 1..7

  if (horarioJson == null || horarioJson.trim().isEmpty) {
    return (false, null, null, 'Horario no configurado');
  }

  try {
    final decoded = jsonDecode(horarioJson);
    if (decoded is! Map) {
      return (false, null, null, 'Horario no disponible');
    }

    final startRaw = decoded['start']?.toString();
    final endRaw = decoded['end']?.toString();
    final daysRaw = decoded['days'];

    TimeOfDay? parse(String? s) {
      final v = (s ?? '').trim();
      if (!v.contains(':')) return null;
      final parts = v.split(':');
      if (parts.length < 2) return null;
      final h = int.tryParse(parts[0]);
      final m = int.tryParse(parts[1]);
      if (h == null || m == null) return null;
      if (h < 0 || h > 23) return null;
      if (m < 0 || m > 59) return null;
      return TimeOfDay(hour: h, minute: m);
    }

    final start = parse(startRaw);
    final end = parse(endRaw);

    final days = <int>{};
    if (daysRaw is List) {
      for (final d in daysRaw) {
        final v = int.tryParse(d.toString());
        if (v != null && v >= 1 && v <= 7) days.add(v);
      }
    }

    final isWorkDay = days.isNotEmpty && days.contains(weekday);
    final label = (start == null || end == null)
        ? 'Horario definido'
        : 'Horario: ${_fmtTod(start)}–${_fmtTod(end)}';

    return (isWorkDay, start, end, label);
  } catch (_) {
    return (false, null, null, 'Horario no disponible');
  }
}

Future<(int?, int?)> _loadMyPunches({
  required int? userId,
  required int startMs,
  required int endMs,
}) async {
  if (userId == null) return (null, null);

  try {
    final rows = await AppDatabase.instance.db.query(
      'ponches',
      columns: const ['tipo', 'hora'],
      where: 'usuario_id = ? AND hora >= ? AND hora < ?',
      whereArgs: [userId, startMs, endMs],
      orderBy: 'hora ASC',
    );

    int? entrada;
    int? salida;
    for (final r in rows) {
      final tipo = (r['tipo'] as String?) ?? '';
      final hora = (r['hora'] as int?) ?? 0;
      if (hora <= 0) continue;
      if (tipo == 'LABOR_ENTRADA') entrada ??= hora;
      if (tipo == 'LABOR_SALIDA') salida = hora;
    }
    return (entrada, salida);
  } catch (_) {
    return (null, null);
  }
}

String _fmtTod(TimeOfDay t) {
  final hh = t.hour.toString().padLeft(2, '0');
  final mm = t.minute.toString().padLeft(2, '0');
  return '$hh:$mm';
}

String _yyyyMmDd(DateTime dt) {
  final y = dt.year.toString().padLeft(4, '0');
  final m = dt.month.toString().padLeft(2, '0');
  final d = dt.day.toString().padLeft(2, '0');
  return '$y-$m-$d';
}

Future<List<Map<String, Object?>>> _safeRawQuery(
  String sql,
  List<Object?> args,
) async {
  try {
    return await AppDatabase.instance.db.rawQuery(sql, args);
  } catch (_) {
    return const [];
  }
}

String _fmtDate(DateTime dt) {
  const months = [
    'Enero',
    'Febrero',
    'Marzo',
    'Abril',
    'Mayo',
    'Junio',
    'Julio',
    'Agosto',
    'Septiembre',
    'Octubre',
    'Noviembre',
    'Diciembre',
  ];
  final m = months[(dt.month - 1).clamp(0, 11)];
  return '${dt.day} $m ${dt.year}';
}

String _fmtTime(DateTime dt) {
  final hh = dt.hour.toString().padLeft(2, '0');
  final mm = dt.minute.toString().padLeft(2, '0');
  return '$hh:$mm';
}
