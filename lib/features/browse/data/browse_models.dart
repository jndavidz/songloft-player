/// kwqq 插件在线浏览数据模型（spec: songloft .scratch/musicfree-style-library）。
///
/// 形状与 kwqq 插件 `/browse/*` 端点一一对应（MusicFree 函数语义归一）。
/// 音乐条目自带 `dedup_key` / `source_data`：点播链直接把它们透传给
/// `POST /api/v1/songs/remote`（dedup 幂等），客户端不拼任何格式。

library;

import 'dart:convert';

import '../../../shared/utils/published_time.dart';

/// 上游来源平台标识 → 中文简称（品牌名，不进 l10n）。
const Map<String, String> kBrowsePlatformLabels = {
  'kuwo': '酷我',
  'kugou': '酷狗',
  'qq': 'QQ',
  'qianqian': '千千',
  'netease': '网易云',
  'migu': '咪咕',
  'bilibili': '哔哩哔哩',
};

/// 平台中文简称；未知 source 原样返回，缺省给 '未知'。
String browsePlatformLabel(String? source) {
  if (source == null || source.isEmpty) return '未知';
  return kBrowsePlatformLabels[source] ?? source;
}

/// 平台展示顺序（推荐歌单 / 榜单统一）：网易云 → QQ → 酷狗 → 酷我。
const List<String> kBrowsePlatformOrder = ['netease', 'qq', 'kugou', 'kuwo'];

/// 按 [kBrowsePlatformOrder] 归一排序；顺序表外的平台（migu 等）保持原顺序追加在后。
List<String> orderBrowsePlatforms(Iterable<String> sources) {
  final ordered = <String>[
    for (final s in kBrowsePlatformOrder)
      if (sources.contains(s)) s,
  ];
  final rest = <String>[];
  for (final s in sources) {
    if (!kBrowsePlatformOrder.contains(s) && !rest.contains(s)) rest.add(s);
  }
  return [...ordered, ...rest];
}

/// 在线音乐条目（多源聚合单曲 / 专辑曲目 / 歌单曲目 / 榜单曲目共用）。
class BrowseTrack {
  final String title;
  final String artist;
  final String? album;
  final int duration; // 秒
  final String? coverUrl;

  /// 上游来源平台标识（kuwo/qq/netease/...），仅作 UI 标注。
  final String? source;
  final Map<String, dynamic>? sourceData;
  final String? dedupKey;

  /// 曲序号（专辑页官方曲序，1 起）；非专辑场景为 null。
  final int? trackNo;

  const BrowseTrack({
    required this.title,
    required this.artist,
    this.album,
    this.duration = 0,
    this.coverUrl,
    this.source,
    this.sourceData,
    this.dedupKey,
    this.trackNo,
  });

  factory BrowseTrack.fromJson(Map<String, dynamic> json) => BrowseTrack(
    title: json['title'] as String? ?? 'Unknown',
    artist: json['artist'] as String? ?? 'Unknown',
    album: json['album'] as String?,
    duration: (json['duration'] as num?)?.toInt() ?? 0,
    coverUrl: json['cover_url'] as String?,
    source: json['source'] as String?,
    sourceData:
        json['source_data'] is Map<String, dynamic>
            ? json['source_data'] as Map<String, dynamic>
            : null,
    dedupKey: json['dedup_key'] as String?,
    trackNo: json['track_no'] as int?,
  );

  bool get isPlayable => sourceData != null && (sourceData!['s'] ?? '') != '';

  /// 转 `POST /songs/remote` 的请求体元素（插件 /import 同式）。
  Map<String, dynamic> toRemotePayload() => {
    'title': title,
    'artist': artist,
    if (album != null && album!.isNotEmpty) 'album': album,
    if (coverUrl != null && coverUrl!.isNotEmpty) 'cover_url': coverUrl,
    'duration': duration.toDouble(),
    'plugin_entry_path': 'kwqq',
    'source_data': jsonEncode(sourceData ?? const {}),
    if (dedupKey != null && dedupKey!.isNotEmpty) 'dedup_key': dedupKey,
  };
}

