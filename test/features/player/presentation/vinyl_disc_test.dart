import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:songloft_flutter/features/player/presentation/widgets/vinyl_disc.dart';

Widget _host(bool isPlaying, {String? coverUrl, String title = '晴天'}) {
  return MaterialApp(
    home: Scaffold(
      body: Center(
        child: VinylDisc(
          isPlaying: isPlaying,
          diameter: 220,
          coverUrl: coverUrl,
          title: title,
          period: const Duration(seconds: 4),
        ),
      ),
    ),
  );
}

/// 盘心旋转角度（弧度），从 Transform 矩阵取 cos/sin。
double _angleOf(WidgetTester tester) {
  final transform = tester.widget<Transform>(
    find.byKey(const ValueKey('vinyl-label-rotation')),
  );
  final storage = transform.transform.storage;
  return math.atan2(storage[1], storage[0]);
}

double _armPose(WidgetTester tester) {
  final paint = tester.widget<CustomPaint>(
    find.descendant(
      of: find.byKey(const ValueKey('vinyl-tonearm')),
      matching: find.byType(CustomPaint),
    ),
  );
  return (paint.painter! as VinylTonearmPainter).pose;
}

void main() {
  testWidgets('播放中盘心持续转动', (tester) async {
    await tester.pumpWidget(_host(true));
    expect(find.byKey(const ValueKey('vinyl-disc')), findsOneWidget);

    final a1 = _angleOf(tester);
    await tester.pump(const Duration(milliseconds: 400));
    final a2 = _angleOf(tester);
    expect(a2, isNot(closeTo(a1, 1e-6)));
  });

  testWidgets('暂停是缓停而不是硬停，停稳后 Ticker 自行停止', (tester) async {
    await tester.pumpWidget(_host(true));
    await tester.pump(const Duration(milliseconds: 400));

    // 切到暂停：仍在惯性转动（缓停）。
    await tester.pumpWidget(_host(false));
    final a1 = _angleOf(tester);
    await tester.pump(const Duration(milliseconds: 120));
    final a2 = _angleOf(tester);
    expect(a2, isNot(closeTo(a1, 1e-6)));

    // 衰减到 0 后不再申请帧，避免后台空转耗电。
    await tester.pump(const Duration(seconds: 2));
    expect(tester.binding.transientCallbackCount, 0);
  });

  testWidgets('暂停态重新播放会从当前角度继续转', (tester) async {
    await tester.pumpWidget(_host(true));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpWidget(_host(false));
    await tester.pump(const Duration(seconds: 2));
    final paused = _angleOf(tester);

    await tester.pumpWidget(_host(true));
    await tester.pump(const Duration(milliseconds: 400));
    expect(_angleOf(tester), isNot(closeTo(paused, 1e-6)));
  });

  testWidgets('无封面时回退默认黑胶盘（曲名首字 label）', (tester) async {
    await tester.pumpWidget(_host(false, title: '晴天'));
    expect(find.text('晴'), findsOneWidget);
  });

  testWidgets('唱臂姿态跟随播放态：播放落针、暂停抬起', (tester) async {
    await tester.pumpWidget(_host(true));
    await tester.pump(const Duration(milliseconds: 600));
    expect(_armPose(tester), closeTo(1.0, 1e-6));

    await tester.pumpWidget(_host(false));
    await tester.pump(const Duration(milliseconds: 600));
    expect(_armPose(tester), closeTo(0.0, 1e-6));
  });
}
