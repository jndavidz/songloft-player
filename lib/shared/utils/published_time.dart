/// 上游发布时间的解析与展示（评论发布时间等）。
///
/// 上游字段形态不统一：Unix 秒 / 毫秒时间戳（数字或数字串）、以及已格式化
/// 文本。这里只做**保守归一**：识别不出的一律返回 null，由 UI 整条隐藏，
/// 绝不补 1970 或默认 00:00。
library;

/// 毫秒时间戳的判定阈值：1e11。
///
/// Unix 秒到 1e11 已是公元 5138 年，现实中不可能；而毫秒到 1e11 只是 1973 年，
/// 所以大于等于该值的一律按毫秒处理。
const double _kMillisThreshold = 1e11;

/// 解析上游时间：支持 num、数字字符串、毫秒时间戳。
///
/// 非纯数字的字符串（例如 `2024-05-01`）**不**按时间戳解析——只给日期时
/// 强行补出 `00:00` 等于编造时间，这类值请走 [formatPublishedTime] 之外的
/// 文本通道直接展示。
DateTime? parsePublishedTime(dynamic value) {
  if (value is num) return _fromEpoch(value.toDouble());
  if (value is String) {
    final text = value.trim();
    if (text.isEmpty) return null;
    final numeric = double.tryParse(text);
    if (numeric != null) return _fromEpoch(numeric);
  }
  return null;
}

DateTime? _fromEpoch(double raw) {
  if (!raw.isFinite || raw <= 0) return null;
  final millis = raw >= _kMillisThreshold ? raw : raw * 1000;
  return DateTime.fromMillisecondsSinceEpoch(millis.round());
}

/// 展示规则：今天 `hh:mm`、昨天 `<昨天标签> hh:mm`、同年 `MM-DD hh:mm`、
/// 跨年 `yyyy-MM-DD`。
///
/// [now] 仅用于测试注入；[yesterdayLabel] 由调用方按当前语言传入。
String formatPublishedTime(
  DateTime value, {
  String yesterdayLabel = '昨天',
  DateTime? now,
}) {
  final local = value.toLocal();
  final reference = (now ?? DateTime.now()).toLocal();

  String two(int n) => n.toString().padLeft(2, '0');
  final hhmm = '${two(local.hour)}:${two(local.minute)}';

  if (_isSameDay(local, reference)) return hhmm;

  final yesterday = reference.subtract(const Duration(days: 1));
  if (_isSameDay(local, yesterday)) return '$yesterdayLabel $hhmm';

  final monthDay = '${two(local.month)}-${two(local.day)}';
  if (local.year == reference.year) return '$monthDay $hhmm';

  return '${local.year}-$monthDay';
}

bool _isSameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;
