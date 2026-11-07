import 'package:flutter_test/flutter_test.dart';
import 'package:songloft_flutter/features/browse/data/browse_models.dart';

void main() {
  group('BrowseComment 发布时间', () {
    test('create_time（Unix 秒）解析为结构化时间', () {
      final comment = BrowseComment.fromJson({
        'id': 'c1',
        'nickName': '小明',
        'comment': '好听',
        'create_time': 1700000000,
      });
      expect(
        comment.publishedAt,
        DateTime.fromMillisecondsSinceEpoch(1700000000000),
      );
      expect(comment.publishedAtText, isNull);
    });

    test('create_time 为毫秒或数字串都能识别', () {
      final millis = BrowseComment.fromJson({
        'id': 'c2',
        'comment': 'x',
        'create_time': 1700000000000,
      });
      final numericString = BrowseComment.fromJson({
        'id': 'c3',
        'comment': 'x',
        'create_time': '1700000000000',
      });
      expect(millis.publishedAt, isNotNull);
      expect(numericString.publishedAt, millis.publishedAt);
    });

    test('旧形态 createAt（毫秒）兼容', () {
      final comment = BrowseComment.fromJson({
        'id': 'c4',
        'comment': 'x',
        'createAt': 1700000000000,
      });
      expect(
        comment.publishedAt,
        DateTime.fromMillisecondsSinceEpoch(1700000000000),
      );
    });

    test('只有已格式化文本时直接采用', () {
      final comment = BrowseComment.fromJson({
        'id': 'c5',
        'comment': 'x',
        'create_time_text': ' 2024-05-01 ',
      });
      expect(comment.publishedAt, isNull);
      expect(comment.publishedAtText, '2024-05-01');

      final byTime = BrowseComment.fromJson({
        'id': 'c6',
        'comment': 'x',
        'time': '昨天 21:30',
      });
      expect(byTime.publishedAtText, '昨天 21:30');
    });

    test('结构化时间优先于文本', () {
      final comment = BrowseComment.fromJson({
        'id': 'c7',
        'comment': 'x',
        'create_time': 1700000000,
        'create_time_text': '随便写',
      });
      expect(comment.publishedAt, isNotNull);
      expect(comment.publishedAtText, isNull);
    });

    test('字段全缺失时两项都为 null（UI 整条隐藏）', () {
      final comment = BrowseComment.fromJson({'id': 'c8', 'comment': 'x'});
      expect(comment.publishedAt, isNull);
      expect(comment.publishedAtText, isNull);
    });

    test('值为 0 不产生 1970 时间', () {
      final comment = BrowseComment.fromJson({
        'id': 'c9',
        'comment': 'x',
        'create_time': 0,
      });
      expect(comment.publishedAt, isNull);
    });
  });
}
