import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:songloft_flutter/features/player/domain/lyric_parser.dart';
import 'package:songloft_flutter/features/player/presentation/providers/lyric_provider.dart';
import 'package:songloft_flutter/features/player/presentation/widgets/compact_lyrics.dart';

class _Lyrics extends LyricNotifier {
  @override
  LyricState build() => const LyricState(
    currentIndex: 0,
    lyrics: [
      LyricLine(time: Duration.zero, text: '第一行'),
      LyricLine(time: Duration(seconds: 3), text: '第二行'),
      LyricLine(time: Duration(seconds: 6), text: '第三行'),
    ],
  );

  void advance(int index) =>
      state = LyricState(currentIndex: index, lyrics: state.lyrics);
}

void main() {
  testWidgets('两行歌词窗口：首行高亮、切行时整窗上滚一行', (tester) async {
    final container = ProviderContainer(
      overrides: [lyricStateProvider.overrideWith(_Lyrics.new)],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 320,
                child: CompactLyrics(
                  activeColor: Colors.deepOrange,
                  rowHeight: 34,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 首行是正在播放的行（强调色），次行是下一行（浅灰）。
    expect(find.text('第一行'), findsOneWidget);
    expect(find.text('第二行'), findsOneWidget);
    expect(
      tester.widget<Text>(find.text('第一行')).style!.color,
      Colors.deepOrange,
    );
    expect(
      tester.widget<Text>(find.text('第二行')).style!.color,
      isNot(Colors.deepOrange),
    );

    // 换行后整窗上移恰好一行高度（不是整段滚动）。
    (container.read(lyricStateProvider.notifier) as _Lyrics).advance(1);
    await tester.pumpAndSettle();
    final transform = tester.widget<Transform>(
      find.descendant(
        of: find.byType(CompactLyrics),
        matching: find.byType(Transform),
      ),
    );
    expect(transform.transform.getTranslation().y, closeTo(-34, 0.01));
    expect(find.text('第三行'), findsOneWidget);
  });
}
