import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import 'dart:async';

import '../../data/cloud_settings.dart';
import '../../data/sync/sync_service.dart';
import '../../features/catalogo/catalogo_page.dart';
import '../../features/beneficios/beneficios_page.dart';
import '../../features/clientes/clientes_page.dart';
import '../../features/configuracion/configuracion_page.dart';
import '../../features/nomina/nomina_page.dart';
import '../../features/operaciones/operaciones_page.dart';
import '../../features/ponche/ponche_page.dart';
import '../../features/reporte/reporte_page.dart';
import '../../features/rrhh/rrhh_page.dart';
import '../../features/usuarios/usuarios_page.dart';
import '../../features/presupuestos/presupuestos_page.dart';
import '../../features/ventas/ventas_page.dart';
import '../theme/fulltech_brand.dart';

enum FullTechPage {
  reporte,
  ponche,
  ventas,
  operaciones,
}

class FullTechShell extends StatefulWidget {
  const FullTechShell({super.key});

  @override
  State<FullTechShell> createState() => _FullTechShellState();
}

class _FullTechShellState extends State<FullTechShell> {
  FullTechPage _page = FullTechPage.reporte;
  Timer? _syncTimer;

  @override
  void initState() {
    super.initState();
    _syncOnce();
    _syncTimer = Timer.periodic(const Duration(minutes: 2), (_) => _syncOnce());
  }

  @override
  void dispose() {
    _syncTimer?.cancel();
    super.dispose();
  }

  List<FullTechPage> _bottomPages() {
    return const [
      FullTechPage.reporte,
      FullTechPage.ponche,
      FullTechPage.ventas,
      FullTechPage.operaciones,
    ];
  }

  void _setPage(FullTechPage page) {
    setState(() {
      _page = page;
    });
  }

