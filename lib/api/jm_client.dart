import 'dart:convert';

import 'package:http/http.dart' as http;

import 'jm_crypto.dart';

/// 业务错误（HTTP 200 但业务 code != 200）。
class JmApiException implements Exception {
  JmApiException(this.code, this.msg);

  final int code;
  final String msg;

  @override
  String toString() => 'API 错误 code=$code msg=$msg';
}

/// HTTP 层错误（重试耗尽后抛出）。
class JmHttpException implements Exception {
  JmHttpException(this.status, [this.body = '', this.cause]);

  /// HTTP 状态码（0 表示网络错误）。
  final int status;
  final String body;
  final Object? cause;

  @override
  String toString() {
    if (status != 0) return 'HTTP $status: $body';
    return '网络错误: $cause';
  }
}

/// 统一响应信封（已解密）。
class JmResponse {
  JmResponse({
    required this.code,
    this.msg = '',
    this.data,
    this.raw = const <String, dynamic>{},
  });

  final int code;
  final String msg;
  final dynamic data;
  final Map<String, dynamic> raw;
}

/// 主机配置（远程加密配置解密后的结构）。
class JmHostConfig {
  JmHostConfig({
    required this.setting,
    required this.server,
    required this.jm3Server,
  });

  factory JmHostConfig.fromMap(Map<String, dynamic> m) => JmHostConfig(
        setting: (m['Setting'] as List?)?.cast<String>() ?? <String>[],
        server: (m['Server'] as List?)?.cast<String>() ?? <String>[],
        jm3Server: ((m['jm3_Server'] as List?) ?? <dynamic>[])
            .map((e) => (e as List).map((x) => x.toString()).toList())
            .toList(),
      );

  final List<String> setting;
  final List<String> server;
  final List<List<String>> jm3Server;
}

/// JMComic 传输客户端。
///
/// 负责：URL 拼接、Token 协议头、登录态头、重试与响应解密、线路管理。
/// 主机解析顺序：显式指定 → 远程加密配置随机挑选 → APK 内置兜底配置。
class JmClient {
  JmClient._internal();
  static final JmClient instance = JmClient._internal();

  final http.Client _http = http.Client();

  String _baseUrl = '';
  JmHostConfig? _hostConfig;

  /// 封面/头像图床主机（由 setting 接口填充）。
  String imgHost = '';

  /// 请求语言参数（TW / CN）。
  String lang = 'TW';

  String _jwt = '';
  String _avs = '';
  bool _initialized = false;

  String get baseUrl => _baseUrl;
  JmHostConfig? get hostConfig => _hostConfig;
  bool get isLogged => _jwt.isNotEmpty;
  bool get initialized => _initialized;

  /// 显式指定线路主机（如 "www.cdnhjk.net"）。
  void setBaseUrl(String host) {
    var h = host.trim();
    if (h.isEmpty) return;
    if (!h.contains('://')) h = 'https://$h';
    _baseUrl = h.endsWith('/') ? h : '$h/';
  }

  /// 全部可用线路 [主机, 线路名]。
  List<List<String>> get lines => _hostConfig?.jm3Server ?? <List<String>>[];

  /// 切换到第 [idx] 条线路（0 基）。
  void switchLine(int idx) {
    final ls = lines;
    if (idx < 0 || idx >= ls.length) return;
    setBaseUrl(ls[idx].first);
  }

  /// 设置登录态。
  void setAuth(String jwt, String avs) {
    _jwt = jwt;
    _avs = avs;
  }

