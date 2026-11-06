import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/color_extraction.dart';

/// Opaque, surface-based cover tints keep the whole player readable in both modes.
/// No image blur/saveLayer is needed (including on Windows).
class PlayerBackdrop extends StatelessWidget {
  final CoverPalette? palette;
  final Widget child;

  /// true = 分两块：上半播放区「顶部显色 → 向下变浅」的竖向渐变，
  /// 平滑过渡到底部控制区的近白 / 浅灰底色（[PlayerBackdropColors.control]）。
  final bool splitControl;

  const PlayerBackdrop({
    super.key,
    this.palette,
    this.splitControl = false,
    required this.child,
  });

  static PlayerBackdropColors colorsOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_BackdropScope>()?.colors ??
      PlayerBackdropColors.fromTheme(Theme.of(context));

  @override
  Widget build(BuildContext context) {
    final colors = PlayerBackdropColors.fromTheme(
      Theme.of(context),
      palette,
      splitControl,
    );
    final animated = AnimatedContainer(
      duration: const Duration(milliseconds: 500),
      curve: Curves.easeInOut,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: splitControl ? Alignment.topCenter : Alignment.topLeft,
          end: splitControl ? Alignment.bottomCenter : Alignment.bottomRight,
          colors: colors.background,
          stops: colors.stops,
        ),
      ),
      child: child,
    );
    return _BackdropScope(
      colors: colors,
      child:
          splitControl
              // 底部先铺控制区底色，渐变层叠在上面淡出到同一个颜色，接缝无硬边。
              ? Stack(
                fit: StackFit.expand,
                children: [
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 500),
                    curve: Curves.easeInOut,
                    color: colors.control,
                  ),
                  animated,
                ],
              )
              : animated,
    );
  }
}

class PlayerBackdropColors {
  final List<Color> background;
  final Color active;
  final Color secondary;

  /// 控制区（进度条 / 播放键 / 工具栏）底色：浅色主题近白，深色主题为相对更亮的浅灰。
  final Color control;

  /// 是否分块渐变（[background] 为 4 段，[stops] 与之对应）。
  final bool split;

  const PlayerBackdropColors({
    required this.background,
    required this.active,
    required this.secondary,
    this.control = Colors.transparent,
    this.split = false,
  });

  /// 分块模式的停止点：上部显色，约 2/3 处抵达控制区底色并保持到尾。
  List<double>? get stops => split ? const [0.0, 0.34, 0.66, 1.0] : null;

