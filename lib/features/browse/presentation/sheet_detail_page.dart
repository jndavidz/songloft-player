/// 歌单详情页（票 10）：hero（封面/创建者/简介/曲目数）+ 曲目分页列表 + 点播链。
/// 长歌单（数百曲）触底分页；非 netease 精装路径的 501 给「该源暂不支持」提示。

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

void pushSheetDetail(BuildContext context, BrowseSheet sheet) {
  Navigator.of(context).push(
    MaterialPageRoute<void>(builder: (_) => SheetDetailPage(sheet: sheet)),
  );
}

class SheetDetailPage extends ConsumerStatefulWidget {
  final BrowseSheet sheet;

  const SheetDetailPage({super.key, required this.sheet});

  @override
  ConsumerState<SheetDetailPage> createState() => _SheetDetailPageState();
}

class _SheetDetailPageState extends ConsumerState<SheetDetailPage> {
  BrowseSheetInfo _info = const BrowseSheetInfo(isEnd: true, tracks: []);
  bool _isLoading = true;
  bool _isLoadingMore = false;
  Object? _error;
  int _page = 1;
  bool _isPlayingAll = false;

  @override
  void initState() {
    super.initState();
    _load(reset: true);
  }

  BrowseSheet get _sheet => _info.sheet ?? widget.sheet;

  Future<void> _load({bool reset = false}) async {
    if (reset) {
      setState(() {
        _isLoading = true;
        _error = null;
        _page = 1;
      });
    } else {
      if (_isLoadingMore || _info.isEnd) return;
      setState(() => _isLoadingMore = true);
    }
    try {
      final api = ref.read(pluginBrowseApiProvider);
      final info = await api.sheetInfo(
        id: _sheet.id,
        page: reset ? 1 : _page + 1,
      );
      if (!mounted) return;
      setState(() {
        _info = BrowseSheetInfo(
          sheet: info.sheet ?? (reset ? null : _info.sheet),
          isEnd: info.isEnd,
          total: info.total,
          tracks: reset ? info.tracks : [..._info.tracks, ...info.tracks],
        );
        if (!info.isEnd) _page = reset ? 1 : _page + 1;
        _isLoading = false;
        _isLoadingMore = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _isLoading = false;
        _isLoadingMore = false;
      });
    }
  }

  Future<void> _playAll() async {
    if (_info.tracks.isEmpty || _isPlayingAll) return;
    setState(() => _isPlayingAll = true);
    try {
      final tracks = _info.tracks.take(kPlayAllImportCap).toList();
      final started = await RemotePlayback.importAndPlay(context, ref, tracks);
      if (!started) return;
      // 后台补齐剩余页（gotchas §六）：队列先建、批次追加
      final total = _info.total ?? tracks.length;
      final loaded = tracks.length;
      final id = _sheet.id;
      RemotePlayback.startBackgroundCatchUp(
        ref,
        total: total,
        alreadyLoaded: loaded,
        fetchTracks: (offset, limit) async {
          final info = await ref
              .read(pluginBrowseApiProvider)
              .sheetInfo(id: id, page: offset ~/ limit + 1, limit: limit);
          return info.tracks;
        },
      );
    } finally {
      if (mounted) setState(() => _isPlayingAll = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final currentSong = ref.watch(currentSongProvider);
    final theme = Theme.of(context);
    final sheet = _sheet;
    final meta = <String>[
      if (sheet.creator.isNotEmpty) l10n.browseSheetCreator(sheet.creator),
      if ((sheet.trackCount > 0)) l10n.browseTrackCount(sheet.trackCount),
      if (sheet.playCount > 0) l10n.browsePlayCount(sheet.playCount),
    ].join(' · ');

    return Scaffold(
      appBar: AppBar(title: Text(sheet.name, overflow: TextOverflow.ellipsis)),
      body: NotificationListener<ScrollNotification>(
        onNotification: (n) {
          if (n.metrics.pixels >= n.metrics.maxScrollExtent - 200) {
            _load();
          }
          return false;
        },
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    BrowseCover(
                      url: sheet.coverUrl,
                      size: 112,
                      borderRadius: BorderRadius.circular(8),
                      fallbackIcon: Icons.queue_music_outlined,
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            sheet.name,
                            style: theme.textTheme.titleLarge,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
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
                            onPressed: _info.tracks.isEmpty ? null : _playAll,
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
            if (sheet.description != null && sheet.description!.isNotEmpty)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.md,
                  ),
                  child: Text(
                    sheet.description!,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
            const SliverToBoxAdapter(child: SizedBox(height: AppSpacing.sm)),
            if (_isLoading)
              const SliverFillRemaining(
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_error != null)
              SliverFillRemaining(
                child: BrowseStateView(
                  isLoading: false,
                  error: _error,
                  onRetry: () => _load(reset: true),
                  emptyTitle: '',
                ),
              )
            else if (_info.tracks.isEmpty)
              const SliverFillRemaining(child: SizedBox.shrink())
            else
              SliverList.builder(
                itemCount: _info.tracks.length + (_info.isEnd ? 0 : 1),
                itemBuilder: (context, index) {
                  if (index >= _info.tracks.length) {
                    return const Padding(
                      padding: EdgeInsets.all(16),
                      child: Center(child: CircularProgressIndicator()),
                    );
                  }
                  final track = _info.tracks[index];
                  return BrowseTrackTile(
                    track: track,
                    index: index,
                    isCurrent: isCurrentBrowseTrack(currentSong, track),
                    onTap:
                        () => RemotePlayback.importAndPlay(
                          context,
                          ref,
                          _info.tracks,
                          startIndex: index,
                        ),
                    onAddToPlaylist:
                        () => RemotePlayback.showAddToPlaylist(context, ref, [
                          track,
                        ]),
                  );
                },
              ),
            const SliverToBoxAdapter(child: SizedBox(height: 32)),
          ],
        ),
      ),
    );
  }
}