/// 发行时间兼容上游三种形态：毫秒/秒时间戳（num）、数字字符串、'YYYY-MM-DD' 日期串。
/// 插件与门面对该字段的规范不统一（musicdl 原样透传字符串），严格 `as num?` 会抛
/// 类型错误并让整页专辑解析失败，故在边界做归一。
int? _parsePublishTime(dynamic value) {
  if (value is num) return value.toInt();
  if (value is String && value.isNotEmpty) {
    final numeric = int.tryParse(value);
    if (numeric != null) return numeric;
    final date = DateTime.tryParse(value);
    if (date != null) return date.millisecondsSinceEpoch;
  }
  return null;
}

/// 在线专辑条目（搜索结果 / 歌手作品列表）。
class BrowseAlbum {
  final String id;
  final String name;
  final String artist;
  final String? coverUrl;
  final int trackCount;
  final int? publishTime; // 毫秒时间戳
  final String? company;
  final String? description;
  final String? source;

  const BrowseAlbum({
    required this.id,
    required this.name,
    required this.artist,
    this.coverUrl,
    this.trackCount = 0,
    this.publishTime,
    this.company,
    this.description,
    this.source,
  });

  factory BrowseAlbum.fromJson(Map<String, dynamic> json) => BrowseAlbum(
    id: json['id']?.toString() ?? '',
    name: json['name'] as String? ?? '',
    artist: json['artist'] as String? ?? '',
    coverUrl: json['cover_url'] as String?,
    trackCount: (json['track_count'] as num?)?.toInt() ?? 0,
    publishTime: _parsePublishTime(json['publish_time']),
    company: json['company'] as String?,
    description: json['description'] as String?,
    source: json['source'] as String?,
  );
}

/// 在线歌手条目。
class BrowseArtist {
  final String id;
  final String name;
  final String? avatarUrl;
  final String? alias;
  final String? description;
  final int albumCount;
  final int musicCount;
  final String? source;

  const BrowseArtist({
    required this.id,
    required this.name,
    this.avatarUrl,
    this.alias,
    this.description,
    this.albumCount = 0,
    this.musicCount = 0,
    this.source,
  });

  factory BrowseArtist.fromJson(Map<String, dynamic> json) => BrowseArtist(
    id: json['id']?.toString() ?? '',
    name: json['name'] as String? ?? '',
    avatarUrl: json['avatar_url'] as String?,
    alias: json['alias'] as String?,
    description: json['description'] as String?,
    albumCount: (json['album_count'] as num?)?.toInt() ?? 0,
    musicCount: (json['music_count'] as num?)?.toInt() ?? 0,
    source: json['source'] as String?,
  );
}

/// 在线歌单条目（搜索结果 / 分类推荐列表）。
class BrowseSheet {
  final String id;
  final String name;
  final String creator;
  final String? coverUrl;
  final int trackCount;
  final int playCount;
  final String? description;
  final String? source;

  const BrowseSheet({
    required this.id,
    required this.name,
    this.creator = '',
    this.coverUrl,
    this.trackCount = 0,
    this.playCount = 0,
    this.description,
    this.source,
  });

  factory BrowseSheet.fromJson(Map<String, dynamic> json) => BrowseSheet(
    id: json['id']?.toString() ?? '',
    name: json['name'] as String? ?? '',
    creator: json['creator'] as String? ?? '',
    coverUrl: json['cover_url'] as String?,
    trackCount: (json['track_count'] as num?)?.toInt() ?? 0,
    playCount: (json['play_count'] as num?)?.toInt() ?? 0,
    description: json['description'] as String?,
    source: json['source'] as String?,
  );
}

/// 平台榜单条目。
class BrowseToplist {
  final String id;
  final String name;
  final String? coverUrl;
  final String? description;
  final String? updateFrequency;
  final String? source;

  const BrowseToplist({
    required this.id,
    required this.name,
    this.coverUrl,
    this.description,
    this.updateFrequency,
    this.source,
  });

  factory BrowseToplist.fromJson(Map<String, dynamic> json) => BrowseToplist(
    id: json['id']?.toString() ?? '',
    name: json['name'] as String? ?? '',
    coverUrl: json['cover_url'] as String?,
    description: json['description'] as String?,
    updateFrequency: json['update_frequency'] as String?,
    source: json['source'] as String?,
  );
}

/// 推荐歌单标签（平台接口下发，非本地枚举）。
class BrowseTag {
  final String id;
  final String title;

