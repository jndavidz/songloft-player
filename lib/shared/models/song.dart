import 'dart:convert';

/// 歌曲模型
class Song {
  final int id;
  final String type; // 'local', 'remote', 'radio'
  final String title;
  final String? artist;
  final String? album;
  final int year; // 发行年份，0 表示未知
  final String? genre; // 流派
  final String? language; // 语种
  final String? style; // 风格
  final double duration;
  final String? filePath;
  final String? url;
  final String? coverUrl; // 封面URL（后端统一处理）
  final String? lyricUrl; // 歌词URL（后端统一处理，有歌词时为 /api/v1/songs/{id}/lyric，无歌词时为空）
  final String? lyricRemoteUrl; // 歌词原始 URL（lyric_source=url 时的原始 URL）
  final int fileSize;
  final String? format;
  final int bitRate;
  final int sampleRate;
  final String? sourceUrl;
  final String? sourceCoverUrl;

  /// 音源插件入口标识（如 `kwqq`），远程歌曲用于展示「播放来源」。
  final String pluginEntryPath;

  /// 上游音源元数据（远程歌曲通常是 JSON 字符串，含 `source` 平台标识等）。
  final Map<String, dynamic>? sourceData;

  /// 词曲编曲（服务端/插件提供，字段可能缺失或为空）。
  final SongCredits? credits;

  final bool isLive;
  final bool isVideo; // 是否含真实视频轨（后端 ffprobe 探测），据此渲染画面/选择投屏 mime
  final DateTime addedAt;
  final DateTime updatedAt;

  const Song({
    required this.id,
    required this.type,
    required this.title,
    this.artist,
    this.album,
    this.year = 0,
    this.genre,
    this.language,
    this.style,
    required this.duration,
    this.filePath,
    this.url,
    this.coverUrl,
    this.lyricUrl,
    this.lyricRemoteUrl,
    this.fileSize = 0,
    this.format,
    this.bitRate = 0,
    this.sampleRate = 0,
    this.sourceUrl,
    this.sourceCoverUrl,
    this.pluginEntryPath = '',
    this.sourceData,
    this.credits,
    this.isLive = false,
    this.isVideo = false,
    required this.addedAt,
    required this.updatedAt,
  });

