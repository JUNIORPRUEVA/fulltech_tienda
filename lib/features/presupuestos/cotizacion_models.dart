class CotizacionLinea {
  CotizacionLinea({
    required this.productoId,
    required this.codigo,
    required this.nombre,
    required this.precio,
    required this.cantidad,
  });

  final int? productoId;
  final String codigo;
  final String nombre;
  final double precio;
  double cantidad;
  double descuento = 0.0;

  double get subtotal => precio * cantidad;
  double get total => (subtotal - descuento).clamp(0.0, double.infinity);
}

String money(double value, String moneda) => '$moneda ${value.toStringAsFixed(2)}';
