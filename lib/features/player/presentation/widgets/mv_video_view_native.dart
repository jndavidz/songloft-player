import 'dart:async';

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../../../../l10n/app_localizations.dart';
import 'progress_bar.dart';

/// 在线 MV 画面（原生）：独立的 media_kit Player，与音频播放器完全隔离。
///
/// 退出页面即释放播放器，不影响正在进行的音频播放（音频由 `SongMvPage` 暂停/恢复）。
///
/// 控制层为自绘（关闭 media_kit 自带的贴底控制条）：自带控制条的进度条贴着窗口
/// 底边，会被手势导航条/虚拟按键裁掉或压住。这里把控制层放进 `SafeArea` 并额外
/// 留出底部内边距，保证进度条完整可见且可点可拖（长屏、三键导航、手势导航都适用）。
class MvVideoView extends StatefulWidget {
  const MvVideoView({super.key, required this.url, this.onError});

  final String url;
  final ValueChanged<String>? onError;

  @override
  State<MvVideoView> createState() => _MvVideoViewState();
}

class _MvVideoViewState extends State<MvVideoView> {
  late final Player _player;
  late final VideoController _controller;
  final List<StreamSubscription<dynamic>> _subs = [];

  bool _playing = false;
  bool _controlsVisible = true;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  Timer? _hideTimer;

  @override
  void initState() {
    super.initState();
    // Android/iOS 不走 just_audio_media_kit 的注册，需自行初始化（幂等）。
    MediaKit.ensureInitialized();
    _player = Player();
    _controller = VideoController(_player);
    _subs.add(
      _player.stream.error.listen((message) {
        debugPrint('[MvVideoView] player error: $message');
        widget.onError?.call(message);
      }),
    );
    _subs.add(
      _player.stream.playing.listen((value) {
        if (!mounted) return;
        setState(() => _playing = value);
        _scheduleAutoHide();
      }),
    );
    _subs.add(
      _player.stream.position.listen((value) {
        if (!mounted) return;
        setState(() => _position = value);
      }),
    );
    _subs.add(
      _player.stream.duration.listen((value) {
        if (!mounted) return;
        setState(() => _duration = value);
      }),
    );
    _player.open(Media(widget.url));
    _scheduleAutoHide();
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    for (final sub in _subs) {
      sub.cancel();
    }
    _player.dispose();
    super.dispose();
  }

  /// 播放中 3 秒后收起控制层，避免遮挡画面；暂停时保持可见。
  void _scheduleAutoHide() {
    _hideTimer?.cancel();
    if (!_playing) return;
    _hideTimer = Timer(const Duration(seconds: 3), () {
      if (!mounted) return;
      setState(() => _controlsVisible = false);
    });
  }

  void _toggleControls() {
    setState(() => _controlsVisible = !_controlsVisible);
    _scheduleAutoHide();
  }

  Future<void> _togglePlay() async {
    _scheduleAutoHide();
    await _player.playOrPause();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        Video(
          controller: _controller,
          controls: NoVideoControls,
          fit: BoxFit.contain,
        ),
        // 点击画面显隐控制层
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _toggleControls,
          ),
        ),
        if (_controlsVisible)
          Align(
            alignment: Alignment.bottomCenter,
            child: SafeArea(
              top: false,
              minimum: const EdgeInsets.fromLTRB(16, 0, 16, 20),
              child: _buildControls(context),
            ),
          ),
      ],
    );
  }

  Widget _buildControls(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    // 视频页固定黑底：控制条文字/轨道用白色系，不随 App 主题明暗变化。
    final darkTheme = theme.copyWith(
      colorScheme: theme.colorScheme.copyWith(
        onSurfaceVariant: Colors.white,
        primary: Colors.white,
      ),
    );

    return Container(
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Theme(
            data: darkTheme,
            child: PlayerProgressBar(
              position: _position,
              duration: _duration,
              onSeek: (value) {
                _player.seek(value);
                _scheduleAutoHide();
              },
              activeColor: Colors.white,
              inactiveColor: Colors.white.withValues(alpha: 0.28),
            ),
          ),
          Row(
            children: [
              IconButton(
                onPressed: _togglePlay,
                iconSize: 30,
                color: Colors.white,
                tooltip: _playing ? l10n.playerPause : l10n.playerPlay,
                icon: Icon(
                  _playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
