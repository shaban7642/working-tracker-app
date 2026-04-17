/// Utilities for parsing server timestamps.
///
/// The backend stores UTC timestamps but serialises them with the
/// server's local offset (e.g. `+04:00`) instead of `Z`.  This means
/// `2026-03-04T11:17:00.000+04:00` is really 11:17 UTC, not 07:17 UTC.
///
/// These helpers strip any trailing offset / Z so the raw date-time
/// digits are always interpreted as UTC.

final _offsetOrZ = RegExp(r'[Zz]|[+-]\d{2}:\d{2}$');

/// Strips any trailing timezone designator and re-parses as UTC.
DateTime parseUtcDateTime(String value) {
  final stripped = value.replaceAll(_offsetOrZ, '');
  final dt = DateTime.parse(stripped);
  return DateTime.utc(
    dt.year, dt.month, dt.day,
    dt.hour, dt.minute, dt.second,
    dt.millisecond, dt.microsecond,
  );
}

/// Like [parseUtcDateTime] but returns `null` on invalid input.
DateTime? tryParseUtcDateTime(String? value) {
  if (value == null || value.isEmpty) return null;
  final stripped = value.replaceAll(_offsetOrZ, '');
  final dt = DateTime.tryParse(stripped);
  if (dt == null) return null;
  return DateTime.utc(
    dt.year, dt.month, dt.day,
    dt.hour, dt.minute, dt.second,
    dt.millisecond, dt.microsecond,
  );
}
