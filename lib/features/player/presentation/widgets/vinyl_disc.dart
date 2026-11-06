import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

/// 黑胶唱片视觉。
///
/// 分层原则（性能红线）：
/// - 盘体 / 沟槽 / 高光 / 唱臂都是**静态**层，各自 `RepaintBoundary` 缓存，不进旋转子树；
/// - 只有盘心 label（专辑封面或默认 label）参与旋转，且旋转层内部再包一层 `RepaintBoundary`，
///   使每帧只做合成层变换（`RenderTransform` + `needsCompositing`），不触发重绘；
/// - 发光/阴影一律由调用方放在本组件**之外**，绝不能进旋转子树（否则每帧重算 blur）。
///
/// 启停由 [isPlaying] 决定；[isPlaying] 应由 `activePlaybackStateProvider` 提供
/// （投屏时它是 dlna 实际状态），不要用本机 `playerStateProvider`。
/// 暂停采用指数趋近缓停（时间常数约 0.17s），不是 `stop()` 硬停；停稳后 Ticker 自行停止，
/// 不再产生任何帧。
class VinylDisc extends StatefulWidget {
  const VinylDisc({
    super.key,
    required this.isPlaying,
    required this.diameter,
    this.coverUrl,
    this.title = '',
    this.coverDecodeWidth = 512,
    this.period = const Duration(seconds: 7),
    this.showTonearm = true,
  });

  /// 是否应旋转（跟随实际发声设备的播放态）。
  final bool isPlaying;

  /// 盘体直径（label 直径为其一半）。
  final double diameter;

  /// 封面地址；为空 / 加载失败时回退到「默认黑胶盘」label。
  final String? coverUrl;

  /// 曲名，仅用于兜底 label 的首字标识。
  final String title;

  /// 封面解码宽度（按实际显示尺寸传，避免大图解码）。
  final int coverDecodeWidth;

  /// 转一圈的时长。
  final Duration period;

  /// 是否绘制唱臂。
  final bool showTonearm;

  @override
  State<VinylDisc> createState() => _VinylDiscState();
}

