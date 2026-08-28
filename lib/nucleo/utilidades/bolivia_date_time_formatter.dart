class BoliviaDateTimeFormatter {
  const BoliviaDateTimeFormatter._();

  static const Duration _boliviaUtcOffset = Duration(hours: -4);

  static String format(DateTime? value) {
    if (value == null) return 'Sin fecha';

    final boliviaTime = value.toUtc().add(_boliviaUtcOffset);
    final day = boliviaTime.day.toString().padLeft(2, '0');
    final month = boliviaTime.month.toString().padLeft(2, '0');
    final year = boliviaTime.year;
    final hour = boliviaTime.hour.toString().padLeft(2, '0');
    final minute = boliviaTime.minute.toString().padLeft(2, '0');
    return '$day/$month/$year $hour:$minute';
  }
}
