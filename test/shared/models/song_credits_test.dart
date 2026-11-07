import 'package:flutter_test/flutter_test.dart';
import 'package:songloft_flutter/shared/models/song.dart';

Song _songFromJson(Map<String, dynamic> extra) => Song.fromJson({
  'id': 1,
  'type': 'remote',
  'title': '晴天',
  'duration': 0,
  'added_at': '2026-01-01T00:00:00Z',
  'updated_at': '2026-01-01T00:00:00Z',
  ...extra,
});

void main() {
  group('SongCredits', () {
    test('顶层 credits 解析并保留多值', () {
      final song = _songFromJson({
        'credits': {
          'lyricist': ['方文山', '周杰伦'],
          'composer': ['周杰伦'],
          'arranger': ['钟兴民', '洪敬尧'],
        },
      });
      expect(song.credits, isNotNull);
      expect(song.credits!.lyricist, ['方文山', '周杰伦']);
      expect(song.credits!.composer, ['周杰伦']);
      expect(song.credits!.arranger, ['钟兴民', '洪敬尧']);
    });

    test('插件写在 source_data（JSON 字符串）里的 credits 也能读到', () {
      final song = _songFromJson({
        'source_data':
            '{"s":"netease","credits":'
            '{"lyricist":["方文山"],"composer":["周杰伦"]}}',
      });
      expect(song.credits!.lyricist, ['方文山']);
      expect(song.credits!.composer, ['周杰伦']);
      expect(song.credits!.arranger, isEmpty);
    });

    test('缺字段 / 空数组 → 对应列表为空，整块视为无数据', () {
      final song = _songFromJson({
        'credits': {'lyricist': [], 'composer': <String>[], 'arranger': []},
      });
      expect(song.credits, isNull);

      final partial = SongCredits.tryParse({
        'lyricist': ['方文山'],
      });
      expect(partial!.lyricist, ['方文山']);
      expect(partial.composer, isEmpty);
      expect(partial.arranger, isEmpty);
    });

    test('单值字符串与空白值容错', () {
      final credits = SongCredits.tryParse({
        'lyricist': ' 方文山 ',
        'composer': ['', '  '],
      });
      expect(credits!.lyricist, ['方文山']);
      expect(credits.composer, isEmpty);
    });

    test('无 credits 字段时为 null', () {
      final song = _songFromJson({});
      expect(song.credits, isNull);
    });
  });
}
