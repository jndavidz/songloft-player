import 'dart:js_interop';
import 'dart:ui_web' as ui_web;

import 'package:flutter/material.dart';
import 'package:web/web.dart' as web;

// hls.js 桥接（与 WebVideoPlaybackNotifier 共用同一个全局对象）
@JS('SongloftHls.canUse')
external bool _hlsCanUse();

@JS('SongloftHls.attach')
external void _hlsAttach(
  web.HTMLVideoElement element,
  String url,
  JSFunction onError,
);

@JS('SongloftHls.destroy')
external void _hlsDestroy(web.HTMLVideoElement element);

/// 在线 MV 画面（Web）：独立 `<video>` 元素 + 原生浏览器控制条。
///
/// - mp4/webm 直接 `src`；m3u8 走 hls.js（不支持时回退 `src` 交给浏览器）。
/// - 与音频播放完全隔离：进入页面时音频被暂停，退出后恢复。
class MvVideoView extends StatefulWidget {
  const MvVideoView({super.key, required this.url, this.onError});

  final String url;
  final ValueChanged<String>? onError;

  @override
  State<MvVideoView> createState() => _MvVideoViewState();
}

class _MvVideoViewState extends State<MvVideoView> {
  static int _seq = 0;
  late final String _viewType;
  web.HTMLVideoElement? _video;
  bool _hlsAttached = false;

  @override
  void initState() {
    super.initState();
    _viewType = 'songloft-mv-${_seq++}';
    ui_web.platformViewRegistry.registerViewFactory(_viewType, (int viewId) {
      final el = web.document.createElement('video') as web.HTMLVideoElement;
      el
        ..autoplay = true
        ..controls = true;
      el.setAttribute('playsinline', 'true');
      el.style
        ..width = '100%'
        ..height = '100%'
        ..backgroundColor = 'black';
      el.style.setProperty('object-fit', 'contain');
      el.addEventListener(
        'error',
        ((web.Event event) {
          widget.onError?.call('视频加载失败');
        }).toJS,
      );
      _video = el;

      if (widget.url.contains('.m3u8') || widget.url.contains('m3u8')) {
        if (_hlsCanUse()) {
          _hlsAttached = true;
          _hlsAttach(
            el,
            widget.url,
            ((JSString message) {
              _hlsAttached = false;
              widget.onError?.call(message.toDart);
            }).toJS,
          );
        } else {
          el.src = widget.url;
        }
      } else {
        el.src = widget.url;
      }
      return el;
    });
  }

  @override
  void dispose() {
    final el = _video;
    if (el != null) {
      el.pause();
      el.removeAttribute('src');
      if (_hlsAttached) _hlsDestroy(el);
    }
    _video = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Colors.black,
      child: HtmlElementView(viewType: _viewType),
    );
  }
}
