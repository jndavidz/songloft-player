import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../l10n/app_localizations.dart';
import '../../../../shared/models/song.dart';
import '../../domain/lyric_parser.dart';
import '../lyric_adjust_page.dart';
import '../providers/lyric_provider.dart';
import '../providers/player_provider.dart';
import '../../../settings/presentation/providers/player_lyric_font_size_provider.dart';
import 'karaoke_line.dart';
import 'player_backdrop.dart';

/// 歌词显示组件
///
/// 从 [lyricStateProvider] 消费歌词状态，自动滚动到当前行并高亮显示。
/// 用户手动滚动时暂停自动滚动，几秒后自动恢复。
/// 点击歌词行可跳转到对应时间点播放。
///
/// 当 [editable] 为 true 且 [song] 是本地歌曲时，右上角显示「调整」按钮，
/// 点击进入 LyricAdjustPage 编辑歌词时间戳。保存后会自动重新拉取歌词。
class LyricsView extends ConsumerStatefulWidget {
  /// 当前播放位置（仍需接收，用于歌词行点击 seek）
  final Duration currentPosition;

  /// 点击歌词行时的回调，传入被点击行的时间点
  final ValueChanged<Duration>? onSeek;

  /// 关联的歌曲对象。仅当 [editable] 为 true 时用于决定是否展示「调整」按钮。
  final Song? song;

  /// 是否允许编辑歌词。即使为 true，也只有 song.type == 'local' 才会显示按钮。
  final bool editable;

  /// 是否允许「长按歌词并上下拖动」按行时间调整播放进度。
  /// 电台 / 时长未知 / 纯文本歌词场景由调用方置 false。
  final bool scrubEnabled;

  /// 点击非歌词行的空白区域时触发（用于点按切回封面）。
  final VoidCallback? onTapBackground;

  const LyricsView({
    super.key,
    required this.currentPosition,
    this.onSeek,
    this.song,
    this.editable = false,
    this.scrubEnabled = false,
    this.onTapBackground,
  });

  @override
  ConsumerState<LyricsView> createState() => _LyricsViewState();
}

class _LyricsViewState extends ConsumerState<LyricsView> {
  final ScrollController _scrollController = ScrollController();
  final GlobalKey _listKey = GlobalKey();

  bool _isUserScrolling = false;
  Timer? _resumeTimer;
  int _lastScrolledIndex = -1;

  /// 长按拖拽进度时落到的歌词行索引（null 表示未在拖拽）。
  int? _scrubIndex;

  /// ListView 的上下留白（让首尾行也能居中），由 LayoutBuilder 更新。
  double _verticalPadding = 0;

  /// 每行统一高度，随是否含翻译/罗马音在 build 中动态计算。
  /// 保持统一便于用 `index * _lineHeight` 精确定位滚动。
  double _lineHeight = 48.0;

  /// 主歌词行高（随歌词字号档位缩放）。
  double _mainRowHeight = 48.0;
  static const double _translationRowHeight = 22.0;
  static const double _romajiRowHeight = 20.0;
  static const Duration _resumeDelay = Duration(seconds: 3);

  /// 播放页歌词字号档位（设置项），影响当前行/非当前行与行高。
  PlayerLyricFontSize _fontSizeSetting = PlayerLyricFontSize.medium;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _resumeTimer?.cancel();
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToLine(int index) {
    if (!_scrollController.hasClients) return;

    final targetOffset = index * _lineHeight;
    final clampedOffset = targetOffset.clamp(
      0.0,
      _scrollController.position.maxScrollExtent,
    );

    _scrollController.animateTo(
      clampedOffset,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
    );
  }

  void _onScroll() {
    if (_scrollController.position.isScrollingNotifier.value) {
      _onUserScrollStart();
    }
  }

  void _onUserScrollStart() {
    _isUserScrolling = true;
    _resumeTimer?.cancel();
    _resumeTimer = Timer(_resumeDelay, _onResumeAutoScroll);
  }

