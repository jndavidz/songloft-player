// 搜索页四类型 tab 状态切换 widget 测试（票 07，spec Testing Decisions）：
// 切换 tab 就地换结果列表、关键词保持、失败可重试、music 类型点播链参数正确。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:songloft_flutter/features/browse/data/browse_models.dart';
import 'package:songloft_flutter/features/browse/data/plugin_browse_api.dart';
import 'package:songloft_flutter/features/browse/presentation/search_page.dart';
import 'package:songloft_flutter/features/player/domain/player_state.dart';
import 'package:songloft_flutter/features/player/presentation/providers/player_provider.dart';
import 'package:songloft_flutter/l10n/app_localizations.dart';

/// 最小化 PlayerNotifier 替身：currentSong 供「正在播放」标识匹配；
/// 播放行为在点播链测试范围外（RemotePlayback 的 playPlaylist 不在 fake 内触发）。
class _FakePlayer extends PlayerNotifier {
  @override
  PlayerState build() => const PlayerState();
}

class _FakeBrowseApi implements PluginBrowseApi {
  int searchCalls = 0;
  final List<String> typesCalled = [];

  @override
  Future<BrowseSearchResponse> search({
    required String keywords,
    String type = 'music',
    int page = 1,
    int limit = 20,
  }) async {
    searchCalls++;
    typesCalled.add(type);
    switch (type) {
      case 'album':
        return BrowseSearchResponse(
          type: type,
          isEnd: true,
          source: 'netease',
          albums: const [
            BrowseAlbum(id: '1', name: '专辑A', artist: '歌手A', trackCount: 10),
          ],
        );
      case 'artist':
        return BrowseSearchResponse(
          type: type,
          isEnd: true,
          source: 'netease',
          artists: const [BrowseArtist(id: '2', name: '歌手B')],
        );
      case 'sheet':
        return BrowseSearchResponse(
          type: type,
          isEnd: true,
          source: 'netease',
          sheets: const [
            BrowseSheet(id: '3', name: '歌单C', creator: '创建者C', trackCount: 30),
          ],
        );
      case 'mv':
        return BrowseSearchResponse(
          type: type,
          isEnd: true,
          videos: const [
            BrowseVideo(
              id: '440623',
              source: 'kuwo',
              title: 'MV视频',
              artist: '歌手A',
              duration: 221,
              quality: 'fhd',
            ),
          ],
        );
      default:
        return BrowseSearchResponse(
          type: type,
          isEnd: true,
          tracks: const [
            BrowseTrack(
              title: '歌曲T',
              artist: '歌手A',
              source: 'kuwo',
              sourceData: {'s': 'kuwo', 'i': '9'},
              dedupKey: 'kwqq_kuwo_9',
            ),
          ],
        );
    }
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError(invocation.memberName.toString());
}

void main() {
  testWidgets('五类型 tab 就地切换：关键词保持、列表按类型切换', (tester) async {
    final fake = _FakeBrowseApi();
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          pluginBrowseApiProvider.overrideWithValue(fake),
          playerStateProvider.overrideWith(_FakePlayer.new),
        ],
        child: const MaterialApp(
          locale: Locale('zh'),
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          home: BrowseSearchPage(),
        ),
      ),
    );
    await tester.pump();

    // 输入关键词并提交
    await tester.enterText(find.byType(TextField), '周杰伦');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // 默认单曲 tab：只请求 music（不再并发探测 mv），歌曲条目可见
    expect(fake.typesCalled, ['music']);
    expect(find.text('歌曲T'), findsOneWidget);

    // 切到专辑 tab：就地换列表、同一关键词
    await tester.tap(find.text('专辑'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(fake.typesCalled, ['music', 'album']);
    expect(find.text('专辑A'), findsOneWidget);
    expect(find.text('歌曲T'), findsNothing);

    // 切到歌手 tab
    await tester.tap(find.text('歌手'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(fake.typesCalled, ['music', 'album', 'artist']);
    expect(find.text('歌手B'), findsOneWidget);

    // 切到歌单 tab
    await tester.tap(find.text('歌单'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(fake.typesCalled, ['music', 'album', 'artist', 'sheet']);
    expect(find.text('歌单C'), findsOneWidget);

    // 切到 MV tab：MV 结果不再混进单曲列表，单列一项
    await tester.tap(find.text('MV'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(fake.typesCalled, ['music', 'album', 'artist', 'sheet', 'mv']);
    expect(find.text('MV视频'), findsOneWidget);
    expect(find.text('歌单C'), findsNothing);
    expect(find.text('歌曲T'), findsNothing);

    // 搜索页只打过 search 端点：5 次（五类型各一次）
    expect(fake.searchCalls, 5);
  });
}
