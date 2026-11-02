/// 浏览页统一三态（加载 / 空 / 错误），票 01 的骨架级统一样式。
///
/// 错误态区分「该源暂不支持」（501 能力缺失）与一般失败：前者只提示不支持、
/// 不给重试（重试必然再失败）；后者给重试按钮。

library;

import 'package:flutter/material.dart';

import '../../../../l10n/app_localizations.dart';
import '../../data/plugin_browse_api.dart';

class BrowseStateView extends StatelessWidget {
  final bool isLoading;

  /// 任意异常对象：BrowseUnsupportedException 走「暂不支持」态，其余给重试。
  final Object? error;
  final VoidCallback? onRetry;

  /// 空态文案标题（错误为空且数据为空时展示）。
  final String emptyTitle;
  final String? emptySubtitle;
  final IconData emptyIcon;

  /// 空态底部的额外语义动作（如本地音乐的「去扫描」）。
  final Widget? emptyAction;

  const BrowseStateView({
    super.key,
    required this.isLoading,
    this.error,
    this.onRetry,
    required this.emptyTitle,
    this.emptySubtitle,
    this.emptyIcon = Icons.music_note_outlined,
    this.emptyAction,
  });

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (error != null) {
      final message = error.toString();
      final isUnsupported =
          error is BrowseUnsupportedException || _looksUnsupported(message);
      final l10n = AppLocalizations.of(context);
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                isUnsupported ? Icons.block_outlined : Icons.cloud_off_outlined,
                size: 48,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              const SizedBox(height: 12),
              Text(
                isUnsupported ? l10n.browseUnsupported : message,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              if (!isUnsupported && onRetry != null) ...[
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh),
                  label: Text(l10n.browseRetry),
                ),
              ],
            ],
          ),
        ),
      );
    }
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              emptyIcon,
              size: 48,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 12),
            Text(
              emptyTitle,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            if (emptySubtitle != null) ...[
              const SizedBox(height: 4),
              Text(
                emptySubtitle!,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
            if (emptyAction != null) ...[
              const SizedBox(height: 12),
              emptyAction!,
            ],
          ],
        ),
      ),
    );
  }

  static bool _looksUnsupported(String message) =>
      message.contains('BrowseUnsupportedException') ||
      message.contains('暂不支持') ||
      message.contains('not supported');
}
