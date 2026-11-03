/// 在线搜索页（MusicFree 形态，票 01/02/07）。
///
/// 第一排搜索框、第二排「单曲/专辑/歌手/歌单」四类型 tab（默认单曲）；
/// 切换 tab 就地换结果列表、保持同一关键词免重输。进入时展示搜索历史
/// （设备本地持久化：置顶去重、上限 20、单条删除、整体清空）。

library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_dimensions.dart';
import '../../../l10n/app_localizations.dart';
import '../../player/presentation/providers/player_provider.dart';
import '../../../shared/widgets/empty_state.dart';
import '../data/browse_identity.dart';
import '../data/browse_models.dart';
import '../data/plugin_browse_api.dart';
import '../data/remote_playback.dart';
import '../data/search_history_store.dart';
import 'album_detail_page.dart';
import 'artist_detail_page.dart';
import 'sheet_detail_page.dart';
import 'widgets/browse_cover.dart';
import 'widgets/browse_state_view.dart';
import 'widgets/browse_track_tile.dart';

enum BrowseSearchType { music, album, artist, sheet }

class BrowseSearchPage extends ConsumerStatefulWidget {
  const BrowseSearchPage({super.key});

  @override
  ConsumerState<BrowseSearchPage> createState() => _BrowseSearchPageState();
}

class _BrowseSearchPageState extends ConsumerState<BrowseSearchPage> {
  final _searchController = TextEditingController();
  final _focusNode = FocusNode();
  final _scrollController = ScrollController();

  /// 已提交的搜索词（空串 = 停留在历史/占位态）。
  String _keyword = '';
  BrowseSearchType _type = BrowseSearchType.music;

  final List<BrowseTrack> _tracks = [];
  final List<BrowseAlbum> _albums = [];
  final List<BrowseArtist> _artists = [];
  final List<BrowseSheet> _sheets = [];

