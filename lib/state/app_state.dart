import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api/jm_api.dart';
import '../api/jm_client.dart';
import '../api/models.dart';

/// 阅读方向。
enum ReadDirection { vertical, horizontal }

/// 全局应用状态：主题模式 / 阅读设置 / 登录态 / 图源与语言。
class AppState extends ChangeNotifier {
  AppState();

  final JmApi api = JmApi.instance;
  final JmClient _c = JmClient.instance;

  bool _ready = false;
  bool get ready => _ready;

  // ---------- 主题（默认跟随系统） ----------
  ThemeMode _themeMode = ThemeMode.system;
  ThemeMode get themeMode => _themeMode;

  // ---------- 阅读设置 ----------
  bool _volumeKeyPaging = true;
  bool get volumeKeyPaging => _volumeKeyPaging;

  ReadDirection _readDirection = ReadDirection.vertical;
  ReadDirection get readDirection => _readDirection;

  bool _keepScreenOn = true;
  bool get keepScreenOn => _keepScreenOn;

  // ---------- 图源 / 语言 ----------
  bool _express = false; // 加速图源
  bool get express => _express;

  String _lang = 'TW';
  String get lang => _lang;

  // ---------- 登录态 ----------
  LoginData? _user;
  LoginData? get user => _user;
  bool get isLogged => _user != null;

  String? _initError;
  String? get initError => _initError;

  /// 初始化：恢复持久化设置 → 恢复登录态 → 解析主机并拉取 setting（图床）。
  Future<void> init() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final tm = prefs.getString('theme_mode') ?? 'system';
      _themeMode = switch (tm) {
        'light' => ThemeMode.light,
        'dark' => ThemeMode.dark,
        _ => ThemeMode.system,
      };
      _volumeKeyPaging = prefs.getBool('volume_key_paging') ?? true;
      _readDirection =
          (prefs.getString('read_direction') ?? 'vertical') == 'horizontal'
              ? ReadDirection.horizontal
              : ReadDirection.vertical;
      _keepScreenOn = prefs.getBool('keep_screen_on') ?? true;
      _express = prefs.getBool('express') ?? false;
      _lang = prefs.getString('lang') ?? 'TW';

      final jwt = prefs.getString('jwt') ?? '';
      final avs = prefs.getString('avs') ?? '';
      final userMap = prefs.getString('user');
      _c.setAuth(jwt, avs);
      if (userMap != null && userMap.isNotEmpty) {
        try {
          _user = LoginData.fromMapSafe(
              Map<String, dynamic>.from(json.decode(userMap) as Map));
        } catch (_) {
          _user = null;
        }
      }
    } catch (_) {
      // 设置恢复失败不阻塞启动
    }

    // 主机解析 + 拉取全局 setting（img_host 封面图床）
    try {
      await _c.init(language: _lang);
      _ready = true;
      notifyListeners();
      try {
        final setting = await api.getSetting();
        if (setting.imgHost.isNotEmpty) _c.imgHost = setting.imgHost;
        notifyListeners();
      } catch (_) {}
    } catch (e) {
      _initError = e.toString();
      _ready = true;
      notifyListeners();
    }
  }

  Future<void> _persist(String key, Object value) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (value is bool) {
        await prefs.setBool(key, value);
      } else if (value is String) {
        await prefs.setString(key, value);
      } else if (value is int) {
        await prefs.setInt(key, value);
      } else if (value is double) {
        await prefs.setDouble(key, value);
      }
    } catch (_) {}
  }

  // ---------- 设置项写入 ----------

  Future<void> setThemeMode(ThemeMode mode) async {
    _themeMode = mode;
    notifyListeners();
    await _persist('theme_mode', switch (mode) {
      ThemeMode.light => 'light',
      ThemeMode.dark => 'dark',
      _ => 'system',
    });
  }

  Future<void> setVolumeKeyPaging(bool v) async {
    _volumeKeyPaging = v;
    notifyListeners();
    await _persist('volume_key_paging', v);
  }

  Future<void> setReadDirection(ReadDirection d) async {
    _readDirection = d;
    notifyListeners();
    await _persist('read_direction',
        d == ReadDirection.horizontal ? 'horizontal' : 'vertical');
  }

  Future<void> setKeepScreenOn(bool v) async {
    _keepScreenOn = v;
    notifyListeners();
    await _persist('keep_screen_on', v);
  }

  Future<void> setExpress(bool v) async {
    _express = v;
    notifyListeners();
    await _persist('express', v);
  }

  Future<void> setLang(String v) async {
    _lang = v;
    _c.lang = v;
    notifyListeners();
    await _persist('lang', v);
    try {
      await api.updateSetting(v);
    } catch (_) {}
  }

  // ---------- 登录态 ----------

  Future<void> setUser(LoginData user) async {
    _user = user;
    _c.setAuth(user.jwtToken, user.s);
    notifyListeners();
    await _persist('jwt', user.jwtToken);
    await _persist('avs', user.s);
    await _persist('user', json.encode(user.toMap()));
  }

  Future<void> clearUser() async {
    _user = null;
    _c.setAuth('', '');
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('jwt');
      await prefs.remove('avs');
      await prefs.remove('user');
    } catch (_) {}
  }
}
