/// 在线歌曲点播链：add-remote 导入（dedup 幂等）→ 播放。
///
/// kwqq 是唯一在线解析层（既有定案）：本文件只把浏览条目透传给
/// `POST /api/v1/songs/remote`（`dedup_key` 由插件下发、重复点播不产生重复行），
/// 拿到宿主 song id 后走既有 `playPlaylist` 播放；音质档位 hint 由
/// audio_service 的 buildSongUrl 按歌曲类型与设置自动附带，此处不复制映射。

library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/app_localizations.dart';
import '../../../shared/models/song.dart';
import '../../../shared/utils/responsive_snackbar.dart';
import '../../../shared/widgets/add_to_playlist_modal.dart';
import '../../library/presentation/providers/songs_provider.dart';
import '../../player/presentation/providers/player_provider.dart';
import 'browse_models.dart';

class RemotePlayback {
  RemotePlayback._();

  /// 导入（幂等）并立即播放 [tracks]，从 [startIndex] 开始。
  /// 失败时弹出错误提示并返回 false。
  static Future<bool> importAndPlay(
    BuildContext context,
    WidgetRef ref,
    List<BrowseTrack> tracks, {
    int startIndex = 0,
  }) async {
    final songs = await importTracks(ref, tracks);
    if (songs == null || songs.isEmpty) {
      if (context.mounted) _showError(context);
      return false;
    }
    final safeIndex = startIndex.clamp(0, songs.length - 1);
    await ref
        .read(playerStateProvider.notifier)
        .playPlaylist(songs, startIndex: safeIndex);
    return true;
  }

  /// 批量导入（不播放）。返回 null 表示失败；重复歌曲由 dedup_key 幂等去重。
  static Future<List<Song>?> importTracks(
    WidgetRef ref,
    List<BrowseTrack> tracks,
  ) async {
    final playable = tracks.where((t) => t.isPlayable).toList();
    if (playable.isEmpty) return const [];
    try {
      final songsApi = ref.read(songsApiProvider);
      return await songsApi.createRemoteSongs(
        playable.map((t) => t.toRemotePayload()).toList(),
      );
    } catch (_) {
      return null;
    }
  }

  /// 「加入歌单」：先 ensure 导入（已入库的歌幂等命中 dedup_key 拿回同一 id），
  /// 再复用现有歌单选择器弹层（含新建歌单与重复加入 skip 反馈）。
  static Future<void> showAddToPlaylist(
    BuildContext context,
    WidgetRef ref,
    List<BrowseTrack> tracks,
  ) async {
    final songs = await importTracks(ref, tracks);
    if (songs == null || songs.isEmpty) {
      if (context.mounted) {
        ResponsiveSnackBar.showError(
          context,
          message: AppLocalizations.of(context).browsePlayFailed,
        );
      }
      return;
    }
    if (!context.mounted) return;
    await AddToPlaylistModal.show(
      context,
      songIds: songs.map((s) => s.id).toList(),
    );
  }

  static void _showError(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    ResponsiveSnackBar.showError(context, message: l10n.browsePlayFailed);
  }
}
