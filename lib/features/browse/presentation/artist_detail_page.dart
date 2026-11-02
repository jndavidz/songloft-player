/// 歌手详情页（票 09）：hero（头像/简介）+ 热门单曲（可播）+ 专辑列表（进 08 专辑页）。
/// 作品列表分页/截断；无数据的源给明确错误态。

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
import 'album_detail_page.dart';
import 'widgets/browse_cover.dart';
import 'widgets/browse_state_view.dart';
import 'widgets/browse_track_tile.dart';

void pushArtistDetail(BuildContext context, BrowseArtist artist) {
  Navigator.of(context).push(
    MaterialPageRoute<void>(builder: (_) => ArtistDetailPage(artist: artist)),
  );
}

class ArtistDetailPage extends ConsumerStatefulWidget {
  final BrowseArtist artist;

  const ArtistDetailPage({super.key, required this.artist});

  @override
  ConsumerState<ArtistDetailPage> createState() => _ArtistDetailPageState();
}

class _ArtistDetailPageState extends ConsumerState<ArtistDetailPage> {
  BrowseArtist? _info;
  Object? _error;

  // 作品区
  bool _worksAlbumMode = false;
  final List<BrowseTrack> _tracks = [];
  final List<BrowseAlbum> _albums = [];
  bool _worksLoading = false;
  bool _worksLoadingMore = false;
  bool _worksEnd = false;
  int _worksPage = 1;

  @override
  void initState() {
    super.initState();
    _loadInfo();
    _loadWorks(reset: true);
  }

  Future<void> _loadInfo() async {
    try {
      final api = ref.read(pluginBrowseApiProvider);
      final info = await api.artistInfo(id: widget.artist.id);
      if (!mounted) return;
      setState(() => _info = info);
    } catch (_) {
      // 详情失败不阻塞作品列表（搜索结果已带名称/头像）。
    }
  }

  Future<void> _loadWorks({bool reset = false}) async {
    if (_worksLoading || _worksLoadingMore) return;
    setState(() {
      if (reset) {
        _worksPage = 1;
        _worksEnd = false;
        _tracks.clear();
        _albums.clear();
        _worksLoading = true;
      } else {
        _worksLoadingMore = true;
      }
      _error = null;
    });
    try {
      final api = ref.read(pluginBrowseApiProvider);
      final works = await api.artistWorks(
        id: widget.artist.id,
        type: _worksAlbumMode ? 'album' : 'music',
        page: reset ? 1 : _worksPage + 1,
      );
      if (!mounted) return;
      setState(() {
        if (works.type == 'album') {
          _albums.addAll(works.albums);
        } else {
          _tracks.addAll(works.tracks);
        }
        _worksEnd = works.isEnd;
        if (!works.isEnd) _worksPage = reset ? 1 : _worksPage + 1;
        _worksLoading = false;
        _worksLoadingMore = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _worksLoading = false;
        _worksLoadingMore = false;
      });
    }
  }

  void _switchWorksMode(bool albumMode) {
    if (albumMode == _worksAlbumMode) return;
    _worksAlbumMode = albumMode;
    _loadWorks(reset: true);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final currentSong = ref.watch(currentSongProvider);
    final artist = _info ?? widget.artist;
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: Text(artist.name)),
      body: NotificationListener<ScrollNotification>(
        onNotification: (n) {
          if (n.metrics.pixels >= n.metrics.maxScrollExtent - 200 &&
              !_worksEnd &&
              !_worksLoading &&
              !_worksLoadingMore &&
              _error == null) {
            _loadWorks();
          }
          return false;
        },
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: Row(
                  children: [
                    BrowseCover(
                      url: artist.avatarUrl,
                      size: 88,
                      circle: true,
                      fallbackIcon: Icons.person_outline,
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(artist.name, style: theme.textTheme.titleLarge),
                          const SizedBox(height: 4),
                          Text(
                            '${l10n.browseTabAlbums} ${artist.albumCount} · ${l10n.browseTabTracks} ${artist.musicCount}',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (artist.description != null && artist.description!.isNotEmpty)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.md,
                  ),
                  child: GestureDetector(
                    onTap:
                        () =>
                            _showFullDescription(context, artist.description!),
                    child: Text(
                      artist.description!,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
              ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: AppSpacing.sm,
                ),
                child: Row(
                  children: [
                    ChoiceChip(
                      label: Text(l10n.browseArtistTopSongs),
                      selected: !_worksAlbumMode,
                      visualDensity: VisualDensity.compact,
                      onSelected: (_) => _switchWorksMode(false),
                    ),
                    const SizedBox(width: 8),
                    ChoiceChip(
                      label: Text(l10n.browseArtistAlbums),
                      selected: _worksAlbumMode,
                      visualDensity: VisualDensity.compact,
                      onSelected: (_) => _switchWorksMode(true),
                    ),
                  ],
                ),
              ),
            ),
            if (_worksLoading)
              const SliverFillRemaining(
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_error != null)
              SliverFillRemaining(
                child: BrowseStateView(
                  isLoading: false,
                  error: _error,
                  onRetry: () => _loadWorks(reset: true),
                  emptyTitle: '',
                ),
              )
            else if (!_worksAlbumMode && _tracks.isEmpty)
              SliverFillRemaining(
                child: BrowseStateView(
                  isLoading: false,
                  emptyTitle: l10n.browseArtistTopSongs,
                  emptyIcon: Icons.music_off_outlined,
                ),
              )
            else if (_worksAlbumMode && _albums.isEmpty)
              SliverFillRemaining(
                child: BrowseStateView(
                  isLoading: false,
                  emptyTitle: l10n.browseArtistAlbums,
                  emptyIcon: Icons.album_outlined,
                ),
              )
            else if (!_worksAlbumMode)
              SliverList.builder(
                itemCount: _tracks.length + (_worksEnd ? 0 : 1),
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
              )
            else
              SliverList.builder(
                itemCount: _albums.length + (_worksEnd ? 0 : 1),
                itemBuilder: (context, index) {
                  if (index >= _albums.length) {
                    return const Padding(
                      padding: EdgeInsets.all(16),
                      child: Center(child: CircularProgressIndicator()),
                    );
                  }
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
                      '${album.artist} · ${album.trackCount}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    onTap: () => pushAlbumDetail(context, album),
                  );
                },
              ),
            const SliverToBoxAdapter(child: SizedBox(height: 32)),
          ],
        ),
      ),
    );
  }

  void _showFullDescription(BuildContext context, String description) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder:
          (context) => SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
              child: SingleChildScrollView(child: Text(description)),
            ),
          ),
    );
  }
}
