/// 在线曲目列表条目：曲序号/封面 + 标题/歌手/专辑 + 来源标注 + 正在播放标识。
///
/// 整张列表的播放统一走 [onPlay]（RemotePlayback.importAndPlay），
/// 本组件不持有任何播放状态。专辑名可点（[onAlbumTap]）跳专辑详情。

library;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../../../l10n/app_localizations.dart';
import '../../data/browse_models.dart';
import 'browse_cover.dart';

class BrowseTrackTile extends StatefulWidget {
  final BrowseTrack track;
  final int index;

  /// 传入即显示曲序号（专辑页官方曲序）。
  final bool showTrackNo;

  /// 是否显示来源平台标注（多源聚合列表开）。
  final bool showSource;

  final bool isCurrent;
  final VoidCallback? onTap;

  /// 专辑名点击（进专辑详情）；null 时专辑为纯文本。
  final VoidCallback? onAlbumTap;
  final VoidCallback? onAddToPlaylist;

  const BrowseTrackTile({
    super.key,
    required this.track,
    required this.index,
    this.showTrackNo = false,
    this.showSource = false,
    this.isCurrent = false,
    this.onTap,
    this.onAlbumTap,
    this.onAddToPlaylist,
  });

  @override
  State<BrowseTrackTile> createState() => _BrowseTrackTileState();
}

class _BrowseTrackTileState extends State<BrowseTrackTile> {
  TapGestureRecognizer? _albumRecognizer;

  @override
  void dispose() {
    _albumRecognizer?.dispose();
    super.dispose();
  }

  TapGestureRecognizer? _buildAlbumRecognizer(VoidCallback? onAlbumTap) {
    if (onAlbumTap == null) return null;
    // 列表项复用时闭包随 build 变化（索引/曲目更新），每次重建都要重挂。
    final r = _albumRecognizer ??= TapGestureRecognizer();
    r.onTap = onAlbumTap;
    return r;
  }

  @override
  Widget build(BuildContext context) {
    final track = widget.track;
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final hasAlbum = track.album != null && track.album!.isNotEmpty;
    final showSource = widget.showSource && track.source != null;
    final subtitleStyle = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final primaryColor = theme.colorScheme.primary;

    // 副标题：歌手 · 专辑(可点) · 平台。用 RichText 才能只在专辑名上挂点击。
    final spans = <InlineSpan>[
      if (track.artist.isNotEmpty) TextSpan(text: track.artist),
      if (hasAlbum) ...[
        if (track.artist.isNotEmpty) const TextSpan(text: ' · '),
        TextSpan(
          text: track.album!,
          recognizer: _buildAlbumRecognizer(widget.onAlbumTap),
          style:
              widget.onAlbumTap == null
                  ? null
                  : TextStyle(
                    color: primaryColor,
                    decoration: TextDecoration.underline,
                    decorationColor: primaryColor.withValues(alpha: 0.5),
                  ),
        ),
      ],
      if (showSource) ...[
        if (track.artist.isNotEmpty || hasAlbum) const TextSpan(text: ' · '),
        TextSpan(text: browsePlatformLabel(track.source)),
      ],
    ];

    return ListTile(
      leading:
          widget.showTrackNo && track.trackNo != null
              ? SizedBox(
                width: 40,
                child: Text(
                  '${track.trackNo}',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color:
                        widget.isCurrent
                            ? primaryColor
                            : theme.colorScheme.onSurfaceVariant,
                  ),
                  textAlign: TextAlign.center,
                ),
              )
              : BrowseCover(url: track.coverUrl, size: 44),
      title: Text(
        track.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.bodyLarge?.copyWith(
          color: widget.isCurrent ? primaryColor : null,
        ),
      ),
      subtitle:
          spans.isEmpty
              ? null
              : RichText(
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                text: TextSpan(
                  style: subtitleStyle,
                  children: spans,
                ),
              ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (widget.isCurrent)
            Icon(Icons.graphic_eq, size: 16, color: primaryColor)
          else if (track.duration > 0)
            Text(
              _formatDuration(track.duration),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          if (widget.onAddToPlaylist != null)
            IconButton(
              icon: const Icon(Icons.playlist_add, size: 20),
              tooltip: l10n.browseAddToPlaylist,
              onPressed: widget.onAddToPlaylist,
            ),
        ],
      ),
      onTap: track.isPlayable ? widget.onTap : null,
    );
  }

  static String _formatDuration(int seconds) {
    final m = seconds ~/ 60;
    final s = seconds % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }
}
