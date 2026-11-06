import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/backend/run_mode_provider.dart';
import '../../../../core/theme/app_dimensions.dart';
import '../../../../core/theme/responsive.dart';
import '../../../../core/utils/color_extraction.dart';
import '../../../../core/utils/url_helper.dart';
import '../../../settings/presentation/providers/song_cache_provider.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../../shared/models/song.dart';
import '../../../../shared/widgets/add_to_playlist_modal.dart';
import '../../../browse/presentation/browse_comments_sheet.dart';
import '../../../../shared/widgets/favorite_button.dart';
import '../../domain/player_state.dart';
import '../providers/player_provider.dart';
import '../queue_page.dart';
import 'lyrics_view.dart';
import 'player_backdrop.dart';
import 'lyrics_screen_awake.dart';
import '../providers/audio_track_provider.dart';
import 'audio_track_control.dart';
import 'equalizer_panel.dart';
import 'play_controls.dart';
import 'popup_controls.dart';
import 'progress_bar.dart';
import '../utils/full_player_route.dart';
import '../utils/player_song_actions.dart';
import 'vinyl_disc.dart';
import 'video_player_surface.dart';
import 'video_stage.dart';
import 'song_meta_chips.dart';
import '../../../dlna/presentation/widgets/cast_button.dart';
import 'volume_control.dart';

/// Desktop/Tablet 全屏播放器（左右分栏布局）
class DesktopFullPlayer extends ConsumerStatefulWidget {
  const DesktopFullPlayer({super.key});

  @override
  ConsumerState<DesktopFullPlayer> createState() => _DesktopFullPlayerState();
}