  factory PlayerBackdropColors.fromTheme(
    ThemeData theme, [
    CoverPalette? palette,
    bool splitControl = false,
  ]) {
    final scheme = theme.colorScheme;
    final extension = theme.extension<SongloftThemeExtension>();
    final highContrast = extension?.increaseContrast ?? false;
    final gradient = extension?.playerGradientColors;
    // Missing/loading/failed covers all use the theme, never metadata hash colors.
    final top =
        palette?.vibrantColor ??
        palette?.dominantColor ??
        gradient?.firstOrNull ??
        scheme.primary;
    final bottom =
        palette?.mutedColor ??
        palette?.vibrantColor ??
        palette?.dominantColor ??
        gradient?.lastOrNull ??
        scheme.tertiary;
    final dark = theme.brightness == Brightness.dark;
    Color tint(Color color, double opacity) =>
        Color.alphaBlend(color.withValues(alpha: opacity), scheme.surface);
    final coverOpacity = dark ? .24 : .28;
    // 分块模式的控制区底色：深色主题抬亮到「相对浅灰」，不做近黑。
    final control =
        highContrast
            ? scheme.surface
            : dark
            ? Color.alphaBlend(
              Colors.white.withValues(alpha: 0.16),
              scheme.surface,
            )
            : Color.alphaBlend(
              Colors.white.withValues(alpha: 0.95),
              scheme.surface,
            );
    final controlTinted =
        highContrast || palette == null
            ? control
            : Color.alphaBlend(
              top.withValues(alpha: dark ? .05 : .035),
              control,
            );
    final splitBackground =
        highContrast
            ? [scheme.surface, scheme.surface, scheme.surface, scheme.surface]
            : [
              // 顶部最显色，向下逐渐变浅直到等于控制区底色。
              Color.alphaBlend(
                top.withValues(alpha: dark ? .38 : .32),
                controlTinted,
              ),
              Color.lerp(
                Color.alphaBlend(
                  top.withValues(alpha: dark ? .38 : .32),
                  controlTinted,
                ),
                controlTinted,
                .55,
              )!,
              controlTinted,
              controlTinted,
            ];
    final background =
        splitControl
            ? splitBackground
            : highContrast
            ? [scheme.surface, scheme.surface]
            : [
              tint(top, palette == null ? (dark ? .18 : .12) : coverOpacity),
              tint(bottom, palette == null ? (dark ? .08 : .04) : .18),
            ];
    // Text updates immediately while AnimatedContainer can still show any prior
    // cover. The current gradient needs the full 7:1, but the 500ms transition
    // only needs to stay legible, so a both-extremes 7:1 bound would needlessly
    // neutralize every accent hue.
    final transition =
        highContrast
            ? background
            : [
              tint(Colors.black, coverOpacity),
              tint(Colors.white, coverOpacity),
            ];
    return PlayerBackdropColors(
      background: background,
      control: splitControl ? controlTinted : Colors.transparent,
      split: splitControl,
      active: _readable(
        scheme.primary,
        scheme.onSurface,
        background,
        7,
        transition: transition,
        transitionMinimum: 4.5,
      ),
      secondary: _readable(
        Color.lerp(background.first, scheme.onSurface, .68)!,
        scheme.onSurface,
        background,
        highContrast ? 7 : 4.5,
        transition: transition,
        transitionMinimum: 4.5,
      ),
    );
  }

  static double _contrast(Color a, Color b) {
    final values = [a.computeLuminance(), b.computeLuminance()]..sort();
    return (values.last + .05) / (values.first + .05);
  }

  static Color _readable(
    Color preferred,
    Color foreground,
    List<Color> backgrounds,
    double minimum, {
    List<Color> transition = const [],
    double transitionMinimum = 0,
  }) {
    bool acceptable(Color candidate) =>
        backgrounds.every((bg) => _contrast(candidate, bg) >= minimum) &&
        transition.every((bg) => _contrast(candidate, bg) >= transitionMinimum);

    if (acceptable(preferred)) return preferred;
    // Keep the accent hue: move only lightness toward black/white instead of
    // mixing into the neutral onSurface, so the active lyric stays colored.
    final base = HSLColor.fromColor(preferred);
    final darken = foreground.computeLuminance() < .5;
    for (var step = 1; step <= 20; step++) {
      final lightness =
          darken
              ? base.lightness * (1 - step / 20)
              : base.lightness + (1 - base.lightness) * step / 20;
      final candidate = base.withLightness(lightness.clamp(0.0, 1.0)).toColor();
      if (acceptable(candidate)) return candidate;
    }
    for (var step = 1; step <= 20; step++) {
      final candidate = Color.lerp(preferred, foreground, step / 20)!;
      if (acceptable(candidate)) return candidate;
    }
    // A stronger cover wash can exceed onSurface's contrast headroom.
    final extreme = darken ? Colors.black : Colors.white;
    for (var step = 1; step <= 20; step++) {
      final candidate = Color.lerp(foreground, extreme, step / 20)!;
      if (acceptable(candidate)) return candidate;
    }
    return extreme;
  }
}

class _BackdropScope extends InheritedWidget {
  final PlayerBackdropColors colors;

  const _BackdropScope({required this.colors, required super.child});

  @override
  bool updateShouldNotify(_BackdropScope oldWidget) =>
      colors != oldWidget.colors;
}
