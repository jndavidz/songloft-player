import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:songloft_flutter/features/player/presentation/widgets/song_meta_chips.dart';
import 'package:songloft_flutter/l10n/app_localizations.dart';
import 'package:songloft_flutter/shared/models/song.dart';

Song _song({
  String type = 'remote',
  int year = 0,
  int bitRate = 0,
  int sampleRate = 0,
  String pluginEntryPath = '',
  Map<String, dynamic>? sourceData,
}) {
  final now = DateTime(2026, 1, 1);
  return Song(
    id: 1,
    type: type,
    title: '晴天',
    duration: 120,
    year: year,
    bitRate: bitRate,
    sampleRate: sampleRate,
    pluginEntryPath: pluginEntryPath,
    sourceData: sourceData,
    addedAt: now,
    updatedAt: now,
  );
}

Widget _host(Song song) {
  return MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    locale: const Locale('zh'),
    home: Scaffold(body: Center(child: SongMetaChips(song: song))),
  );
}

void main() {
  testWidgets('远程歌曲展示年份、平台与码率/采样率', (tester) async {
    await tester.pumpWidget(
      _host(
        _song(
          year: 2019,
          bitRate: 320,
          sampleRate: 44100,
          sourceData: const {'source': 'kugou'},
        ),
      ),
    );
    expect(find.text('2019'), findsOneWidget);
    expect(find.text('酷狗'), findsOneWidget);
    expect(find.text('320 kbps · 44.1 kHz'), findsOneWidget);
  });

  testWidgets('远程歌曲未探测到码率时不显示数字（不臆造）', (tester) async {
    await tester.pumpWidget(_host(_song(sourceData: const {'source': 'qq'})));
    expect(find.text('QQ'), findsOneWidget);
    expect(find.textContaining('kbps'), findsNothing);
  });

  testWidgets('本地歌曲显示「本地」来源，WebDAV 插件显示 WebDAV', (tester) async {
    await tester.pumpWidget(_host(_song(type: 'local', bitRate: 1411)));
    expect(find.text('本地'), findsOneWidget);
    expect(find.textContaining('kbps'), findsOneWidget);

    await tester.pumpWidget(
      _host(_song(type: 'remote', pluginEntryPath: 'songloft-plugin-dav')),
    );
    expect(find.text('WebDAV'), findsOneWidget);
  });

  testWidgets('真实音源取 source_data.s，内部枚举不外露', (tester) async {
    await tester.pumpWidget(
      _host(
        _song(
          pluginEntryPath: 'kwqq',
          sourceData: const {'s': 'netease', 'i': '123'},
        ),
      ),
    );
    expect(find.text('网易云'), findsOneWidget);
    expect(find.text('kwqq'), findsNothing);
    expect(find.text('browse'), findsNothing);
    expect(find.text('remote'), findsNothing);
  });
}
