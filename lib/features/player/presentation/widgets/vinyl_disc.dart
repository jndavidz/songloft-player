import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

/// 黑胶唱片视觉（酷狗概念版观感）：近透明白玻璃盘体 + 封面折射 + 星光 + 极淡唱臂。
///
/// 分层原则（性能红线）：
/// - 盘体 / 沟槽 / 高光 / 星光 / 唱臂都是**静态**层，各自 `RepaintBoundary` 缓存，不进旋转子树；
/// - 旋转子树内只有「封面折射层（预烘焙纹理）」与「盘心 label」，且内部再包一层
///   `RepaintBoundary`，使每帧只做合成层变换（`RenderTransform` + `needsCompositing`），
///   不触发重绘；
/// - 封面折射的颜色来自封面：低分辨率封面在加载完成时**一次性**烘焙成「模糊 + 半透明」
///   的静态 `ui.Image`，运行时该层只做一次 `drawImageRect`，绝不每帧重算 blur；
/// - 发光/阴影一律由调用方放在本组件**之外**，绝不能进旋转子树。
///
/// 启停由 [isPlaying] 决定；[isPlaying] 应由 `activePlaybackStateProvider` 提供
/// （投屏时它是 dlna 实际状态），不要用本机 `playerStateProvider`。
/// 暂停采用指数趋近缓停（时间常数约 0.17s），不是 `stop()` 硬停；停稳后 Ticker 自行停止。
class VinylDisc extends StatefulWidget {
  const VinylDisc({
    super.key,
    required this.isPlaying,
    required this.diameter,
    this.coverUrl,
    this.title = '',
    this.coverDecodeWidth = 512,
    this.period = const Duration(seconds: 20),
    this.showTonearm = true,
    this.tintColor,
    this.refractionUrl,
    this.showSparkles = true,
  });

  /// 盘心（专辑封面）直径 / 盘体直径。
  static const double labelRatio = 0.54;

  /// 盘体直径 / 组件方形边长。
  ///
  /// 盘不再铺满整个方形：缩到 0.78 给右侧唱臂留出摆放空间（唱盘与唱臂同坐标，
  /// 盘缩了臂才有「整根退到盘外」的余量）。
  static const double discScale = 0.78;

  /// 是否应旋转（跟随实际发声设备的播放态）。
  final bool isPlaying;

  /// 盘体直径。
  final double diameter;

  /// 封面地址；为空 / 加载失败时回退到「默认黑胶盘」label。
  final String? coverUrl;

  /// 曲名，仅用于兜底 label 的首字标识。
  final String title;

  /// 封面解码宽度（按实际显示尺寸传，避免大图解码）。
  final int coverDecodeWidth;

  /// 转**一整圈**（360°）的时长。角度按累计值连续推进，暂停/恢复不重置。
  final Duration period;

  /// 是否绘制唱臂。
  final bool showTonearm;

  /// 封面主色：用于盘体薄纱折射（无折射图时的兜底色相）。
  final Color? tintColor;

  /// 低分辨率封面地址：加载后烘焙为旋转的折射纹理（无则只用 [tintColor] 兜底）。
  final String? refractionUrl;

  /// 是否绘制星光层（测试 / 低性能场景可关）。
  final bool showSparkles;

  @override
  State<VinylDisc> createState() => _VinylDiscState();
}

class _VinylDiscState extends State<VinylDisc> with TickerProviderStateMixin {
  static const _spinReduction = 0.0025;
  static const _sparklePeriod = Duration(milliseconds: 3800);

  final ValueNotifier<double> _angle = ValueNotifier<double>(0);
  late final Ticker _ticker;
  late final AnimationController _sparkle;
  double _rate = 0;
  Duration? _lastElapsed;

  ui.Image? _refraction;
  ImageStream? _refractionStream;
  ImageStreamListener? _refractionListener;

  @override
  void initState() {
    super.initState();
    _rate = widget.isPlaying ? 1 : 0;
    _ticker = createTicker(_onTick);
    if (widget.isPlaying) _ticker.start();
    // 星光：错峰明灭，整圈 3.8s 一个呼吸周期；TickerMode 关闭时自动静音。
    // 暂停态不重复（保留一个静态相位），避免页面空闲时仍在申请帧。
    _sparkle = AnimationController(vsync: this, duration: _sparklePeriod);
    if (widget.isPlaying) {
      _sparkle.repeat();
    } else {
      _sparkle.value = 0.42;
    }
    _listenRefraction();
  }

