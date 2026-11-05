/// 推荐歌单页（票 12；2026-11 四分区改版）：
/// ① 顶部平台切换（网易云 / QQ / 酷狗 / 酷我，顺序统一）；
/// ② 该平台一级分类（默认 + 分组），只占一行，点击后在第三分区展开；
/// ③ 二级分类（选中分类下的标签），只占一行；
/// ④ 歌单列表，每行 4 个，标题固定 2 行高，歌曲数落在封面右下角。
/// 标签/歌单均来自插件多源聚合。

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

  /// 当前一级分类；null = 「默认」（不带 cat，拉该平台全部热门歌单）。
  BrowseTagGroup? _selectedGroup;
  String? _selectedTag;
  final List<BrowseSheet> _sheets = [];
  bool _sheetsLoading = false;
  bool _sheetsLoadingMore = false;
  bool _sheetsEnd = false;
  int _page = 1;
  Object? _sheetsError;

  /// 平台按全站统一顺序展示（插件返回顺序不作数，避免各端不一致）。
  List<BrowsePlatformTags> get _platforms {
    final platforms = _tags?.platforms ?? const <BrowsePlatformTags>[];
    final order = orderBrowsePlatforms(platforms.map((p) => p.source));
    return [
      for (final s in order)
        for (final p in platforms)
          if (p.source == s) p,
    ];
  }

  BrowsePlatformTags? get _currentPlatform {
    final platforms = _platforms;
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
      final platforms = _platforms;
      if (_selectedSource == null && platforms.isNotEmpty) {
        _selectPlatform(platforms.first.source);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _tagsError = e);
    }
  }

  Future<void> _selectPlatform(String source) async {
    setState(() {
      _selectedSource = source;
      _selectedGroup = null; // 切平台回到「默认」
      _selectedTag = null;
      _sheets.clear();
      _sheetsEnd = false;
      _page = 1;
      _sheetsLoading = true;
      _sheetsError = null;
    });
    await _fetchSheets(reset: true);
  }

  /// 选一级分类：null = 默认（cat=''）；有分组时默认选中该分类第一个标签。
  Future<void> _selectGroup(BrowseTagGroup? group) async {
    setState(() {
      _selectedGroup = group;
      _selectedTag =
          group != null && group.tags.isNotEmpty ? group.tags.first.id : null;
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
      if (cat != (_selectedTag ?? '') || source != _selectedSource) {
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
                  _buildGroupBar(context),
                  _buildTagBar(context),
                  const Divider(height: 1),
                  Expanded(child: _buildSheetList(context)),
                ],
              ),
    );
  }

  /// 分区一：平台切换（一行横向滚动，顺序固定）。
  Widget _buildPlatformBar(BuildContext context) {
    final platforms = _platforms;
    return SizedBox(
      height: 48,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(AppSpacing.md, 8, AppSpacing.md, 8),
        children: [
          for (final p in platforms) ...[
            ChoiceChip(
              label: Text(browsePlatformLabel(p.source)),
              selected: p.source == _selectedSource,
              visualDensity: VisualDensity.compact,
              onSelected: (_) => _selectPlatform(p.source),
            ),
            const SizedBox(width: 8),
          ],
        ],
      ),
    );
  }

  /// 分区二：一级分类（默认 + 平台分组），只占一行。
  Widget _buildGroupBar(BuildContext context) {
    final platform = _currentPlatform;
    if (platform == null) return const SizedBox.shrink();
    final groups = platform.groups.where((g) => g.tags.isNotEmpty).toList();
    return SizedBox(
      height: 44,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(AppSpacing.md, 4, AppSpacing.md, 4),
        children: [
          _groupChip(
            label: '默认',
            group: null,
            selected: _selectedGroup == null,
          ),
          for (final g in groups) ...[
            const SizedBox(width: 8),
            _groupChip(
              label: g.title.isNotEmpty ? g.title : '分类',
              group: g,
              selected: _selectedGroup == g,
            ),
          ],
        ],
      ),
    );
  }

  Widget _groupChip({
    required String label,
    required BrowseTagGroup? group,
    required bool selected,
  }) {
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      visualDensity: VisualDensity.compact,
      onSelected: (_) => _selectGroup(group),
    );
  }

  /// 分区三：二级分类（当前一级分类下的标签），只占一行；默认分类下不显示。
  Widget _buildTagBar(BuildContext context) {
    final group = _selectedGroup;
    if (group == null || group.tags.isEmpty) return const SizedBox.shrink();
    return SizedBox(
      height: 44,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(AppSpacing.md, 2, AppSpacing.md, 4),
        children: [
          for (final tag in group.tags) ...[
            FilterChip(
              label: Text(tag.title),
              selected: tag.id == _selectedTag,
              visualDensity: VisualDensity.compact,
              onSelected: (_) => _selectTag(tag.id),
            ),
            const SizedBox(width: 8),
          ],
        ],
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
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 4,
          mainAxisSpacing: AppSpacing.md,
          crossAxisSpacing: 8,
          // 封面 1:1 + 固定 2 行标题区，按 4 列卡片取长宽比。
          childAspectRatio: 0.68,
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
                      top: 4,
                      right: 4,
                      child: _Badge(text: _compactCount(sheet.playCount)),
                    ),
                  // 歌曲数量固定在封面右下角（标题区不再显示，保持封面尺寸一致）。
                  if (sheet.trackCount > 0)
                    Positioned(
                      bottom: 4,
                      right: 4,
                      child: _Badge(
                        text: l10n.browseTrackCount(sheet.trackCount),
                        icon: Icons.music_note,
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 4),
          // 标题区固定 2 行高：1 行与 2 行标题的卡片封面尺寸保持一致。
          SizedBox(
            height: 32,
            child: Text(
              sheet.name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall,
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

class _Badge extends StatelessWidget {
  final String text;
  final IconData? icon;

  const _Badge({required this.text, this.icon});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 11, color: Colors.white),
            const SizedBox(width: 2),
          ],
          Text(
            text,
            style: theme.textTheme.labelSmall?.copyWith(color: Colors.white),
          ),
        ],
      ),
    );
  }
}
