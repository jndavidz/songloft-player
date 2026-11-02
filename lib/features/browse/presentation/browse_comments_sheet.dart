/// 播放页评论弹层（票 13，只读）：热评优先 + 分页加载 + 用户名/头像/内容/时间/点赞。
/// 当前歌为在线歌时优先按标题/歌手回搜（Song 模型不透出 source_data，插件端点
/// 支持 title+artist 回搜 netease id）；无评论资源时给空态；限流/失败给错误态可重试。

library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_dimensions.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/models/song.dart';
import '../data/browse_models.dart';
import '../data/plugin_browse_api.dart';
import 'widgets/browse_state_view.dart';

class BrowseCommentsSheet extends ConsumerStatefulWidget {
  final Song song;

  const BrowseCommentsSheet({super.key, required this.song});

  static Future<void> show(BuildContext context, Song song) {
    return showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      useSafeArea: true,
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.75,
      ),
      builder: (_) => BrowseCommentsSheet(song: song),
    );
  }

  @override
  ConsumerState<BrowseCommentsSheet> createState() =>
      _BrowseCommentsSheetState();
}

class _BrowseCommentsSheetState extends ConsumerState<BrowseCommentsSheet> {
  final List<BrowseComment> _hot = [];
  final List<BrowseComment> _comments = [];

  bool _isLoading = true;
  bool _isLoadingMore = false;
  bool _hasMore = false;
  int _page = 1;
  int _total = 0;
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
      if (_isLoadingMore || !_hasMore) return;
      setState(() => _isLoadingMore = true);
    }
    try {
      final api = ref.read(pluginBrowseApiProvider);
      final page = reset ? 1 : _page + 1;
      final res = await api.comments(
        title: widget.song.title,
        artist: widget.song.artist,
        page: page,
      );
      if (!mounted) return;
      setState(() {
        if (reset) {
          _hot.clear();
          _comments.clear();
        }
        _hot.addAll(reset ? res.hot : const []);
        _comments.addAll(res.comments);
        _total = res.total;
        _hasMore = res.hasMore;
        if (res.hasMore) _page = page;
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
    final l10n = AppLocalizations.of(context);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  '${l10n.browseComments} $_total',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close, size: 20),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
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
                  : _hot.isEmpty && _comments.isEmpty
                  ? BrowseStateView(
                    isLoading: false,
                    emptyTitle: l10n.browseCommentsEmpty,
                    emptyIcon: Icons.chat_bubble_outline,
                  )
                  : NotificationListener<ScrollNotification>(
                    onNotification: (n) {
                      if (n.metrics.pixels >= n.metrics.maxScrollExtent - 200) {
                        _load();
                      }
                      return false;
                    },
                    child: ListView.builder(
                      padding: const EdgeInsets.only(bottom: 24),
                      itemCount:
                          _hot.length +
                          _comments.length +
                          (_hasMore ? 1 : 0) +
                          (_hot.isNotEmpty ? 1 : 0),
                      itemBuilder: (context, index) {
                        if (_hot.isNotEmpty && index == 0) {
                          return Padding(
                            padding: const EdgeInsets.fromLTRB(
                              AppSpacing.lg,
                              AppSpacing.sm,
                              AppSpacing.lg,
                              0,
                            ),
                            child: Text(
                              l10n.browseCommentsHot,
                              style: Theme.of(context).textTheme.labelLarge,
                            ),
                          );
                        }
                        final hotEnd = _hot.length + (_hot.isNotEmpty ? 1 : 0);
                        if (index < hotEnd) {
                          return _CommentTile(comment: _hot[index - 1]);
                        }
                        if (_hot.isNotEmpty && index == hotEnd) {
                          return Padding(
                            padding: const EdgeInsets.fromLTRB(
                              AppSpacing.lg,
                              AppSpacing.sm,
                              AppSpacing.lg,
                              0,
                            ),
                            child: Text(
                              l10n.browseCommentsLatest,
                              style: Theme.of(context).textTheme.labelLarge,
                            ),
                          );
                        }
                        final latestIndex =
                            index - hotEnd - (_hot.isNotEmpty ? 1 : 0);
                        if (latestIndex < _comments.length) {
                          return _CommentTile(comment: _comments[latestIndex]);
                        }
                        return const Padding(
                          padding: EdgeInsets.all(16),
                          child: Center(child: CircularProgressIndicator()),
                        );
                      },
                    ),
                  ),
        ),
      ],
    );
  }
}

class _CommentTile extends StatelessWidget {
  final BrowseComment comment;

  const _CommentTile({required this.comment});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.sm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              ClipOval(
                child:
                    comment.avatar != null && comment.avatar!.isNotEmpty
                        ? Image.network(
                          comment.avatar!,
                          width: 28,
                          height: 28,
                          fit: BoxFit.cover,
                          errorBuilder:
                              (_, _, _) =>
                                  const ColoredBox(color: Color(0x1A808080)),
                        )
                        : Container(
                          width: 28,
                          height: 28,
                          color: const Color(0x1A808080),
                          child: const Icon(Icons.person, size: 16),
                        ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  comment.nickName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              Icon(
                Icons.thumb_up_alt_outlined,
                size: 14,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 4),
              Text(
                '${comment.like}',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(comment.comment, style: theme.textTheme.bodyMedium),
          for (final reply in comment.replies)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text.rich(
                  TextSpan(
                    text: '${reply.nickName}：',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.primary,
                    ),
                    children: [
                      TextSpan(
                        text: reply.comment,
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
