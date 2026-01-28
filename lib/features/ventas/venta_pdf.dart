import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

const PdfColor _brandBlue = PdfColor.fromInt(0xFF1E3AFF);
const PdfColor _brandBlue2 = PdfColor.fromInt(0xFF2B4DFF);
const PdfColor _ink = PdfColor.fromInt(0xFF0E0E0E);

class VentaPdfLinea {
  const VentaPdfLinea({
    required this.nombre,
    required this.cantidad,
    required this.precio,
    required this.costo,
  });

  final String nombre;
  final double cantidad;
  final double precio;
  final double costo;

  double get total => (precio * cantidad).clamp(0.0, double.infinity);

  double get puntos =>
      ((precio - costo) * cantidad).clamp(0.0, double.infinity);
}

Future<Uint8List> buildVentaPdf({
  required String codigo,
  required DateTime fecha,
  required String clienteNombre,
  required String clienteTelefono,
  required String moneda,
  required double total,
  required double puntos,
  required double comision,
  required List<VentaPdfLinea> lines,
  String? empresaNombre,
  String? empresaRnc,
  String? empresaTelefono,
  String? empresaEmail,
  String? empresaDireccion,
  String? empresaWeb,
  Uint8List? logoBytes,
}) async {
  final doc = pw.Document();

  final displayNombre = (empresaNombre ?? '').trim().isEmpty
      ? 'FULLTECH'
      : empresaNombre!.trim();

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
                        child: pw.Image(pw.MemoryImage(logoBytes), fit: pw.BoxFit.contain),
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
                            'Venta',
                            style: pw.TextStyle(color: PdfColors.grey800, fontSize: 10),
                          ),
                          if (headerLines.isNotEmpty) ...[
                            pw.SizedBox(height: 4),
                            pw.Text(
                              headerLines.join(' • '),
                              style: pw.TextStyle(color: PdfColors.grey700, fontSize: 8),
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
                    _dateTime(fecha),
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
              pw.Text(clienteNombre.isEmpty ? '—' : clienteNombre),
              if (clienteTelefono.trim().isNotEmpty) ...[
                pw.SizedBox(height: 4),
                pw.Text(
                  clienteTelefono,
                  style: pw.TextStyle(color: PdfColors.grey700),
                ),
              ],
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
            1: const pw.FlexColumnWidth(1.0),
            2: const pw.FlexColumnWidth(1.4),
            3: const pw.FlexColumnWidth(1.5),
            4: const pw.FlexColumnWidth(1.5),
          },
          children: [
            _headerRow(),
            ...lines.map(
              (l) => _lineRow(
                nombre: l.nombre,
                cantidad: l.cantidad,
                precio: l.precio,
                total: l.total,
                puntos: l.puntos,
                moneda: moneda,
              ),
            ),
          ],
        ),
        pw.SizedBox(height: 14),
        pw.Align(
          alignment: pw.Alignment.centerRight,
          child: pw.Container(
            width: 260,
            padding: const pw.EdgeInsets.all(12),
            decoration: pw.BoxDecoration(
              border: pw.Border.all(color: _brandBlue2),
              borderRadius: pw.BorderRadius.circular(8),
            ),
            child: pw.Column(
              children: [
                _totalRow('Total', _money(total, moneda)),
                _totalRow('Puntos', _money(puntos, moneda)),
                _totalRow('Comisión (10%)', _money(comision, moneda)),
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
    fontWeight: pw.FontWeight.bold,
    color: PdfColors.white,
    fontSize: 10,
  );
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
      pw.Padding(
          padding: const pw.EdgeInsets.all(8),
          child:
              pw.Text('Puntos', style: style, textAlign: pw.TextAlign.right)),
    ],
  );
}

pw.TableRow _lineRow({
  required String nombre,
  required double cantidad,
  required double precio,
  required double total,
  required double puntos,
  required String moneda,
}) {
  final cell = pw.TextStyle(fontSize: 10, color: _ink);
  return pw.TableRow(
    children: [
      pw.Padding(
          padding: const pw.EdgeInsets.all(8),
          child: pw.Text(nombre, style: cell)),
      pw.Padding(
        padding: const pw.EdgeInsets.all(8),
        child:
            pw.Text(_qty(cantidad), style: cell, textAlign: pw.TextAlign.right),
      ),
      pw.Padding(
        padding: const pw.EdgeInsets.all(8),
        child: pw.Text(_money(precio, moneda),
            style: cell, textAlign: pw.TextAlign.right),
      ),
      pw.Padding(
        padding: const pw.EdgeInsets.all(8),
        child: pw.Text(_money(total, moneda),
            style: cell, textAlign: pw.TextAlign.right),
      ),
      pw.Padding(
        padding: const pw.EdgeInsets.all(8),
        child: pw.Text(_money(puntos, moneda),
            style: cell, textAlign: pw.TextAlign.right),
      ),
    ],
  );
}

pw.Widget _totalRow(String label, String value) {
  return pw.Padding(
    padding: const pw.EdgeInsets.symmetric(vertical: 3),
    child: pw.Row(
      children: [
        pw.Expanded(
          child: pw.Text(
            label,
            style: pw.TextStyle(
              fontWeight: pw.FontWeight.bold,
              fontSize: 10,
              color: _brandBlue2,
            ),
          ),
        ),
        pw.Text(
          value,
          style: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: _ink),
        ),
      ],
    ),
  );
}

String _money(double value, String moneda) =>
    '$moneda ${value.toStringAsFixed(2)}';

String _qty(double value) {
  final isInt = value % 1 == 0;
  return value.toStringAsFixed(isInt ? 0 : 2);
}

String _dateTime(DateTime dt) {
  String two(int v) => v.toString().padLeft(2, '0');
  return '${two(dt.day)}/${two(dt.month)}/${dt.year} ${two(dt.hour)}:${two(dt.minute)}';
}
