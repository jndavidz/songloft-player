/// 推荐歌单页（票 12）：平台分类标签（pinned 热门 + 全量分组，非硬编码）横向
/// 滚动 → 点击分类拉取该类歌单列表 → 点击歌单进歌单详情页。

library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_dimensions.dart';
import '../../../l10n/app_localizations.dart';
import '../data/browse_models.dart';
import '../data/plugin_browse_api.dart';
import 'sheet_detail_page.dart';
import 'widgets/browse_cover.dart';
import 'widgets/browse_state_view.dart';

class RecommendSheetsPage extends ConsumerStatefulWidget {
  const RecommendSheetsPage({super.key});

  @override
  ConsumerState<RecommendSheetsPage> createState() =>
      _RecommendSheetsPageState();
}

class _RecommendSheetsPageState extends ConsumerState<RecommendSheetsPage> {
  BrowseRecommendTags? _tags;
  Object? _tagsError;

  String? _selectedTag;
  final List<BrowseSheet> _sheets = [];
  bool _sheetsLoading = false;
  bool _sheetsLoadingMore = false;
  bool _sheetsEnd = false;
  int _page = 1;
  Object? _sheetsError;

  @override
  void initState() {
    super.initState();
    _loadTags();
  }

  Future<void> _loadTags() async {
    try {
      final api = ref.read(pluginBrowseApiProvider);
      final tags = await api.recommendTags();
      if (!mounted) return;
      setState(() => _tags = tags);
      if (_selectedTag == null && tags.pinned.isNotEmpty) {
        _selectTag(tags.pinned.first.id);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _tagsError = e);
    }
  }

  Future<void> _selectTag(String tag) async {
    if (tag == _selectedTag) return;
    setState(() {
      _selectedTag = tag;
      _sheets.clear();
      _sheetsEnd = false;
      _page = 1;
      _sheetsLoading = true;
      _sheetsError = null;
    });
    await _fetchSheets(reset: true);
  }

  Future<void> _fetchSheets({bool reset = false}) async {
    final cat = _selectedTag ?? '';
    try {
      final api = ref.read(pluginBrowseApiProvider);
      final page = reset ? 1 : _page + 1;
      final res = await api.recommendSheets(cat: cat, page: page);
      if (!mounted) return;
      if (cat != _selectedTag) return; // 分类已切换，丢弃过期响应
      setState(() {
        if (reset) _sheets.clear();
        _sheets.addAll(res.items);
        _sheetsEnd = res.isEnd;
        if (!res.isEnd) _page = page;
        _sheetsLoading = false;
        _sheetsLoadingMore = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _sheetsError = e;
        _sheetsLoading = false;
        _sheetsLoadingMore = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.discoverRecommend)),
      body:
          _tags == null && _tagsError == null
              ? const Center(child: CircularProgressIndicator())
              : _tagsError != null
              ? BrowseStateView(
                isLoading: false,
                error: _tagsError,
                onRetry: _loadTags,
                emptyTitle: '',
              )
              : Column(
                children: [
                  _buildTagBar(context),
                  const Divider(height: 1),
                  Expanded(child: _buildSheetList(context)),
                ],
              ),
    );
  }

  Widget _buildTagBar(BuildContext context) {
    final tags = _tags!;
    final all = [...tags.pinned, for (final g in tags.groups) ...g.tags];
    // 同名去重（pinned 与分组会重复出现热门标签）。
    final seen = <String>{};
    final unique = all.where((t) => seen.add(t.id)).toList();

    return SizedBox(
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
        itemCount: unique.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final tag = unique[index];
          final selected = tag.id == _selectedTag;
          return ChoiceChip(
            label: Text(tag.title),
            selected: selected,
            visualDensity: VisualDensity.compact,
            onSelected: (_) => _selectTag(tag.id),
          );
        },
      ),
    );
  }

  Widget _buildSheetList(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    if (_sheetsLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_sheetsError != null) {
      return BrowseStateView(
        isLoading: false,
        error: _sheetsError,
        onRetry: () {
          setState(() => _sheetsError = null);
          _fetchSheets(reset: true);
        },
        emptyTitle: '',
      );
    }
    if (_sheets.isEmpty) {
      return BrowseStateView(
        isLoading: false,
        emptyTitle: l10n.discoverRecommend,
        emptyIcon: Icons.queue_music_outlined,
      );
    }
    return NotificationListener<ScrollNotification>(
      onNotification: (n) {
        if (n.metrics.pixels >= n.metrics.maxScrollExtent - 200 &&
            !_sheetsEnd &&
            !_sheetsLoading &&
            !_sheetsLoadingMore &&
            _sheetsError == null) {
          setState(() => _sheetsLoadingMore = true);
          _fetchSheets();
        }
        return false;
      },
      child: GridView.builder(
        padding: const EdgeInsets.all(AppSpacing.md),
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 200,
          mainAxisSpacing: AppSpacing.md,
          crossAxisSpacing: AppSpacing.md,
          childAspectRatio: 0.75,
        ),
        itemCount: _sheets.length + (_sheetsEnd ? 0 : 1),
        itemBuilder: (context, index) {
          if (index >= _sheets.length) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(8),
                child: CircularProgressIndicator(),
              ),
            );
          }
          final sheet = _sheets[index];
          return _SheetCard(
            sheet: sheet,
            onTap: () => pushSheetDetail(context, sheet),
          );
        },
      ),
    );
  }
}

class _SheetCard extends StatelessWidget {
  final BrowseSheet sheet;
  final VoidCallback onTap;

  const _SheetCard({required this.sheet, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
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
                  BrowseCover(
                    url: sheet.coverUrl,
                    width: double.infinity,
                    height: double.infinity,
                    fallbackIcon: Icons.queue_music_outlined,
                  ),
                  if (sheet.playCount > 0)
                    Positioned(
                      top: 6,
                      right: 6,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.45),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          _compactCount(sheet.playCount),
                          style: theme.textTheme.labelSmall?.copyWith(
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
            sheet.name,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall,
          ),
          if (sheet.trackCount > 0)
            Text(
              l10n.browseTrackCount(sheet.trackCount),
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
        ],
      ),
    );
  }

  static String _compactCount(int n) {
    if (n >= 100000000) return '${(n / 100000000).toStringAsFixed(1)}亿';
    if (n >= 10000) return '${(n / 10000).toStringAsFixed(1)}万';
    return '$n';
  }
}
