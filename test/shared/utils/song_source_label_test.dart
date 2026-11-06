import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:songloft_flutter/features/player/presentation/widgets/song_meta_chips.dart';
import 'package:songloft_flutter/l10n/app_localizations.dart';
import 'package:songloft_flutter/shared/models/song.dart';
import 'package:songloft_flutter/shared/utils/song_source_label.dart';

Song _song({
  String type = 'remote',
  Map<String, dynamic>? sourceData,
  String pluginEntryPath = '',
}) {
  return Song(
    id: 1,
    type: type,
    title: '半岛铁盒',
    artist: '周杰伦',
    duration: 257,
    pluginEntryPath: pluginEntryPath,
    sourceData: sourceData,
    addedAt: DateTime(2026),
    updatedAt: DateTime(2026),
  );
}

void main() {
  group('songPlatformName', () {
    test('kwqq 的 source_data.s 映射为平台中文名', () {
      expect(songPlatformName(_song(sourceData: {'s': 'qq'})), 'QQ');
      expect(songPlatformName(_song(sourceData: {'s': 'netease'})), '网易云');
      expect(songPlatformName(_song(sourceData: {'s': 'kugou'})), '酷狗');
      expect(songPlatformName(_song(sourceData: {'s': 'kuwo'})), '酷我');
      expect(songPlatformName(_song(sourceData: {'s': 'migu'})), '咪咕');
      expect(songPlatformName(_song(sourceData: {'s': 'qianqian'})), '千千');
      expect(songPlatformName(_song(sourceData: {'s': 'bilibili'})), '哔哩哔哩');
    });

    test('兼容 source_data.source 形态', () {
      expect(songPlatformName(_song(sourceData: {'source': 'QQ'})), 'QQ');
    });

    test('WebDAV 按插件入口识别', () {
      expect(songPlatformName(_song(pluginEntryPath: 'webdav')), 'WebDAV');
    });

    test('本地歌曲与未登记来源不臆造平台名', () {
      expect(songPlatformName(_song(type: 'local')), isNull);
      expect(songPlatformName(_song(sourceData: {'s': 'browse'})), isNull);
      expect(songPlatformName(_song(sourceData: {'s': 'kwqq'})), isNull);
    });
  });

  group('SongMetaChips 播放来源', () {
    testWidgets('在线歌曲显示平台名而不是内部枚举', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('zh'),
          home: Scaffold(
            body: SongMetaChips(song: _song(sourceData: {'s': 'qq'})),
          ),
        ),
      );

      expect(find.text('QQ'), findsOneWidget);
      expect(find.text('browse'), findsNothing);
      expect(find.text('kwqq'), findsNothing);
      expect(find.text('remote'), findsNothing);
      expect(find.text('在线播放'), findsNothing);
    });
  });
}
