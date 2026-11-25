String _two(int n) => n.toString().padLeft(2, '0');

String formatDate(DateTime t) => '${t.year.toString().padLeft(4, '0')}-${_two(t.month)}-${_two(t.day)}';

String formatHourMinute(DateTime t) => '${_two(t.hour)}:${_two(t.minute)}';

String formatTime(DateTime t) => '${formatHourMinute(t)}:${_two(t.second)}';

String formatDateTime(DateTime t) => '${formatDate(t)} ${formatHourMinute(t)}';
