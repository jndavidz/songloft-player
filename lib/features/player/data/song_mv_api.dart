/// 在线歌曲 MV / 视频数据层。
///
/// 契约（服务端并行开发中，客户端先按此形状实现）：
/// - 插件聚合端点：`GET /api/v1/jsplugin/kwqq/mv?source=&id=&title=&artist=`
///   → `{items:[{id,source,title,artist,cover,duration_s,url,quality}]}`
/// - 门面端点：`GET /api/v1/jsplugin/kwqq/{source}/mv?id=`
///   → `data:{id,source,url,cover,duration_s,quality}`
///
/// 优先聚合端点；返回空列表或失败时回退门面端点。找不到可用 MV 返回 null，
/// 由 UI 层给出「该歌曲暂无可用 MV」的明确提示，不静默。
library;

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../config/app_config.dart';
import '../../../core/network/api_client.dart';

class MvTrack {
  const MvTrack({
    required this.id,
    required this.source,
    required this.title,
    required this.artist,
    required this.url,
    this.cover = '',
    this.durationSeconds,
    this.quality = '',
  });

  final String id;
  final String source;
  final String title;
  final String artist;
  final String url;
  final String cover;
  final int? durationSeconds;
  final String quality;

  bool get playable => url.trim().isNotEmpty;

  factory MvTrack.fromJson(Map<String, dynamic> json) {
    final duration = json['duration_s'] ?? json['duration'];
    return MvTrack(
      id: (json['id'] ?? '').toString(),
      source: (json['source'] ?? '').toString(),
      title: (json['title'] ?? '').toString(),
      artist: (json['artist'] ?? '').toString(),
      url: (json['url'] ?? '').toString(),
      cover: (json['cover'] ?? '').toString(),
      durationSeconds: duration is num ? duration.round() : null,
      quality: (json['quality'] ?? '').toString(),
    );
  }
}

class SongMvApi {
  SongMvApi(this._dio);

  final Dio _dio;

  static const String entryPath = 'kwqq';

  String _url(String path) => '${AppConfig.apiPrefix}/jsplugin/$entryPath$path';

  /// 查找该曲可用的 MV；无可用结果返回 null（不抛异常，避免菜单点击闪退）。
  Future<MvTrack?> findMv({
    required String source,
    required String id,
    required String title,
    required String artist,
  }) async {
    final query = {
      'source': source,
      'id': id,
      'title': title,
      'artist': artist,
    };
    try {
      final response = await _dio.get<Map<String, dynamic>>(
        _url('/mv'),
        queryParameters: query,
      );
      final items = response.data?['items'];
      if (items is List) {
        for (final item in items) {
          if (item is Map) {
            final mv = MvTrack.fromJson(Map<String, dynamic>.from(item));
            if (mv.playable) return mv;
          }
        }
      }
    } catch (error) {
      debugPrint('[SongMvApi] aggregate /mv failed: $error');
    }

    try {
      final response = await _dio.get<Map<String, dynamic>>(
        _url('/$source/mv'),
        queryParameters: {'id': id},
      );
      final data = response.data?['data'];
      if (data is Map) {
        final mv = MvTrack.fromJson(Map<String, dynamic>.from(data));
        if (mv.playable) return mv;
      }
    } catch (error) {
      debugPrint('[SongMvApi] facade /$source/mv failed: $error');
    }
    return null;
  }
}

final songMvApiProvider = Provider<SongMvApi>((ref) {
  return SongMvApi(ref.watch(dioProvider));
});
