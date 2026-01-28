class QuincenaInfo {
  const QuincenaInfo({
    required this.start,
    required this.endExclusive,
    required this.payDate,
    required this.index,
  });

  final DateTime start;
  final DateTime endExclusive;
  final DateTime payDate;

  /// 1 = primera quincena (pago 15), 2 = segunda quincena (pago 30/fin de mes)
  final int index;

  String get label => index == 1 ? '1ra quincena' : '2da quincena';
}

int _lastDayOfMonth(int year, int month) => DateTime(year, month + 1, 0).day;

DateTime _date(int year, int month, int day) {
  final lastDay = _lastDayOfMonth(year, month);
  final safeDay = day.clamp(1, lastDay);
  return DateTime(year, month, safeDay);
}

QuincenaInfo quincenaFor(DateTime now) {
  final year = now.year;
  final month = now.month;
  final day = now.day;

  final pay15 = _date(year, month, 15);
  final pay30 = _date(year, month, 30);

  if (day < pay15.day) {
    // Primera quincena: 1 -> 15 (exclusivo)
    return QuincenaInfo(
      start: DateTime(year, month, 1),
      endExclusive: DateTime(year, month, pay15.day),
      payDate: pay15,
      index: 1,
    );
  }

  // Segunda quincena: 15 -> 1 del próximo mes
  return QuincenaInfo(
    start: DateTime(year, month, pay15.day),
    endExclusive: DateTime(year, month + 1, 1),
    payDate: pay30,
    index: 2,
  );
}

QuincenaInfo quincenaForMonth({
  required int year,
  required int month,
  required int index,
}) {
  final pay15 = _date(year, month, 15);
  final pay30 = _date(year, month, 30);

  if (index == 1) {
    return QuincenaInfo(
      start: DateTime(year, month, 1),
      endExclusive: DateTime(year, month, pay15.day),
      payDate: pay15,
      index: 1,
    );
  }

  return QuincenaInfo(
    start: DateTime(year, month, pay15.day),
    endExclusive: DateTime(year, month + 1, 1),
    payDate: pay30,
    index: 2,
  );
}

String fmtDate(DateTime? dt) {
  if (dt == null) return '—';
  String two(int v) => v.toString().padLeft(2, '0');
  return '${two(dt.day)}/${two(dt.month)}/${dt.year}';
}
