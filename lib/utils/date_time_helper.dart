import 'package:intl/intl.dart';

class DateTimeHelper {
  static final _dateFormat = DateFormat('EEE, d MMM yyyy');
  static final _timeFormat = DateFormat('h:mm a');

  static String date(DateTime value) => _dateFormat.format(value);
  static String time(DateTime value) => _timeFormat.format(value);
  static String range(DateTime start, DateTime end) =>
      '${date(start)} · ${time(start)} – ${date(end)} · ${time(end)}';
}
