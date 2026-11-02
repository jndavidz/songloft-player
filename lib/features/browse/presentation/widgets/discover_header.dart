/// 曲库顶部「在线发现」区（票 01）：顶部搜索框（kwqq 源标识）+
/// 「推荐歌单 / 榜单 / 播放历史 / 本地音乐」四入口，MusicFree 信息架构。
/// 既有库内浏览视图（分类聚合/文件夹/标签）保留，本区叠在其上方常驻。

library;

import 'package:flutter/material.dart';

import '../../../../core/theme/app_dimensions.dart';
import '../../../../l10n/app_localizations.dart';
import '../recent_plays_page.dart';
import '../recommend_sheets_page.dart';
import '../search_page.dart';
import '../toplists_page.dart';

class DiscoverHeader extends StatelessWidget {
  /// 「本地音乐」入口：曲库内已有 local 扁平视图，直接切换视图而非新开页。
  final void Function(String viewKey) onSelectView;

  const DiscoverHeader({super.key, required this.onSelectView});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.sm,
        AppSpacing.md,
        AppSpacing.xs,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 顶部搜索框（带 kwqq 源标识，点击进入在线搜索页）
          InkWell(
            borderRadius: BorderRadius.circular(AppSpacing.xl),
            onTap:
                () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const BrowseSearchPage(),
                  ),
                ),
            child: InputDecorator(
              decoration: InputDecoration(
                hintText: l10n.browseSearchHint,
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppSpacing.xl),
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                isDense: true,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 1,
                    ),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      'kwqq',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onPrimaryContainer,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          // 四入口宫格
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _Entry(
                icon: Icons.explore_outlined,
                label: l10n.discoverRecommend,
                onTap:
                    () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const RecommendSheetsPage(),
                      ),
                    ),
              ),
              _Entry(
                icon: Icons.leaderboard_outlined,
                label: l10n.discoverToplists,
                onTap:
                    () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const ToplistsPage(),
                      ),
                    ),
              ),
              _Entry(
                icon: Icons.history,
                label: l10n.discoverPlayHistory,
                onTap:
                    () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const RecentPlaysPage(),
                      ),
                    ),
              ),
              _Entry(
                icon: Icons.library_music_outlined,
                label: l10n.discoverLocalMusic,
                onTap: () => onSelectView('local'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Entry extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _Entry({required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: theme.colorScheme.primary),
            const SizedBox(height: 4),
            Text(
              label,
              style: theme.textTheme.labelSmall,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}
