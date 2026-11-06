import 'package:flutter/material.dart';

import '../../../../l10n/app_localizations.dart';
import '../../../../shared/models/song.dart';
import '../../../../shared/utils/song_source_label.dart';

/// 单曲播放页的附加信息胶囊：年份 / 播放来源 / 码率·采样率。
///
/// 数据全部来自 [Song] 的既有字段，缺失时不臆造数字：
/// - 年份：`songs.year`（扫描落库，远程歌曲通常为空）；
/// - 播放来源：远程歌曲取 `source_data.s`（kwqq 插件写入的真实音源）或
///   `source_data.source`，映射为平台名；WebDAV 按插件入口识别；本地写「本地」。
///   **不展示 `browse` / `kwqq` / `remote` 等内部枚举**。
/// - 码率/采样率：本地歌曲扫描即有；远程歌曲依赖后端 ffprobe 探测落库，
///   未探测成功时该胶囊整体不显示。
class SongMetaChips extends StatelessWidget {
  const SongMetaChips({super.key, required this.song});

  final Song song;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final quality = _qualityLabel();
    final chips = <String>[
      if (song.year > 0) '${song.year}',
      _originLabel(l10n),
      if (quality != null) quality,
    ];

    return Wrap(
      spacing: 6,
      runSpacing: 4,
      alignment: WrapAlignment.center,
      children: [
        for (final chip in chips)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              color: theme.colorScheme.onSurface.withValues(alpha: 0.08),
            ),
            child: Text(
              chip,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
      ],
    );
  }

  String _originLabel(AppLocalizations l10n) {
    final platform = songPlatformName(song);
    if (platform != null) return platform;
    switch (song.type) {
      case 'radio':
        return l10n.songTypeRadioLabel;
      case 'remote':
        return l10n.songTypeRemoteLabel;
      default:
        return l10n.songTypeLocalLabel;
    }
  }

  String? _qualityLabel() {
    final parts = <String>[];
    if (song.bitRate > 0) {
      final kbps =
          song.bitRate >= 1000 ? (song.bitRate / 1000).round() : song.bitRate;
      parts.add('$kbps kbps');
    }
    if (song.sampleRate > 0) {
      parts.add('${(song.sampleRate / 1000).toStringAsFixed(1)} kHz');
    }
    return parts.isEmpty ? null : parts.join(' · ');
  }
}
