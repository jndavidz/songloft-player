import 'package:flutter_test/flutter_test.dart';
import 'package:songloft_flutter/features/player/data/song_mv_api.dart';

void main() {
  group('MvTrack.fromJson（服务端 MV 契约）', () {
    test('聚合端点条目：duration_s + quality 解析', () {
      final mv = MvTrack.fromJson(const {
        'id': 'abc',
        'source': 'netease',
        'title': '晴天',
        'artist': '周杰伦',
        'cover': 'https://x/cover.jpg',
        'duration_s': 269,
        'url': 'https://x/mv.m3u8',
        'quality': '1080p',
      });
      expect(mv.id, 'abc');
      expect(mv.source, 'netease');
      expect(mv.durationSeconds, 269);
      expect(mv.quality, '1080p');
      expect(mv.playable, isTrue);
    });

    test('门面端点用 duration 字段名也兼容；无 url 视为不可播放', () {
      final mv = MvTrack.fromJson(const {
        'id': 'abc',
        'source': 'qq',
        'duration': 200.0,
      });
      expect(mv.durationSeconds, 200);
      expect(mv.playable, isFalse);
    });
  });
}
