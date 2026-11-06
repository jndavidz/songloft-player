import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:songloft_flutter/l10n/app_localizations.dart';
import 'package:songloft_flutter/features/player/domain/lyric_parser.dart';
import 'package:songloft_flutter/features/player/domain/player_state.dart';
import 'package:songloft_flutter/features/player/presentation/providers/lyric_provider.dart';
import 'package:songloft_flutter/features/player/presentation/providers/player_provider.dart';
import 'package:songloft_flutter/features/player/presentation/widgets/lyrics_view.dart';

const _state = LyricState(
  lyrics: [
    LyricLine(time: Duration.zero, text: 'L0'),
    LyricLine(time: Duration(seconds: 10), text: 'L1'),
    LyricLine(time: Duration(seconds: 20), text: 'L2'),
    LyricLine(time: Duration(seconds: 30), text: 'L3'),
    LyricLine(time: Duration(seconds: 40), text: 'L4'),
  ],
);

/// 跳过真实网络加载，直接暴露固定歌词。
class _FakeLyricNotifier extends LyricNotifier {
  @override
  LyricState build() => _state;
}

/// 跳过音频 handler 初始化，仅暴露播放态。
class _FakePlayerNotifier extends PlayerNotifier {
  @override
  PlayerState build() => const PlayerState(isPlaying: false);
}

Widget _host({
  required List<Duration> seeked,
  VoidCallback? onBackground,
  bool scrubEnabled = true,
}) {
  return ProviderScope(
    overrides: [
      lyricStateProvider.overrideWith(_FakeLyricNotifier.new),
      playerStateProvider.overrideWith(_FakePlayerNotifier.new),
    ],
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('zh'),
      home: Scaffold(
        body: SizedBox(
          width: 360,
          height: 560,
          child: LyricsView(
            currentPosition: Duration.zero,
            onSeek: seeked.add,
            scrubEnabled: scrubEnabled,
            onTapBackground: onBackground,
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('点击歌词行按行时间 seek', (tester) async {
    final seeked = <Duration>[];
    await tester.pumpWidget(_host(seeked: seeked));
    await tester.tap(find.text('L3'));
    await tester.pump();
    expect(seeked.single, const Duration(seconds: 30));
  });

  testWidgets('长按歌词并拖动，松手 seek 到目标行时间', (tester) async {
    final seeked = <Duration>[];
    await tester.pumpWidget(_host(seeked: seeked));
    final gesture = await tester.startGesture(
      tester.getCenter(find.text('L2')),
    );

    // 长按成立后才开始拖拽（与列表滚动的手势竞技场不冲突）。
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('0:20'), findsOneWidget);
    await gesture.up();
    await tester.pump();

    expect(seeked.single, const Duration(seconds: 20));
  });

  testWidgets('长按后向下拖动会落到更后面的行', (tester) async {
    final seeked = <Duration>[];
    await tester.pumpWidget(_host(seeked: seeked));
    final gesture = await tester.startGesture(
      tester.getCenter(find.text('L1')),
    );
    await tester.pump(const Duration(milliseconds: 600));
    await gesture.moveBy(const Offset(0, 96)); // 两行 ≈ 2 * 48
    await tester.pump();
    expect(find.text('0:30'), findsOneWidget);
    await gesture.up();
    await tester.pump();
    expect(seeked.single, const Duration(seconds: 30));
  });

  testWidgets('scrubEnabled=false（电台/无时长）时长按不出现拖拽浮层', (tester) async {
    final seeked = <Duration>[];
    await tester.pumpWidget(_host(seeked: seeked, scrubEnabled: false));
    final gesture = await tester.startGesture(
      tester.getCenter(find.text('L2')),
    );
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('0:20'), findsNothing);
    await gesture.up();
    await tester.pump();
    // 长按未启用拖拽，松手仍按行点击 seek。
    expect(seeked.single, const Duration(seconds: 20));
  });

  testWidgets('点击歌词空白区触发返回封面回调', (tester) async {
    var taps = 0;
    final seeked = <Duration>[];
    await tester.pumpWidget(_host(seeked: seeked, onBackground: () => taps++));
    await tester.tapAt(const Offset(180, 540));
    await tester.pump();
    expect(taps, 1);
    expect(seeked, isEmpty);
  });
}
