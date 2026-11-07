import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:songloft_flutter/l10n/app_localizations.dart';
import 'package:songloft_flutter/shared/models/song.dart';
import 'package:songloft_flutter/shared/widgets/song_tile.dart';

Song _song({
  String type = 'remote',
  String? album,
  Map<String, dynamic>? sourceData,
  String pluginEntryPath = 'kwqq',
}) => Song(
  id: 1,
  type: type,
  title: '晴天',
  artist: '周杰伦',
  album: album,
  duration: 0,
  pluginEntryPath: pluginEntryPath,
  sourceData: sourceData,
  addedAt: DateTime(2026),
  updatedAt: DateTime(2026),
);

Future<void> _pumpTile(
  WidgetTester tester,
  Song song, {
  bool showSourceMeta = true,
}) {
  return tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        locale: const Locale('zh'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: SongTile(song: song, showSourceMeta: showSourceMeta),
        ),
      ),
    ),
  );
}

void main() {
  group('SongTile 在线来源补充信息', () {
    testWidgets('在线歌曲显示「专辑 · 平台」', (tester) async {
      await _pumpTile(
        tester,
        _song(album: '叶惠美', sourceData: {'s': 'netease'}),
      );
      await tester.pump();

      expect(find.text('叶惠美 · 网易云'), findsOneWidget);
      // 不应出现内部枚举值。
      expect(find.textContaining('netease'), findsNothing);
      expect(find.text('未知专辑'), findsNothing);
    });

    testWidgets('缺专辑时只显示平台', (tester) async {
      await _pumpTile(tester, _song(sourceData: {'s': 'kugou'}));
      await tester.pump();

      expect(find.text('酷狗'), findsOneWidget);
      expect(find.text('未知专辑'), findsNothing);
    });

    testWidgets('本地歌曲不占平台位，也不显示「未知」', (tester) async {
      await _pumpTile(tester, _song(type: 'local', pluginEntryPath: ''));
      await tester.pump();

      expect(find.text('周杰伦'), findsOneWidget);
      expect(find.textContaining('未知'), findsNothing);
      expect(find.textContaining('WebDAV'), findsNothing);
    });

    testWidgets('WebDAV 条目不显示平台位', (tester) async {
      await _pumpTile(tester, _song(pluginEntryPath: 'webdav', album: '我的专辑'));
      await tester.pump();

      expect(find.text('WebDAV'), findsNothing);
    });

    testWidgets('未开启开关时保持单行副标题', (tester) async {
      await _pumpTile(
        tester,
        _song(album: '叶惠美', sourceData: {'s': 'netease'}),
        showSourceMeta: false,
      );
      await tester.pump();

      expect(find.text('叶惠美 · 网易云'), findsNothing);
      expect(find.text('网易云'), findsNothing);
    });
  });
}
