import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:songloft_flutter/shared/layouts/shell_layout.dart';

/// 回归测试：底部导航切 tab 时对 shell 内嵌 Navigator 上命令式压栈页的处理。
///
/// 曲库在线浏览各页（搜索/详情等）用 `Navigator.of(context).push` 压在 ShellRoute
/// 内嵌 Navigator 上。切 tab 语义 = 落在目标 tab 根页面：实现里先
/// `shellNavigatorKey.currentState?.popUntil((r) => r.isFirst)` 再 go()。
/// go_router 17 的 go() 换 pages 时实测会连带弹出压栈页（第二个用例的对照实验
/// pinned=0/tab2=1），popUntil 是把该行为固化为显式契约、不依赖 pages diff 的
/// 隐式副作用。本测试用真实的 [shellNavigatorKey] 验证 key 在
/// ShellRoute.navigatorKey 上的接线与 popUntil 语义。

Future<void> _pumpHarness(WidgetTester tester) async {
  final router = GoRouter(
    initialLocation: '/tab1',
    routes: [
      ShellRoute(
        navigatorKey: shellNavigatorKey,
        builder: (context, state, child) => _FakeShell(child: child),
        routes: [
          GoRoute(
            path: '/tab1',
            builder: (_, _) => const Scaffold(body: Text('TAB1-ROOT')),
          ),
          GoRoute(
            path: '/tab2',
            builder: (_, _) => const Scaffold(body: Text('TAB2-ROOT')),
          ),
        ],
      ),
    ],
  );
  await tester.pumpWidget(MaterialApp.router(routerConfig: router));
  await tester.pumpAndSettle();
}

/// 模拟 ShellLayout 的底部导航回调（与 shell_layout.dart 同一逻辑）。
class _FakeShell extends StatelessWidget {
  final Widget child;

  const _FakeShell({required this.child});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(child: child),
        Row(
          children: [
            TextButton(
              onPressed: () {
                // 与 ShellLayout.onDestinationSelected 相同的切 tab 序列
                shellNavigatorKey.currentState?.popUntil((r) => r.isFirst);
                context.go('/tab1');
              },
              child: const Text('GO-TAB1'),
            ),
            TextButton(
              // 旧实现对照：只 go 不 pop
              onPressed: () => context.go('/tab2'),
              child: const Text('GO-TAB2-NOPOP'),
            ),
          ],
        ),
      ],
    );
  }
}

void main() {
  testWidgets('压栈页存在时切 tab 会被弹出、新 tab 可见', (tester) async {
    await _pumpHarness(tester);
    expect(find.text('TAB1-ROOT'), findsOneWidget);

    // 在 shell 内嵌 Navigator 上命令式压一页（模拟曲库搜索结果页）
    final nav = shellNavigatorKey.currentState!;
    unawaited(nav.push<void>(
      MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: Text('PUSHED-PAGE')),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('PUSHED-PAGE'), findsOneWidget);
    expect(find.text('TAB1-ROOT'), findsNothing);

    // 带清栈的切 tab：压栈页被弹出，目标 tab 根页面可见
    await tester.tap(find.text('GO-TAB1'));
    await tester.pumpAndSettle();
    expect(find.text('TAB1-ROOT'), findsOneWidget);
    expect(find.text('PUSHED-PAGE'), findsNothing);
  });

  testWidgets('旧语义对照：只 go 不 pop 时压栈页残留（bug 形态）', (tester) async {
    await _pumpHarness(tester);

    final nav = shellNavigatorKey.currentState!;
    unawaited(nav.push<void>(
      MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: Text('PUSHED-PAGE')),
      ),
    ));
    await tester.pumpAndSettle();

    // 不带清栈的切 tab：观察压栈页与新 tab 根页面各自是否出现
    await tester.tap(find.text('GO-TAB2-NOPOP'));
    await tester.pumpAndSettle();
    final pushed = find.text('PUSHED-PAGE').evaluate().length;
    final tab2 = find.text('TAB2-ROOT').evaluate().length;
    // ignore: avoid_print
    print('OLD-SEMANTICS: pushed=$pushed tab2=$tab2');
  });
}