  const BrowseTag({required this.id, required this.title});

  factory BrowseTag.fromJson(Map<String, dynamic> json) => BrowseTag(
    id: json['id']?.toString() ?? '',
    title: json['title'] as String? ?? '',
  );
}

/// 推荐歌单标签分组。
class BrowseTagGroup {
  final String title;
  final List<BrowseTag> tags;

  const BrowseTagGroup({required this.title, required this.tags});

  factory BrowseTagGroup.fromJson(Map<String, dynamic> json) => BrowseTagGroup(
    title: json['title'] as String? ?? '',
    tags:
        (json['data'] as List<dynamic>? ?? [])
            .map((e) => BrowseTag.fromJson(e as Map<String, dynamic>))
            .toList(),
  );
}

/// 评论（只读，MusicFree IComment 形状）。
class BrowseComment {
  final String id;
  final String nickName;
  final String? avatar;
  final String comment;
  final int like;

  /// 结构化发布时间（已归一为本地时区语义），来自 `create_time`（秒/毫秒）或
  /// MusicFree 的 `createAt`（毫秒）。识别不出时为 null。
  final DateTime? publishedAt;

  /// 上游已格式化好的时间文本（`create_time_text` / `time` 之类字符串），
  /// 存在且没有结构化时间时直接展示。
  final String? publishedAtText;

  final List<BrowseCommentReply> replies;

  const BrowseComment({
    required this.id,
    required this.nickName,
    required this.comment,
    this.avatar,
    this.like = 0,
    this.publishedAt,
    this.publishedAtText,
    this.replies = const [],
  });

  factory BrowseComment.fromJson(Map<String, dynamic> json) {
    // 结构化时间优先级：create_time（服务端/插件新字段）→ createAt（旧形状）。
    final publishedAt = parsePublishedTime(
      json['create_time'] ?? json['createTime'] ?? json['createAt'],
    );
    // 只有拿不到结构化时间时才用上游文本，避免出现两套口径。
    final publishedAtText =
        publishedAt == null
            ? _cleanText(
              json['create_time_text'] ??
                  json['createTimeText'] ??
                  json['time'],
            )
            : null;
    return BrowseComment(
      id: json['id']?.toString() ?? '',
      nickName: json['nickName'] as String? ?? '匿名用户',
      avatar: json['avatar'] as String?,
      comment: json['comment'] as String? ?? '',
      like: (json['like'] as num?)?.toInt() ?? 0,
      publishedAt: publishedAt,
      publishedAtText: publishedAtText,
      replies:
          (json['replies'] as List<dynamic>? ?? [])
              .map(
                (e) => BrowseCommentReply.fromJson(e as Map<String, dynamic>),
              )
              .toList(),
    );
  }
}

/// 非空字符串原样返回（去首尾空白），其余形态返回 null。
String? _cleanText(dynamic value) {
  if (value is String) {
    final text = value.trim();
    if (text.isNotEmpty) return text;
  }
  return null;
}

/// 评论的楼中楼回复。
class BrowseCommentReply {
  final String id;
  final String nickName;
  final String? avatar;
  final String comment;

  const BrowseCommentReply({
    required this.id,
    required this.nickName,
    required this.comment,
    this.avatar,
  });

  factory BrowseCommentReply.fromJson(Map<String, dynamic> json) =>
      BrowseCommentReply(
        id: json['id']?.toString() ?? '',
        nickName: json['nickName'] as String? ?? '已注销',
        avatar: json['avatar'] as String?,
        comment: json['comment'] as String? ?? '',
      );
}

/// 分页结果统一包装（isEnd 驱动触底加载）。
class BrowsePage<T> {
  final List<T> items;
  final bool isEnd;
  final int? total;

  const BrowsePage({required this.items, required this.isEnd, this.total});
}

/// 搜索响应（type=music/album/artist/sheet 四类型共用信封）。
class BrowseSearchResponse {
  final String type;
  final bool isEnd;
  final List<BrowseTrack> tracks;
  final List<BrowseAlbum> albums;
  final List<BrowseArtist> artists;
  final List<BrowseSheet> sheets;
  final List<BrowseVideo> videos;
  final String? source;

  const BrowseSearchResponse({
    required this.type,
    required this.isEnd,
    this.tracks = const [],
    this.albums = const [],
    this.artists = const [],
    this.sheets = const [],
    this.videos = const [],
    this.source,
  });

