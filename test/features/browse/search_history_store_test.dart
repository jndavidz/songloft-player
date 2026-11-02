// 搜索历史持久化单测（票 02）：增/删/去重置顶/上限截断/清空/重启不复活。
// spec: songloft .scratch/musicfree-style-library issues/02
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:songloft_flutter/features/browse/data/search_history_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<SearchHistoryStore> newStore(Map<String, Object> initial) async {
    SharedPreferences.setMockInitialValues(initial);
    final prefs = await SharedPreferences.getInstance();
    return SearchHistoryStore(prefs);
  }

  test('add 去重置顶：重复词只留一条且置顶', () async {
    var store = await newStore({});
    var list = await store.add('a');
    list = await store.add('b');
    list = await store.add('a');
    expect(list, ['a', 'b']);
  });

  test('add 上限截断：超 20 条时最旧词被挤出', () async {
    var store = await newStore({});
    List<String> list = [];
    for (var i = 0; i < 25; i++) {
      list = await store.add('kw$i');
    }
    expect(list.length, SearchHistoryStore.maxLength);
    expect(list.first, 'kw24');
    expect(list.last, 'kw5'); // kw0..kw4 被挤出
    expect(list.contains('kw0'), isFalse);
  });

  test('remove / clear 生效', () async {
    var store = await newStore({});
    await store.add('a');
    await store.add('b');
    var list = await store.remove('a');
    expect(list, ['b']);
    list = await store.clear();
    expect(list, isEmpty);
    expect(store.load(), isEmpty);
  });

  test('持久化：新 store 实例（模拟重启）读回同一批词，删除不复活', () async {
    final store1 = await newStore({});
    await store1.add('周杰伦');
    await store1.add('孙燕姿');

    // 模拟重启：同一份 SharedPreferences 数据新建 store。
    final store2 = await newStore({
      SearchHistoryStore.storageKey: '["周杰伦","孙燕姿"]',
    });
    expect(store2.load(), ['周杰伦', '孙燕姿']);

    await store2.remove('周杰伦');
    final store3 = await newStore({SearchHistoryStore.storageKey: '["孙燕姿"]'});
    expect(store3.load(), ['孙燕姿']);
  });

  test('坏数据防御：存储内容非法 JSON 时返回空列表', () async {
    final store = await newStore({SearchHistoryStore.storageKey: '{oops'});
    expect(store.load(), isEmpty);
  });

  test('add 空白词与纯空格不进历史', () async {
    final store = await newStore({});
    final list = await store.add('   ');
    expect(list, isEmpty);
  });
}
