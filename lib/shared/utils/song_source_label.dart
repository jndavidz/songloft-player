import '../models/song.dart';

/// 在线音源平台标识 → 展示名。
///
/// 取值与 kwqq 插件写入 `source_data.s` 的平台标识一致（netease/qq/kugou/kuwo/
/// migu/qianqian/bilibili）；WebDAV 按插件入口识别。
/// **只用于 UI 展示，不得回显 `browse` / `kwqq` / `remote` 等内部枚举值。**
const Map<String, String> kSongPlatformNames = {
  'netease': '网易云',
  'qq': 'QQ',
  'kugou': '酷狗',
  'kuwo': '酷我',
  'migu': '咪咕',
  'qianqian': '千千',
  'bilibili': '哔哩哔哩',
  'webdav': 'WebDAV',
};

/// 歌曲真实内容来源的平台展示名；本地歌曲（含 WebDAV 之外）识别不出时返回 null。
///
/// 优先读 `source_data.s`（kwqq 插件写入的真实音源），其次 `source_data.source`
/// （其它接口形态）；两者都只在白名单里查，未命中不回显原值。
/// WebDAV 歌曲的 `source_data` 可能为空，按 `plugin_entry_path` 含 `dav` 识别。
String? songPlatformName(Song song) {
  for (final key in const ['s', 'source']) {
    final value = song.sourceData?[key];
    if (value is String && value.trim().isNotEmpty) {
      final name = kSongPlatformNames[value.trim().toLowerCase()];
      if (name != null) return name;
    }
  }
  if (song.pluginEntryPath.toLowerCase().contains('dav')) {
    return kSongPlatformNames['webdav'];
  }
  return null;
}
