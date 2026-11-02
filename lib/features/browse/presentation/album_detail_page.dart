/// 专辑详情页（票 08，详情页模板：hero 区 + 曲目区 + 点播链，09/10 复用此结构）。
///
/// hero：封面 + 专辑名/歌手 + 发行时间/发行公司/介绍（平台可得多少给多少）；
/// 曲目区：官方曲序（track_no 从 1 起）。「播放全部」= 按曲序批量 add-remote
/// dedup 入库 → 队列连播。kuwo/qq 等未接入源（501）给「该源暂不支持」提示。

library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_dimensions.dart';
import '../../../l10n/app_localizations.dart';
import '../../player/presentation/providers/player_provider.dart';
import '../data/browse_identity.dart';
import '../data/browse_models.dart';
import '../data/plugin_browse_api.dart';
import '../data/remote_playback.dart';
import 'widgets/browse_cover.dart';
import 'widgets/browse_state_view.dart';
import 'widgets/browse_track_tile.dart';

void pushAlbumDetail(BuildContext context, BrowseAlbum album) {
  Navigator.of(context).push(
    MaterialPageRoute<void>(builder: (_) => AlbumDetailPage(album: album)),
  );
}

class AlbumDetailPage extends ConsumerStatefulWidget {
  final BrowseAlbum album;

  const AlbumDetailPage({super.key, required this.album});

  @override
  ConsumerState<AlbumDetailPage> createState() => _AlbumDetailPageState();
}

class _AlbumDetailPageState extends ConsumerState<AlbumDetailPage> {
  BrowseAlbumInfo? _info;
  bool _isLoading = true;
  Object? _error;
  bool _isPlayingAll = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final api = ref.read(pluginBrowseApiProvider);
      final a = widget.album;
      final info = await api.albumInfo(
        id: a.id,
        name: a.name,
        artist: a.artist,
        source: a.source ?? 'netease',
      );
      if (!mounted) return;
      setState(() {
        _info = info;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _isLoading = false;
      });
    }
  }

  static String _formatPublishTime(int ms) {
    final d = DateTime.fromMillisecondsSinceEpoch(ms);
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }

  Future<void> _playAll() async {
    final info = _info;
    if (info == null || info.tracks.isEmpty || _isPlayingAll) return;
    setState(() => _isPlayingAll = true);
    try {
      await RemotePlayback.importAndPlay(context, ref, info.tracks);
    } finally {
      if (mounted) setState(() => _isPlayingAll = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final album = _info?.album ?? widget.album;

    return Scaffold(
      appBar: AppBar(title: Text(album.name, overflow: TextOverflow.ellipsis)),
      body:
          _isLoading
              ? const Center(child: CircularProgressIndicator())
              : _error != null
              ? BrowseStateView(
                isLoading: false,
                error: _error,
                onRetry: _load,
                emptyTitle: '',
              )
              : _buildBody(context, album, l10n),
    );
  }

  Widget _buildBody(
    BuildContext context,
    BrowseAlbum album,
    AppLocalizations l10n,
  ) {
    final info = _info!;
    final currentSong = ref.watch(currentSongProvider);
    final theme = Theme.of(context);
    final meta = <String>[
      if (album.publishTime != null)
        '${l10n.browsePublishedAt}: ${_formatPublishTime(album.publishTime!)}',
      if (album.company != null && album.company!.isNotEmpty)
        '${l10n.browseCompany}: ${album.company!}',
      if (album.trackCount > 0) l10n.browseTrackCount(album.trackCount),
    ].join(' · ');

    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                BrowseCover(
                  url: album.coverUrl,
                  size: 128,
                  borderRadius: BorderRadius.circular(8),
                  fallbackIcon: Icons.album_outlined,
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        album.name,
                        style: theme.textTheme.titleLarge,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (album.artist.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          album.artist,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.primary,
                          ),
                        ),
                      ],
                      if (meta.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Text(
                          meta,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                      const SizedBox(height: 12),
                      FilledButton.icon(
                        onPressed: info.tracks.isEmpty ? null : _playAll,
                        icon:
                            _isPlayingAll
                                ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                                : const Icon(Icons.play_arrow_rounded),
                        label: Text(l10n.browsePlayAll),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        if (album.description != null && album.description!.isNotEmpty)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
              child: Text(
                album.description!,
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ),
        const SliverToBoxAdapter(child: SizedBox(height: AppSpacing.sm)),
        SliverList.builder(
          itemCount: info.tracks.length,
          itemBuilder: (context, index) {
            final track = info.tracks[index];
            return BrowseTrackTile(
              track: track,
              index: index,
              showTrackNo: true,
              showSource: (album.source ?? 'netease') != track.source,
              isCurrent: isCurrentBrowseTrack(currentSong, track),
              onTap:
                  () => RemotePlayback.importAndPlay(
                    context,
                    ref,
                    info.tracks,
                    startIndex: index,
                  ),
              onAddToPlaylist:
                  () => RemotePlayback.showAddToPlaylist(context, ref, [track]),
            );
          },
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 32)),
      ],
    );
  }
}