  void _onResumeAutoScroll() {
    _isUserScrolling = false;
    final lyricState = ref.read(lyricStateProvider);
    if (lyricState.currentIndex >= 0) {
      _scrollToLine(lyricState.currentIndex);
    }
  }

  /// 把拖拽位置换算成歌词行索引；越界钳到有效范围。
  int? _indexAt(Offset globalPosition) {
    final box = _listKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !_scrollController.hasClients) return null;
    final lyrics = ref.read(lyricStateProvider).lyrics;
    if (lyrics.isEmpty) return null;
    final local = box.globalToLocal(globalPosition);
    final y = local.dy - _verticalPadding + _scrollController.offset;
    return (y / _lineHeight).floor().clamp(0, lyrics.length - 1);
  }

  void _onScrubStart(LongPressStartDetails details) {
    final index = _indexAt(details.globalPosition);
    if (index == null) return;
    _isUserScrolling = true;
    _resumeTimer?.cancel();
    setState(() => _scrubIndex = index);
  }

  void _onScrubMove(LongPressMoveUpdateDetails details) {
    if (_scrubIndex == null) return;
    final index = _indexAt(details.globalPosition);
    if (index == null || index == _scrubIndex) return;
    setState(() => _scrubIndex = index);
  }

  void _onScrubEnd(LongPressEndDetails details) {
    final index = _scrubIndex;
    if (index == null) return;
    final lyrics = ref.read(lyricStateProvider).lyrics;
    setState(() => _scrubIndex = null);
    if (index < lyrics.length) widget.onSeek?.call(lyrics[index].time);
    _isUserScrolling = false;
    _resumeTimer?.cancel();
    _resumeTimer = Timer(_resumeDelay, _onResumeAutoScroll);
  }

  String _formatTime(Duration time) {
    final minutes = time.inMinutes;
    final seconds = time.inSeconds.remainder(60);
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  /// 拖拽进度时的浮层提示：目标行时间，松手后 seek 到该行。
  Widget _buildScrubHint(ThemeData theme) {
    final lyrics = ref.read(lyricStateProvider).lyrics;
    final index = _scrubIndex;
    if (index == null || index >= lyrics.length) return const SizedBox.shrink();
    final colors = PlayerBackdrop.colorsOf(context);
    return Align(
      alignment: Alignment.topCenter,
      child: IgnorePointer(
        child: Container(
          margin: const EdgeInsets.only(top: 8),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          decoration: BoxDecoration(
            color: theme.colorScheme.surface.withValues(alpha: 0.82),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            _formatTime(lyrics[index].time),
            style: TextStyle(
              color: colors.active,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }

  bool get _shouldShowEditButton {
    if (!widget.editable) return false;
    final s = widget.song;
    if (s == null || s.type != 'local') return false;
    final lyricState = ref.read(lyricStateProvider);
    // 纯文本歌词（无时间轴）无法调整时间戳，不展示「调整」入口。
    return lyricState.hasLyrics &&
        lyricState.synced &&
        !lyricState.isLoading &&
        !lyricState.loadFailed;
  }

  Future<void> _openAdjustPage() async {
    final song = widget.song;
    final lyricState = ref.read(lyricStateProvider);
    final lyricText = lyricState.rawLyricText;
    if (song == null || lyricText == null || lyricText.isEmpty) return;

    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => LyricAdjustPage(song: song, originalLyric: lyricText),
      ),
    );

    if (saved == true && mounted) {
      ref.read(lyricStateProvider.notifier).invalidate();
    }
  }

  /// 手动重新抓取当前歌曲歌词（清缓存 + 绕过浏览器缓存重跑歌词搜索）。
  void _refetchLyrics() {
    ref.read(lyricStateProvider.notifier).refetch();
  }

  /// 当前歌曲是否允许（重新）抓取歌词。
  /// 本地歌曲即使后端未返回 lyricUrl 也允许——客户端可由歌曲 ID 拼接端点触发搜索。
  bool get _canRefetch {
    final song = ref.watch(playerStateProvider.select((s) => s.currentSong));
    if (song == null) return false;
    if (song.type == 'local') return true;
    final url = song.lyricUrl;
    return url != null && url.isNotEmpty;
  }

  /// 加载失败 / 暂无歌词时的占位：提示文案 + 可选「重新抓取歌词」按钮。
  Widget _buildStatusPlaceholder(ThemeData theme, String message) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            message,
            style: theme.textTheme.bodyLarge?.copyWith(
              color: PlayerBackdrop.colorsOf(context).secondary,
            ),
          ),
          if (_canRefetch) ...[
            const SizedBox(height: 16),
            FilledButton.tonalIcon(
              onPressed: _refetchLyrics,
              icon: const Icon(Icons.refresh, size: 18),
              label: Text(AppLocalizations.of(context).playerLyricsRefetch),
            ),
          ],
        ],
      ),
    );
  }

  /// 构建单行：主歌词（当前行有逐字数据时用 [KaraokeLine] 逐字高亮，否则行级高亮）
  /// + 可选翻译 / 罗马音子行。
  Widget _buildLine(
    ThemeData theme,
    LyricLine lyric,
    bool isCurrent, {
    bool plain = false,
  }) {
    final colors = PlayerBackdrop.colorsOf(context);
    final primary = colors.active;
    final dim = colors.secondary;
    // 纯文本歌词无「当前行」概念，整体用较高可读性的中性色静态展示。
    final plainColor = colors.active;

    Widget main;
    if (isCurrent && lyric.hasWords) {
      main = KaraokeLine(
        line: lyric,
        activeColor: primary,
        // 未唱字明显淡于「已唱」与相邻行的灰，逐字推进才看得出层次
        // （两色仅色相不同、明度接近时会被误读成整行高亮）。
        inactiveColor: dim.withValues(alpha: 0.45),
        fontSize: _fontSizeSetting.fullCurrentSize,
      );
    } else {
      final text = lyric.text;
      main = Text(
        text.isEmpty ? '...' : text,
        style: TextStyle(
          fontSize:
              plain
                  ? _fontSizeSetting.fullOtherSize + 1
                  : (isCurrent
                      ? _fontSizeSetting.fullCurrentSize
                      : _fontSizeSetting.fullOtherSize),
          fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
          color: plain ? plainColor : (isCurrent ? primary : dim),
        ),
        textAlign: TextAlign.center,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      );
    }

    final children = <Widget>[main];
    final translation = lyric.translation;
    final romaji = lyric.romaji;
    // 罗马音置于原文与译文之间，符合常见排版
    if (romaji != null) {
      children.add(
        Text(
          romaji,
          style: TextStyle(
            fontSize: isCurrent ? 13 : 12,
            color: isCurrent ? primary : dim,
          ),
          textAlign: TextAlign.center,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      );
    }
    if (translation != null) {
      children.add(
        Text(
          translation,
          style: TextStyle(
            fontSize: isCurrent ? 14 : 13,
            fontWeight: isCurrent ? FontWeight.w500 : FontWeight.normal,
            color: isCurrent ? primary : dim,
          ),
          textAlign: TextAlign.center,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      );
    }

    if (children.length == 1) return main;
    return Column(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: children,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final lyricState = ref.watch(lyricStateProvider);

    if (lyricState.isLoading) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: PlayerBackdrop.colorsOf(context).active,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              AppLocalizations.of(context).playerLyricsLoading,
              style: theme.textTheme.bodyLarge?.copyWith(
                color: PlayerBackdrop.colorsOf(context).secondary,
              ),
            ),
          ],
        ),
      );
    }

    if (lyricState.loadFailed) {
      return _buildStatusPlaceholder(
        theme,
        AppLocalizations.of(context).playerLyricsLoadFailed,
      );
    }

    if (!lyricState.hasLyrics) {
      return _buildStatusPlaceholder(
        theme,
        AppLocalizations.of(context).playerLyricsEmpty,
      );
    }

    // 当行索引变化时自动滚动
    final currentIndex = lyricState.currentIndex;
    if (currentIndex != _lastScrolledIndex &&
        !_isUserScrolling &&
        currentIndex >= 0) {
      _lastScrolledIndex = currentIndex;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !_isUserScrolling) {
          _scrollToLine(currentIndex);
        }
      });
    }

    final lyrics = lyricState.lyrics;
    final isPlain = !lyricState.synced;

    // 字号来自设置项：主行高随当前行字号等比缩放，保证滚动定位精确。
    _fontSizeSetting = ref.watch(playerLyricFontSizeProvider);
    _mainRowHeight = _fontSizeSetting.fullCurrentSize * 2.4;

    // 统一行高：轨道含翻译/罗马音时为所有行预留对应行高，保持等距，滚动定位精确。
    final hasTranslations = lyrics.any((l) => l.translation != null);
    final hasRomaji = lyrics.any((l) => l.romaji != null);
    _lineHeight =
        _mainRowHeight +
        (hasTranslations ? _translationRowHeight : 0) +
        (hasRomaji ? _romajiRowHeight : 0);

    final body = LayoutBuilder(
      builder: (context, constraints) {
        final verticalPadding = ((constraints.maxHeight - _lineHeight) / 2)
            .clamp(0.0, double.infinity);
        _verticalPadding = verticalPadding;
        // 长按拖拽调整进度：仅时间轴歌词 + 有时长 + 调用方允许时启用。
        final canScrub =
            widget.scrubEnabled && lyricState.synced && widget.onSeek != null;

        final list = NotificationListener<ScrollNotification>(
          onNotification: (notification) {
            if (notification is ScrollStartNotification) {
              if (notification.dragDetails != null) {
                _onUserScrollStart();
              }
            }
            return false;
          },
          child: ListView.builder(
            key: _listKey,
            controller: _scrollController,
            padding: EdgeInsets.symmetric(
              vertical: verticalPadding,
              horizontal: 24,
            ),
            itemExtent: _lineHeight,
            itemCount: lyrics.length,
            itemBuilder: (context, index) {
              final lyric = lyrics[index];
              final isCurrent = index == currentIndex;

              return Semantics(
                button: true,
                label: AppLocalizations.of(context).playerLyricsSeekTo,
                child: GestureDetector(
                  onTap: () {
                    if (widget.onSeek != null) {
                      widget.onSeek!(lyric.time);
                      _isUserScrolling = false;
                      _resumeTimer?.cancel();
                    }
                  },
                  child: Container(
                    height: _lineHeight,
                    alignment: Alignment.center,
                    child: _buildLine(theme, lyric, isCurrent, plain: isPlain),
                  ),
                ),
              );
            },
          ),
        );

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTapBackground,
          onLongPressStart: canScrub ? _onScrubStart : null,
          onLongPressMoveUpdate: canScrub ? _onScrubMove : null,
          onLongPressEnd: canScrub ? _onScrubEnd : null,
          child: SizedBox.expand(
            child: Stack(
              children: [
                Positioned.fill(child: list),
                if (_scrubIndex != null)
                  Positioned.fill(child: _buildScrubHint(theme)),
              ],
            ),
          ),
        );
      },
    );

    final showEdit = _shouldShowEditButton;
    final showRefetch = _canRefetch;
    if (!showEdit && !showRefetch) return body;

    return Stack(
      children: [
        Positioned.fill(child: body),
        Positioned(
          top: 4,
          right: 4,
          child: Material(
            color: Colors.transparent,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (showRefetch)
                  IconButton(
                    icon: const Icon(Icons.refresh, size: 22),
                    tooltip: AppLocalizations.of(context).playerLyricsRefetch,
                    color: PlayerBackdrop.colorsOf(context).active,
                    onPressed: _refetchLyrics,
                  ),
                if (showEdit)
                  IconButton(
                    icon: const Icon(Icons.tune, size: 22),
                    tooltip: AppLocalizations.of(context).playerAdjustLyrics,
                    color: PlayerBackdrop.colorsOf(context).active,
                    onPressed: _openAdjustPage,
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