  factory BrowseSearchResponse.fromJson(Map<String, dynamic> json) {
    final type = json['type'] as String? ?? 'music';
    final items = json['items'] as List<dynamic>? ?? [];
    return BrowseSearchResponse(
      type: type,
      isEnd: json['isEnd'] as bool? ?? true,
      source: json['source'] as String?,
      tracks:
          type == 'music'
              ? items
                  .map((e) => BrowseTrack.fromJson(e as Map<String, dynamic>))
                  .toList()
              : const [],
      albums:
          type == 'album'
              ? items
                  .map((e) => BrowseAlbum.fromJson(e as Map<String, dynamic>))
                  .toList()
              : const [],
      artists:
          type == 'artist'
              ? items
                  .map((e) => BrowseArtist.fromJson(e as Map<String, dynamic>))
                  .toList()
              : const [],
      sheets:
          type == 'sheet'
              ? items
                  .map((e) => BrowseSheet.fromJson(e as Map<String, dynamic>))
                  .toList()
              : const [],
      videos:
          (type == 'mv' || type == 'video')
              ? items
                  .map((e) => BrowseVideo.fromJson(e as Map<String, dynamic>))
                  .toList()
              : const [],
    );
  }
}

/// 在线 MV / 视频搜索结果条目（服务端按类型搜 MV：`type=mv`）。
///
/// 只携带可点选的定位信息（id / 平台 / 封面 / 时长 / 清晰度），可播放直链由
/// `SongMvApi.findMv` 按 source+id 再查（与「...」菜单 → 歌曲视频同一链路）。
class BrowseVideo {
  final String id;
  final String source;
  final String title;
  final String artist;
  final String? coverUrl;
  final int duration; // 秒
  final String? quality;

  const BrowseVideo({
    required this.id,
    required this.source,
    required this.title,
    this.artist = '',
    this.coverUrl,
    this.duration = 0,
    this.quality,
  });

  /// 是否具备点播条件：缺 id 或平台源码的条目直接不展示，避免死入口。
  bool get isPlayable => id.isNotEmpty && source.isNotEmpty;

  factory BrowseVideo.fromJson(Map<String, dynamic> json) => BrowseVideo(
    id: json['id']?.toString() ?? '',
    source: (json['source'] as String? ?? '').trim().toLowerCase(),
    title: json['title'] as String? ?? 'Unknown',
    artist: json['artist'] as String? ?? '',
    coverUrl: json['cover'] as String? ?? json['cover_url'] as String?,
    duration:
        (json['duration_s'] as num?)?.toInt() ??
        (json['duration'] as num?)?.toInt() ??
        0,
    quality: json['quality'] as String?,
  );
}

/// 专辑详情响应（hero 元数据 + 官方曲序曲目）。
class BrowseAlbumInfo {
  final BrowseAlbum album;
  final List<BrowseTrack> tracks;

  const BrowseAlbumInfo({required this.album, required this.tracks});

  factory BrowseAlbumInfo.fromJson(Map<String, dynamic> json) =>
      BrowseAlbumInfo(
        album: BrowseAlbum.fromJson(
          json['album'] as Map<String, dynamic>? ?? {},
        ),
        tracks:
            (json['tracks'] as List<dynamic>? ?? [])
                .map((e) => BrowseTrack.fromJson(e as Map<String, dynamic>))
                .toList(),
      );
}

/// 歌手作品响应（type=music 单曲 / type=album 专辑）。
class BrowseArtistWorks {
  final String type;
  final bool isEnd;
  final List<BrowseTrack> tracks;
  final List<BrowseAlbum> albums;

  const BrowseArtistWorks({
    required this.type,
    required this.isEnd,
    this.tracks = const [],
    this.albums = const [],
  });

  factory BrowseArtistWorks.fromJson(Map<String, dynamic> json) {
    final type = json['type'] as String? ?? 'music';
    final items = json['items'] as List<dynamic>? ?? [];
    return BrowseArtistWorks(
      type: type,
      isEnd: json['isEnd'] as bool? ?? true,
      tracks:
          type == 'music'
              ? items
                  .map((e) => BrowseTrack.fromJson(e as Map<String, dynamic>))
                  .toList()
              : const [],
      albums:
          type == 'album'
              ? items
                  .map((e) => BrowseAlbum.fromJson(e as Map<String, dynamic>))
                  .toList()
              : const [],
    );
  }
}

