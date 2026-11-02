/// kwqq 插件在线浏览 API 客户端。
///
/// 调用宿主既有插件转发链 `/api/v1/jsplugin/{entryPath}/*`（catch-all 已带 JWT
/// 鉴权并原样透传 QuickJS 响应，server 不落库任何浏览载荷）。端点按 MusicFree
/// 函数语义命名，契约事实源：kwqq 插件 test/browse.test.mjs 与 musicdl
/// API-REFERENCE §4/§5.1。
///
/// 501（该源不支持）与上游 502 以 [BrowseUnsupportedException] /
/// [BrowseUpstreamException] 抛出，UI 层给出「该源暂不支持」等明确提示。

library;

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../config/app_config.dart';
import '../../../core/network/api_client.dart';
import 'browse_models.dart';

/// 该源不支持此能力（插件 501 envelope：{error, unsupported:true}）。
class BrowseUnsupportedException implements Exception {
  final String message;
  BrowseUnsupportedException(this.message);
  @override
  String toString() => message;
}

/// 上游失败（插件 502 / 网络 / 超时）。
class BrowseUpstreamException implements Exception {
  final String message;
  BrowseUpstreamException(this.message);
  @override
  String toString() => message;
}

class PluginBrowseApi {
  final Dio _dio;

  PluginBrowseApi(this._dio);

  static const entryPath = 'kwqq';

  String _url(String endpoint) =>
      '${AppConfig.apiPrefix}/jsplugin/$entryPath/$endpoint';

  Future<Map<String, dynamic>> _post(
    String endpoint,
    Map<String, dynamic> body,
  ) async {
    final Response response;
    try {
      response = await _dio.post<Map<String, dynamic>>(
        _url(endpoint),
        data: body,
      );
    } on DioException catch (e) {
      final code = e.response?.statusCode;
      final data = e.response?.data;
      if (code == 501) {
        throw BrowseUnsupportedException(
          data is Map && data['error'] != null
              ? data['error'].toString()
              : '该源暂不支持此能力',
        );
      }
      throw BrowseUpstreamException(
        data is Map && data['error'] != null
            ? data['error'].toString()
            : '在线内容加载失败（$code）',
      );
    }
    return response.data ?? const {};
  }

  /// 多类型搜索：type ∈ music/album/artist/sheet。
  Future<BrowseSearchResponse> search({
    required String keywords,
    String type = 'music',
    int page = 1,
    int limit = 20,
  }) async {
    final data = await _post('browse/search', {
      'keywords': keywords,
      'type': type,
      'page': page,
      'limit': limit,
    });
    return BrowseSearchResponse.fromJson(data);
  }

  /// 专辑详情：netease 优先按 id 精确透传，其余源按 name+artist 精装二段式。
  Future<BrowseAlbumInfo> albumInfo({
    String? id,
    String? name,
    String? artist,
    String source = 'netease',
  }) async {
    final data = await _post('album/info', {
      'source': source,
      if (id != null && id.isNotEmpty) 'id': id,
      if (name != null && name.isNotEmpty) 'name': name,
      if (artist != null && artist.isNotEmpty) 'artist': artist,
    });
    return BrowseAlbumInfo.fromJson(data);
  }

  /// 歌手详情。
  Future<BrowseArtist> artistInfo({required String id}) async {
    final data = await _post('artist/info', {'id': id});
    return BrowseArtist.fromJson(
      data['artist'] as Map<String, dynamic>? ?? const {},
    );
  }

  /// 歌手作品：type ∈ music/album。
  Future<BrowseArtistWorks> artistWorks({
    required String id,
    String type = 'music',
    int page = 1,
    int limit = 30,
  }) async {
    final data = await _post('artist/works', {
      'id': id,
      'type': type,
      'page': page,
      'limit': limit,
    });
    return BrowseArtistWorks.fromJson(data);
  }

  /// 歌单详情（曲目分页；page=1 时附歌单元数据）。
  Future<BrowseSheetInfo> sheetInfo({
    required String id,
    int page = 1,
    int limit = 50,
  }) async {
    final data = await _post('sheet/info', {
      'id': id,
      'page': page,
      'limit': limit,
    });
    return BrowseSheetInfo.fromJson(data);
  }

  /// 平台榜单列表。
  Future<List<BrowseToplist>> toplists() async {
    final data = await _post('toplists', const {});
    return (data['items'] as List<dynamic>? ?? [])
        .map((e) => BrowseToplist.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// 榜单详情（榜单 id 即平台歌单 id）。
  Future<BrowsePage<BrowseTrack>> toplistDetail({
    required String id,
    int page = 1,
    int limit = 50,
  }) async {
    final data = await _post('toplist/detail', {
      'id': id,
      'page': page,
      'limit': limit,
    });
    return BrowsePage(
      isEnd: data['isEnd'] as bool? ?? true,
      total: (data['total'] as num?)?.toInt(),
      items:
          (data['tracks'] as List<dynamic>? ?? [])
              .map((e) => BrowseTrack.fromJson(e as Map<String, dynamic>))
              .toList(),
    );
  }

  /// 推荐歌单标签（pinned + 分组）。
  Future<BrowseRecommendTags> recommendTags() async {
    final data = await _post('recommend/tags', const {});
    return BrowseRecommendTags.fromJson(data);
  }

  /// 某分类下的推荐歌单列表。
  Future<BrowsePage<BrowseSheet>> recommendSheets({
    required String cat,
    int page = 1,
    int limit = 30,
  }) async {
    final data = await _post('recommend/sheets', {
      'cat': cat,
      'page': page,
      'limit': limit,
    });
    return BrowsePage(
      isEnd: data['isEnd'] as bool? ?? true,
      total: (data['total'] as num?)?.toInt(),
      items:
          (data['items'] as List<dynamic>? ?? [])
              .map((e) => BrowseSheet.fromJson(e as Map<String, dynamic>))
              .toList(),
    );
  }

  /// 歌曲评论（只读）。id 缺省时按 title+artist 回搜 netease 歌曲。
  Future<BrowseCommentsResponse> comments({
    String? id,
    String? title,
    String? artist,
    int page = 1,
    int limit = 20,
  }) async {
    final data = await _post('music/comments', {
      if (id != null && id.isNotEmpty) 'id': id,
      if (title != null && title.isNotEmpty) 'title': title,
      if (artist != null && artist.isNotEmpty) 'artist': artist,
      'page': page,
      'limit': limit,
    });
    return BrowseCommentsResponse.fromJson(data);
  }
}

final pluginBrowseApiProvider = Provider<PluginBrowseApi>((ref) {
  final dio = ref.watch(dioProvider);
  return PluginBrowseApi(dio);
});
