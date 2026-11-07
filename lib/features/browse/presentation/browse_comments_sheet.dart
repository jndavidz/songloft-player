/// 播放页评论弹层（票 13，只读）：热评优先 + 分页加载 + 用户名/头像/内容/时间/点赞。
/// **按歌曲自己的音源取评论**（netease/qq/kugou/kuwo，各自内容不同），不再固定
/// 回搜 netease；源不支持评论（migu/qianqian）或歌曲没有在线来源时给明确提示。

library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_dimensions.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/models/song.dart';
import '../../../shared/utils/published_time.dart';
import '../../../shared/utils/song_source_label.dart';
import '../data/browse_models.dart';
import '../data/plugin_browse_api.dart';
import 'widgets/browse_cover.dart';
import 'widgets/browse_state_view.dart';

/// 服务端门面已实现评论的来源（与 kwqq 插件 COMMENT_SOURCES 一致）。
const Set<String> kCommentSourceKeys = {'netease', 'qq', 'kugou', 'kuwo'};

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
  bool _unsupported = false;
  int _page = 1;
  int _total = 0;
  Object? _error;

  /// 当前歌曲的音源标识（source_data.s），与展示名分开：路由用标识、UI 用名称。
  String? _source;
  String? _songSourceId;

  /// 实际命中来源（插件回传优先），用于头部「当前来源」标识。
  String? _displaySource;

  @override
  void initState() {
    super.initState();
    _source = songSourceKey(widget.song);
    _songSourceId = songSourceId(widget.song);
    _displaySource = _source;
    _load(reset: true);
  }

  Future<void> _load({bool reset = false}) async {
    final source = _source;
    // 源不支持或歌曲没有在线来源：不发请求，直接给明确提示（不换源、不装空列表）。
    if (source == null || !kCommentSourceKeys.contains(source)) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _isLoadingMore = false;
          _hasMore = false;
          _unsupported = true;
          _error = null;
        });
      }
      return;
    }
    if (reset) {
      setState(() {
        _isLoading = true;
        _error = null;
        _unsupported = false;
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
        source: source,
        id: _songSourceId,
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
        _displaySource = res.source ?? source;
        if (res.hasMore) _page = page;
        _isLoading = false;
        _isLoadingMore = false;
      });
    } on BrowseUnsupportedException {
      if (!mounted) return;
      setState(() {
        _unsupported = true;
        _error = null;
        _isLoading = false;
        _isLoadingMore = false;
        _hasMore = false;
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
    final sourceLabel =
        _displaySource == null ? null : kSongPlatformNames[_displaySource];
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
          child: Row(
            children: [
              Text(
                '${l10n.browseComments} $_total',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              if (sourceLabel != null) ...[
                const SizedBox(width: 8),
                _SourceBadge(label: sourceLabel),
              ],
              const Spacer(),
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
                  : _unsupported
                  ? BrowseStateView(
                    isLoading: false,
                    emptyTitle:
                        _source == null
                            ? l10n.browseCommentsNoSource
                            : l10n.browseCommentsUnsupported,
                    emptySubtitle: _source == null ? null : sourceLabel,
                    emptyIcon: Icons.block_outlined,
                  )
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

/// 当前来源小标识（克制样式：浅底小字，只标平台名，不出现内部枚举）。
class _SourceBadge extends StatelessWidget {
  final String label;

  const _SourceBadge({required this.label});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

class _CommentTile extends StatelessWidget {
  final BrowseComment comment;

  const _CommentTile({required this.comment});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    // 字段缺失时整条隐藏：不显示空占位，也不拿 1970 兜底。
    final timeLabel =
        comment.publishedAt != null
            ? formatPublishedTime(
              comment.publishedAt!,
              yesterdayLabel: l10n.browseTimeYesterday,
            )
            : comment.publishedAtText;
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
              BrowseCover(
                url: comment.avatar,
                size: 28,
                circle: true,
                fallbackIcon: Icons.person_outline,
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
              if (timeLabel != null) ...[
                const SizedBox(width: 8),
                Text(
                  timeLabel,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
              const SizedBox(width: 8),
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
