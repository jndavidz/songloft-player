/// 榜单页（票 11）：平台榜单列表（名称/封面/更新频率）→ 榜单详情曲目可播。
/// 上游失败给错误态可重试。

library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_dimensions.dart';
import '../../../l10n/app_localizations.dart';
import '../data/browse_models.dart';
import '../data/plugin_browse_api.dart';
import '../data/remote_playback.dart';
import 'widgets/browse_state_view.dart';
import 'widgets/browse_track_tile.dart';

class ToplistsPage extends ConsumerStatefulWidget {
  const ToplistsPage({super.key});

  @override
  ConsumerState<ToplistsPage> createState() => _ToplistsPageState();
}

class _ToplistsPageState extends ConsumerState<ToplistsPage> {
  List<BrowseToplist>? _toplists;
  Object? _error;

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
      setState(() => _toplists = lists);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
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
              : RefreshIndicator(
                onRefresh: _load,
                child: GridView.builder(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 240,
                    mainAxisSpacing: AppSpacing.md,
                    crossAxisSpacing: AppSpacing.md,
                    childAspectRatio: 0.9,
                  ),
                  itemCount: _toplists!.length,
                  itemBuilder: (context, index) {
                    final tl = _toplists![index];
                    return _ToplistCard(
                      toplist: tl,
                      onTap:
                          () => Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => ToplistDetailPage(toplist: tl),
                            ),
                          ),
                    );
                  },
                ),
              ),
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
              borderRadius: BorderRadius.circular(8),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  toplist.coverUrl != null && toplist.coverUrl!.isNotEmpty
                      ? Image.network(
                        toplist.coverUrl!,
                        fit: BoxFit.cover,
                        errorBuilder:
                            (_, _, _) =>
                                const ColoredBox(color: Color(0x1A808080)),
                      )
                      : const ColoredBox(color: Color(0x1A808080)),
                  Positioned(
                    left: 8,
                    right: 8,
                    bottom: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.45),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        toplist.updateFrequency ?? '',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            toplist.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodyMedium,
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
  int _page = 1;
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
      final res = await api.toplistDetail(id: widget.toplist.id, page: page);
      if (!mounted) return;
      setState(() {
        if (reset) _tracks.clear();
        _tracks.addAll(res.items);
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.toplist.name, overflow: TextOverflow.ellipsis),
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
