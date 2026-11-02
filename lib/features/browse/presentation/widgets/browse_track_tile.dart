/// 在线曲目列表条目：曲序号/封面 + 标题/歌手/专辑 + 来源标注 + 正在播放标识。
///
/// 整张列表的播放统一走 [onPlay]（RemotePlayback.importAndPlay），
/// 本组件不持有任何播放状态。

library;

import 'package:flutter/material.dart';

import '../../../../l10n/app_localizations.dart';
import '../../../../shared/widgets/network_cover_image.dart';
import '../../data/browse_models.dart';

class BrowseTrackTile extends StatelessWidget {
  final BrowseTrack track;
  final int index;

  /// 传入即显示曲序号（专辑页官方曲序）。
  final bool showTrackNo;

  /// 是否显示来源平台标注（多源聚合列表开）。
  final bool showSource;

  final bool isCurrent;
  final VoidCallback? onTap;
  final VoidCallback? onAddToPlaylist;

  const BrowseTrackTile({
    super.key,
    required this.track,
    required this.index,
    this.showTrackNo = false,
    this.showSource = false,
    this.isCurrent = false,
    this.onTap,
    this.onAddToPlaylist,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final subtitle = [
      if (track.artist.isNotEmpty) track.artist,
      if (track.album != null && track.album!.isNotEmpty) track.album!,
      if (showSource && track.source != null) track.source!,
    ].join(' · ');
    final primaryColor = theme.colorScheme.primary;

    return ListTile(
      leading:
          showTrackNo && track.trackNo != null
              ? SizedBox(
                width: 40,
                child: Text(
                  '${track.trackNo}',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color:
                        isCurrent
                            ? primaryColor
                            : theme.colorScheme.onSurfaceVariant,
                  ),
                  textAlign: TextAlign.center,
                ),
              )
              : SizedBox(
                width: 44,
                height: 44,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child:
                      track.coverUrl != null && track.coverUrl!.isNotEmpty
                          ? NetworkCoverImage(
                            imageUrl: track.coverUrl!,
                            width: 44,
                            height: 44,
                          )
                          : const ColoredBox(color: Color(0x1A808080)),
                ),
              ),
      title: Text(
        track.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.bodyLarge?.copyWith(
          color: isCurrent ? primaryColor : null,
        ),
      ),
      subtitle:
          subtitle.isEmpty
              ? null
              : Text(
                subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isCurrent)
            Icon(Icons.graphic_eq, size: 16, color: primaryColor)
          else if (track.duration > 0)
            Text(
              _formatDuration(track.duration),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          if (onAddToPlaylist != null)
            IconButton(
              icon: const Icon(Icons.playlist_add, size: 20),
              tooltip: l10n.browseAddToPlaylist,
              onPressed: onAddToPlaylist,
            ),
        ],
      ),
      onTap: track.isPlayable ? onTap : null,
    );
  }

  static String _formatDuration(int seconds) {
    final m = seconds ~/ 60;
    final s = seconds % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }
}
