import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/storage/song_cache_service.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../../shared/models/song.dart';
import '../../../../shared/utils/responsive_snackbar.dart';
import '../../../../shared/utils/device_cache_action.dart';
import '../../../../shared/utils/song_source_label.dart';
import '../../../../shared/widgets/confirm_dialog.dart';
import '../../../../shared/widgets/delete_song_dialog.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../../library/presentation/providers/songs_provider.dart';
import '../../../settings/presentation/providers/song_cache_provider.dart';
import '../../data/song_mv_api.dart';
import '../providers/player_provider.dart';
import '../song_mv_page.dart';

Future<bool> deleteCurrentSongFromPlayer(
  BuildContext context,
  WidgetRef ref,
) async {
  final state = ref.read(playerStateProvider);
  final song = state.currentSong;
  if (song == null) return false;

  final l10n = AppLocalizations.of(context);
  final result = await DeleteSongDialog.show(
    context,
    title: l10n.playerDeleteSongTitle,
    content: l10n.playerDeleteSongConfirm(song.title),
  );
  if (result == null) return false;

  try {
    await ref
        .read(songsApiProvider)
        .deleteSong(song.id, deleteFiles: result.deleteFiles);
    final notifier = ref.read(playerStateProvider.notifier);
    await notifier.removeFromPlaylist(state.currentIndex);
    ref.invalidate(songsListProvider);
    if (context.mounted) {
      ResponsiveSnackBar.showSuccess(context, message: l10n.playerSongDeleted);
    }
    return true;
  } catch (e) {
    if (context.mounted) {
      ResponsiveSnackBar.showError(context, message: l10n.playerDeleteFailed);
    }
    return false;
  }
}

/// 把一首歌手动缓存到本机（songloft-org/songloft#312）。
///
/// 视频歌曲缓存前弹体积提示；缓存音质取当前播放音质设置；超本地上限时提示。
Future<void> cacheSongToDevice(
  BuildContext context,
  WidgetRef ref,
  Song song,
) async {
  final l10n = AppLocalizations.of(context);

  if (song.isVideo) {
    final ok = await ConfirmDialog.show(
      context,
      title: l10n.songCacheVideoWarnTitle,
      content: l10n.songCacheVideoWarnContent,
      confirmText: l10n.songCacheConfirm,
    );
    if (!ok) return;
  }

  final prefs = await ref.read(appPreferencesProvider.future);
  final quality = prefs.getAudioQuality();
  final maxSize = prefs.getLocalCacheMaxSize();

  if (context.mounted) {
    ResponsiveSnackBar.show(
      context,
      message: l10n.songCacheStarted(song.title),
    );
  }

  try {
    await ref
        .read(songCacheProvider.notifier)
        .cacheSong(song, quality: quality, maxSize: maxSize);
    if (context.mounted) {
      ResponsiveSnackBar.showSuccess(context, message: l10n.songCacheDone);
    }
  } on SongCacheLimitExceeded {
    if (context.mounted) {
      ResponsiveSnackBar.showError(
        context,
        message: l10n.songCacheLimitExceeded,
      );
    }
  } catch (e) {
    if (context.mounted) {
      ResponsiveSnackBar.showError(context, message: l10n.songCacheFailed);
    }
  }
}

/// 从本机缓存删除一首歌。
Future<void> removeSongFromDevice(
  BuildContext context,
  WidgetRef ref,
  Song song,
) async {
  final l10n = AppLocalizations.of(context);
  final notifier = ref.read(songCacheProvider.notifier);
  await runDeviceCacheRemoval(
    context,
    () => notifier.removeSong(song.id),
    successMessage: l10n.songCacheRemoved,
  );
}

/// 打开当前歌曲的在线 MV（「...」菜单 → 歌曲视频）。
///
/// 平台与平台曲 id 取自 `source_data.s` / `source_data.i`（kwqq 插件写入）；
/// 查不到可用 MV 时给出明确提示，不静默无反应。
Future<void> openSongMv(BuildContext context, WidgetRef ref, Song song) async {
  final l10n = AppLocalizations.of(context);
  final sourceData = song.sourceData;
  final source =
      (sourceData?['s'] ?? sourceData?['source'] ?? '')
          .toString()
          .trim()
          .toLowerCase();
  final platformId = (sourceData?['i'] ?? '').toString().trim();

  if (source.isEmpty || platformId.isEmpty) {
    ResponsiveSnackBar.show(context, message: l10n.songMvUnavailable);
    return;
  }

  final track = await ref
      .read(songMvApiProvider)
      .findMv(
        source: source,
        id: platformId,
        title: song.title,
        artist: song.artist ?? '',
      );

  if (!context.mounted) return;
  if (track == null) {
    ResponsiveSnackBar.show(context, message: l10n.songMvUnavailable);
    return;
  }

  await Navigator.of(
    context,
    rootNavigator: true,
  ).push(MaterialPageRoute<void>(builder: (_) => SongMvPage(track: track)));
}