  /// 主机解析：显式 > 远程配置 > 内置兜底。
  Future<void> init({String? baseUrl, String language = 'TW'}) async {
    if (language.isNotEmpty) lang = language;
    if (baseUrl != null && baseUrl.isNotEmpty) {
      setBaseUrl(baseUrl);
      _initialized = true;
      return;
    }
    for (final url in JmCrypto.hostConfigUrls) {
      try {
        final resp = await _http
            .get(Uri.parse(url), headers: <String, String>{
          'User-Agent': JmCrypto.userAgent,
        }).timeout(const Duration(seconds: 10));
        if (resp.statusCode != 200) continue;
        final cfg = JmCrypto.decryptHostConfig(utf8.decode(resp.bodyBytes));
        if (cfg == null) continue;
        final parsed = JmHostConfig.fromMap(cfg);
        if (parsed.server.isEmpty) continue;
        _hostConfig = parsed;
        parsed.server.shuffle();
        setBaseUrl(parsed.server.first);
        _initialized = true;
        return;
      } catch (_) {
        continue;
      }
    }
    // 回退到 APK 内置兜底配置
    final cfg = JmCrypto.decryptHostConfig(JmCrypto.backupHostCode);
    if (cfg != null) {
      final parsed = JmHostConfig.fromMap(cfg);
      _hostConfig = parsed;
      if (parsed.server.isNotEmpty) {
        parsed.server.shuffle();
        setBaseUrl(parsed.server.first);
        _initialized = true;
        return;
      }
    }
    throw JmHttpException(0, '主机解析失败(远程与内置均失败)');
  }

  /// 构造带协议头的请求头。
  Map<String, String> _headers({String? contentType}) {
    final t = JmCrypto.randomToken();
    return <String, String>{
      'User-Agent': JmCrypto.userAgent,
      'Tokenparam': t.tokenparam,
      'Token': t.token,
      if (_jwt.isNotEmpty) 'Authorization': 'Bearer $_jwt',
      if (_avs.isNotEmpty) 'Cookie': 'AVS=$_avs',
      'Content-Type': ?contentType,
    };
  }

  /// 编码 GET query（过滤空值，自动补 lang）。
  Map<String, String> _buildQuery(Map<String, dynamic> params) {
    final q = <String, String>{};
    params.forEach((k, v) {
      if (v == null) return;
      final s = v.toString();
      if (s.isEmpty) return;
      q[k] = s;
    });
    if (!q.containsKey('lang') && lang.isNotEmpty) q['lang'] = lang;
    return q;
  }

  String _fullUrl(String path) {
    if (path.startsWith('http')) return path;
    return _baseUrl + (path.startsWith('/') ? path.substring(1) : path);
  }

  /// 统一请求入口（首次 + 最多 3 次重试；401/400 不重试）。
  Future<JmResponse> _do(
    String method,
    String path, {
    Map<String, dynamic> params = const <String, dynamic>{},
    String? body,
    String? contentType,
  }) async {
    final url = Uri.parse(_fullUrl(path)).replace(
      queryParameters: method == 'GET' ? _buildQuery(params) : null,
    );
    Object? lastCause;
    int? lastStatus;
    String lastBody = '';

    for (var attempt = 0; attempt < 4; attempt++) {
      try {
        final headers = _headers(contentType: contentType);
        final req = http.Request(method, url)..headers.addAll(headers);
        if (body != null && body.isNotEmpty) req.body = body;
        final resp = await _http.send(req).timeout(const Duration(seconds: 20));

        final respBody =
            await http.Response.fromStream(resp).timeout(const Duration(seconds: 20));
        lastStatus = resp.statusCode;
        lastBody = respBody.body;

        if (resp.statusCode < 200 || resp.statusCode > 299) {
          if (resp.statusCode == 401 || resp.statusCode == 400) {
            throw JmHttpException(resp.statusCode, _truncate(respBody.body));
          }
          continue; // 非 401/400 重试
        }
        return _decryptResponse(path, respBody.body);
      } on JmApiException {
        rethrow;
      } on JmHttpException {
        rethrow;
      } catch (e) {
        lastCause = e;
        continue;
      }
    }
    if (lastStatus != null && lastStatus != 0) {
      throw JmHttpException(lastStatus, _truncate(lastBody));
    }
    throw JmHttpException(0, '', lastCause);
  }

