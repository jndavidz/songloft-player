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

  test('唱臂落点半径：播放落沟槽环带中线，暂停长端垂直（落点略在盘缘外侧）', () {
    const size = Size(220, 220);
    const center = Offset(110, 110);
    const radius = 110.0;

    final playing =
        (VinylTonearmPainter.tipPosition(size, 1) - center).distance / radius;
    final paused =
        (VinylTonearmPainter.tipPosition(size, 0) - center).distance / radius;

    // 沟槽环带 label(0.54R) → 盘缘(1.0R)，中线约 0.77R。
    expect(playing, inInclusiveRange(0.70, 0.82));
    // 暂停姿态以「直杆（长端）垂直」为先：0.845d 的臂长在 0° 时唱针落到 1.18R，
    // 比「贴盘缘 0.99R」外移约 0.19R（≈0.09d）——支点/杆长不变时二者无法同时满足。
    expect(paused, inInclusiveRange(1.10, 1.24));

    // 长端垂直 = 暂停角 0°；两段配比 7:2；折角 30°。
    expect(VinylTonearmPainter.pausedDegrees, 0.0);
    expect(
      VinylTonearmPainter.straightLength / VinylTonearmPainter.bendLength,
      closeTo(3.5, 0.02),
    );
    expect(VinylTonearmPainter.bendDegrees, 30.0);

    // 落点都在盘心右侧（不是盘心里侧）。
    expect(VinylTonearmPainter.tipPosition(size, 1).dx, greaterThan(center.dx));
    expect(VinylTonearmPainter.tipPosition(size, 0).dx, greaterThan(center.dx));
  });
}