/// 打开「歌曲信息」弹窗：码率/格式/采样率/大小/类型/播放来源/缓存位置。
///
/// 播放来源按歌曲自身的真实音源显示平台名（网易云/QQ/酷狗/酷我/咪咕/千千/
/// 哔哩哔哩/WebDAV），本地歌曲写「本地」——**不再展示 `在线播放` 这类笼统文案**。
/// 码率/采样率缺失（远端探测失败或未扫描）时整行隐藏，不显示 `--`。
void showSongInfoDialog(BuildContext context, WidgetRef ref, Song song) {
  showDialog<void>(
    context: context,
    builder: (context) => _SongInfoDialog(song: song),
  );
}

class _SongInfoDialog extends ConsumerWidget {
  final Song song;

  const _SongInfoDialog({required this.song});

  String _typeLabel(AppLocalizations l10n) {
    switch (song.type) {
      case 'radio':
        return l10n.songTypeRadioLabel;
      case 'remote':
        return l10n.songTypeRemoteLabel;
      default:
        return l10n.songTypeLocalLabel;
    }
  }

  String _bitRateLabel() {
    final kbps =
        song.bitRate >= 1000 ? (song.bitRate / 1000).round() : song.bitRate;
    return '$kbps kbps';
  }

  String _sampleRateLabel() {
    return '${(song.sampleRate / 1000).toStringAsFixed(1)} kHz';
  }

  /// 播放来源：优先真实平台名；识别不出时按歌曲类型给通用文案（本地写「本地」）。
  String _sourceLabel(AppLocalizations l10n) {
    return songPlatformName(song) ?? _typeLabel(l10n);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    // watch 修订号，缓存增删后刷新缓存位置行。
    ref.watch(songCacheProvider);
    final entry = ref.read(songCacheProvider.notifier).entry(song.id);
    final cached = entry != null;

    final rows = <(String, String)>[
      if (song.artist != null && song.artist!.isNotEmpty)
        (l10n.songInfoArtist, song.artist!),
      if (song.album != null && song.album!.isNotEmpty)
        (l10n.songInfoAlbum, song.album!),
      // 词曲编曲：数据未就绪或该值为空时整行隐藏（不写 `--` / 「未知」）。
      if (song.credits != null) ...[
        if (song.credits!.lyricist.isNotEmpty)
          (l10n.songInfoLyricist, song.credits!.lyricist.join('、')),
        if (song.credits!.composer.isNotEmpty)
          (l10n.songInfoComposer, song.credits!.composer.join('、')),
        if (song.credits!.arranger.isNotEmpty)
          (l10n.songInfoArranger, song.credits!.arranger.join('、')),
      ],
      (l10n.songInfoType, _typeLabel(l10n)),
      if (song.format != null && song.format!.isNotEmpty)
        (l10n.songInfoFormat, song.format!.toUpperCase()),
      if (song.bitRate > 0) (l10n.songInfoBitRate, _bitRateLabel()),
      if (song.sampleRate > 0) (l10n.songInfoSampleRate, _sampleRateLabel()),
      if (song.fileSize > 0)
        (l10n.songInfoFileSize, Formatters.formatFileSize(song.fileSize)),
      (l10n.songInfoPlaybackSource, _sourceLabel(l10n)),
      if (cached) (l10n.songInfoCachePath, entry.path),
    ];

    return AlertDialog(
      title: Text(song.title, maxLines: 2, overflow: TextOverflow.ellipsis),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final (label, value) in rows)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 84,
                      child: Text(
                        label,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                    Expanded(
                      child: Text(value, style: theme.textTheme.bodyMedium),
                    ),
                  ],
                ),
              ),
            if (cached) ...[
              const SizedBox(height: 8),
              Text(
                l10n.songInfoQualityNote,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.commonConfirm),
        ),
      ],
    );
  }
}
