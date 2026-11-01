import 'package:flutter_test/flutter_test.dart';
import 'package:songloft_flutter/config/constants.dart';
import 'package:songloft_flutter/core/utils/url_helper.dart';

void main() {
  group('resolvePlayQualityParams（音质档位路由，spec: audio-quality-routing D2/D3）', () {
    test('本地歌：任何设置档都不产生 quality 与 source_quality', () {
      for (final setting in ['original', '128', '192', '320']) {
        final params = UrlHelper.resolvePlayQualityParams(
          songType: AppConstants.songTypeLocal,
          setting: setting,
        );
        expect(params.quality, isNull, reason: 'local quality=$setting');
        expect(params.sourceQualityHint, isNull, reason: 'local hint=$setting');
      }
    });

    test('网络歌：设置档映射为 native 拼写 hint，且不再触发后端转码 quality', () {
      expect(
        UrlHelper.resolvePlayQualityParams(
          songType: AppConstants.songTypeRemote,
          setting: '320',
        ).sourceQualityHint,
        '320k',
      );
      expect(
        UrlHelper.resolvePlayQualityParams(
          songType: AppConstants.songTypeRemote,
          setting: '192',
        ).sourceQualityHint,
        '192k',
      );
      expect(
        UrlHelper.resolvePlayQualityParams(
          songType: AppConstants.songTypeRemote,
          setting: '128',
        ).sourceQualityHint,
        '128k',
      );
      final params = UrlHelper.resolvePlayQualityParams(
        songType: AppConstants.songTypeRemote,
        setting: '320',
      );
      expect(params.quality, isNull, reason: '播放链路不再请求后端转码');
    });

    test('网络歌 original：不带任何音质参数', () {
      final params = UrlHelper.resolvePlayQualityParams(
        songType: AppConstants.songTypeRemote,
        setting: 'original',
      );
      expect(params.quality, isNull);
      expect(params.sourceQualityHint, isNull);
    });

    test('电台：直播流不参与档位路由', () {
      final params = UrlHelper.resolvePlayQualityParams(
        songType: AppConstants.songTypeRadio,
        setting: '320',
      );
      expect(params.quality, isNull);
      expect(params.sourceQualityHint, isNull);
    });
  });

  group('buildSongUrl sourceQualityHint', () {
    test('hint 非空时追加 source_quality 参数', () {
      final url = UrlHelper.buildSongUrl(
        '/api/v1/songs/1/play',
        sourceQualityHint: '320k',
      );
      expect(url, contains('source_quality=320k'));
      expect(url, isNot(contains('quality=')));
    });

    test('hint 为空时不追加 source_quality（与旧版 URL 形态一致）', () {
      final url = UrlHelper.buildSongUrl('/api/v1/songs/1/play');
      expect(url, isNot(contains('source_quality=')));
    });

    test('hint 与 normalize/seek 等参数可组合', () {
      final url = UrlHelper.buildSongUrl(
        '/api/v1/songs/1/play',
        sourceQualityHint: '128k',
        normalize: true,
      );
      expect(url, contains('source_quality=128k'));
      expect(url, contains('normalize=1'));
    });
  });
}
