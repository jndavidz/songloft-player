/// 推荐歌单页（票 12；2026-11 多源改版）：顶部两段式——第一段平台选择、
/// 第二段该平台标签（Wrap 换行，不再横向拉动）→ 点击标签拉取该类歌单列表
/// → 点击歌单进歌单详情页。标签/歌单均来自插件多源聚合（netease/kugou）。

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

  String? _selectedSource;
  String? _selectedTag;
  final List<BrowseSheet> _sheets = [];
  bool _sheetsLoading = false;
  bool _sheetsLoadingMore = false;
  bool _sheetsEnd = false;
  int _page = 1;
  Object? _sheetsError;

  BrowsePlatformTags? get _currentPlatform {
    final platforms = _tags?.platforms ?? const [];
    for (final p in platforms) {
      if (p.source == _selectedSource) return p;
    }
    return platforms.isNotEmpty ? platforms.first : null;
  }

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
      if (_selectedSource == null && tags.platforms.isNotEmpty) {
        _selectPlatform(tags.platforms.first.source);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _tagsError = e);
    }
  }

  /// 该平台默认标签：pinned 首个，否则首个分组首个，再否则空（cat='' 全部）。
  String? _defaultTagFor(BrowsePlatformTags platform) {
    if (platform.pinned.isNotEmpty) return platform.pinned.first.id;
    for (final g in platform.groups) {
      if (g.tags.isNotEmpty) return g.tags.first.id;
    }
    return null;
  }

  Future<void> _selectPlatform(String source) async {
    final platform = _tags!.platforms.firstWhere((p) => p.source == source);
    setState(() {
      _selectedSource = source;
      _selectedTag = _defaultTagFor(platform);
      _sheets.clear();
      _sheetsEnd = false;
      _page = 1;
      _sheetsLoading = true;
      _sheetsError = null;
    });
    await _fetchSheets(reset: true);
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
    final source = _selectedSource ?? 'netease';
    try {
      final api = ref.read(pluginBrowseApiProvider);
      final page = reset ? 1 : _page + 1;
      final res = await api.recommendSheets(
        cat: cat,
        source: source,
        page: page,
      );
      if (!mounted) return;
      if (cat != _selectedTag || source != _selectedSource) {
        return; // 分类/平台已切换，丢弃过期响应
      }
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
                  _buildPlatformBar(context),
                  const Divider(height: 1),
                  _buildTagArea(context),
                  const Divider(height: 1),
                  Expanded(child: _buildSheetList(context)),
                ],
              ),
    );
  }

  /// 第一段：平台选择（选中平台只看该平台标签）。
  Widget _buildPlatformBar(BuildContext context) {
    final platforms = _tags!.platforms;
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.md, 8, AppSpacing.md, 4),
      child: Wrap(
        spacing: 8,
        runSpacing: 4,
        children: [
          for (final p in platforms)
            ChoiceChip(
              label: Text(browsePlatformLabel(p.source)),
              selected: p.source == _selectedSource,
              visualDensity: VisualDensity.compact,
              onSelected: (_) => _selectPlatform(p.source),
            ),
        ],
      ),
    );
  }

  /// 第二段：当前平台的标签，Wrap 换行竖排（不再横向滚动）。
  /// pinned 置顶在前，分组带小标题；区域限高、超高竖向滚动。
  Widget _buildTagArea(BuildContext context) {
    final platform = _currentPlatform;
    if (platform == null) return const SizedBox.shrink();
    final theme = Theme.of(context);

    Widget tagChip(BrowseTag tag) {
      final selected = tag.id == _selectedTag;
      return ChoiceChip(
        label: Text(tag.title),
        selected: selected,
        visualDensity: VisualDensity.compact,
        onSelected: (_) => _selectTag(tag.id),
      );
    }

    final children = <Widget>[
      for (final t in platform.pinned) tagChip(t),
      for (final g in platform.groups)
        if (g.tags.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              g.title,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          for (final t in g.tags) tagChip(t),
        ],
    ];

    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 220),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(AppSpacing.md, 6, AppSpacing.md, 8),
        child: Wrap(
          spacing: 8,
          runSpacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: children,
        ),
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
            showSource: _tags!.platforms.length > 1,
            onTap: () => pushSheetDetail(context, sheet),
          );
        },
      ),
    );
  }
}

class _SheetCard extends StatelessWidget {
  final BrowseSheet sheet;

  /// 多平台时在封面角标来源平台。
  final bool showSource;
  final VoidCallback onTap;

  const _SheetCard({
    required this.sheet,
    this.showSource = false,
    required this.onTap,
  });

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
                  if (showSource)
                    Positioned(
                      top: 6,
                      left: 6,
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
                          browsePlatformLabel(sheet.source),
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: Colors.white,
                          ),
                        ),
                      ),
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
