import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:songloft_flutter/features/browse/data/plugin_browse_api.dart';
import 'package:songloft_flutter/shared/models/song.dart';
import 'package:songloft_flutter/shared/utils/song_source_label.dart';

Song _song({Map<String, dynamic>? sourceData}) => Song(
  id: 1,
  type: 'remote',
  title: '晴天',
  artist: '周杰伦',
  duration: 0,
  sourceData: sourceData,
  addedAt: DateTime(2026),
  updatedAt: DateTime(2026),
);

/// 记录请求体并返回固定响应的假 Dio 适配器。
class _RecordingAdapter implements HttpClientAdapter {
  Map<String, dynamic>? body;
  String responseJson =
      '{"total":0,"has_more":false,"hot":[],"comments":[],"source":"qq"}';
  int statusCode = 200;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    body = Map<String, dynamic>.from(options.data as Map);
    return ResponseBody.fromString(
      responseJson,
      statusCode,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

PluginBrowseApi _api(_RecordingAdapter adapter) {
  final dio = Dio()..httpClientAdapter = adapter;
  return PluginBrowseApi(dio);
}

void main() {
  group('歌曲音源标识提取', () {
    test('乐队 source_data.s / i 原样取用（QQ mid、酷狗 hash 都是字符串）', () {
      final qq = _song(sourceData: {'s': 'QQ', 'i': '0039MnYb0qxYhV'});
      expect(songSourceKey(qq), 'qq');
      expect(songSourceId(qq), '0039MnYb0qxYhV');

      final kugou = _song(sourceData: {'s': 'kugou', 'i': 'A1B2C3D4E5F6'});
      expect(songSourceId(kugou), 'A1B2C3D4E5F6');
    });

    test('数字 id 也能取到字符串', () {
      final netease = _song(sourceData: {'s': 'netease', 'i': 186016});
      expect(songSourceId(netease), '186016');
    });

    test('缺 source_data 时都返回 null（靠 title+artist 或给明确提示）', () {
      final local = _song();
      expect(songSourceKey(local), isNull);
      expect(songSourceId(local), isNull);
    });

    test('i 为空值时返回 null', () {
      expect(songSourceId(_song(sourceData: {'s': 'kuwo', 'i': '  '})), isNull);
    });
  });

  group('评论请求', () {
    test('显式带 source 与 id', () async {
      final adapter = _RecordingAdapter();
      await _api(adapter).comments(
        source: 'qq',
        id: '0039MnYb0qxYhV',
        title: '晴天',
        artist: '周杰伦',
      );
      expect(adapter.body!['source'], 'qq');
      expect(adapter.body!['id'], '0039MnYb0qxYhV');
    });

    test('无 id 时靠 title+artist 回查，且仍带 source', () async {
      final adapter = _RecordingAdapter();
      await _api(
        adapter,
      ).comments(source: 'netease', title: '晴天', artist: '周杰伦');
      expect(adapter.body!.containsKey('id'), isFalse);
      expect(adapter.body!['source'], 'netease');
      expect(adapter.body!['title'], '晴天');
      expect(adapter.body!['artist'], '周杰伦');
    });

    test('响应回传的 source 被解析', () async {
      final res = await _api(_RecordingAdapter()).comments(source: 'qq');
      expect(res.source, 'qq');
    });

    test('源不支持（200 + unsupported 标记）归一为 UnsupportedException', () async {
      final adapter =
          _RecordingAdapter()
            ..responseJson =
                '{"error":"源 migu 暂不支持评论","source":"migu","unsupported":true}';
      await expectLater(
        _api(adapter).comments(source: 'migu', title: '晴天'),
        throwsA(isA<BrowseUnsupportedException>()),
      );
    });
  });
}
