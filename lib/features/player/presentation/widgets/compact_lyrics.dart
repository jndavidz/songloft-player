import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/lyric_provider.dart';
import 'karaoke_line.dart';

/// 唱盘下方的常驻两行歌词窗口（酷狗概念版观感）：
/// - 首行为当前正在播放的行，复用 [KaraokeLine] 做逐字渐变（已唱字渐变到 [activeColor]）；
/// - 次行为下一行，浅灰；
/// - 当前行切换时**整窗上滚一行**（两行固定窗口，逐行上移，不是整段滚动）。
///
/// 进度来源是 [lyricStateProvider]，其时间轴跟随 `activePlaybackStateProvider`，
/// 因此投屏态下也按设备实际进度滚动。
class CompactLyrics extends ConsumerWidget {
  const CompactLyrics({
    super.key,
    this.activeColor,
    this.rowHeight = 34,
    this.fontSize = 15,
  });

  /// 已唱字的目标色（封面同色系、更浅）。
  final Color? activeColor;

  /// 每行高度（两行窗口 = 2 倍）。
  final double rowHeight;

  /// 字号。
  final double fontSize;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final state = ref.watch(lyricStateProvider);
    final idle = theme.colorScheme.onSurface.withValues(alpha: 0.55);
    final active = activeColor ?? theme.colorScheme.primary;
    final height = rowHeight * 2;

    if (!state.hasLyrics) {
      // 无歌词也占位，避免盘面随歌词到位而跳动。
      return SizedBox(height: height, width: double.infinity);
    }

    // 纯文本歌词没有时间轴：不逐字、不滚动，固定展示开头两行。
    final index = state.synced ? math.max(0, state.currentIndex) : 0;

    final rows = <Widget>[];
    for (var i = 0; i < state.lyrics.length; i++) {
      final line = state.lyrics[i];
      final isCurrent = i == index;
      rows.add(
        SizedBox(
          height: rowHeight,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Center(
              child:
                  isCurrent
                      ? (line.hasWords && state.synced
                          ? KaraokeLine(
                            key: ValueKey('compact-karaoke-$i'),
                            line: line,
                            activeColor: active,
                            inactiveColor: idle,
                            fontSize: fontSize,
                            fontWeight: FontWeight.w500,
                            maxLines: 1,
                            height: 1.2,
                          )
                          : Text(
                            line.text,
                            style: TextStyle(
                              fontSize: fontSize,
                              fontWeight: FontWeight.w500,
                              color: active,
                              height: 1.2,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                          ))
                      : Text(
                        line.text,
                        style: TextStyle(
                          fontSize: fontSize,
                          fontWeight: FontWeight.w400,
                          color: idle,
                          height: 1.2,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                      ),
            ),
          ),
        ),
      );
    }

    return SizedBox(
      height: height,
      width: double.infinity,
      child: ClipRect(
        child: OverflowBox(
          alignment: Alignment.topCenter,
          minHeight: 0,
          maxHeight: double.infinity,
          child: TweenAnimationBuilder<double>(
            tween: Tween<double>(end: index * rowHeight),
            duration: const Duration(milliseconds: 420),
            curve: Curves.easeOutCubic,
            builder:
                (context, offset, child) => Transform.translate(
                  offset: Offset(0, -offset),
                  child: child,
                ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: rows,
            ),
          ),
        ),
      ),
    );
  }
}
