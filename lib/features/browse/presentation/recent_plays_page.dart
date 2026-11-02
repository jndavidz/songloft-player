/// 播放历史页（票 03）：跨上下文最近播放（时间 + 歌曲，倒序），
/// 点击重播（既有 add-remote dedup → play 链），支持清空、触底分页。

library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/app_localizations.dart';
import '../../../shared/utils/responsive_snackbar.dart';
import '../../../shared/widgets/song_tile.dart';
import '../../player/domain/play_history_entry.dart';
import '../../player/presentation/providers/player_provider.dart';
import '../../player/presentation/providers/play_history_provider.dart';
import 'widgets/browse_state_view.dart';

class RecentPlaysPage extends ConsumerStatefulWidget {
  const RecentPlaysPage({super.key});

  @override
  ConsumerState<RecentPlaysPage> createState() => _RecentPlaysPageState();
}

class _RecentPlaysPageState extends ConsumerState<RecentPlaysPage> {
  final List<PlayHistoryEntry> _entries = [];

  bool _isLoading = true;
  bool _isLoadingMore = false;
  bool _isEnd = false;
  int _offset = 0;
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
        _offset = 0;
      });
    } else {
      if (_isLoadingMore || _isEnd) return;
      setState(() => _isLoadingMore = true);
    }
    try {
      final api = ref.read(playHistoryApiProvider);
      final page = await api.getRecentHistory(
        limit: 50,
        offset: reset ? 0 : _offset,
      );
      if (!mounted) return;
      setState(() {
        if (reset) _entries.clear();
        _entries.addAll(page);
        _isEnd = page.length < 50;
        if (!_isEnd) _offset = reset ? page.length : _offset + page.length;
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

  Future<void> _clearAll() async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: Text(l10n.browseClearHistory),
            content: Text(l10n.deleteIrreversible),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text(l10n.commonCancel),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: Text(l10n.commonConfirm),
              ),
            ],
          ),
    );
    if (confirmed != true) return;
    try {
      await ref.read(playHistoryApiProvider).clearRecentHistory();
      if (!mounted) return;
      setState(() {
        _entries.clear();
        _isEnd = true;
      });
      ResponsiveSnackBar.show(context, message: l10n.browseHistoryEmpty);
    } catch (_) {
      if (!mounted) return;
      ResponsiveSnackBar.showError(context, message: l10n.browseLoadFailed);
    }
  }

  void _playFrom(int index) {
    final songs = _entries.map((e) => e.song).toList();
    ref
        .read(playerStateProvider.notifier)
        .playPlaylist(songs, startIndex: index);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final currentSong = ref.watch(currentSongProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.discoverPlayHistory),
        actions: [
          if (_entries.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_sweep_outlined),
              tooltip: l10n.browseClearHistory,
              onPressed: _clearAll,
            ),
        ],
      ),
      body:
          _isLoading
              ? const Center(child: CircularProgressIndicator())
              : _error != null
              ? BrowseStateView(
                isLoading: false,
                error: _error,
                onRetry: () => _load(reset: true),
                emptyTitle: '',
              )
              : _entries.isEmpty
              ? BrowseStateView(
                isLoading: false,
                emptyTitle: l10n.browseRecentEmpty,
                emptyIcon: Icons.history,
              )
              : NotificationListener<ScrollNotification>(
                onNotification: (n) {
                  if (n.metrics.pixels >= n.metrics.maxScrollExtent - 200) {
                    _load();
                  }
                  return false;
                },
                child: ListView.builder(
                  padding: const EdgeInsets.only(bottom: 32),
                  itemCount: _entries.length + (_isEnd ? 0 : 1),
                  itemBuilder: (context, index) {
                    if (index >= _entries.length) {
                      return const Padding(
                        padding: EdgeInsets.all(16),
                        child: Center(child: CircularProgressIndicator()),
                      );
                    }
                    final entry = _entries[index];
                    return SongTile(
                      song: entry.song,
                      subtitleSuffix: _formatTime(entry.playedAt),
                      isCurrentSong: currentSong?.id == entry.song.id,
                      onTap: () => _playFrom(index),
                    );
                  },
                ),
              ),
    );
  }

  static String _formatTime(DateTime utc) {
    final d = utc.toLocal();
    final now = DateTime.now();
    final diff = now.difference(d);
    final hh = d.hour.toString().padLeft(2, '0');
    final mm = d.minute.toString().padLeft(2, '0');
    if (diff.inDays == 0) {
      return '$hh:$mm';
    } else if (diff.inDays < 30) {
      return '${d.month}/${d.day} $hh:$mm';
    }
    return '${d.year}/${d.month}/${d.day}';
  }
}
