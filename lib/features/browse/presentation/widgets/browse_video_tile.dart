/// 在线搜索结果里的 MV/视频条目卡片（「MV」tab 专用）。
///
/// 16:9 封面 + 播放角标，标题为 MV 名，副标题为「平台 · 歌手 · 清晰度 · 时长」，
/// 与其它结果 tab 的条目信息结构一致。条目只做定位（id + 平台），点击后经
/// `SongMvApi.findMv` 取可播放直链，再进既有 [SongMvPage]；取不到时给出明确
/// 提示，不静默无反应。
library;

import 'package:flutter/material.dart';

import '../../../../core/utils/formatters.dart';
import 'browse_cover.dart';
import '../../data/browse_models.dart';

class BrowseVideoTile extends StatelessWidget {
  const BrowseVideoTile({
    super.key,
    required this.video,
    required this.platformLabel,
    required this.onTap,
    this.tag,
  });

  final BrowseVideo video;
  final String platformLabel;
  final VoidCallback onTap;

  /// 可选的角落角标文案（如「MV」），为空则不画。
  final String? tag;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final subtitle = [
      platformLabel,
      if (video.artist.isNotEmpty) video.artist,
      if (video.quality != null && video.quality!.isNotEmpty)
        video.quality!.toUpperCase(),
      if (video.duration > 0)
        Formatters.formatDuration(video.duration.toDouble()),
    ].join(' · ');

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Row(
          children: [
            Stack(
              alignment: Alignment.center,
              children: [
                BrowseCover(
                  url: video.coverUrl,
                  width: 96,
                  height: 54,
                  fallbackIcon: Icons.movie_outlined,
                ),
                Container(
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.45),
                    shape: BoxShape.circle,
                  ),
                  padding: const EdgeInsets.all(4),
                  child: const Icon(
                    Icons.play_arrow_rounded,
                    size: 18,
                    color: Colors.white,
                  ),
                ),
                if (tag != null && tag!.isNotEmpty)
                  Positioned(
                    left: 4,
                    bottom: 2,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 1,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.65),
                        borderRadius: BorderRadius.circular(3),
                      ),
                      child: Text(
                        tag!,
                        style: const TextStyle(
                          fontSize: 9,
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    video.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