/// 歌单详情响应（曲目分页 + 首页附元数据）。
class BrowseSheetInfo {
  final BrowseSheet? sheet;
  final bool isEnd;
  final int? total;
  final List<BrowseTrack> tracks;

  const BrowseSheetInfo({
    this.sheet,
    required this.isEnd,
    this.total,
    required this.tracks,
  });

  factory BrowseSheetInfo.fromJson(Map<String, dynamic> json) =>
      BrowseSheetInfo(
        sheet:
            json['sheet'] == null
                ? null
                : BrowseSheet.fromJson(json['sheet'] as Map<String, dynamic>),
        isEnd: json['isEnd'] as bool? ?? true,
        total: (json['total'] as num?)?.toInt(),
        tracks:
            (json['tracks'] as List<dynamic>? ?? [])
                .map((e) => BrowseTrack.fromJson(e as Map<String, dynamic>))
                .toList(),
      );
}

/// 单平台的推荐标签集（pinned 热门 + grouped 全量分类）。
class BrowsePlatformTags {
  final String source;
  final List<BrowseTag> pinned;
  final List<BrowseTagGroup> groups;

  const BrowsePlatformTags({
    required this.source,
    required this.pinned,
    required this.groups,
  });

  factory BrowsePlatformTags.fromJson(Map<String, dynamic> json) =>
      BrowsePlatformTags(
        source: json['source'] as String? ?? 'netease',
        pinned:
            (json['pinned'] as List<dynamic>? ?? [])
                .map((e) => BrowseTag.fromJson(e as Map<String, dynamic>))
                .toList(),
        groups:
            (json['categories'] as List<dynamic>? ?? [])
                .map((e) => BrowseTagGroup.fromJson(e as Map<String, dynamic>))
                .toList(),
      );
}

/// 推荐标签响应（多平台：platforms 逐平台 pinned + grouped 全量分类）。
///
/// 兼容旧插件（只回顶层 pinned/categories 的 netease 单源形状）：
/// platforms 缺省时收拢为一个 netease 平台。
class BrowseRecommendTags {
  final List<BrowsePlatformTags> platforms;

  const BrowseRecommendTags({required this.platforms});

  factory BrowseRecommendTags.fromJson(Map<String, dynamic> json) {
    final platformList =
        (json['platforms'] as List<dynamic>?)
            ?.map((e) => BrowsePlatformTags.fromJson(e as Map<String, dynamic>))
            .toList();
    if (platformList != null && platformList.isNotEmpty) {
      return BrowseRecommendTags(platforms: platformList);
    }
    return BrowseRecommendTags(
      platforms: [
        BrowsePlatformTags(
          source: 'netease',
          pinned:
              (json['pinned'] as List<dynamic>? ?? [])
                  .map((e) => BrowseTag.fromJson(e as Map<String, dynamic>))
                  .toList(),
          groups:
              (json['categories'] as List<dynamic>? ?? [])
                  .map(
                    (e) => BrowseTagGroup.fromJson(e as Map<String, dynamic>),
                  )
                  .toList(),
        ),
      ],
    );
  }
}

/// 评论响应（热评优先；首页 hot 仅在 page=1 出现）。
class BrowseCommentsResponse {
  final int total;
  final bool hasMore;
  final List<BrowseComment> hot;
  final List<BrowseComment> comments;

  const BrowseCommentsResponse({
    this.total = 0,
    this.hasMore = false,
    this.hot = const [],
    this.comments = const [],
  });

  factory BrowseCommentsResponse.fromJson(Map<String, dynamic> json) =>
      BrowseCommentsResponse(
        total: (json['total'] as num?)?.toInt() ?? 0,
        hasMore: json['has_more'] as bool? ?? false,
        hot:
            (json['hot'] as List<dynamic>? ?? [])
                .map((e) => BrowseComment.fromJson(e as Map<String, dynamic>))
                .toList(),
        comments:
            (json['comments'] as List<dynamic>? ?? [])
                .map((e) => BrowseComment.fromJson(e as Map<String, dynamic>))
                .toList(),
      );
}
