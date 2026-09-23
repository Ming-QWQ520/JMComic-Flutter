import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// 本地持久化存储（SharedPreferences 封装）。
///
/// 统一管理：设置项、登录态、搜索历史。
class LocalStore {
  LocalStore._();
  static final LocalStore instance = LocalStore._();

  SharedPreferences? _prefs;

  Future<SharedPreferences> get _db async =>
      _prefs ??= await SharedPreferences.getInstance();

  // ---------- 基础类型 ----------

  Future<String> getString(String key, [String def = '']) async {
    final p = await _db;
    return p.getString(key) ?? def;
  }

  Future<void> setString(String key, String value) async {
    final p = await _db;
    await p.setString(key, value);
  }

  Future<bool> getBool(String key, [bool def = false]) async {
    final p = await _db;
    return p.getBool(key) ?? def;
  }

  Future<void> setBool(String key, bool value) async {
    final p = await _db;
    await p.setBool(key, value);
  }

  Future<int> getInt(String key, [int def = 0]) async {
    final p = await _db;
    return p.getInt(key) ?? def;
  }

  Future<void> setInt(String key, int value) async {
    final p = await _db;
    await p.setInt(key, value);
  }

  Future<void> remove(String key) async {
    final p = await _db;
    await p.remove(key);
  }

  // ---------- 结构化对象 ----------

  Future<Map<String, dynamic>> getJson(String key) async {
    final s = await getString(key);
    if (s.isEmpty) return <String, dynamic>{};
    try {
      final v = json.decode(s);
      if (v is Map<String, dynamic>) return v;
    } catch (_) {}
    return <String, dynamic>{};
  }

  Future<void> setJson(String key, Map<String, dynamic> value) =>
      setString(key, json.encode(value));

  // ---------- 搜索历史 ----------

  static const String _kSearchHistory = 'search_history';

  Future<List<String>> getSearchHistory() async {
    final s = await getString(_kSearchHistory);
    if (s.isEmpty) return <String>[];
    try {
      final v = json.decode(s);
      if (v is List) return v.whereType<String>().toList();
    } catch (_) {}
    return <String>[];
  }

  /// 新增一条搜索历史（去重、最新在前、最多 12 条）。
  Future<List<String>> pushSearchHistory(String keyword) async {
    final k = keyword.trim();
    if (k.isEmpty) return getSearchHistory();
    final list = await getSearchHistory()
      ..removeWhere((String e) => e == k)
      ..insert(0, k);
    final trimmed = list.length > 12 ? list.sublist(0, 12) : list;
    await setString(_kSearchHistory, json.encode(trimmed));
    return trimmed;
  }

  Future<List<String>> clearSearchHistory() async {
    await remove(_kSearchHistory);
    return <String>[];
  }
}
