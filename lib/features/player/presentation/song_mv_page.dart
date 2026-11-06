import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_dimensions.dart';
import '../../../l10n/app_localizations.dart';
import '../data/song_mv_api.dart';
import 'providers/player_provider.dart';
import 'widgets/mv_video_view.dart';

/// 在线歌曲 MV 播放页（「...」菜单 → 歌曲视频）。
///
/// 用独立的视频播放器（原生 media_kit / Web `<video>` + hls.js），与音频播放
/// 完全隔离：进入时暂停音频、退出时恢复原来的音频播放态，不打断播放队列。
class SongMvPage extends ConsumerStatefulWidget {
  const SongMvPage({super.key, required this.track});

  final MvTrack track;

  @override
  ConsumerState<SongMvPage> createState() => _SongMvPageState();
}

class _SongMvPageState extends ConsumerState<SongMvPage> {
  /// 进入页面时由本页暂停了音频（退出需恢复）。
  bool _audioPaused = false;
  bool _loadFailed = false;

  @override
  void initState() {
    super.initState();
    final playing = ref.read(activePlaybackStateProvider).isPlaying;
    if (playing) {
      _audioPaused = true;
      // 音频停在同一位置，退出后从该位置继续。
      unawaited(ref.read(playerStateProvider.notifier).togglePlay());
    }
  }

  @override
  void dispose() {
    if (_audioPaused) {
      // 页面内没有其它音频操作入口，退出即恢复进入前的播放态。
      unawaited(ref.read(playerStateProvider.notifier).togglePlay());
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final artist = widget.track.artist.trim();
    final quality = widget.track.quality.trim();

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        elevation: 0,
        titleSpacing: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.track.title.isEmpty
                  ? l10n.playerSongVideo
                  : widget.track.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 16, color: Colors.white),
            ),
            if (artist.isNotEmpty || quality.isNotEmpty)
              Text(
                [
                  if (artist.isNotEmpty) artist,
                  if (quality.isNotEmpty) quality,
                ].join(' · '),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12, color: Colors.white70),
              ),
          ],
        ),
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          MvVideoView(
            url: widget.track.url,
            onError: (message) {
              debugPrint('[SongMvPage] video error: $message');
              if (mounted && !_loadFailed) {
                setState(() => _loadFailed = true);
              }
            },
          ),
          if (_loadFailed)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.xl),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.videocam_off_outlined,
                      color: Colors.white70,
                      size: 40,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      l10n.songMvLoadFailed,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: Colors.white70,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