  @override
  void didUpdateWidget(VinylDisc oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isPlaying != oldWidget.isPlaying) {
      // 由暂停转播放：立即起转（rate 会平滑升到 1）；
      // 由播放转暂停：Ticker 继续跑到 rate 衰减为 0 再停，实现缓停。
      _lastElapsed = null;
      if (!_ticker.isActive) _ticker.start();
      if (widget.isPlaying) {
        _sparkle.repeat();
      } else {
        _sparkle.stop();
        _sparkle.value = 0.42;
      }
    }
    if (widget.refractionUrl != oldWidget.refractionUrl) {
      _detachRefraction();
      _refraction?.dispose();
      _refraction = null;
      _listenRefraction();
    }
  }

  void _detachRefraction() {
    final stream = _refractionStream;
    final listener = _refractionListener;
    if (stream != null && listener != null) stream.removeListener(listener);
    _refractionStream = null;
    _refractionListener = null;
  }

  void _listenRefraction() {
    final url = widget.refractionUrl;
    if (url == null || url.isEmpty) return;
    final provider = ResizeImage(NetworkImage(url), width: 96, height: 96);
    final stream = provider.resolve(ImageConfiguration.empty);
    final listener = ImageStreamListener(
      (info, _) => _bakeRefraction(info.image),
      onError:
          (error, stack) =>
              debugPrint('[VinylDisc] refraction image failed: $error'),
    );
    _refractionStream = stream;
    _refractionListener = listener;
    stream.addListener(listener);
  }

  /// 把低分辨率封面一次性烘焙成「模糊 + 半透明」纹理。
  ///
  /// 只在封面变化时执行一次；运行时该层仅做一次 `drawImageRect`，
  /// 因此旋转时不会产生任何 blur 重算。
  Future<void> _bakeRefraction(ui.Image source) async {
    try {
      const double side = 160;
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      canvas.drawImageRect(
        source,
        Rect.fromLTWH(0, 0, source.width.toDouble(), source.height.toDouble()),
        const Rect.fromLTWH(0, 0, side, side),
        Paint()
          ..imageFilter = ui.ImageFilter.blur(
            sigmaX: 14,
            sigmaY: 14,
            tileMode: TileMode.decal,
          )
          ..colorFilter = const ColorFilter.mode(
            Color(0x66FFFFFF),
            BlendMode.modulate,
          ),
      );
      final picture = recorder.endRecording();
      final baked = await picture.toImage(side.toInt(), side.toInt());
      picture.dispose();
      if (!mounted) {
        baked.dispose();
        return;
      }
      _refraction?.dispose();
      setState(() => _refraction = baked);
    } catch (error) {
      debugPrint('[VinylDisc] refraction bake failed: $error');
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
    _detachRefraction();
    _refraction?.dispose();
    _sparkle.dispose();
    _ticker.dispose();
    _angle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.diameter;
    final labelSize = d * VinylDisc.discScale * VinylDisc.labelRatio;

    return SizedBox.square(
      dimension: d,
      child: Stack(
        key: const ValueKey('vinyl-disc'),
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          // 静态盘体（近透明白玻璃 + 封面薄纱 + 沟槽 + 静态高光），不参与旋转。
          Positioned.fill(
            child: RepaintBoundary(
              child: CustomPaint(
                painter: _VinylBodyPainter(tint: widget.tintColor),
              ),
            ),
          ),
          // 星光：独立层、固定方位、不随盘转动。
          if (widget.showSparkles)
            Positioned.fill(
              child: IgnorePointer(
                child: RepaintBoundary(
                  child: CustomPaint(painter: _SparklePainter(_sparkle)),
                ),
              ),
            ),
          // 旋转层：封面折射 + 盘心 label。
          Positioned.fill(
            child: ValueListenableBuilder<double>(
              valueListenable: _angle,
              builder:
                  (context, degrees, child) => Transform.rotate(
                    key: const ValueKey('vinyl-label-rotation'),
                    angle: degrees * math.pi / 180,
                    child: child,
                  ),
              child: RepaintBoundary(
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    if (_refraction != null)
                      Positioned.fill(
                        child: CustomPaint(
                          painter: _RefractionPainter(image: _refraction!),
                        ),
                      ),
                    SizedBox.square(
                      dimension: labelSize,
                      child: ClipOval(
                        child: _VinylLabel(
                          coverUrl: widget.coverUrl,
                          title: widget.title,
                          coverDecodeWidth: widget.coverDecodeWidth,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          // 唱臂（静态层，仅姿态过渡时重绘）。
          if (widget.showTonearm)
            Positioned.fill(
              child: IgnorePointer(
                child: TweenAnimationBuilder<double>(
                  key: const ValueKey('vinyl-tonearm'),
                  tween: Tween<double>(end: widget.isPlaying ? 1 : 0),
                  duration: const Duration(milliseconds: 360),
                  curve: Curves.easeOutCubic,
                  builder:
                      (context, pose, _) =>
                          CustomPaint(painter: VinylTonearmPainter(pose: pose)),
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
              color: Colors.white.withValues(alpha: 0.30),
              width: 1.2,
            ),
          ),
        ),
      ],
    );
  }
}

/// 盘体：近透明白玻璃 + 封面主色薄纱 + 同心沟槽 + 静态高光。径向对称，不需要旋转。
class _VinylBodyPainter extends CustomPainter {
  const _VinylBodyPainter({this.tint});

  final Color? tint;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    // 盘径 = 方形边长 × discScale（与唱臂同一坐标系），封面 / 沟槽 / 星光比例同比不变。
    final r = size.shortestSide / 2 * VinylDisc.discScale;
    final labelR = r * VinylDisc.labelRatio;

    // 近透明白玻璃：几乎不压暗背景，靠极低不透明度白叠出亚克力质感。
    canvas.drawCircle(
      center,
      r,
      Paint()
        ..shader = const RadialGradient(
          colors: [
            Color(0x33FFFFFF),
            Color(0x1FFFFFFF),
            Color(0x0FFFFFFF),
            Color(0x06FFFFFF),
          ],
          stops: [0.0, 0.40, 0.74, 1.0],
        ).createShader(Rect.fromCircle(center: center, radius: r)),
    );

    // 封面主色薄纱：静态底色调，真正的「随盘转动」由旋转层折射纹理负责。
    final coverTint = tint;
    if (coverTint != null) {
      canvas.drawCircle(
        center,
        r,
        Paint()
          ..shader = RadialGradient(
            center: const Alignment(-0.56, -0.52),
            radius: 0.85,
            colors: [
              coverTint.withValues(alpha: 0.20),
              coverTint.withValues(alpha: 0.0),
            ],
          ).createShader(Rect.fromCircle(center: center, radius: r)),
      );
      canvas.drawCircle(
        center,
        r,
        Paint()
          ..shader = RadialGradient(
            center: const Alignment(0.64, 0.56),
            radius: 0.88,
            colors: [
              coverTint.withValues(alpha: 0.16),
              coverTint.withValues(alpha: 0.0),
            ],
          ).createShader(Rect.fromCircle(center: center, radius: r)),
      );
    }

    // 沟槽区整体材质：不是「深色底 + 白线」，而是整圈半透明白的亚克力雾面。
    // 以 label 外沿为起点铺白，中段最亮、接近盘缘时略收，让沟槽带本身读作白色材质。
    canvas.drawCircle(
      center,
      r,
      Paint()
        ..shader = RadialGradient(
          colors: [
            Colors.white.withValues(alpha: 0.0),
            Colors.white.withValues(alpha: 0.0),
            Colors.white.withValues(alpha: 0.10),
            Colors.white.withValues(alpha: 0.16),
            Colors.white.withValues(alpha: 0.10),
            Colors.white.withValues(alpha: 0.04),
          ],
          stops: [
            0.0,
            VinylDisc.labelRatio,
            VinylDisc.labelRatio + 0.04,
            VinylDisc.labelRatio + 0.26,
            0.90,
            1.0,
          ],
        ).createShader(Rect.fromCircle(center: center, radius: r)),
    );

    // 沟槽：在白色雾面材质上用极细的亮线 / 淡暗线撑层次，不再加高对比白线。
    final groovePaint = Paint()..style = PaintingStyle.stroke;
    var i = 0;
    for (var radius = labelR + 3; radius < r - 1.5; radius += 2.4, i++) {
      final bright = i.isEven;
      groovePaint
        ..color =
            bright
                ? Colors.white.withValues(alpha: 0.085)
                : Colors.white.withValues(alpha: 0.03)
        ..strokeWidth = bright ? 0.8 : 1.0;
      canvas.drawCircle(center, radius, groovePaint);
    }

    // 外缘导引带：参考图中最外侧的白色亮边比较明显。
    canvas.drawCircle(
      center,
      r - 1.2,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..color = Colors.white.withValues(alpha: 0.30),
    );
    canvas.drawCircle(
      center,
      r - 3.6,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = Colors.white.withValues(alpha: 0.08),
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
        ..color = Colors.white.withValues(alpha: 0.10),
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
        ..color = Colors.black.withValues(alpha: 0.06),
    );

    // 斜向玻璃反光（静态层）。
    canvas.save();
    canvas.clipPath(
      Path()..addOval(Rect.fromCircle(center: center, radius: r)),
    );
    canvas.drawRect(
      Rect.fromCircle(center: center, radius: r),
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.white.withValues(alpha: 0.12),
            Colors.white.withValues(alpha: 0.0),
            Colors.white.withValues(alpha: 0.0),
            Colors.white.withValues(alpha: 0.05),
          ],
          stops: const [0.0, 0.34, 0.64, 1.0],
        ).createShader(Rect.fromCircle(center: center, radius: r)),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_VinylBodyPainter oldDelegate) => oldDelegate.tint != tint;
}

/// 封面折射层：画进旋转子树，随盘转动把封面色块真实位移。
///
/// 纹理已在加载时预烘焙（模糊 + 半透明），此处只做一次 `drawImageRect` + 圆环裁剪；
/// 旋转由外层 `Transform` 完成，因此不会每帧重算模糊。
class _RefractionPainter extends CustomPainter {
  const _RefractionPainter({required this.image});

  final ui.Image image;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final r = size.shortestSide / 2 * VinylDisc.discScale;
    final labelR = r * VinylDisc.labelRatio;

    // 只让沟槽环带透出封面色彩（盘心由封面本身覆盖，外侧留白边）。
    final annulus =
        Path()
          ..fillType = PathFillType.evenOdd
          ..addOval(Rect.fromCircle(center: center, radius: r - 1))
          ..addOval(Rect.fromCircle(center: center, radius: labelR));
    canvas.save();
    canvas.clipPath(annulus);
    final side = r * 2.5;
    canvas.drawImageRect(
      image,
      Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
      Rect.fromCenter(center: center, width: side, height: side),
      Paint(),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_RefractionPainter oldDelegate) =>
      oldDelegate.image != image;
}

/// 星光：24 颗点状高光，各自错峰明灭（整圈不同步），位置固定不随盘转。
class _SparklePainter extends CustomPainter {
  _SparklePainter(this.progress) : super(repaint: progress);

  final Animation<double> progress;

  static const int count = 24;
  static const double periodSec = 3.8;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final r = size.shortestSide / 2 * VinylDisc.discScale;
    final t = progress.value * periodSec;

    final core = Paint();
    final halo = Paint();
    for (var i = 0; i < count; i++) {
      final angle = (i / count) * math.pi * 2 + (i % 5) * 0.31;
      final radiusFraction = (78 + (i * 17) % 42) / 131.0;
      final delay = (i * 0.23) % periodSec;
      final phase = ((t + delay) % periodSec) / periodSec;
      final opacity = _fade(phase);
      if (opacity <= 0.02) continue;
      final scale = _scale(phase);
      final offset = Offset(
        center.dx + math.cos(angle) * r * radiusFraction,
        center.dy + math.sin(angle) * r * radiusFraction,
      );
      final coreRadius = r * 0.0085 * scale;
      halo
        ..color = Colors.white.withValues(alpha: 0.16 * opacity)
        ..style = PaintingStyle.fill;
      canvas.drawCircle(offset, coreRadius * 3.0, halo);
      core
        ..color = Colors.white.withValues(alpha: 0.95 * opacity)
        ..style = PaintingStyle.fill;
      canvas.drawCircle(offset, coreRadius, core);
    }
  }

  static double _lerp(double a, double b, double t) =>
      a + (b - a) * t.clamp(0.0, 1.0);

  static double _fade(double t) {
    if (t < 0.38) return _lerp(0, 0.92, t / 0.38);
    if (t < 0.62) return _lerp(0.92, 0.35, (t - 0.38) / 0.24);
    return _lerp(0.35, 0, (t - 0.62) / 0.38);
  }

  static double _scale(double t) {
    if (t < 0.38) return _lerp(0.6, 1.0, t / 0.38);
    if (t < 0.62) return _lerp(1.0, 0.85, (t - 0.38) / 0.24);
    return _lerp(0.85, 0.6, (t - 0.62) / 0.38);
  }

  // 重绘由 [Animation] 的 Listenable 驱动，无其他状态。
  @override
  bool shouldRepaint(_SparklePainter oldDelegate) => false;
}

/// 唱臂：极细半透明杆体 + 极轻边缘阴影，支点在盘圆外侧、且垂直位置不高于盘顶。
///
/// 几何（单位 = 组件方形边长 w，见 [VinylDisc.discScale] 盘径 0.78w）：
/// - 盘顶 y = 0.110w、盘缘 x = 0.890w（盘心 (0.5w, 0.5w)、R = 0.390w）；
/// - 支点 (0.954w, 0.130w)：水平在盘圆外（离盘心 0.586w ≈ 1.50R），垂直在盘顶**以下**
///   0.020w —— 不允许再架到方形上部的空角里；
/// - 细杆：直杆 0.390w + 末端 30° 折角 0.070w，唱针到支点 0.491w；杆宽 0.0062w
///   （= 盘径的 0.008）；
/// - 暂停 0°（长端垂直）：杆身 / 折角 / 唱头 / 唱针**整根都在盘圆之外**（最近点 1.039R，
///   间隙 0.015w），唱针尖端 1.063R 贴盘缘外侧；
/// - 播放 13.4°（几何反算）：唱针落到封面圆外的沟槽环带中线 0.770R，杆身不进入封面圆。
///
/// 两个姿态只由「绕支点旋转」得到，不改杆长与支点。
@visibleForTesting
class VinylTonearmPainter extends CustomPainter {
  const VinylTonearmPainter({required this.pose});

  final double pose;

  /// 支点（相对方形边长）：盘圆右侧、垂直位置在盘顶之下 0.020w。
  ///
  /// 盘顶 y = (1 - [VinylDisc.discScale]) / 2 = 0.110；支点 y 必须 ≥ 该值，
  /// 否则又会被架到方形上部的空角里（用户明确否掉）。
  static const Offset pivotFraction = Offset(0.954, 0.130);

  /// 直杆段长（相对方形边长）。细杆的主要可视长度。
  static const double straightLength = 0.390;

  /// 末端折角段长。
  static const double bendLength = 0.070;

  /// 折角角度（度，向盘内侧）。
  static const double bendDegrees = 30.0;

  /// 唱头宽 / 高（沿杆方向）与唱针长（相对方形边长）。
  static const double headWidth = 0.030;
  static const double headHeight = 0.046;
  static const double stylusLength = 0.020;

  /// 杆宽（相对方形边长）。约等于盘径的 0.008，保持「很细的杆」的观感。
  static const double rodWidth = 0.0062;

  /// 播放 / 暂停的杆体角度（相对「竖直向下」，顺时针为正）。
  ///
  /// 暂停 = 0°：直杆（长端）垂直；播放 = 13.4°：几何反算出的最小内旋角，
  /// 唱针正好落到 (封面半径, 盘半径) 环带的中线。
  static const double playingDegrees = 13.4;
  static const double pausedDegrees = 0.0;

  /// 盘体半径（与各盘体绘制层同一坐标系）。
  @visibleForTesting
  static double discRadius(Size size) =>
      size.shortestSide / 2 * VinylDisc.discScale;

  /// 折角段末端（局部坐标：原点在支点，+y 沿杆向下）。
  static Offset _bendEnd(double w) {
    const r = bendDegrees * math.pi / 180;
    return Offset(
      -w * bendLength * math.sin(r),
      w * (straightLength + bendLength * math.cos(r)),
    );
  }

  /// 唱针落点（局部坐标）。
  static Offset _localTip(double w) {
    const r = bendDegrees * math.pi / 180;
    final reach = w * (headHeight / 2 + stylusLength);
    return _bendEnd(w) + Offset(-reach * math.sin(r), reach * math.cos(r));
  }

  /// 当前姿态下唱针落点（供测试断言「播放落环带中线、暂停贴盘缘」）。
  @visibleForTesting
  static Offset tipPosition(Size size, double pose) {
    final w = size.shortestSide;
    final pivot = Offset(w * pivotFraction.dx, w * pivotFraction.dy);
    final local = _localTip(w);
    final radians = _radians(pose);
    return pivot + _rotate(local, radians);
  }

  /// 唱臂覆盖区域的采样点（全局坐标）：杆身中线与两侧边缘、折角段、唱头四角、唱针两端。
  ///
  /// 供测试断言两条硬约束：暂停态「整根在盘圆之外」、播放态「不进封面圆」。
  @visibleForTesting
  static List<Offset> armSamples(Size size, double pose) {
    final w = size.shortestSide;
    final pivot = Offset(w * pivotFraction.dx, w * pivotFraction.dy);
    final radians = _radians(pose);
    const bendRad = bendDegrees * math.pi / 180;
    final halfRod = w * rodWidth / 2;
    final normal = Offset(math.cos(bendRad), math.sin(bendRad));
    final bendDirection = Offset(-math.sin(bendRad), math.cos(bendRad));
    final bendEnd = _bendEnd(w);

    Offset toGlobal(Offset local) => pivot + _rotate(local, radians);

    final points = <Offset>[];
    // 杆身：中线 + 两侧边缘（整根杆是描边路径，边缘即为最外侧投影）。
    const rodSteps = 24;
    for (var i = 0; i <= rodSteps; i++) {
      final y = w * straightLength * i / rodSteps;
      points
        ..add(toGlobal(Offset(0, y)))
        ..add(toGlobal(Offset(halfRod, y)))
        ..add(toGlobal(Offset(-halfRod, y)));
    }
    // 折角段：中线 + 两侧边缘。
    for (var i = 0; i <= 8; i++) {
      final base = Offset.lerp(Offset(0, w * straightLength), bendEnd, i / 8)!;
      points
        ..add(toGlobal(base))
        ..add(toGlobal(base + normal * halfRod))
        ..add(toGlobal(base - normal * halfRod));
    }
    // 唱头四角 + 唱针两端。
    for (final sh in const [-0.5, 0.5]) {
      for (final sw in const [-0.5, 0.5]) {
        points.add(
          toGlobal(
            bendEnd +
                bendDirection * (sh * w * headHeight) +
                normal * (sw * w * headWidth),
          ),
        );
      }
    }
    points
      ..add(toGlobal(bendEnd + bendDirection * (w * headHeight / 2)))
      ..add(toGlobal(_localTip(w)));
    return points;
  }

  static Offset _rotate(Offset local, double radians) => Offset(
    local.dx * math.cos(radians) - local.dy * math.sin(radians),
    local.dx * math.sin(radians) + local.dy * math.cos(radians),
  );

  static double _radians(double pose) =>
      (pausedDegrees + pose * (playingDegrees - pausedDegrees)) * math.pi / 180;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.shortestSide;
    final pivot = Offset(w * pivotFraction.dx, w * pivotFraction.dy);
    final radians = _radians(pose);

    // —— 轴座（静态层，不随杆旋转）：竖向淡白圆角夹座 + 两道卡扣细线 + 中心圆柱 ——
    // 与细杆同比例缩小；轴心即支点，座体上下各 0.060w（不把支点视觉上「抬高」）。
    final baseRect = Rect.fromCenter(
      center: pivot,
      width: w * 0.058,
      height: w * 0.120,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        baseRect.translate(w * 0.003, w * 0.004),
        Radius.circular(w * 0.0135),
      ),
      Paint()
        ..color = const Color(0xFF101820).withValues(alpha: 0.10)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, w * 0.008),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(baseRect, Radius.circular(w * 0.0135)),
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.white.withValues(alpha: 0.60),
            const Color(0xFFEDF1F6).withValues(alpha: 0.44),
            Colors.white.withValues(alpha: 0.24),
          ],
          stops: const [0.0, 0.58, 1.0],
        ).createShader(baseRect),
    );
    for (final dy in const [-0.026, 0.023]) {
      canvas.drawLine(
        Offset(pivot.dx - w * 0.018, pivot.dy + w * dy),
        Offset(pivot.dx + w * 0.018, pivot.dy + w * dy),
        Paint()
          ..color = const Color(0xFF98A2AE).withValues(alpha: 0.18)
          ..strokeWidth = w * 0.0020,
      );
    }
    canvas.drawCircle(
      pivot + Offset(0, w * 0.004),
      w * 0.0110,
      Paint()..color = Colors.white.withValues(alpha: 0.30),
    );

    // —— 杆体（随姿态旋转）：细直杆 + 末端 30° 折角，末端挂唱头与短唱针 ——
    canvas.save();
    canvas.translate(pivot.dx, pivot.dy);
    canvas.rotate(radians);

    const bendRad = bendDegrees * math.pi / 180;
    final bendEnd = _bendEnd(w);
    final rodPath =
        Path()
          ..moveTo(0, -w * 0.012)
          ..lineTo(0, w * straightLength)
          ..lineTo(bendEnd.dx, bendEnd.dy);

    // 投影：极轻的一点落感，不做高反差投影。
    canvas.drawPath(
      rodPath.shift(Offset(w * 0.0025, w * 0.004)),
      Paint()
        ..color = const Color(0xFF101820).withValues(alpha: 0.10)
        ..strokeWidth = w * rodWidth
        ..strokeCap = StrokeCap.round
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, w * 0.005),
    );
    // 杆体：低对比半透明白（左亮右淡），不用纯白 → 浅灰的高反差渐变。
    canvas.drawPath(
      rodPath,
      Paint()
        ..strokeWidth = w * rodWidth
        ..strokeCap = StrokeCap.round
        ..shader = LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [
            Colors.white.withValues(alpha: 0.66),
            Colors.white.withValues(alpha: 0.50),
            const Color(0xFFE6EBF2).withValues(alpha: 0.32),
          ],
          stops: const [0.0, 0.5, 1.0],
        ).createShader(
          Rect.fromLTRB(
            -w * rodWidth / 2,
            0,
            w * rodWidth / 2,
            w * (straightLength + bendLength),
          ),
        ),
    );

    // 唱头：沿折角方向的短圆角块 + 探出的极短唱针。
    canvas.save();
    canvas.translate(bendEnd.dx, bendEnd.dy);
    canvas.rotate(bendRad);
    final headRect = Rect.fromCenter(
      center: Offset.zero,
      width: w * headWidth,
      height: w * headHeight,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        headRect.translate(w * 0.0025, w * 0.004),
        Radius.circular(w * 0.008),
      ),
      Paint()
        ..color = const Color(0xFF101820).withValues(alpha: 0.10)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, w * 0.006),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(headRect, Radius.circular(w * 0.008)),
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.white.withValues(alpha: 0.62),
            Colors.white.withValues(alpha: 0.42),
            const Color(0xFFD8DEE7).withValues(alpha: 0.26),
          ],
          stops: const [0.0, 0.6, 1.0],
        ).createShader(headRect),
    );
    canvas.drawLine(
      Offset(0, w * headHeight / 2),
      Offset(0, w * (headHeight / 2 + stylusLength)),
      Paint()
        ..color = const Color(0xFF8E959F).withValues(alpha: 0.40)
        ..strokeWidth = w * 0.0020
        ..strokeCap = StrokeCap.round,
    );
    canvas.restore();
    canvas.restore();
  }

  @override
  bool shouldRepaint(VinylTonearmPainter oldDelegate) =>
      oldDelegate.pose != pose;
}