  @override
  Widget build(BuildContext context) {
    final bottomPages = _bottomPages();
    final navIndex = bottomPages.indexOf(_page);

    final body = switch (_page) {
      FullTechPage.reporte => const ReportePage(),
      FullTechPage.ponche => const PonchePage(),
      FullTechPage.ventas => const VentasPage(),
      FullTechPage.operaciones => const OperacionesPage(),
    };

    return Scaffold(
      appBar: AppBar(
        title: Text(_titleForPage(_page)),
        actions: [
          IconButton(
            tooltip: 'Usuarios',
            icon: const Icon(Icons.person_outline),
            onPressed: () {
              _openFeaturePage(
                context,
                title: 'Usuarios',
                child: const UsuariosPage(),
                onAdd: UsuariosPage.openAddForm,
                closeDrawer: false,
              );
            },
          ),
          const SizedBox(width: 6),
        ],
      ),
      drawer: _buildDrawer(context),
      body: SafeArea(child: body),
      floatingActionButton: _buildFabForPage(context, _page),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      bottomNavigationBar: SafeArea(
        top: false,
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: FullTechBrand.navGradient,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withAlpha(55),
                blurRadius: 14,
                offset: const Offset(0, -2),
              ),
            ],
          ),
          child: NavigationBar(
            backgroundColor: Colors.transparent,
            selectedIndex: navIndex < 0 ? 0 : navIndex,
            onDestinationSelected: (idx) {
              Feedback.forTap(context);
              HapticFeedback.selectionClick();
              if (idx < 0 || idx >= bottomPages.length) return;
              _setPage(bottomPages[idx]);
            },
            height: 60,
            labelBehavior: NavigationDestinationLabelBehavior.alwaysHide,
            destinations: bottomPages
                .map(
                  (p) => NavigationDestination(
                    icon: Icon(_navIcon(p, selected: false)),
                    selectedIcon: Icon(_navIcon(p, selected: true)),
                    label: _navLabel(p),
                  ),
                )
                .toList(growable: false),
          ),
        ),
      ),
    );
  }

  String _navLabel(FullTechPage p) {
    switch (p) {
      case FullTechPage.reporte:
        return 'Reporte';
      case FullTechPage.ponche:
        return 'Ponche';
      case FullTechPage.ventas:
        return 'Ventas';
      case FullTechPage.operaciones:
        return 'Operaciones';
    }
  }

  IconData _navIcon(FullTechPage p, {required bool selected}) {
    switch (p) {
      case FullTechPage.reporte:
        return selected ? Icons.bar_chart : Icons.bar_chart_outlined;
      case FullTechPage.ponche:
        return selected ? Icons.punch_clock : Icons.punch_clock_outlined;
      case FullTechPage.ventas:
        return selected
            ? Icons.point_of_sale_rounded
            : Icons.point_of_sale_outlined;
      case FullTechPage.operaciones:
        return selected ? Icons.work : Icons.work_outline;
    }
  }

  String _titleForPage(FullTechPage page) {
    switch (page) {
      case FullTechPage.reporte:
        return 'Reporte';
      case FullTechPage.ponche:
        return 'Ponche';
      case FullTechPage.ventas:
        return 'Ventas';
      case FullTechPage.operaciones:
        return 'Operaciones';
    }
  }

  Drawer _buildDrawer(BuildContext context) {
    return Drawer(
      child: SafeArea(
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            const DrawerHeader(
              decoration: BoxDecoration(color: FullTechBrand.corporateBlack),
              child: Align(
                alignment: Alignment.bottomLeft,
                child: Text(
                  'FULLTECH',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ),
            _drawerSection('Ventas'),
            _drawerItem(
              context,
              icon: Icons.inventory_2_outlined,
              label: 'Productos',
              onTap: () => _openFeaturePage(
                context,
                title: 'Productos',
                child: const CatalogoPage(),
                onAdd: CatalogoPage.openAddForm,
                closeDrawer: true,
              ),
            ),
            _drawerItem(
              context,
              icon: Icons.people_alt_outlined,
              label: 'Clientes',
              onTap: () => _openFeaturePage(
                context,
                title: 'Clientes',
                child: const ClientesPage(),
                onAdd: ClientesPage.openAddForm,
                closeDrawer: true,
              ),
            ),
            _drawerItem(
              context,
              icon: Icons.request_quote_outlined,
              label: 'Presupuestos',
              onTap: () => _openFeaturePage(
                context,
                title: 'Presupuestos',
                child: const PresupuestosPage(),
                onAdd: PresupuestosPage.openAddForm,
                closeDrawer: true,
              ),
            ),
            _drawerSection('Equipo'),
            _drawerItem(
              context,
              icon: Icons.groups_2_outlined,
              label: 'RRHH',
              onTap: () => _openFeaturePage(
                context,
                title: 'RRHH',
                child: const RrhhPage(),
                closeDrawer: true,
              ),
            ),
            _drawerItem(
              context,
              icon: Icons.payments_outlined,
              label: 'Nómina',
              onTap: () => _openFeaturePage(
                context,
                title: 'Nómina',
                child: const NominaPage(),
                closeDrawer: true,
              ),
            ),
            _drawerItem(
              context,
              icon: Icons.card_giftcard_outlined,
              label: 'Beneficios',
              onTap: () => _openFeaturePage(
                context,
                title: 'Beneficios',
                child: const BeneficiosPage(),
                closeDrawer: true,
              ),
            ),
            _drawerSection('Ajustes'),
            _drawerItem(
              context,
              icon: Icons.settings_outlined,
              label: 'Configuración',
              onTap: () => _openFeaturePage(
                context,
                title: 'Configuración',
                child: const ConfiguracionPage(),
                closeDrawer: true,
              ),
            ),
            _drawerItem(
              context,
              icon: Icons.public_outlined,
              label: 'Virtual',
              onTap: () => _showVirtualDialog(context),
            ),
          ],
        ),
      ),
    );
  }

  Widget _drawerSection(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Text(
        title.toUpperCase(),
        style: const TextStyle(
          fontWeight: FontWeight.w800,
          fontSize: 12,
          color: Colors.black54,
        ),
      ),
    );
  }

  Widget _drawerItem(
    BuildContext context, {
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return ListTile(
      leading: Icon(icon),
      title: Text(label),
      onTap: onTap,
    );
  }

  Future<void> Function(BuildContext)? _addHandlerForPage(FullTechPage page) {
    switch (page) {
      case FullTechPage.reporte:
        return null;
      case FullTechPage.ponche:
        return PonchePage.openAddForm;
      case FullTechPage.ventas:
        return VentasPage.openAddForm;
      case FullTechPage.operaciones:
        return OperacionesPage.openAddForm;
    }
  }

  Widget? _buildFabForPage(BuildContext context, FullTechPage page) {
    final handler = _addHandlerForPage(page);
    if (handler == null) return null;

    return FloatingActionButton(
      tooltip: 'Agregar',
      onPressed: () async {
        await handler(context);
      },
      child: const Icon(Icons.add),
    );
  }

  void _openFeaturePage(
    BuildContext context, {
    required String title,
    required Widget child,
    Future<void> Function(BuildContext context)? onAdd,
    required bool closeDrawer,
  }) {
    if (closeDrawer) {
      Navigator.of(context).pop();
    }
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (routeContext) => Scaffold(
          appBar: AppBar(
            title: Text(title),
          ),
          body: SafeArea(child: child),
          floatingActionButton: onAdd == null
              ? null
              : FloatingActionButton(
                  tooltip: 'Agregar',
                  onPressed: () async {
                    await onAdd(routeContext);
                  },
                  child: const Icon(Icons.add),
                ),
          floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
        ),
      ),
    );
  }

  Future<void> _showVirtualDialog(BuildContext context) async {
    Navigator.of(context).pop();

    final settings = await CloudSettings.load();
    final email = settings.email.trim();
    final baseUrl = settings.baseUrl.trim();

    final link = email.isEmpty
        ? ''
        : '$baseUrl/virtual?email=${Uri.encodeComponent(email)}';

    if (!context.mounted) return;

    await showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Catálogo virtual'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                email.isEmpty
                    ? 'Necesitas iniciar sesión en la nube para generar el enlace.'
                    : 'Comparte este enlace con tus clientes.',
              ),
              const SizedBox(height: 12),
              if (email.isNotEmpty)
                SelectableText(
                  link,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cerrar'),
            ),
            if (email.isNotEmpty)
              TextButton(
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: link));
                  if (!context.mounted) return;
                  Navigator.of(context).pop();
                },
                child: const Text('Copiar'),
              ),
            if (email.isNotEmpty)
              FilledButton(
                onPressed: () async {
                  final uri = Uri.parse(link);
                  await launchUrl(uri, mode: LaunchMode.externalApplication);
                  if (!context.mounted) return;
                  Navigator.of(context).pop();
                },
                child: const Text('Abrir'),
              ),
          ],
        );
      },
    );
  }

  Future<void> _syncOnce() async {
    try {
      final settings = await CloudSettings.load();
      if (!settings.hasSession) return;
      await SyncService().syncNow();
    } catch (_) {
      // Avoid noisy UI here; Perfil shows last sync time.
    }
  }
}
