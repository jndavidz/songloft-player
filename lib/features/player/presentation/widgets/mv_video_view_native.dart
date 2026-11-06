import 'dart:async';

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

/// 在线 MV 画面（原生）：独立的 media_kit Player，与音频播放器完全隔离。
///
/// 退出页面即释放播放器，不影响正在进行的音频播放（音频由 [SongMvPage] 暂停/恢复）。
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
  StreamSubscription<String>? _errorSub;

  @override
  void initState() {
    super.initState();
    // Android/iOS 不走 just_audio_media_kit 的注册，需自行初始化（幂等）。
    MediaKit.ensureInitialized();
    _player = Player();
    _controller = VideoController(_player);
    _errorSub = _player.stream.error.listen((message) {
      debugPrint('[MvVideoView] player error: $message');
      widget.onError?.call(message);
    });
    _player.open(Media(widget.url));
  }

  @override
  void dispose() {
    _errorSub?.cancel();
    _player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Video(controller: _controller, fit: BoxFit.contain);
  }
}
