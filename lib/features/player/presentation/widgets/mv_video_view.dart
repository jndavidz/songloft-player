// MV 视频画面组件的条件导出（镜像 web_video_view.dart 的写法）。
// 默认（web）用 _web.dart（package:web + HtmlElementView 渲染 <video>）；
// dart.library.io（原生）用 _native.dart（media_kit 独立 Player，不干扰音频播放）。
export 'mv_video_view_web.dart'
    if (dart.library.io) 'mv_video_view_native.dart';
