/// 「正在播放」标识的匹配逻辑（spec US22）：浏览条目与当前播放歌都没有稳定的
/// 共享 id（Song 模型不透出 dedup_key/source_data），按 title+artist 归一匹配，
/// 且仅对 remote 歌生效（电台/本地歌与在线条目同名不应误标）。
library;

import '../../../shared/models/song.dart';
import '../data/browse_models.dart';

bool isCurrentBrowseTrack(Song? current, BrowseTrack track) {
  if (current == null || current.type != 'remote') return false;
  String norm(String? v) => (v ?? '').trim().toLowerCase();
  final title = norm(current.title);
  if (title.isEmpty || title != norm(track.title)) return false;
  final artist = norm(current.artist);
  return artist.isEmpty || artist == norm(track.artist);
}
