/// 榜单页（票 11）：平台榜单列表（名称/封面/更新频率）→ 榜单详情曲目可播。
/// 上游失败给错误态可重试。

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
import 'widgets/browse_state_view.dart';
import 'widgets/browse_cover.dart';
import 'widgets/browse_track_tile.dart';

class ToplistsPage extends ConsumerStatefulWidget {
  const ToplistsPage({super.key});

  @override
  ConsumerState<ToplistsPage> createState() => _ToplistsPageState();
}

class _ToplistsPageState extends ConsumerState<ToplistsPage> {
  List<BrowseToplist>? _toplists;
  Object? _error;
  String? _selectedSource;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _error = null;
      _toplists ??= null;
    });
    try {
      final api = ref.read(pluginBrowseApiProvider);
      final lists = await api.toplists();
      if (!mounted) return;
      setState(() {
        _toplists = lists;
        if (_selectedSource == null && lists.isNotEmpty) {
          _selectedSource = lists.first.source;
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e);
    }
  }

  /// 平台分组：顺序统一为 网易云 / QQ / 酷狗 / 酷我。
  Map<String, List<BrowseToplist>> _groups() {
    final groups = <String, List<BrowseToplist>>{};
    for (final tl in _toplists ?? const <BrowseToplist>[]) {
      groups.putIfAbsent(tl.source ?? '', () => []).add(tl);
    }
    final ordered = <String, List<BrowseToplist>>{};
    for (final s in orderBrowsePlatforms(groups.keys)) {
      ordered[s] = groups[s]!;
    }
    return ordered;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final groups = _groups();
    final sources = groups.keys.toList();
    final selected =
        groups.containsKey(_selectedSource)
            ? _selectedSource!
            : (sources.isNotEmpty ? sources.first : null);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.discoverToplists)),
      body:
          _toplists == null && _error == null
              ? const Center(child: CircularProgressIndicator())
              : _error != null
              ? BrowseStateView(
                isLoading: false,
                error: _error,
                onRetry: _load,
                emptyTitle: '',
              )
              : _toplists!.isEmpty
              ? BrowseStateView(
                isLoading: false,
                emptyTitle: l10n.discoverToplists,
                emptyIcon: Icons.leaderboard_outlined,
              )
              : Column(
                children: [
                  if (sources.length > 1) ...[
                    _buildPlatformBar(sources, selected),
                    const Divider(height: 1),
                  ],
                  Expanded(
                    child: RefreshIndicator(
                      onRefresh: _load,
                      child: ListView(
                        padding: const EdgeInsets.symmetric(
                          vertical: AppSpacing.sm,
                        ),
                        children: [
                          _ToplistGrid(
                            toplists: groups[selected] ?? const [],
                            onTap:
                                (tl) => Navigator.of(context).push(
                                  MaterialPageRoute<void>(
                                    builder:
                                        (_) => ToplistDetailPage(toplist: tl),
                                  ),
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

  /// 顶部平台按钮：网易云 / QQ / 酷狗 / 酷我，点击只看该平台榜单。
  Widget _buildPlatformBar(List<String> sources, String? selected) {
    return SizedBox(
      height: 48,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(AppSpacing.md, 8, AppSpacing.md, 8),
        children: [
          for (final source in sources) ...[
            ChoiceChip(
              label: Text(browsePlatformLabel(source)),
              selected: source == selected,
              visualDensity: VisualDensity.compact,
              onSelected: (_) => setState(() => _selectedSource = source),
            ),
            const SizedBox(width: 8),
          ],
        ],
      ),
    );
  }
}

/// 一排 5 个的小榜单卡：小封面 + 榜单名，多平台时不浪费纵向空间。
class _ToplistGrid extends StatelessWidget {
  final List<BrowseToplist> toplists;
  final ValueChanged<BrowseToplist> onTap;

  const _ToplistGrid({required this.toplists, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 4,
        mainAxisSpacing: AppSpacing.md,
        crossAxisSpacing: AppSpacing.sm,
        // 封面 1:1 + 固定 2 行标题区，标题 1 行/2 行的卡片封面尺寸一致。
        childAspectRatio: 0.68,
      ),
      itemCount: toplists.length,
      itemBuilder: (context, index) {
        final tl = toplists[index];
        return _ToplistCard(toplist: tl, onTap: () => onTap(tl));
      },
    );
  }
}

class _ToplistCard extends StatelessWidget {
  final BrowseToplist toplist;
  final VoidCallback onTap;

  const _ToplistCard({required this.toplist, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: BrowseCover(
                url: toplist.coverUrl,
                width: double.infinity,
                height: double.infinity,
                fallbackIcon: Icons.leaderboard_outlined,
              ),
            ),
          ),
          const SizedBox(height: 4),
          // 固定 2 行标题高度：避免 1 行标题的卡片封面被拉大。
          SizedBox(
            height: 32,
            child: Text(
              toplist.name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelSmall,
            ),
          ),
        ],
      ),
    );
  }
}

/// 榜单详情：榜单 id 即平台歌单 id，曲目分页可播。
class ToplistDetailPage extends ConsumerStatefulWidget {
  final BrowseToplist toplist;

  const ToplistDetailPage({super.key, required this.toplist});

  @override
  ConsumerState<ToplistDetailPage> createState() => _ToplistDetailPageState();
}

class _ToplistDetailPageState extends ConsumerState<ToplistDetailPage> {
  final List<BrowseTrack> _tracks = [];
  bool _isLoading = true;
  bool _isLoadingMore = false;
  bool _isEnd = false;
  bool _isPlayingAll = false;
  int _page = 1;
  int? _total;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load(reset: true);
  }

  Future<void> _load({bool reset = false}) async {
    if (reset) {
      setState(() {
        _isLoading = true;
        _error = null;
        _page = 1;
      });
    } else {
      if (_isLoadingMore || _isEnd) return;
      setState(() => _isLoadingMore = true);
    }
    try {
      final api = ref.read(pluginBrowseApiProvider);
      final page = reset ? 1 : _page + 1;
      final res = await api.toplistDetail(
        id: widget.toplist.id,
        source: widget.toplist.source ?? 'netease',
        page: page,
      );
      if (!mounted) return;
      setState(() {
        if (reset) _tracks.clear();
        _tracks.addAll(res.items);
        _total = res.total ?? _total;
        _isEnd = res.isEnd;
        if (!res.isEnd) _page = page;
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
    if (_tracks.isEmpty || _isPlayingAll) return;
    setState(() => _isPlayingAll = true);
    try {
      final tracks = _tracks.take(kPlayAllImportCap).toList();
      final started = await RemotePlayback.importAndPlay(context, ref, tracks);
      if (!started) return;
      // 后台补齐剩余页（gotchas §六）：队列先建、批次追加
      final id = widget.toplist.id;
      final source = widget.toplist.source ?? 'netease';
      RemotePlayback.startBackgroundCatchUp(
        ref,
        total: _total ?? tracks.length,
        alreadyLoaded: tracks.length,
        fetchTracks: (offset, limit) async {
          final res = await ref
              .read(pluginBrowseApiProvider)
              .toplistDetail(
                id: id,
                source: source,
                page: offset ~/ limit + 1,
                limit: limit,
              );
          return res.items;
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
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.toplist.name, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            tooltip: l10n.browsePlayAll,
            onPressed: _tracks.isEmpty || _isPlayingAll ? null : _playAll,
            icon:
                _isPlayingAll
                    ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                    : const Icon(Icons.play_arrow_rounded),
          ),
        ],
      ),
      body: NotificationListener<ScrollNotification>(
        onNotification: (n) {
          if (n.metrics.pixels >= n.metrics.maxScrollExtent - 200) {
            _load();
          }
          return false;
        },
        child:
            _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                ? BrowseStateView(
                  isLoading: false,
                  error: _error,
                  onRetry: () => _load(reset: true),
                  emptyTitle: '',
                )
                : _tracks.isEmpty
                ? BrowseStateView(
                  isLoading: false,
                  emptyTitle: widget.toplist.name,
                  emptyIcon: Icons.leaderboard_outlined,
                )
                : ListView.builder(
                  itemCount: _tracks.length + (_isEnd ? 0 : 1),
                  itemBuilder: (context, index) {
                    if (index >= _tracks.length) {
                      return const Padding(
                        padding: EdgeInsets.all(16),
                        child: Center(child: CircularProgressIndicator()),
                      );
                    }
                    final track = _tracks[index];
                    return BrowseTrackTile(
                      track: track,
                      index: index,
                      isCurrent: isCurrentBrowseTrack(currentSong, track),
                      onTap:
                          () => RemotePlayback.importAndPlay(
                            context,
                            ref,
                            _tracks,
                            startIndex: index,
                          ),
                      onAddToPlaylist:
                          () => RemotePlayback.showAddToPlaylist(context, ref, [
                            track,
                          ]),
                    );
                  },
                ),
      ),
    );
  }
}
