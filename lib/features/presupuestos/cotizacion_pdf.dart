import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'cotizacion_models.dart';

const PdfColor _brandBlue = PdfColor.fromInt(0xFF1E3AFF);
const PdfColor _brandBlue2 = PdfColor.fromInt(0xFF2B4DFF);
const PdfColor _ink = PdfColor.fromInt(0xFF0E0E0E);

Future<Uint8List> buildCotizacionPdf({
  required String codigo,
  required DateTime fecha,
  required String clienteNombre,
  required String clienteTelefono,
  required String moneda,
  required bool itbisActivo,
  required double itbisTasa,
  required double descuentoGlobal,
  required List<CotizacionLinea> lines,
  String? empresaNombre,
  String? empresaRnc,
  String? empresaTelefono,
  String? empresaEmail,
  String? empresaDireccion,
  String? empresaWeb,
  Uint8List? logoBytes,
}) async {
  final doc = pw.Document();

  final displayNombre =
      (empresaNombre ?? '').trim().isEmpty ? 'FULLTECH' : empresaNombre!.trim();

  final headerLines = <String>[];
  final rnc = (empresaRnc ?? '').trim();
  final tel = (empresaTelefono ?? '').trim();
  final email = (empresaEmail ?? '').trim();
  final dir = (empresaDireccion ?? '').trim();
  final web = (empresaWeb ?? '').trim();
  if (rnc.isNotEmpty) headerLines.add('RNC: $rnc');
  if (tel.isNotEmpty) headerLines.add('Tel: $tel');
  if (email.isNotEmpty) headerLines.add(email);
  if (web.isNotEmpty) headerLines.add(web);
  if (dir.isNotEmpty) headerLines.add(dir);

  final subtotal = lines.fold<double>(0.0, (s, l) => s + l.subtotal);
  final descuentoLineas = lines.fold<double>(0.0, (s, l) => s + l.descuento);
  final descuentoTotal = descuentoGlobal.clamp(0.0, subtotal - descuentoLineas);

  final base =
      (subtotal - descuentoLineas - descuentoTotal).clamp(0.0, double.infinity);
  final itbis = itbisActivo ? base * itbisTasa : 0.0;
  final total = base + itbis;

  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(28),
      build: (context) => [
        pw.Container(
          padding: const pw.EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: pw.BoxDecoration(
            color: PdfColors.white,
            border: pw.Border.all(color: _brandBlue, width: 1),
            borderRadius: pw.BorderRadius.circular(12),
          ),
          child: pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Expanded(
                child: pw.Row(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    if (logoBytes != null)
                      pw.Container(
                        width: 44,
                        height: 44,
                        padding: const pw.EdgeInsets.all(6),
                        decoration: pw.BoxDecoration(
                          color: PdfColors.white,
                          border: pw.Border.all(color: _brandBlue, width: 1),
                          borderRadius: pw.BorderRadius.circular(10),
                        ),
                        child: pw.Image(pw.MemoryImage(logoBytes),
                            fit: pw.BoxFit.contain),
                      ),
                    if (logoBytes != null) pw.SizedBox(width: 10),
                    pw.Expanded(
                      child: pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.Text(
                            displayNombre,
                            style: pw.TextStyle(
                              fontSize: 18,
                              fontWeight: pw.FontWeight.bold,
                              color: _ink,
                              letterSpacing: 0.4,
                            ),
                            maxLines: 2,
                            overflow: pw.TextOverflow.clip,
                          ),
                          pw.SizedBox(height: 3),
                          pw.Text(
                            'Cotización / Presupuesto',
                            style: pw.TextStyle(color: PdfColors.grey800, fontSize: 10),
                          ),
                          if (headerLines.isNotEmpty) ...[
                            pw.SizedBox(height: 4),
                            pw.Text(
                              headerLines.join(' • '),
                              style: pw.TextStyle(
                                  color: PdfColors.grey700, fontSize: 8),
                              maxLines: 2,
                              overflow: pw.TextOverflow.clip,
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.end,
                children: [
                  pw.Container(
                    padding: const pw.EdgeInsets.symmetric(
                        horizontal: 10, vertical: 6),
                    decoration: pw.BoxDecoration(
                      color: PdfColors.white,
                      border: pw.Border.all(color: _brandBlue2, width: 1),
                      borderRadius: pw.BorderRadius.circular(999),
                    ),
                    child: pw.Text(
                      codigo,
                      style: pw.TextStyle(
                        fontSize: 11,
                        fontWeight: pw.FontWeight.bold,
                        color: _brandBlue2,
                      ),
                    ),
                  ),
                  pw.SizedBox(height: 6),
                  pw.Text(
                    _date(fecha),
                    style: pw.TextStyle(color: PdfColors.grey800, fontSize: 10),
                  ),
                ],
              ),
            ],
          ),
        ),
        pw.SizedBox(height: 16),
        pw.Container(
          padding: const pw.EdgeInsets.all(12),
          decoration: pw.BoxDecoration(
            color: PdfColors.white,
            border: pw.Border.all(color: _brandBlue2, width: 1),
            borderRadius: pw.BorderRadius.circular(8),
          ),
          child: pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Expanded(
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      'Cliente',
                      style: pw.TextStyle(
                        fontWeight: pw.FontWeight.bold,
                        color: _brandBlue2,
                      ),
                    ),
                    pw.SizedBox(height: 6),
                    pw.Text(clienteNombre.isEmpty
                        ? 'Consumidor final'
                        : clienteNombre),
                    if (clienteTelefono.trim().isNotEmpty) ...[
                      pw.SizedBox(height: 4),
                      pw.Text(clienteTelefono,
                          style: pw.TextStyle(color: PdfColors.grey700)),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
        pw.SizedBox(height: 16),
        pw.Text(
          'Detalle',
          style: pw.TextStyle(
            fontSize: 14, fontWeight: pw.FontWeight.bold, color: _brandBlue2),
        ),
        pw.SizedBox(height: 8),
        pw.Table(
          border: pw.TableBorder.all(color: _brandBlue2, width: 0.8),
          columnWidths: {
            0: const pw.FlexColumnWidth(3.8),
            1: const pw.FlexColumnWidth(1.2),
            2: const pw.FlexColumnWidth(1.6),
            3: const pw.FlexColumnWidth(1.6),
          },
          children: [
            _headerRow(),
            ...lines.map(
              (l) => _lineRow(
                nombre: l.nombre,
                cantidad: l.cantidad,
                precio: l.precio,
                descuento: l.descuento,
                total: l.total,
                moneda: moneda,
              ),
            ),
          ],
        ),
        pw.SizedBox(height: 14),
        pw.Align(
          alignment: pw.Alignment.centerRight,
          child: pw.Container(
            width: 240,
            padding: const pw.EdgeInsets.all(12),
            decoration: pw.BoxDecoration(
              border: pw.Border.all(color: _brandBlue2),
              borderRadius: pw.BorderRadius.circular(8),
            ),
            child: pw.Column(
              children: [
                _totalRow('Subtotal', _money(subtotal, moneda)),
                _totalRow(
                    'Desc. líneas', '- ${_money(descuentoLineas, moneda)}'),
                _totalRow('Desc. total', '- ${_money(descuentoTotal, moneda)}'),
                _totalRow('ITBIS (${(itbisTasa * 100).toStringAsFixed(0)}%)',
                    itbisActivo ? _money(itbis, moneda) : '—'),
                pw.Divider(),
                pw.Container(
                  padding:
                      const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  decoration: pw.BoxDecoration(
                    color: PdfColors.white,
                    border: pw.Border.all(color: _brandBlue, width: 1),
                    borderRadius: pw.BorderRadius.circular(8),
                  ),
                  child: _totalRowStyled(
                    'Total',
                    _money(total, moneda),
                    bold: true,
                    invert: false,
                  ),
                ),
              ],
            ),
          ),
        ),
        pw.SizedBox(height: 24),
        pw.Text(
          'Gracias por su preferencia.',
          style: pw.TextStyle(color: PdfColors.grey700),
        ),
      ],
    ),
  );

  return doc.save();
}

pw.TableRow _headerRow() {
  final style = pw.TextStyle(
      fontWeight: pw.FontWeight.bold, color: PdfColors.white, fontSize: 10);
  return pw.TableRow(
    decoration: const pw.BoxDecoration(color: _brandBlue),
    children: [
      pw.Padding(
          padding: const pw.EdgeInsets.all(8),
          child: pw.Text('Producto', style: style)),
      pw.Padding(
          padding: const pw.EdgeInsets.all(8),
          child: pw.Text('Cant.', style: style, textAlign: pw.TextAlign.right)),
      pw.Padding(
          padding: const pw.EdgeInsets.all(8),
          child:
              pw.Text('Precio', style: style, textAlign: pw.TextAlign.right)),
      pw.Padding(
          padding: const pw.EdgeInsets.all(8),
          child: pw.Text('Total', style: style, textAlign: pw.TextAlign.right)),
    ],
  );
}

pw.TableRow _lineRow({
  required String nombre,
  required double cantidad,
  required double precio,
  required double descuento,
  required double total,
  required String moneda,
}) {
  final qtyText = cantidad % 1 == 0
      ? cantidad.toStringAsFixed(0)
      : cantidad.toStringAsFixed(2);
  final priceText = _money(precio, moneda);
  final totalText = _money(total, moneda);

  return pw.TableRow(
    children: [
      pw.Padding(
        padding: const pw.EdgeInsets.all(8),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(nombre, maxLines: 2, overflow: pw.TextOverflow.clip),
            if (descuento > 0)
              pw.Padding(
                padding: const pw.EdgeInsets.only(top: 2),
                child: pw.Text(
                  'Descuento: -${_money(descuento, moneda)}',
                  style:
                      pw.TextStyle(color: PdfColors.blueGrey700, fontSize: 9),
                ),
              ),
          ],
        ),
      ),
      pw.Padding(
        padding: const pw.EdgeInsets.all(8),
        child: pw.Text(qtyText, textAlign: pw.TextAlign.right),
      ),
      pw.Padding(
        padding: const pw.EdgeInsets.all(8),
        child: pw.Text(priceText, textAlign: pw.TextAlign.right),
      ),
      pw.Padding(
        padding: const pw.EdgeInsets.all(8),
        child: pw.Text(totalText, textAlign: pw.TextAlign.right),
      ),
    ],
  );
}

pw.Widget _totalRow(String label, String value, {bool bold = false}) {
  return _totalRowStyled(label, value, bold: bold);
}

pw.Widget _totalRowStyled(String label, String value,
    {bool bold = false, bool invert = false}) {
  final style = pw.TextStyle(
    fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
    color: invert
        ? PdfColors.white
        : (bold ? _brandBlue2 : _ink),
  );
  return pw.Padding(
    padding: const pw.EdgeInsets.symmetric(vertical: 2),
    child: pw.Row(
      children: [
        pw.Expanded(child: pw.Text(label, style: style)),
        pw.Text(value, style: style),
      ],
    ),
  );
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

String _date(DateTime d) {
  return '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}