  factory Song.fromJson(Map<String, dynamic> json) {
    final sourceData = _parseSourceData(json['source_data']);
    return Song(
      id: json['id'] as int,
      type: json['type'] as String? ?? 'local',
      title: json['title'] as String,
      artist: json['artist'] as String?,
      album: json['album'] as String?,
      year: json['year'] as int? ?? 0,
      genre: json['genre'] as String?,
      language: json['language'] as String?,
      style: json['style'] as String?,
      duration: (json['duration'] as num?)?.toDouble() ?? 0.0,
      filePath: json['file_path'] as String?,
      url: json['url'] as String?,
      coverUrl: json['cover_url'] as String?,
      lyricUrl: json['lyric_url'] as String?,
      lyricRemoteUrl: json['lyric_remote_url'] as String?,
      fileSize: json['file_size'] as int? ?? 0,
      format: json['format'] as String?,
      bitRate: json['bit_rate'] as int? ?? 0,
      sampleRate: json['sample_rate'] as int? ?? 0,
      sourceUrl: json['source_url'] as String?,
      sourceCoverUrl: json['source_cover_url'] as String?,
      pluginEntryPath: json['plugin_entry_path'] as String? ?? '',
      sourceData: sourceData,
      // 顶层字段与插件写入 `source_data.credits` 两种形态都兼容。
      credits: SongCredits.tryParse(json['credits'] ?? sourceData?['credits']),
      isLive: json['is_live'] as bool? ?? false,
      isVideo: json['is_video'] as bool? ?? false,
      addedAt:
          json['added_at'] != null
              ? DateTime.parse(json['added_at'] as String)
              : DateTime.now(),
      updatedAt:
          json['updated_at'] != null
              ? DateTime.parse(json['updated_at'] as String)
              : DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'type': type,
      'title': title,
      'artist': artist,
      'album': album,
      'year': year,
      'genre': genre,
      'language': language,
      'style': style,
      'duration': duration,
      'file_path': filePath,
      'url': url,
      'cover_url': coverUrl,
      'lyric_url': lyricUrl,
      'lyric_remote_url': lyricRemoteUrl,
      'file_size': fileSize,
      'format': format,
      'bit_rate': bitRate,
      'sample_rate': sampleRate,
      'source_url': sourceUrl,
      'source_cover_url': sourceCoverUrl,
      'plugin_entry_path': pluginEntryPath,
      'source_data': sourceData == null ? null : jsonEncode(sourceData),
      'is_live': isLive,
      'is_video': isVideo,
      'added_at': addedAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  Song copyWith({
    int? id,
    String? type,
    String? title,
    String? artist,
    String? album,
    int? year,
    String? genre,
    String? language,
    String? style,
    double? duration,
    String? filePath,
    String? url,
    String? coverUrl,
    String? lyricUrl,
    String? lyricRemoteUrl,
    int? fileSize,
    String? format,
    int? bitRate,
    int? sampleRate,
    String? sourceUrl,
    String? sourceCoverUrl,
    String? pluginEntryPath,
    Map<String, dynamic>? sourceData,
    SongCredits? credits,
    bool? isLive,
    bool? isVideo,
    DateTime? addedAt,
    DateTime? updatedAt,
  }) {
    return Song(
      id: id ?? this.id,
      type: type ?? this.type,
      title: title ?? this.title,
      artist: artist ?? this.artist,
      album: album ?? this.album,
      year: year ?? this.year,
      genre: genre ?? this.genre,
      language: language ?? this.language,
      style: style ?? this.style,
      duration: duration ?? this.duration,
      filePath: filePath ?? this.filePath,
      url: url ?? this.url,
      coverUrl: coverUrl ?? this.coverUrl,
      lyricUrl: lyricUrl ?? this.lyricUrl,
      lyricRemoteUrl: lyricRemoteUrl ?? this.lyricRemoteUrl,
      fileSize: fileSize ?? this.fileSize,
      format: format ?? this.format,
      bitRate: bitRate ?? this.bitRate,
      sampleRate: sampleRate ?? this.sampleRate,
      sourceUrl: sourceUrl ?? this.sourceUrl,
      sourceCoverUrl: sourceCoverUrl ?? this.sourceCoverUrl,
      pluginEntryPath: pluginEntryPath ?? this.pluginEntryPath,
      sourceData: sourceData ?? this.sourceData,
      credits: credits ?? this.credits,
      isLive: isLive ?? this.isLive,
      isVideo: isVideo ?? this.isVideo,
      addedAt: addedAt ?? this.addedAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is Song && other.id == id;
  }

  @override
  int get hashCode => id.hashCode;
}

/// `source_data` 后端以 JSON 字符串落库，部分接口也可能直接给对象；两种形态都兼容。
Map<String, dynamic>? _parseSourceData(dynamic value) {
  if (value is Map<String, dynamic>) return value;
  if (value is String && value.isNotEmpty) {
    try {
      final decoded = jsonDecode(value);
      if (decoded is Map<String, dynamic>) return decoded;
    } catch (_) {
      return null;
    }
  }
  return null;
}

/// 词曲编曲名单（服务端/插件提供，字段可能缺失、为空或为单个字符串）。
class SongCredits {
  final List<String> lyricist;
  final List<String> composer;
  final List<String> arranger;

  const SongCredits({
    this.lyricist = const [],
    this.composer = const [],
    this.arranger = const [],
  });

  /// 三类名单全空时视为「无数据」，UI 整块不展示。
  bool get isEmpty => lyricist.isEmpty && composer.isEmpty && arranger.isEmpty;

  /// 容错解析：Map / JSON 字符串 / 单值字符串 / 数组都接受，缺字段给空列表。
  static SongCredits? tryParse(dynamic value) {
    final map = _asMap(value);
    if (map == null) return null;
    final credits = SongCredits(
      lyricist: _asStringList(map['lyricist'] ?? map['lyric']),
      composer: _asStringList(map['composer']),
      arranger: _asStringList(map['arranger']),
    );
    return credits.isEmpty ? null : credits;
  }

  static Map<String, dynamic>? _asMap(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    if (value is String && value.isNotEmpty) {
      try {
        final decoded = jsonDecode(value);
        if (decoded is Map<String, dynamic>) return decoded;
      } catch (_) {
        return null;
      }
    }
    return null;
  }

  static List<String> _asStringList(dynamic value) {
    final raw = value is List ? value : (value == null ? const [] : [value]);
    return raw
        .map((e) => e?.toString().trim() ?? '')
        .where((e) => e.isNotEmpty)
        .toList();
  }
}

/// 标签分类聚合项：某维度的一个取值、歌曲数量、及一首代表歌曲的封面 URL。
class SongFacet {
  final String value;
  final int count;

  /// 该取值下一首带封面歌曲的封面端点（后端拼好，无则为空 → 前端回退占位图标）。
  final String coverUrl;

  const SongFacet({
    required this.value,
    required this.count,
    this.coverUrl = '',
  });

  factory SongFacet.fromJson(Map<String, dynamic> json) {
    return SongFacet(
      value: json['value'] as String? ?? '',
      count: json['count'] as int? ?? 0,
      coverUrl: json['cover_url'] as String? ?? '',
    );
  }
}

/// 标签分类聚合的分页响应（facets + total）。
class SongFacetResponse {
  final List<SongFacet> facets;
  final int total;

  const SongFacetResponse({required this.facets, required this.total});

  factory SongFacetResponse.fromJson(Map<String, dynamic> json) {
    final list =
        (json['facets'] as List<dynamic>?)
            ?.map((e) => SongFacet.fromJson(e as Map<String, dynamic>))
            .toList() ??
        <SongFacet>[];
    return SongFacetResponse(
      facets: list,
      total: json['total'] as int? ?? list.length,
    );
  }
}

/// 歌曲列表响应
class SongListResponse {
  final List<Song> songs;
  final int total;

  const SongListResponse({required this.songs, required this.total});

  factory SongListResponse.fromJson(Map<String, dynamic> json) {
    final songsList =
        (json['songs'] as List<dynamic>?)
            ?.map((e) => Song.fromJson(e as Map<String, dynamic>))
            .toList() ??
        [];
    return SongListResponse(
      songs: songsList,
      total: json['total'] as int? ?? songsList.length,
    );
  }
}
