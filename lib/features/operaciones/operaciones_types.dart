const kOperacionEstados = <String>[
  'Pendiente',
  'Programada',
  'En proceso',
  'Pendiente de pago',
  'Finalizada',
  'Cancelada',
];

const kOperacionPrioridades = <String>['Normal', 'Alta', 'Urgente'];

const kOperacionTiposServicio = <String>[
  'Instalación de cámaras',
  'Instalación punto de venta (POS)',
  'Instalación motor de portón',
  'Instalación cerco eléctrico',
  'Mantenimiento',
  'Reparación',
  'Visita técnica',
  'Otro',
];

const kPagoFormas = <String>['Efectivo', 'Transferencia', 'Mixto'];

const kPagoEstados = <String>['Pendiente', 'Abono', 'Pagado'];

const kGarantias = <String>['Sin garantía', '1 mes', '3 meses', '6 meses'];

const kTecnicoEspecialidades = <String>['Cámaras', 'POS', 'Portones', 'Cerco eléctrico', 'Mixto'];

const kTecnicoEstados = <String>['Disponible', 'Ocupado', 'Inactivo'];

const kEvidenciaTipos = <String>['ANTES', 'DURANTE', 'DESPUES'];

bool operacionEsFinal(String estado) => estado == 'Finalizada';

bool operacionEsEditable(String estado) => !operacionEsFinal(estado) && estado != 'Cancelada';
