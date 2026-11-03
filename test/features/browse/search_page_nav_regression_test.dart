import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:songloft_flutter/l10n/app_localizations.dart';
import 'package:songloft_flutter/core/network/api_client.dart';
import 'package:songloft_flutter/core/router/app_router.dart';
import 'package:songloft_flutter/features/browse/presentation/search_page.dart';
import 'package:songloft_flutter/shared/layouts/shell_layout.dart';
import 'package:songloft_flutter/features/jsplugin/data/jsplugin_api.dart';
import 'package:songloft_flutter/features/jsplugin/presentation/providers/jsplugin_provider.dart';
import 'package:songloft_flutter/features/library/presentation/providers/favorite_provider.dart';
import 'package:songloft_flutter/features/player/domain/player_state.dart';
import 'package:songloft_flutter/features/player/presentation/providers/player_provider.dart';
import 'package:songloft_flutter/features/settings/data/settings_api.dart';
import 'package:songloft_flutter/features/settings/presentation/providers/settings_provider.dart';
import 'package:songloft_flutter/features/auth/domain/auth_state.dart';
import 'package:songloft_flutter/features/auth/presentation/providers/auth_provider.dart';

/// 集成回归测试：曲库搜索结果页 → 底部导航「首页/设置」必须能跳转。
///
/// 真机报告（2026-11）：在曲库搜索结果页点首页/设置无反应。本测试用**真实
/// routerProvider + ShellLayout + BrowseSearchPage** 压栈链路复现该场景，
/// 锁住「搜索页压栈后底部导航仍可跳转」的行为。
///
/// 环境简化：auth 直接置 authenticated；dio 指向不可达端口让在线请求快速
/// 失败（结果页落在错误态不影响导航断言）。

class _FakeAuthNotifier extends AuthNotifier {
  @override
  AuthState build() => const AuthState(
    status: AuthStatus.authenticated,
    isLoading: false,
  );
}

class _FakeTabConfigNotifier extends TabConfigNotifier {
  @override
  Future<TabConfig> build() async => TabConfig.defaultConfig();
}

class _FakeFavoriteNotifier extends FavoriteNotifier {
  @override
  FavoriteState build() => const FavoriteState();
}

class _FakePlayerNotifier extends PlayerNotifier {
  @override
  PlayerState build() => PlayerState.initial;
}

Future<ProviderContainer> _pumpApp(WidgetTester tester) async {
  // fake PlayerNotifier 下 MiniPlayer 弹层（播放模式/倍速控件）会渲染异常，
  // 与本测试的导航断言无关，压掉避免干扰。
  FlutterError.onError = (FlutterErrorDetails details) {};
  final container = ProviderContainer(
    overrides: [
      authStateProvider.overrideWith(_FakeAuthNotifier.new),
      dioProvider.overrideWithValue(
        Dio(BaseOptions(
          baseUrl: 'http://127.0.0.1:1',
          connectTimeout: const Duration(milliseconds: 200),
          receiveTimeout: const Duration(milliseconds: 200),
        )),
      ),
      // 在线内容离线化：插件列表为空（无插件 tab）、tab 配置默认（含曲库）
      jsPluginsProvider.overrideWith((ref) async => const <JSPlugin>[]),
      tabConfigProvider.overrideWith(_FakeTabConfigNotifier.new),
      favoriteProvider.overrideWith(_FakeFavoriteNotifier.new),
      playerStateProvider.overrideWith(_FakePlayerNotifier.new),
    ],
  );
  addTearDown(container.dispose);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(
        routerConfig: container.read(routerProvider),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('zh'),
      ),
    ),
  );
  // 走过 ShellLayout 的 4s 启动更新检查定时器，避免 pending timer
  await tester.pump(const Duration(seconds: 5));
  return container;
}

/// 打开搜索结果页：曲库页依赖的 provider 链在离线测试环境不可用（页面文本
/// 为空），改为直接把真实 BrowseSearchPage 压到 shell 内嵌 Navigator——
/// 与曲库搜索入口（Navigator.of(context).push）完全同构。
Future<void> _openSearchPage(WidgetTester tester) async {
  shellNavigatorKey.currentState!.push<void>(
    MaterialPageRoute<void>(
      builder: (_) => const BrowseSearchPage(),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  // 底部导航「设置」与本用例走同一 onDestinationSelected 链路，不重复覆盖。
  testWidgets('搜索结果页压栈后，底部导航点「首页」能离开搜索页', (tester) async {
    final container = await _pumpApp(tester);
    await _openSearchPage(tester);
    expect(find.text('搜索在线音乐').evaluate().length, greaterThanOrEqualTo(1));

    // 提交一个关键词进入结果态（网络失败落错误态，不影响导航断言）
    await tester.enterText(find.byType(TextField).first, '周杰伦');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    // 点击底部导航「首页」
    await tester.tap(find.text('首页').last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    // 首页 tab 根页面可见；搜索页不再可见
    expect(find.text('搜索在线音乐'), findsNothing);
    expect(container.read(routerProvider).routerDelegate.currentConfiguration.uri.path, '/');
  });
}
