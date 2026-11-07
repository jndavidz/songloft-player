import 'package:flutter_test/flutter_test.dart';
import 'package:songloft_flutter/shared/utils/published_time.dart';

void main() {
  group('parsePublishedTime', () {
    test('Unix 秒（数字与数字串）与毫秒都识别', () {
      const epochSecond = 1700000000;
      const epochMillis = 1700000000000;

      expect(parsePublishedTime(epochSecond), isNotNull);
      expect(parsePublishedTime('$epochSecond'), isNotNull);
      expect(parsePublishedTime(epochMillis), isNotNull);
      expect(parsePublishedTime('$epochMillis'), isNotNull);
      // 秒与毫秒归一后应指向同一时刻。
      expect(
        parsePublishedTime(epochSecond),
        DateTime.fromMillisecondsSinceEpoch(epochMillis),
      );
      expect(
        parsePublishedTime('$epochMillis'),
        DateTime.fromMillisecondsSinceEpoch(epochMillis),
      );
    });

    test('毫秒带小数的数字串按毫秒处理', () {
      expect(
        parsePublishedTime('1700000000123.0'),
        DateTime.fromMillisecondsSinceEpoch(1700000000123),
      );
    });

    test('缺失/0/负数/非法值一律返回 null（不补 1970）', () {
      expect(parsePublishedTime(null), isNull);
      expect(parsePublishedTime(''), isNull);
      expect(parsePublishedTime('   '), isNull);
      expect(parsePublishedTime(0), isNull);
      expect(parsePublishedTime(-1), isNull);
      expect(parsePublishedTime('abc'), isNull);
      // 只给日期的字符串不按时间戳解析，避免补出 00:00。
      expect(parsePublishedTime('2024-05-01'), isNull);
    });
  });

  group('formatPublishedTime', () {
    final now = DateTime(2026, 11, 7, 12, 0);

    test('今天显示 hh:mm', () {
      expect(
        formatPublishedTime(DateTime(2026, 11, 7, 9, 5), now: now),
        '09:05',
      );
    });

    test('昨天带标签', () {
      expect(
        formatPublishedTime(DateTime(2026, 11, 6, 21, 30), now: now),
        '昨天 21:30',
      );
      expect(
        formatPublishedTime(
          DateTime(2026, 11, 6, 8, 0),
          now: now,
          yesterdayLabel: 'Yesterday',
        ),
        'Yesterday 08:00',
      );
    });

    test('同年显示 MM-DD hh:mm（补零）', () {
      expect(
        formatPublishedTime(DateTime(2026, 3, 2, 8, 0), now: now),
        '03-02 08:00',
      );
    });

    test('跨年显示 yyyy-MM-DD', () {
      expect(
        formatPublishedTime(DateTime(2025, 12, 31), now: now),
        '2025-12-31',
      );
    });
  });
}