class _VinylDiscState extends State<VinylDisc>
    with SingleTickerProviderStateMixin {
  static const _spinReduction = 0.0025;

  final ValueNotifier<double> _angle = ValueNotifier<double>(0);
  late final Ticker _ticker;
  double _rate = 0;
  Duration? _lastElapsed;

  @override
  void initState() {
    super.initState();
    _rate = widget.isPlaying ? 1 : 0;
    _ticker = createTicker(_onTick);
    if (widget.isPlaying) _ticker.start();
  }

  @override
  void didUpdateWidget(VinylDisc oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isPlaying != oldWidget.isPlaying) {
      // 由暂停转播放：立即起转（rate 会平滑升到 1）；
      // 由播放转暂停：Ticker 继续跑到 rate 衰减为 0 再停，实现缓停。
      _lastElapsed = null;
      if (!_ticker.isActive) _ticker.start();
    }
  }

  void _onTick(Duration elapsed) {
    final last = _lastElapsed;
    _lastElapsed = elapsed;
    final dtSec =
        last == null
            ? 1 / 60
            : math.max(0, (elapsed - last).inMicroseconds) / 1000000.0;
    final target = widget.isPlaying ? 1.0 : 0.0;
    final k = 1 - math.pow(_spinReduction, dtSec).toDouble();
    _rate += (target - _rate) * k;
    if (widget.isPlaying) {
      _angle.value += _degreesFor(dtSec) * _rate;
      return;
    }
    if (_rate < 0.01) {
      _rate = 0;
      _lastElapsed = null;
      _ticker.stop();
      return;
    }
    _angle.value += _degreesFor(dtSec) * _rate;
  }

  double _degreesFor(double dtSec) {
    final periodSec = widget.period.inMilliseconds / 1000.0;
    if (periodSec <= 0) return 0;
    return 360 * dtSec / periodSec;
  }

  @override
  void dispose() {
    _ticker.dispose();
    _angle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.diameter;
    final labelSize = d * 0.5;

    return SizedBox.square(
      dimension: d,
      child: Stack(
        key: const ValueKey('vinyl-disc'),
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          // 静态盘体：一次绘制 + 缓存，不参与旋转。
          const Positioned.fill(
            child: RepaintBoundary(
              child: CustomPaint(painter: _VinylBodyPainter(labelRatio: 0.5)),
            ),
          ),
          // 旋转层：仅盘心 label（封面 / 默认 label）。
          SizedBox.square(
            dimension: labelSize,
            child: DecoratedBox(
              decoration: const BoxDecoration(shape: BoxShape.circle),
              child: ClipOval(
                child: ValueListenableBuilder<double>(
                  valueListenable: _angle,
                  builder:
                      (context, degrees, child) => Transform.rotate(
                        key: const ValueKey('vinyl-label-rotation'),
                        angle: degrees * math.pi / 180,
                        child: child,
                      ),
                  child: RepaintBoundary(
                    child: _VinylLabel(
                      coverUrl: widget.coverUrl,
                      title: widget.title,
                      coverDecodeWidth: widget.coverDecodeWidth,
                    ),
                  ),
                ),
              ),
            ),
          ),
          // 中心轴孔（静态，盖在 label 上）。
          Positioned.fill(
            child: IgnorePointer(
              child: Center(
                child: Container(
                  width: d * 0.026,
                  height: d * 0.026,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: const Color(0xFF07070A),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.22),
                      width: 1,
                    ),
                  ),
                ),
              ),
            ),
          ),
          if (widget.showTonearm)
            Positioned(
              top: -d * 0.10,
              right: -d * 0.02,
              child: IgnorePointer(
                child: SizedBox.square(
                  dimension: d * 0.58,
                  child: TweenAnimationBuilder<double>(
                    key: const ValueKey('vinyl-tonearm'),
                    tween: Tween<double>(end: widget.isPlaying ? 1 : 0),
                    duration: const Duration(milliseconds: 520),
                    curve: Curves.easeOutCubic,
                    builder:
                        (context, pose, _) => CustomPaint(
                          painter: VinylTonearmPainter(pose: pose),
                        ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// 盘心 label：默认 label（渐变 + 曲名首字）常驻底层，封面加载成功后淡入覆盖。
/// 封面为空 / 404 / 加载失败时自然停在默认 label 上，不出现灰块或音符占位图。
class _VinylLabel extends StatelessWidget {
  const _VinylLabel({
    required this.coverUrl,
    required this.title,
    required this.coverDecodeWidth,
  });

  final String? coverUrl;
  final String title;
  final int coverDecodeWidth;

  String get _initial {
    final t = title.trim();
    if (t.isEmpty) return '';
    return String.fromCharCodes(t.runes.take(1));
  }

  @override
  Widget build(BuildContext context) {
    final url = coverUrl;
    return Stack(
      fit: StackFit.expand,
      children: [
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              colors: [Color(0xFF3A3A46), Color(0xFF23232C), Color(0xFF15151B)],
              stops: [0.0, 0.55, 1.0],
            ),
          ),
        ),
        if (_initial.isNotEmpty)
          Center(
            child: Text(
              _initial,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.72),
                fontSize: coverDecodeWidth <= 0 ? 28 : 32,
                fontWeight: FontWeight.w600,
                decoration: TextDecoration.none,
              ),
            ),
          ),
        if (url != null && url.isNotEmpty)
          Image.network(
            url,
            fit: BoxFit.cover,
            cacheWidth: coverDecodeWidth > 0 ? coverDecodeWidth : null,
            gaplessPlayback: true,
            frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
              if (wasSynchronouslyLoaded) return child;
              return AnimatedOpacity(
                opacity: frame == null ? 0 : 1,
                duration: const Duration(milliseconds: 320),
                curve: Curves.easeOut,
                child: child,
              );
            },
            // 404 / 解码失败 → 留空，露出下面的默认 label。
            errorBuilder: (context, error, stack) => const SizedBox.shrink(),
          ),
        // label 内缘描边，和封面态共用同一套视觉语言。
        DecoratedBox(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.14),
              width: 1.2,
            ),
          ),
        ),
      ],
    );
  }
}

/// 盘体：同心沟槽 + 外缘导引带 + 静态高光。径向对称，本身不需要旋转。
class _VinylBodyPainter extends CustomPainter {
  const _VinylBodyPainter({required this.labelRatio});

  final double labelRatio;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final r = size.shortestSide / 2;
    final labelR = r * labelRatio;

    canvas.drawCircle(
      center,
      r,
      Paint()
        ..shader = const RadialGradient(
          colors: [
            Color(0xFF2C2C37),
            Color(0xFF17171E),
            Color(0xFF2A2A34),
            Color(0xFF0B0B10),
          ],
          stops: [0.0, 0.45, 0.72, 1.0],
        ).createShader(Rect.fromCircle(center: center, radius: r)),
    );