  bool _isLoading = false;
  bool _isLoadingMore = false;
  bool _isEnd = true;
  int _page = 1;
  Object? _error;
  List<String> _history = [];

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _loadHistory();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _focusNode.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadHistory() async {
    final store = await SearchHistoryStore.create();
    if (!mounted) return;
    setState(() => _history = store.load());
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      _loadMore();
    }
  }

  /// 提交搜索：记录历史 + 拉首页结果。
  Future<void> _submitSearch([String? preset]) async {
    final kw = (preset ?? _searchController.text).trim();
    if (kw.isEmpty) return;
    _searchController.text = kw;
    _keyword = kw;
    _page = 1;
    setState(() {
      _isLoading = true;
      _error = null;
      _tracks.clear();
      _albums.clear();
      _artists.clear();
      _sheets.clear();
    });
    _focusNode.unfocus();

    try {
      final store = await SearchHistoryStore.create();
      await store.add(kw);
      if (!mounted) return;
      setState(() => _history = store.load());
    } catch (_) {
      // 历史写失败不阻塞搜索。
    }

    try {
      final api = ref.read(pluginBrowseApiProvider);
      final res = await api.search(keywords: _keyword, type: _type.name);
      if (!mounted) return;
      setState(() {
        _fillResults(res);
        _isEnd = res.isEnd;
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

  void _fillResults(BrowseSearchResponse res) {
    switch (res.type) {
      case 'album':
        _albums.addAll(res.albums);
      case 'artist':
        _artists.addAll(res.artists);
      case 'sheet':
        _sheets.addAll(res.sheets);
      default:
        _tracks.addAll(res.tracks);
    }
  }

  /// 切换类型 tab：就地换结果列表，同一关键词免重输。
  Future<void> _switchType(BrowseSearchType type) async {
    if (type == _type || _keyword.isEmpty) {
      if (_keyword.isNotEmpty) return;
      setState(() => _type = type);
      return;
    }
    setState(() {
      _type = type;
      _tracks.clear();
      _albums.clear();
      _artists.clear();
      _sheets.clear();
      _isLoading = true;
      _error = null;
      _isEnd = true;
      _page = 1;
    });
    try {
      final api = ref.read(pluginBrowseApiProvider);
      final res = await api.search(keywords: _keyword, type: _type.name);
      if (!mounted) return;
      setState(() {
        _fillResults(res);
        _isEnd = res.isEnd;
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

  Future<void> _loadMore() async {
    if (_isLoading || _isLoadingMore || _isEnd || _keyword.isEmpty) return;
    setState(() => _isLoadingMore = true);
    try {
      final api = ref.read(pluginBrowseApiProvider);
      final res = await api.search(
        keywords: _keyword,
        type: _type.name,
        page: _page + 1,
      );
      if (!mounted) return;
      setState(() {
        _fillResults(res);
        _isEnd = res.isEnd;
        if (!res.isEnd) _page += 1;
        _isLoadingMore = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _isLoadingMore = false);
    }
  }

  void _removeHistory(String keyword) async {
    final store = await SearchHistoryStore.create();
    final next = await store.remove(keyword);
    if (!mounted) return;
    setState(() => _history = next);
  }

  void _clearHistory() async {
    final store = await SearchHistoryStore.create();
    final next = await store.clear();
    if (!mounted) return;
    setState(() => _history = next);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final hasSearched = _keyword.isNotEmpty;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.libraryTitle)),
      body: Column(
        children: [
          _buildSearchField(context),
          if (hasSearched) _buildTypeTabs(context),
          Expanded(
            child:
                hasSearched
                    ? _buildResults(context)
                    : _buildHistoryPanel(context),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchField(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.md, 8, AppSpacing.md, 4),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _searchController,
              focusNode: _focusNode,
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => _submitSearch(),
              decoration: InputDecoration(
                hintText: l10n.browseSearchHint,
                prefixIcon: const Icon(Icons.search),
                suffixIcon:
                    _searchController.text.isNotEmpty
                        ? IconButton(
                          icon: const Icon(Icons.clear),
                          tooltip: AppLocalizations.of(context).clearSearch,
                          onPressed: () {
                            _searchController.clear();
                            setState(() {
                              _keyword = '';
                              _error = null;
                              _tracks.clear();
                              _albums.clear();
                              _artists.clear();
                              _sheets.clear();
                            });
                          },
                        )
                        : null,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppSpacing.xl),
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTypeTabs(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    Widget chip(BrowseSearchType type, String label) {
      final selected = _type == type;
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: ChoiceChip(
          label: Text(label),
          selected: selected,
          visualDensity: VisualDensity.compact,
          onSelected: (_) => _switchType(type),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: 4,
      ),
      child: Row(
        children: [
          chip(BrowseSearchType.music, l10n.browseTabTracks),
          chip(BrowseSearchType.album, l10n.browseTabAlbums),
          chip(BrowseSearchType.artist, l10n.browseTabArtists),
          chip(BrowseSearchType.sheet, l10n.browseTabSheets),
        ],
      ),
    );
  }

  Widget _buildResults(BuildContext context) {
    final currentSong = ref.watch(currentSongProvider);
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return BrowseStateView(
        isLoading: false,
        error: _error,
        onRetry: () => _submitSearch(_keyword),
        emptyTitle: '',
      );
    }
    final empty = switch (_type) {
      BrowseSearchType.music => _tracks.isEmpty,
      BrowseSearchType.album => _albums.isEmpty,
      BrowseSearchType.artist => _artists.isEmpty,
      BrowseSearchType.sheet => _sheets.isEmpty,
    };
    if (empty) {
      return EmptyState(
        icon: Icons.search_off,
        title: AppLocalizations.of(context).browseSearchEmpty(_keyword),
      );
    }
    final count = switch (_type) {
      BrowseSearchType.music => _tracks.length,
      BrowseSearchType.album => _albums.length,
      BrowseSearchType.artist => _artists.length,
      BrowseSearchType.sheet => _sheets.length,
    };
    return ListView.builder(
      controller: _scrollController,
      itemCount: count + (_isEnd ? 0 : 1),
      itemBuilder: (context, index) {
        if (index >= count) {
          return const Padding(
            padding: EdgeInsets.all(16),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        switch (_type) {
          case BrowseSearchType.music:
            final track = _tracks[index];
            return BrowseTrackTile(
              track: track,
              index: index,
              showSource: true,
              isCurrent: isCurrentBrowseTrack(currentSong, track),
              onTap:
                  () => RemotePlayback.importAndPlay(
                    context,
                    ref,
                    _tracks,
                    startIndex: index,
                  ),
              onAddToPlaylist:
                  () => RemotePlayback.showAddToPlaylist(context, ref, [track]),
            );
          case BrowseSearchType.album:
            final album = _albums[index];
            return ListTile(
              leading: BrowseCover(
                url: album.coverUrl,
                fallbackIcon: Icons.album_outlined,
              ),
              title: Text(
                album.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text(
                '${album.artist}${album.trackCount > 0 ? ' · ${album.trackCount}' : ''}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              onTap: () => pushAlbumDetail(context, album),
            );
          case BrowseSearchType.artist:
            final artist = _artists[index];
            return ListTile(
              leading: BrowseCover(
                url: artist.avatarUrl,
                circle: true,
                fallbackIcon: Icons.person_outline,
              ),
              title: Text(
                artist.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle:
                  artist.alias != null
                      ? Text(
                        artist.alias!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      )
                      : null,
              onTap: () => pushArtistDetail(context, artist),
            );
          case BrowseSearchType.sheet:
            final sheet = _sheets[index];
            return ListTile(
              leading: BrowseCover(
                url: sheet.coverUrl,
                fallbackIcon: Icons.queue_music_outlined,
              ),
              title: Text(
                sheet.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text(
                '${sheet.creator} · ${sheet.trackCount}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              onTap: () => pushSheetDetail(context, sheet),
            );
        }
      },
    );
  }

  // ---------- 搜索历史面板（票 02） ----------

  Widget _buildHistoryPanel(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    if (_history.isEmpty) {
      return EmptyState(
        icon: Icons.history,
        title: l10n.browseHistoryEmpty,
        subtitle: l10n.browseSearchHint,
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.md,
            AppSpacing.sm,
            AppSpacing.xs,
            0,
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  l10n.browseSearchHistory,
                  style: Theme.of(context).textTheme.labelLarge,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.delete_sweep_outlined, size: 20),
                tooltip: l10n.browseClearHistory,
                onPressed: _clearHistory,
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: _history.length,
            itemBuilder: (context, index) {
              final keyword = _history[index];
              return ListTile(
                leading: const Icon(Icons.history, size: 20),
                title: Text(
                  keyword,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: IconButton(
                  icon: const Icon(Icons.close, size: 18),
                  tooltip: AppLocalizations.of(context).commonDelete,
                  onPressed: () => _removeHistory(keyword),
                ),
                dense: true,
                onTap: () => _submitSearch(keyword),
              );
            },
          ),
        ),
      ],
    );
  }
}
