import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dart:math' as math;

import '../../../../core/backend/run_mode_provider.dart';
import '../../../../core/theme/app_dimensions.dart';
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
import '../providers/audio_track_provider.dart';
import 'audio_track_control.dart';
import 'lyrics_view.dart';
import 'player_backdrop.dart';
import 'song_meta_chips.dart';
import 'lyrics_screen_awake.dart';
import 'play_controls.dart';
import 'popup_controls.dart';
import '../../../dlna/presentation/widgets/cast_button.dart';
import 'progress_bar.dart';
import 'equalizer_panel.dart';
import '../utils/full_player_route.dart';
import '../utils/player_song_actions.dart';
import 'video_player_surface.dart';
import 'video_stage.dart';
import 'vinyl_disc.dart';
import 'volume_control.dart';

/// 移动端全屏播放器
class MobilePlayer extends ConsumerStatefulWidget {
  /// 初始展示的页面（0: 封面/黑胶盘，1: 歌词）。
  /// 「打开后自动进入歌词」会传 1 直接落在歌词页。
  final int initialPage;

  const MobilePlayer({super.key, this.initialPage = 0});

  @override
  ConsumerState<MobilePlayer> createState() => _MobilePlayerState();
}

class _MobilePlayerState extends ConsumerState<MobilePlayer>
    with FullPlayerAutoExit {
  /// 当前页面索引（0: 封面/黑胶盘, 1: 歌词）
  late int _currentPage;

  @override
  void initState() {
    super.initState();
    _currentPage = widget.initialPage;
    // Web 冷加载 /player 但无队列可恢复时，短暂等待异步恢复；仍无歌曲则退出。
    scheduleFullPlayerAutoExit();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(activePlaybackStateProvider);
    final notifier = ref.read(playerStateProvider.notifier);
    final theme = Theme.of(context);
    final size = MediaQuery.sizeOf(context);

    // 播放列表被清空时，自动关闭全屏播放器并返回上一页
    ref.listen<PlayerState>(playerStateProvider, (previous, next) {
      if (previous?.hasSong == true && !next.hasSong) {
        debugPrint('[Player] MobilePlayer: playlist cleared, closing player');
        dismissFullPlayer(context, ref);
      }
      // 异步恢复出歌曲后，取消冷加载兜底退出
      if (next.hasSong) cancelFullPlayerAutoExit();
    });

    if (!state.hasSong) {
      debugPrint('[Player] MobilePlayer: no song, hiding');
      return const SizedBox.shrink();
    }

    final song = state.currentSong!;

    // 视频/MV:切到视频播放器界面(画面铺满 + 叠加控制层 + 字幕),
    // 不走下面的封面/歌词音乐布局。
    if (song.isVideo) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: VideoPlayerSurface(song: song),
      );
    }

    final paletteAsync = ref.watch(coverColorsProvider(song.coverUrl));
    final palette = paletteAsync.value;

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      body: PlayerBackdrop(
        palette: palette,
        child: SafeArea(
          child: Column(
            children: [
              // 顶部工具栏
              _buildTopBar(context, notifier, state),
              const SizedBox(height: 16),
              // 封面（黑胶盘）/歌词：点击切换，不再左右滑动
              Expanded(
                flex: 4,
                child: Column(
                  children: [
                    Expanded(
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          // 舞台取可用区域与屏宽的较小值，给唱臂溢出留 8% 余量。
                          final stage =
                              math.min(constraints.maxHeight, size.width) *
                              0.88;
                          return IndexedStack(
                            index: _currentPage,
                            children: [
                              // 页面1：视频歌曲渲染画面（支持的平台），否则黑胶盘
                              Center(
                                child: VideoStage(
                                  song: song,
                                  width: stage,
                                  height: stage,
                                  fallback: GestureDetector(
                                    behavior: HitTestBehavior.opaque,
                                    onTap: () => _showPage(1),
                                    child: _buildVinyl(
                                      context,
                                      song,
                                      stage * 0.92,
                                      palette: palette,
                                      isPlaying: state.isPlaying,
                                    ),
                                  ),
                                ),
                              ),
                              // 页面2：歌词（点击空白区返回封面）
                              LyricsScreenAwake(
                                visible: _currentPage == 1,
                                child: LyricsView(
                                  currentPosition: state.currentTime,
                                  onSeek: notifier.seek,
                                  song: song,
                                  editable: true,
                                  scrubEnabled:
                                      !song.isLive &&
                                      state.duration > Duration.zero &&
                                      song.duration > 0,
                                  onTapBackground: () => _showPage(0),
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                    ),
                    // 页面指示器
                    const SizedBox(height: 12),
                    _buildPageIndicator(theme),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              // 歌曲信息
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
                child: Column(
                  children: [
                    Text(
                      song.title,
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      song.artist ??
                          AppLocalizations.of(context).playerUnknownArtist,
                      style: theme.textTheme.bodyLarge?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
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
              const SizedBox(height: 24),
              // 进度条
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
                child: PlayerProgressBar(
                  position: state.currentTime,
                  duration: state.duration,
                  onSeek: notifier.seek,
                ),
              ),
              const SizedBox(height: 16),
              // 主控制行（播放模式 + 上一首/播放/下一首 + 收藏）
              _buildControlsRow(context, state, notifier),
              const SizedBox(height: 20),
              // 工具行（投屏 + 音量 + 队列 + 更多）
              _buildToolBar(context, state, notifier),
              const SizedBox(height: AppSpacing.md),
            ],
          ),
        ),
      ),
    );
  }

  /// 构建页面指示器（小圆点）
  Widget _buildPageIndicator(ThemeData theme) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(2, (index) {
        final isActive = index == _currentPage;
        return Container(
          width: isActive ? 8 : 6,
          height: isActive ? 8 : 6,
          margin: const EdgeInsets.symmetric(horizontal: 4),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color:
                isActive
                    ? theme.colorScheme.primary
                    : theme.colorScheme.onSurface.withValues(alpha: 0.3),
          ),
        );
      }),
    );
  }

  Widget _buildTopBar(
    BuildContext context,
    PlayerNotifier notifier,
    PlayerState state,
  ) {
    final song = state.currentSong;
    final topBarColor = Theme.of(context).colorScheme.onSurface;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
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
          // 歌曲信息（专辑名）
          if (song?.album != null && song!.album!.isNotEmpty)
            Expanded(
              child: Text(
                song.album!,
                style: TextStyle(
                  color: topBarColor.withValues(alpha: 0.9),
                  fontSize: 14,
                ),
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            )
          else
            const Spacer(),
          // 更多操作
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
              // watch 修订号：缓存增删后菜单文案（缓存/从缓存删除）即时切换。
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
                      title: Text(
                        AppLocalizations.of(context).playerAudioTrack,
                      ),
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
                    leading: Icon(
                      Icons.delete_outline,
                      color: colorScheme.error,
                    ),
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
      ),
    );
  }

  /// 黑色/封面页 ↔ 歌词页切换（点击触发，不再左右滑动）。
  void _showPage(int page) {
    if (_currentPage == page) return;
    setState(() => _currentPage = page);
  }

  Widget _buildVinyl(
    BuildContext context,
    Song song,
    double diameter, {
    CoverPalette? palette,
    bool isPlaying = false,
  }) {
    final theme = Theme.of(context);
    final dpr = MediaQuery.devicePixelRatioOf(context);
    // label 只占盘心一半直径，解码宽度按 label 实际像素取，避免大图解码。
    final decodeWidth = (diameter * 0.5 * dpr).clamp(64.0, 1024.0).round();

    final glowColor = palette?.vibrantColor ?? palette?.dominantColor;
    final coverUrl = song.coverUrl;
    final resolvedCover =
        coverUrl != null && coverUrl.isNotEmpty
            ? UrlHelper.buildCoverUrl(coverUrl, width: decodeWidth)
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
        coverDecodeWidth: decodeWidth,
      ),
    );
  }

  /// Spotify 风格控制行：[播放模式] [上一首] [播放/暂停] [下一首] [收藏]
  Widget _buildControlsRow(
    BuildContext context,
    PlayerState state,
    PlayerNotifier notifier,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // 播放模式
          SizedBox(
            width: 48,
            height: 48,
            child: PopupPlayModeControl(
              playMode: state.playMode,
              onPlayModeChanged: notifier.setPlayMode,
            ),
          ),
          const SizedBox(width: 8),
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
            size: 76,
            showGlow: true,
            useRoundedRect: true,
          ),
          const SizedBox(width: 8),
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
        ],
      ),
    );
  }

  /// Spotify 风格工具行：[投屏] [音量] [队列]（Web 无投屏时仅 [音量] [队列]）
  Widget _buildToolBar(
    BuildContext context,
    PlayerState state,
    PlayerNotifier notifier,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          if (!kIsWeb) const CastButton(iconSize: 20),
          PopupVolumeControl(
            volume: state.volume,
            onVolumeChanged: notifier.setVolume,
          ),
          PopupSpeedControl(
            speed: state.speed,
            onSpeedChanged: notifier.setSpeed,
          ),
          IconButton(
            onPressed:
                () => AddToPlaylistModal.show(
                  context,
                  songIds: [state.currentSong!.id],
                ),
            icon: const Icon(Icons.playlist_add, size: 20),
            tooltip: AppLocalizations.of(context).browseAddToPlaylist,
          ),
          IconButton(
            onPressed:
                () => BrowseCommentsSheet.show(context, state.currentSong!),
            icon: const Icon(Icons.comment_outlined, size: 20),
            tooltip: AppLocalizations.of(context).browseComments,
          ),
          IconButton(
            onPressed: () => QueueBottomSheet.show(context),
            icon: const Icon(Icons.queue_music_rounded, size: 20),
            tooltip: AppLocalizations.of(context).playerQueueTitle,
          ),
        ],
      ),
    );
  }
}