    // 沟槽：约 2.4px 间距，亮暗交替，模拟反射差异。
    final groovePaint = Paint()..style = PaintingStyle.stroke;
    var i = 0;
    for (var radius = labelR + 3; radius < r - 1.5; radius += 2.4, i++) {
      groovePaint
        ..color =
            i.isEven
                ? Colors.white.withValues(alpha: 0.045)
                : Colors.black.withValues(alpha: 0.18)
        ..strokeWidth = 1;
      canvas.drawCircle(center, radius, groovePaint);
    }

    // 外缘导引带（唱片最外侧的一圈亮边）。
    canvas.drawCircle(
      center,
      r - 1.5,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.2
        ..color = Colors.white.withValues(alpha: 0.10),
    );
    canvas.drawCircle(
      center,
      r - 4.5,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = Colors.black.withValues(alpha: 0.55),
    );

    // 静态高光：左上到右下的弧形反射（不随盘转动，符合真实打光）。
    final highlightRect = Rect.fromCircle(center: center, radius: r - 8);
    canvas.drawArc(
      highlightRect,
      math.pi * 1.05,
      math.pi * 0.55,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = r * 0.06
        ..strokeCap = StrokeCap.round
        ..color = Colors.white.withValues(alpha: 0.06),
    );
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: r - 10),
      math.pi * 1.55,
      math.pi * 0.28,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = r * 0.03
        ..strokeCap = StrokeCap.round
        ..color = Colors.black.withValues(alpha: 0.35),
    );
  }

  @override
  bool shouldRepaint(_VinylBodyPainter oldDelegate) =>
      oldDelegate.labelRatio != labelRatio;
}

/// 唱臂：支点在右上，播放时压到盘面，暂停时抬起更换唱片。
/// pose 0 = 抬起（暂停），1 = 落针（播放）。
@visibleForTesting
class VinylTonearmPainter extends CustomPainter {
  const VinylTonearmPainter({required this.pose});

  final double pose;

  @override
  void paint(Canvas canvas, Size size) {
    final pivot = Offset(size.width * 0.72, size.height * 0.16);
    final armLength = size.width * 0.62;
    // 基准约 -145°（左下方向），播放时再向盘心压 24°。
    final angle = -math.pi * 0.82 + pose * (math.pi * 0.135);

    canvas.save();
    canvas.translate(pivot.dx, pivot.dy);
    canvas.rotate(angle);

    // 配重（支点另一侧）
    canvas.drawCircle(
      Offset(-armLength * 0.20, 0),
      size.width * 0.045,
      Paint()..color = const Color(0xFF9AA0AA),
    );
    canvas.drawCircle(
      Offset(-armLength * 0.20, 0),
      size.width * 0.028,
      Paint()..color = const Color(0xFF4A4E57),
    );

    // 臂杆
    canvas.drawLine(
      Offset.zero,
      Offset(-armLength, 0),
      Paint()
        ..strokeWidth = size.width * 0.028
        ..strokeCap = StrokeCap.round
        ..shader = const LinearGradient(
          colors: [Color(0xFF8E939C), Color(0xFFE4E7EB)],
        ).createShader(
          Rect.fromLTWH(-armLength, 0, armLength, size.width * 0.03),
        ),
    );

    // 唱头
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset(-armLength, 0),
          width: armLength * 0.16,
          height: size.width * 0.075,
        ),
        Radius.circular(size.width * 0.018),
      ),
      Paint()..color = const Color(0xFF2A2D34),
    );
    // 唱针
    canvas.drawCircle(
      Offset(-armLength - armLength * 0.035, 0),
      size.width * 0.012,
      Paint()..color = const Color(0xFFD8DCE2),
    );

    canvas.restore();

    // 支点轴座
    canvas.drawCircle(
      pivot,
      size.width * 0.055,
      Paint()..color = const Color(0xFF1A1C22),
    );
    canvas.drawCircle(
      pivot,
      size.width * 0.042,
      Paint()..color = const Color(0xFF3C404A),
    );
    canvas.drawCircle(
      pivot,
      size.width * 0.020,
      Paint()..color = const Color(0xFF8E939C),
    );
  }

  @override
  bool shouldRepaint(VinylTonearmPainter oldDelegate) =>
      oldDelegate.pose != pose;
}