class _DesktopFullPlayerState extends ConsumerState<DesktopFullPlayer>
    with FullPlayerAutoExit {
  @override
  void initState() {
    super.initState();
    // Web 冷加载 /player 但无队列可恢复时，短暂等待异步恢复；仍无歌曲则退出。
    scheduleFullPlayerAutoExit();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(activePlaybackStateProvider);
    final notifier = ref.read(playerStateProvider.notifier);
    final theme = Theme.of(context);
    final isDesktop = context.isDesktop;

    // 播放列表被清空时，自动关闭全屏播放器
    ref.listen<PlayerState>(playerStateProvider, (previous, next) {
      if (previous?.hasSong == true && !next.hasSong) {
        debugPrint(
          '[Player] DesktopFullPlayer: playlist cleared, closing player',
        );
        dismissFullPlayer(context, ref);
      }
      // 异步恢复出歌曲后，取消冷加载兜底退出
      if (next.hasSong) cancelFullPlayerAutoExit();
    });

    if (!state.hasSong) {
      debugPrint('[Player] DesktopFullPlayer: no song, hiding');
      return const SizedBox.shrink();
    }

    final song = state.currentSong!;

    // 视频/MV:切到视频播放器界面(画面铺满 + 叠加控制层 + 字幕),
    // 不走下面的左封面/右歌词分栏音乐布局。
    if (song.isVideo) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: VideoPlayerSurface(song: song),
      );
    }

    final coverUrl = song.coverUrl;

    final paletteAsync = ref.watch(coverColorsProvider(coverUrl));
    final palette = paletteAsync.value;

    final horizontalPadding = isDesktop ? 48.0 : 24.0;
    final coverSize = isDesktop ? 300.0 : 220.0;

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      body: PlayerBackdrop(
        palette: palette,
        child: SafeArea(
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
            child: Column(
              children: [
                // 顶部栏
                _buildTopBar(context, state, notifier),
                const SizedBox(height: 16),
                // 左右分栏主体
                Expanded(
                  child: Row(
                    children: [
                      // 左侧：封面 + 歌曲信息
                      Expanded(
                        flex: 4,
                        child: LayoutBuilder(
                          builder: (context, constraints) {
                            // 超宽屏又矮时纵向空间不足，按左栏实际可用高度动态
                            // 收缩封面：为标题+艺术家+间距预留 ~100px、唱片环
                            // 上下各 8px 预留 16px，其余留给封面，避免固定
                            // coverSize 撑破 Column 造成底部溢出。
                            final budget = constraints.maxHeight - 100 - 16;
                            final maxCover = budget < 140.0 ? 140.0 : budget;
                            final effectiveCover =
                                coverSize > maxCover ? maxCover : coverSize;
                            return Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  // 视频歌曲渲染画面，否则封面带唱片环旋转（视频不可用时也回退到此）
                                  VideoStage(
                                    song: song,
                                    width: effectiveCover,
                                    height: effectiveCover,
                                    fallback: _buildVinyl(
                                      context,
                                      song,
                                      effectiveCover * 0.9,
                                      palette: palette,
                                      isPlaying: state.isPlaying,
                                    ),
                                  ),
                                  const SizedBox(height: 24),
                                  // 歌曲信息支持选择复制；切歌时重建以清除旧选区。
                                  SelectionArea(
                                    key: ValueKey(song.id),
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Padding(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: AppSpacing.md,
                                          ),
                                          child: Text(
                                            song.title,
                                            style: theme.textTheme.headlineSmall
                                                ?.copyWith(
                                                  fontWeight: FontWeight.bold,
                                                ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            textAlign: TextAlign.center,
                                          ),
                                        ),
                                        const SizedBox(height: 8),
                                        Text(
                                          song.artist ??
                                              AppLocalizations.of(
                                                context,
                                              ).playerUnknownArtist,
                                          style: theme.textTheme.bodyLarge
                                              ?.copyWith(
                                                color:
                                                    theme
                                                        .colorScheme
                                                        .onSurfaceVariant,
                                              ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          textAlign: TextAlign.center,
                                        ),
                                        const SizedBox(height: 8),
                                        SongMetaChips(song: song),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      ),
                      // 右侧：歌词
                      Expanded(
                        flex: 5,
                        child: LyricsScreenAwake(
                          visible: true,
                          child: LyricsView(
                            currentPosition: state.currentTime,
                            onSeek: notifier.seek,
                            song: song,
                            editable: true,
                            scrubEnabled:
                                !song.isLive &&
                                state.duration > Duration.zero &&
                                song.duration > 0,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                // 进度条
                PlayerProgressBar(
                  position: state.currentTime,
                  duration: state.duration,
                  onSeek: notifier.seek,
                ),
                const SizedBox(height: 12),
                // 主控制按钮
                PlayControls(
                  isPlaying: state.isPlaying,
                  hasPrev: state.hasPrev,
                  hasNext: state.hasNext,
                  isBuffering: state.showBufferingIndicator,
                  onPlay: notifier.togglePlay,
                  onPause: notifier.togglePlay,
                  onPrev: notifier.playPrev,
                  onNext: notifier.playNext,
                  size: 52,
                  showGlow: true,
                ),
                const SizedBox(height: 12),
                // 底部工具栏
                _buildBottomBar(context, state, notifier),
                const SizedBox(height: AppSpacing.md),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 顶部栏：返回按钮 + "正在播放" + 更多操作菜单（均衡器 / 音轨 / 睡眠定时 / 删除）
  Widget _buildTopBar(
    BuildContext context,
    PlayerState state,
    PlayerNotifier notifier,
  ) {
    final topBarColor = Theme.of(context).colorScheme.onSurface;

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        // 返回按钮
        IconButton(
          onPressed: () => dismissFullPlayer(context, ref),
          icon: const Icon(Icons.keyboard_arrow_down_rounded),
          iconSize: 32,
          color: topBarColor,
          tooltip: AppLocalizations.of(context).playerCollapse,
        ),
        // 中间标题
        Text(
          AppLocalizations.of(context).playerNowPlaying,
          style: TextStyle(
            color: topBarColor.withValues(alpha: 0.9),
            fontSize: 14,
          ),
        ),
        // 更多操作（均衡器 / 音轨 / 睡眠定时 / 删除，与 mobile/video 全屏播放器一致）
        PopupMenuButton<String>(
          icon: Icon(
            Icons.more_horiz_rounded,
            color:
                state.sleepTimer != null
                    ? Theme.of(context).colorScheme.primary
                    : topBarColor,
          ),
          onSelected: (value) {
            switch (value) {
              case 'equalizer':
                showEqualizerSheet(context);
              case 'audio_track':
                showAudioTrackSheet(context, ref);
              case 'sleep_timer':
                SleepTimerSheet.show(
                  context,
                  status: state.sleepTimer,
                  isLive: state.currentSong?.isLive ?? false,
                  onSetDuration: notifier.setSleepTimerByDuration,
                  onSetAfterSongs: notifier.setSleepTimerAfterSongs,
                  onCancel: notifier.cancelSleepTimer,
                );
              case 'cache_song':
                final song = state.currentSong;
                if (song == null) break;
                if (ref.read(songCacheProvider.notifier).isCached(song.id)) {
                  removeSongFromDevice(context, ref, song);
                } else {
                  cacheSongToDevice(context, ref, song);
                }
              case 'song_info':
                final song = state.currentSong;
                if (song != null) {
                  showSongInfoDialog(
                    context,
                    ref,
                    song,
                    playbackSource: state.playbackSource,
                  );
                }
              case 'delete':
                deleteCurrentSongFromPlayer(context, ref);
            }
          },
          itemBuilder: (context) {
            final colorScheme = Theme.of(context).colorScheme;
            final hasTimer = state.sleepTimer != null;
            final song = state.currentSong;
            ref.watch(songCacheProvider);
            final runMode = ref.watch(runModeProvider);
            final canCache =
                song != null && canCacheLocally(song, runMode: runMode);
            final isCached =
                song != null &&
                ref.read(songCacheProvider.notifier).isCached(song.id);
            return [
              // 均衡器依赖 libmpv，Web 无 libmpv 不生效，故 Web 隐藏
              if (!kIsWeb)
                PopupMenuItem(
                  value: 'equalizer',
                  child: ListTile(
                    leading: const Icon(Icons.equalizer_rounded),
                    title: Text(AppLocalizations.of(context).playerEqualizer),
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              // 音轨切换：多音轨时才显示（与均衡器同为次要功能，统一收进菜单）
              if (ref.read(audioTrackProvider).hasMultiple)
                PopupMenuItem(
                  value: 'audio_track',
                  child: ListTile(
                    leading: const Icon(Icons.multitrack_audio_rounded),
                    title: Text(AppLocalizations.of(context).playerAudioTrack),
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              PopupMenuItem(
                value: 'sleep_timer',
                child: ListTile(
                  leading: Icon(
                    Icons.bedtime_outlined,
                    color: hasTimer ? colorScheme.primary : null,
                  ),
                  title: Text(
                    hasTimer
                        ? AppLocalizations.of(context).playerSleepTimerOn
                        : AppLocalizations.of(context).playerSleepTimer,
                  ),
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              if (song != null)
                PopupMenuItem(
                  value: 'song_info',
                  child: ListTile(
                    leading: const Icon(Icons.info_outline_rounded),
                    title: Text(AppLocalizations.of(context).songCacheInfo),
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              if (canCache)
                PopupMenuItem(
                  value: 'cache_song',
                  child: ListTile(
                    leading: Icon(
                      isCached
                          ? Icons.download_done_rounded
                          : Icons.download_for_offline_outlined,
                    ),
                    title: Text(
                      isCached
                          ? AppLocalizations.of(context).songCacheRemove
                          : AppLocalizations.of(context).songCacheCacheSong,
                    ),
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              const PopupMenuDivider(),
              PopupMenuItem(
                value: 'delete',
                child: ListTile(
                  leading: Icon(Icons.delete_outline, color: colorScheme.error),
                  title: Text(
                    AppLocalizations.of(context).playerDeleteCurrentSong,
                    style: TextStyle(color: colorScheme.error),
                  ),
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ];
          },
        ),
      ],
    );
  }

  /// 黑胶盘（封面缺失时由 VinylDisc 内部回退默认 label）
  Widget _buildVinyl(
    BuildContext context,
    Song song,
    double diameter, {
    CoverPalette? palette,
    bool isPlaying = false,
  }) {
    final theme = Theme.of(context);
    final glowColor = palette?.vibrantColor ?? palette?.dominantColor;
    final coverUrl = song.coverUrl;
    final resolvedCover =
        coverUrl != null && coverUrl.isNotEmpty
            ? UrlHelper.buildCoverUrl(coverUrl, width: 300)
            : null;

    return Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        // 发光在最外层（旋转子树之外），避免每帧重算 blur。
        boxShadow:
            glowColor != null
                ? AppEffects.primaryGlow(glowColor)
                : AppEffects.softGlow(theme.colorScheme.onSurface),
      ),
      child: VinylDisc(
        isPlaying: isPlaying,
        diameter: diameter,
        coverUrl: resolvedCover,
        title: song.title,
      ),
    );
  }

  /// 底部工具栏
  Widget _buildBottomBar(
    BuildContext context,
    PlayerState state,
    PlayerNotifier notifier,
  ) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceAround,
      children: [
        // 收藏
        SizedBox(
          width: 48,
          height: 48,
          child: Center(
            child: FavoriteButton(
              songId: state.currentSong!.id,
              songType: state.currentSong!.type,
              size: 24,
            ),
          ),
        ),
        // 播放模式
        SizedBox(
          width: 48,
          height: 48,
          child: PopupPlayModeControl(
            playMode: state.playMode,
            onPlayModeChanged: notifier.setPlayMode,
          ),
        ),
        // 播放速度
        SizedBox(
          width: 48,
          height: 48,
          child: PopupSpeedControl(
            speed: state.speed,
            onSpeedChanged: notifier.setSpeed,
          ),
        ),
        // 投屏（Web 无 DLNA，CastButton 返回空占位；显式 kIsWeb 门控，
        // 避免固定 48×48 盒在 spaceAround 下留出空槽导致按钮分布不均）
        if (!kIsWeb)
          const SizedBox(
            width: 48,
            height: 48,
            child: CastButton(iconSize: 24),
          ),
        // 音量
        SizedBox(
          width: 48,
          height: 48,
          child: PopupVolumeControl(
            volume: state.volume,
            onVolumeChanged: notifier.setVolume,
          ),
        ),
        // 加入歌单（票 05）
        SizedBox(
          width: 48,
          height: 48,
          child: IconButton(
            onPressed:
                () => AddToPlaylistModal.show(
                  context,
                  songIds: [state.currentSong!.id],
                ),
            icon: const Icon(Icons.playlist_add),
            tooltip: AppLocalizations.of(context).browseAddToPlaylist,
          ),
        ),
        // 评论（票 13，只读）
        SizedBox(
          width: 48,
          height: 48,
          child: IconButton(
            onPressed:
                () => BrowseCommentsSheet.show(context, state.currentSong!),
            icon: const Icon(Icons.comment_outlined),
            tooltip: AppLocalizations.of(context).browseComments,
          ),
        ),
        // 播放队列
        SizedBox(
          width: 48,
          height: 48,
          child: IconButton(
            onPressed: () {
              QueueBottomSheet.show(context);
            },
            icon: const Icon(Icons.queue_music_rounded),
            tooltip: AppLocalizations.of(context).playerQueueTitle,
          ),
        ),
      ],
    );
  }
}
