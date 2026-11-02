/// 浏览页统一封面/头像组件：统一走 NetworkCoverImage（铁律：禁止裸 Image.network，
/// Web CanvasKit GPU 显存陷阱）+ 主题化占位色 + 可选回退图标；支持圆形（歌手/评论头像）。
library;

import 'package:flutter/material.dart';

import '../../../../core/theme/app_dimensions.dart';
import '../../../../shared/widgets/network_cover_image.dart';

class BrowseCover extends StatelessWidget {
  final String? url;
  final double size;

  /// 卡片式封面可传 null 让其随父约束撑满（榜单/歌单网格）。
  final double? width;
  final double? height;
  final BorderRadius? borderRadius;

  /// true = 圆形裁剪（歌手头像/评论头像）。
  final bool circle;
  final IconData fallbackIcon;

  const BrowseCover({
    super.key,
    required this.url,
    this.size = 48,
    this.width,
    this.height,
    this.borderRadius,
    this.circle = false,
    this.fallbackIcon = Icons.music_note_outlined,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final w = width ?? size;
    final h = height ?? size;
    final radius =
        borderRadius ?? BorderRadius.circular(circle ? w / 2 : AppSpacing.xs);

    Widget placeholder() => Container(
      width: w,
      height: h,
      color: scheme.surfaceContainerHighest,
      child:
          circle
              ? Icon(fallbackIcon, size: w * 0.5)
              : Icon(fallbackIcon, size: 22),
    );

    Widget child;
    if (url != null && url!.isNotEmpty) {
      child = NetworkCoverImage(
        imageUrl: url!,
        width: w,
        height: h,
        errorWidget: (_, _, _) => placeholder(),
      );
    } else {
      child = placeholder();
    }

    if (circle) {
      return ClipOval(child: child);
    }
    return ClipRRect(borderRadius: radius, child: child);
  }
}