  String _truncate(String s) => s.length <= 200 ? s : s.substring(0, 200);

  /// 解密响应信封 `{"code":..,"msg":"..","data":"<base64密文>"}`。
  JmResponse _decryptResponse(String path, String body) {
    Map<String, dynamic> envelope;
    try {
      final decoded = json.decode(body);
      if (decoded is Map<String, dynamic>) {
        envelope = decoded;
      } else {
        throw JmHttpException(0, '响应格式异常: 非 JSON 对象');
      }
    } on FormatException {
      throw JmHttpException(0, '响应 JSON 解析失败');
    }

    final code = (envelope['code'] as num?)?.toInt() ?? 0;
    final msg = (envelope['msg'] ?? '').toString();
    final data = envelope['data'];

    if (code != 200) {
      throw JmApiException(code, msg);
    }
    if (data == null) {
      return JmResponse(code: code, msg: msg, data: null, raw: envelope);
    }
    // data 不是字符串 → 服务端直接返回明文
    if (data is! String) {
      return JmResponse(code: code, msg: msg, data: data, raw: envelope);
    }
    if (data.isEmpty) {
      return JmResponse(code: code, msg: msg, data: null, raw: envelope);
    }

    final isAd =
        path.contains('ad_content_all') || path.contains('advertise_all');
    final plain = JmCrypto.decryptData(data, '', isAd);
    if (plain == null) {
      // 尝试明文解析（少数接口直接返回明文 JSON 字符串）
      try {
        final decoded = json.decode(data);
        return JmResponse(code: code, msg: msg, data: decoded, raw: envelope);
      } on FormatException {
        throw JmHttpException(0, '响应解密失败');
      }
    }
    try {
      final decoded = json.decode(plain);
      return JmResponse(code: code, msg: msg, data: decoded, raw: envelope);
    } on FormatException {
      throw JmHttpException(0, '解密后 JSON 解析失败');
    }
  }

  // ---------- Transport ----------

  /// GET 请求。
  Future<JmResponse> get(String path,
      [Map<String, dynamic> params = const <String, dynamic>{}]) async {
    await _ensureReady();
    return _do('GET', path, params: params);
  }

  /// POST 表单请求。
  Future<JmResponse> postForm(String path,
      [Map<String, dynamic> params = const <String, dynamic>{}]) async {
    await _ensureReady();
    final q = _buildQuery(params);
    final body = q.entries
        .map((e) =>
            '${Uri.encodeComponent(e.key)}=${Uri.encodeComponent(e.value)}')
        .join('&');
    return _do('POST', path,
        body: body, contentType: 'application/x-www-form-urlencoded');
  }

  /// POST JSON 请求（tag_block 等专用）。
  Future<JmResponse> postJson(String path, Object payload) async {
    await _ensureReady();
    return _do('POST', path,
        body: json.encode(payload), contentType: 'application/json');
  }

  /// 图片下载（带 Token 鉴权头；登录后附带 AVS Cookie）。
  Future<List<int>> fetchImage(String rawUrl,
      [Map<String, dynamic> params = const <String, dynamic>{}]) async {
    await _ensureReady();
    var url = Uri.parse(_fullUrl(rawUrl));
    if (params.isNotEmpty) {
      final q = Map<String, String>.from(url.queryParameters);
      q.addAll(_buildQuery(params));
      url = url.replace(queryParameters: q);
    }
    final resp = await _http
        .get(url, headers: _headers())
        .timeout(const Duration(seconds: 30));
    if (resp.statusCode != 200) {
      throw JmHttpException(resp.statusCode, '图片下载失败: $rawUrl');
    }
    return resp.bodyBytes;
  }

  /// 首次使用前确保主机已解析。
  Future<void> _ensureReady() async {
    if (!_initialized) await init(language: lang);
  }

  void dispose() => _http.close();
}
