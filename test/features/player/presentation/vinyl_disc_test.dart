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

  test('暂停态：整根唱臂（杆身 + 折角段 + 唱头 + 唱针）都在盘圆之外', () {
    const size = Size(220, 220);
    const center = Offset(110, 110);
    final rDisc = VinylTonearmPainter.discRadius(size);

    // 逐点断言「臂身与盘圆不相交」：整根臂的投影（含描边两侧）都在盘圆外。
    for (final point in VinylTonearmPainter.armSamples(size, 0)) {
      expect((point - center).distance, greaterThan(rDisc));
    }

    // 唱针贴边但不压盘：尖端落在盘缘外侧一点点。
    final tip = VinylTonearmPainter.tipPosition(size, 0);
    expect((tip - center).distance / rDisc, inInclusiveRange(1.0, 1.10));

    // 长端垂直（暂停角 0°）、末端折角 30°。
    expect(VinylTonearmPainter.pausedDegrees, 0.0);
    expect(VinylTonearmPainter.bendDegrees, 30.0);

    // 支点离盘缘留出足够余量（竖直下垂才可能整根落在盘圆外）。
    final pivot = Offset(
      220 * VinylTonearmPainter.pivotFraction.dx,
      220 * VinylTonearmPainter.pivotFraction.dy,
    );
    expect((pivot - center).distance - rDisc, greaterThan(0.15 * 220));

    // 支点垂直位置不得高于盘顶（用户明确否掉「架在方形上部空角里」）。
    expect(pivot.dy, greaterThanOrEqualTo(center.dy - rDisc));
    expect(pivot.dx, greaterThan(center.dx + rDisc));
  });

  test('播放态：唱针落在 (封面半径, 盘半径) 环带内，杆身不进封面圆', () {
    const size = Size(220, 220);
    const center = Offset(110, 110);
    final rDisc = VinylTonearmPainter.discRadius(size);
    final rLabel = rDisc * VinylDisc.labelRatio;

    final tipR = (VinylTonearmPainter.tipPosition(size, 1) - center).distance;
    // 环带（0.54R → 1.00R）中线 = 0.77R。
    expect(tipR / rDisc, closeTo(0.77, 0.03));
    expect(tipR, greaterThan(rLabel));
    expect(tipR, lessThan(rDisc));

    for (final point in VinylTonearmPainter.armSamples(size, 1)) {
      expect((point - center).distance, greaterThan(rLabel));
    }
    expect(VinylTonearmPainter.playingDegrees, closeTo(13.4, 0.2));
  });

  test('唱臂是细杆：杆宽不超过盘径的 0.009，且仍可见', () {
    expect(
      VinylTonearmPainter.rodWidth,
      lessThanOrEqualTo(0.009 * VinylDisc.discScale),
    );
    expect(
      VinylTonearmPainter.rodWidth,
      greaterThanOrEqualTo(0.006 * VinylDisc.discScale),
    );
  });
}
