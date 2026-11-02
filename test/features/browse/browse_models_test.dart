// 在线点播链单测（票 06/07/08）：BrowseTrack → /songs/remote 请求体形状、
// dedup_key 透传、不可播条目过滤。spec: musicfree-style-library。
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:songloft_flutter/features/browse/data/browse_models.dart';

void main() {
  test('toRemotePayload：source_data 编码为 JSON 字符串，dedup_key 原样透传', () {
    const track = BrowseTrack(
      title: '可爱女人',
      artist: '周杰伦',
      album: 'Jay',
      duration: 239,
      coverUrl: 'https://p/c.jpg',
      source: 'netease',
      sourceData: {'s': 'netease', 'i': '186145', 'n': '可爱女人'},
      dedupKey: 'kwqq_netease_186145',
    );
    final payload = track.toRemotePayload();
    expect(payload['title'], '可爱女人');
    expect(payload['artist'], '周杰伦');
    expect(payload['album'], 'Jay');
    expect(payload['cover_url'], 'https://p/c.jpg');
    expect(payload['duration'], 239.0);
    expect(payload['plugin_entry_path'], 'kwqq');
    expect(payload['dedup_key'], 'kwqq_netease_186145');
    final sd =
        jsonDecode(payload['source_data'] as String) as Map<String, dynamic>;
    expect(sd['s'], 'netease');
    expect(sd['i'], '186145');
  });

  test('toRemotePayload：空 album/cover 不携带，缺 dedup_key 不携带', () {
    const track = BrowseTrack(
      title: 'T',
      artist: 'A',
      sourceData: {'s': 'kuwo', 'i': '1'},
    );
    final payload = track.toRemotePayload();
    expect(payload.containsKey('album'), isFalse);
    expect(payload.containsKey('cover_url'), isFalse);
    expect(payload.containsKey('dedup_key'), isFalse);
    expect(payload['plugin_entry_path'], 'kwqq');
  });

  test('isPlayable：有 source_data 且 s 非空才可播', () {
    const playable = BrowseTrack(
      title: 'T',
      artist: 'A',
      sourceData: {'s': 'netease', 'i': '1'},
    );
    const noSource = BrowseTrack(title: 'T', artist: 'A');
    const emptyS = BrowseTrack(
      title: 'T',
      artist: 'A',
      sourceData: {'s': '', 'i': '1'},
    );
    expect(playable.isPlayable, isTrue);
    expect(noSource.isPlayable, isFalse);
    expect(emptyS.isPlayable, isFalse);
  });

  test('fromJson：netease 曲目字段映射（duration 毫秒→秒由插件完成，此处透传）', () {
    final track = BrowseTrack.fromJson({
      'title': '我怀念的',
      'artist': '孙燕姿',
      'album': '逆光',
      'duration': 289,
      'cover_url': 'https://p/1.jpg',
      'source': 'netease',
      'source_data': {'s': 'netease', 'i': '287063'},
      'dedup_key': 'kwqq_netease_287063',
      'track_no': 1,
    });
    expect(track.title, '我怀念的');
    expect(track.trackNo, 1);
    expect(track.dedupKey, 'kwqq_netease_287063');
    expect(track.isPlayable, isTrue);
  });
}
