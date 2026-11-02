/// 搜索历史（设备本地持久化，不上 server）。
///
/// 语义（票 02）：重复搜索置顶去重、上限 [maxLength] 挤出最旧、单条删除、
/// 整体清空；清空后回到无历史占位态。存储走 SharedPreferences 单 key JSON 数组。

library;

import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SearchHistoryStore {
  static const storageKey = 'browse_search_history_v1';
  static const maxLength = 20;

  final SharedPreferences _prefs;

  SearchHistoryStore(this._prefs);

  static Future<SearchHistoryStore> create() async {
    final prefs = await SharedPreferences.getInstance();
    return SearchHistoryStore(prefs);
  }

  List<String> load() {
    final raw = _prefs.getString(storageKey);
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = jsonDecode(raw);
      if (list is! List) return [];
      return list.whereType<String>().where((e) => e.isNotEmpty).toList();
    } catch (_) {
      return [];
    }
  }

  Future<List<String>> add(String keyword) async {
    final kw = keyword.trim();
    if (kw.isEmpty) return load();
    final next = [kw, ...load().where((e) => e != kw)];
    if (next.length > maxLength) {
      next.removeRange(maxLength, next.length);
    }
    await _save(next);
    return next;
  }

  Future<List<String>> remove(String keyword) async {
    final next = load().where((e) => e != keyword).toList();
    await _save(next);
    return next;
  }

  Future<List<String>> clear() async {
    await _prefs.remove(storageKey);
    return [];
  }

  Future<void> _save(List<String> list) async {
    await _prefs.setString(storageKey, jsonEncode(list));
  }
}

final searchHistoryStoreProvider = FutureProvider<SearchHistoryStore>(
  (ref) => SearchHistoryStore.create(),
);
