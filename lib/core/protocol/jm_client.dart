import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'jm_crypto.dart';
import 'jm_domain.dart';

/// 业务错误（HTTP 200 但业务 code != 200）。
class JmApiException implements Exception {
  JmApiException(this.code, this.msg);

  final int code;
  final String msg;

  @override
  String toString() => 'API 错误 code=$code msg=$msg';
}

/// HTTP 层错误（重试与线路切换耗尽后抛出）。
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
    this.cookies = const <String, String>{},
  });

  final int code;
  final String msg;
  final dynamic data;
  final Map<String, dynamic> raw;
  final Map<String, String> cookies;
}

/// 远程主机配置（newsvr-2025.txt 解密后的结构）。
class JmHostConfig {
  JmHostConfig({
    required this.setting,
    required this.server,
    required this.jm3Server,
  });

  factory JmHostConfig.fromMap(Map<String, dynamic> m) => JmHostConfig(
    setting:
        (m['Setting'] as List?)?.map((e) => e.toString()).toList() ??
        <String>[],
    server:
        (m['Server'] as List?)?.map((e) => e.toString()).toList() ?? <String>[],
    jm3Server: ((m['jm3_Server'] as List?) ?? <dynamic>[])
        .map((e) => (e as List).map((x) => x.toString()).toList())
        .toList(),
  );

  final List<String> setting;
  final List<String> server;
  final List<List<String>> jm3Server;
}

/// JMComic 传输客户端（对齐 tonquer/JMComic-qt 传输方案）。
///
/// 负责：
/// - API 域名 (Url2List) / 图片域名 (PicUrlList) 按索引选择，失败自动切换下一域名；
/// - Token/Tokenparam 签名、登录态 (JWT + AVS Cookie)；
/// - DoH (DNS over HTTPS) 可选解析与 IP 直连；
/// - 远程配置 (newsvr-2025.txt) 拉取更新全部域名；
/// - 响应解密（AES-256-ECB，密钥由请求时间戳派生）。
class JmClient {
  JmClient._internal();
  static final JmClient instance = JmClient._internal();

  HttpClient? _http;
  HttpClient get _client => _http ??= _newHttpClient();

  HttpClient _newHttpClient() {
    final c = HttpClient()
      ..connectionTimeout = const Duration(seconds: 12)
      ..autoUncompress = true
      ..userAgent = JmCrypto.userAgent;
    c.connectionFactory = _connectionFactory;
    return c;
  }

  /// 自定义连接工厂：启用 DoH 时按解析出的 IP 直连。
  Future<ConnectionTask<Socket>> _connectionFactory(
    Uri url,
    String? proxyHost,
    int? proxyPort,
  ) async {
    var host = url.host;
    var port = url.port;
    if (proxyHost != null && proxyPort != null) {
      host = proxyHost;
      port = proxyPort;
    }
    final ip = _dnsCache[host];
    if (ip == null || ip == host) {
      return Socket.startConnect(host, port);
    }
    if (url.scheme == 'https') {
      // IP 直连无法按域名校验证书，需信任
      return SecureSocket.startConnect(
        ip,
        port,
        onBadCertificate: (_) => true,
        supportedProtocols: const <String>['http/1.1'],
      );
    }
    return Socket.startConnect(ip, port);
  }

  // ---------- 线路管理 ----------

  /// 当前 API 线路索引（1..4 普通，5 CDN，6 代理）。
  int apiIndex = 1;

  /// 当前图片线路索引。
  int imgIndex = 1;

  /// 当前 API 主机。
  String get apiHost => JmDomain.getApiUrl(apiIndex);

  /// 当前图片主机。
  String get imgHost => JmDomain.getImgUrl(imgIndex);

  /// 图片域名轮询游标（同一线路失败后自动切下一个）。
  int _imgRotate = 0;

  /// 语言参数（CN / TW）。
  String lang = 'CN';

  /// 远程配置。
  JmHostConfig? _hostConfig;
  JmHostConfig? get hostConfig => _hostConfig;

  // ---------- DoH ----------

  /// 是否启用 DoH。
  bool enableDoh = false;

  /// 当前 DoH 服务索引。
  int dohIndex = 0;

  final Map<String, String> _dnsCache = <String, String>{};
  final Map<String, List<Completer<String?>>> _dohWaiters =
      <String, List<Completer<String?>>>{};

  // ---------- 登录态 ----------

  String _jwt = '';
  String _avs = '';
  bool _initialized = false;

  String get jwt => _jwt;
  String get avs => _avs;
  bool get isLogged => _jwt.isNotEmpty;
  bool get initialized => _initialized;

  /// 设置登录态。
  void setAuth(String jwt, String avs) {
    _jwt = jwt;
    _avs = avs;
  }

  /// 全部可用线路 [主机, 线路名]（远程 jm3_Server 配置）。
  List<List<String>> get lines => _hostConfig?.jm3Server ?? <List<String>>[];

  /// 初始化：拉取远程配置更新域名 → 标记就绪。
  ///
  /// 对齐 qt 启动流程：GetJmServerReq 拉取 newsvr-*.txt（k=v 文本），
  /// 失败则回退加密配置解密，再失败用内置默认域名。
  Future<void> init({
    int? api,
    int? img,
    String language = 'CN',
    bool doh = false,
    int dohIdx = 0,
  }) async {
    if (api != null && api > 0) apiIndex = api;
    if (img != null && img > 0) imgIndex = img;
    if (language.isNotEmpty) lang = language;
    enableDoh = doh;
    if (dohIdx > 0) dohIndex = dohIdx - 1;

    // 1. 远程 k=v 配置（对齐 qt GetJmServerReq → UpdateSetting）
    for (final url in JmCrypto.hostConfigUrls) {
      try {
        final text = await _plainGet(url);
        if (text != null && JmDomain.updateSettingFromText(text)) {
          break;
        }
      } catch (_) {
        continue;
      }
    }

    // 2. 远程加密配置（补充 jm3_Server 线路列表）
    try {
      final text = await _plainGet(JmDomain.jmServerUrl.value);
      if (text != null) {
        final cfg = JmCrypto.decryptHostConfig(text);
        if (cfg != null) {
          final parsed = JmHostConfig.fromMap(cfg);
          if (parsed.jm3Server.isNotEmpty) _hostConfig = parsed;
        }
      }
    } catch (_) {}

    _initialized = true;
  }

  /// 简单 GET 文本（不走 API 协议）。
  Future<String?> _plainGet(String url) async {
    HttpClientRequest? req;
    try {
      req = await _client
          .getUrl(Uri.parse(url))
          .timeout(const Duration(seconds: 10));
      final resp = await req.close().timeout(const Duration(seconds: 10));
      if (resp.statusCode != 200) {
        await resp.drain<void>();
        return null;
      }
      return await _readText(resp);
    } catch (_) {
      return null;
    }
  }

  // ---------- DoH 解析 ----------

  /// 通过 DoH 解析域名 IP（对齐 qt DnsOverHttpsReq）。
  ///
  /// 返回随机一个 A 记录 IP；失败返回 null。
  Future<String?> dohResolve(String host) async {
    if (!enableDoh) return null;
    final cached = _dnsCache[host];
    if (cached != null) return cached;

    final waiters = _dohWaiters.putIfAbsent(host, () => <Completer<String?>>[]);
    if (waiters.isNotEmpty) {
      final c = Completer<String?>();
      waiters.add(c);
      return c.future;
    }

    final urls = JmDomain.dohUrlList.value;
    for (var i = 0; i < urls.length; i++) {
      final dohUrl = urls[(dohIndex + i) % urls.length];
      try {
        final sep = dohUrl.contains('?') ? '&' : '?';
        final uri = Uri.parse('$dohUrl${sep}name=$host&type=A');
        final req = await _client
            .openUrl('GET', uri)
            .timeout(const Duration(seconds: 6));
        req.headers.set('accept', 'application/dns-json');
        final resp = await req.close().timeout(const Duration(seconds: 6));
        final body = await _readText(resp);
        if (resp.statusCode == 200 && body.isNotEmpty) {
          final json = jsonDecode(body);
          final answers = json['Answer'] as List?;
          final ips = <String>[];
          for (final a in answers ?? <dynamic>[]) {
            final data = a is Map ? a['data']?.toString() ?? '' : '';
            if (InternetAddress.tryParse(data) != null) ips.add(data);
          }
          if (ips.isNotEmpty) {
            ips.shuffle();
            _dnsCache[host] = ips.first;
            for (final w in waiters) {
              if (!w.isCompleted) w.complete(ips.first);
            }
            _dohWaiters.remove(host);
            return ips.first;
          }
        }
      } catch (_) {
        continue;
      }
    }
    for (final w in waiters) {
      if (!w.isCompleted) w.complete(null);
    }
    _dohWaiters.remove(host);
    return null;
  }

  void clearDns() => _dnsCache.clear();

  // ---------- 请求头 ----------

  /// API 请求头（对齐 qt GetHeader）。
  ///
  /// ⚠签名三元组 [t] 必须与响应解密使用的 ts 是同一个值：
  /// 服务端用请求头 tokenparam 中的 ts 派生 AES 密钥加密响应 data。
  Map<String, String> _apiHeaders(JmCryptoToken t, {String? contentType}) {
    return <String, String>{
      'tokenparam': t.tokenparam,
      'token': t.token,
      'accept-encoding': 'gzip',
      'version': JmCrypto.clientVersion,
      if (_jwt.isNotEmpty) 'authorization': 'Bearer $_jwt',
      if (_avs.isNotEmpty) 'cookie': 'AVS=$_avs',
      if (contentType != null) 'Content-Type': contentType,
    };
  }

  /// 图片请求头（对齐 qt DownloadBookReq：仅 Accept-Encoding，
  /// 不带 token/authorization，避免 CF 缓存 BYPASS 回源）。
  Map<String, String> _imgHeaders() {
    return <String, String>{'accept-encoding': 'identity'};
  }

  /// `/chapter_view_template` 专用签名头（对齐 qt GetHeader2）。
  Map<String, String> _scrambleHeaders() {
    final t = JmCrypto.scrambleToken();
    return <String, String>{
      'tokenparam': t.tokenparam,
      'token': t.token,
      'user-agent': JmCrypto.userAgent,
      'accept-encoding': 'gzip',
    };
  }

  Map<String, String> _webHeaders({String? referer, String? contentType}) {
    return <String, String>{
      'accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,image/apng,*/*;q=0.8',
      'accept-encoding': 'gzip, deflate, br',
      'accept-language': 'zh-CN,zh;q=0.9',
      'upgrade-insecure-requests': '1',
      'user-agent': JmCrypto.webUserAgent,
      'content-type': ?contentType,
      'referer': ?referer,
    };
  }

  // ---------- URL 构造 ----------

  /// 编码 query（过滤空值，自动补 lang，对齐 qt DictToUrl）。
  String buildQuery(Map<String, dynamic> params, {bool withLang = true}) {
    final parts = <String>[];
    params.forEach((k, v) {
      if (v == null) return;
      final s = v.toString();
      if (s.isEmpty) return;
      parts.add('${Uri.encodeComponent(k)}=${Uri.encodeComponent(s)}');
    });
    if (withLang && lang.isNotEmpty && !params.containsKey('lang')) {
      parts.add('lang=${Uri.encodeComponent(lang)}');
    }
    return parts.join('&');
  }

  /// URL 构造（对齐 qt：GET 带 query 时为 `{path}/?{query}`，POST 为 `{path}`）。
  String _apiUrl(
    String path,
    Map<String, dynamic> params, {
    bool withLang = true,
  }) {
    var base = apiHost;
    if (!base.endsWith('/')) base = '$base/';
    var p = path.startsWith('/') ? path.substring(1) : path;
    final query = buildQuery(params, withLang: withLang);
    var url = '$base$p';
    if (query.isNotEmpty) url += '/?$query';
    return url;
  }

  // ---------- 核心请求 ----------

  /// 统一 API 请求入口。
  ///
  /// 失败时自动切换下一 API 域名重试（对齐 qt ResetToSwitchNextUrl），
  /// 最多遍历全部域名列表 1 轮。
  Future<JmResponse> _do(
    String method,
    String path, {
    Map<String, dynamic> params = const <String, dynamic>{},
    String? body,
    String? contentType,
    bool withLang = true,
    Map<String, String>? extraHeaders,
  }) async {
    await _ensureReady();
    final attemptMax = JmDomain.apiUrlList.value.length;
    Object? lastCause;

    for (var attempt = 0; attempt < attemptMax; attempt++) {
      final urlStr = _apiUrl(path, params, withLang: withLang);
      // 每次尝试生成一次签名；请求头与响应解密使用同一个 ts（对齐 qt：
      // self.now 同时用于 GetHeader 与 ParseData，不可两次生成）。
      final t = JmCrypto.randomToken();
      try {
        final resp = await _send(
          method,
          Uri.parse(urlStr),
          headers: {
            ..._apiHeaders(t, contentType: contentType),
            ...?extraHeaders,
          },
          body: body,
        );
        if (resp != null) {
          return await _decryptResponse(resp, ts: t.ts);
        }
        lastCause = 'HTTP 错误';
      } on JmApiException {
        rethrow;
      } on JmHttpException catch (e) {
        if (e.status == 401 || e.status == 400) rethrow;
        lastCause = e;
      } catch (e) {
        lastCause = e;
      }
      // 切换下一个 API 域名重试
      final list = JmDomain.apiUrlList.value;
      if (list.isEmpty) break;
      apiIndex = apiIndex % list.length + 1;
    }
    throw JmHttpException(0, '', lastCause);
  }

  /// 底层 HTTP 发送（支持 DoH 预解析）。
  Future<HttpClientResponse?> _send(
    String method,
    Uri url, {
    Map<String, String> headers = const <String, String>{},
    String? body,
    Duration timeout = const Duration(seconds: 20),
  }) async {
    if (enableDoh) await dohResolve(url.host);
    final req = await _client.openUrl(method, url).timeout(timeout);
    headers.forEach((k, v) => req.headers.set(k, v));
    if (body != null && body.isNotEmpty) {
      req.add(utf8.encode(body));
    }
    final resp = await req.close().timeout(timeout);
    if (resp.statusCode < 200 || resp.statusCode > 299) {
      await resp.drain<void>().catchError((_) {});
      if (resp.statusCode == 401 || resp.statusCode == 400) {
        throw JmHttpException(resp.statusCode);
      }
      return null; // 其它状态码 → 切换线路
    }
    return resp;
  }

  /// 读取响应文本（gzip 由 HttpClient 自动解压）。
  Future<String> _readText(HttpClientResponse resp) async {
    try {
      return await resp.transform(utf8.decoder).join();
    } catch (_) {
      return '';
    }
  }

  /// 收集响应 set-cookie（登录 AVS 等）。
  Map<String, String> _cookiesOf(HttpClientResponse resp) {
    final out = <String, String>{};
    for (final c in resp.cookies) {
      if (c.name.isNotEmpty) out[c.name] = c.value;
    }
    return out;
  }

  /// 解密响应信封 `{"code":..,"msg"/"errorMsg":..,"data":"<base64密文>"}`。
  ///
  /// [ts] 为本次请求头 tokenparam 中的时间戳（服务端用它派生加密密钥）。
  Future<JmResponse> _decryptResponse(
    HttpClientResponse resp, {
    required String ts,
  }) async {
    final body = await _readText(resp);
    Map<String, dynamic> envelope;
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map<String, dynamic>) {
        envelope = decoded;
      } else {
        throw JmHttpException(0, '响应格式异常: 非 JSON 对象');
      }
    } on FormatException {
      throw JmHttpException(0, '响应 JSON 解析失败');
    }

    final code = (envelope['code'] as num?)?.toInt() ?? 0;
    final msg =
        (envelope['msg'] ?? envelope['errorMsg'] ?? envelope['message'] ?? '')
            .toString();
    final data = envelope['data'];

    if (code != 200) {
      throw JmApiException(code, msg);
    }
    if (data == null) {
      return JmResponse(
        code: code,
        msg: msg,
        data: null,
        raw: envelope,
        cookies: _cookiesOf(resp),
      );
    }
    // data 不是字符串 → 服务端直接返回明文
    if (data is! String) {
      return JmResponse(
        code: code,
        msg: msg,
        data: data,
        raw: envelope,
        cookies: _cookiesOf(resp),
      );
    }
    if (data.isEmpty) {
      return JmResponse(
        code: code,
        msg: msg,
        data: null,
        raw: envelope,
        cookies: _cookiesOf(resp),
      );
    }

    final plain = JmCrypto.decryptData(data, ts);
    if (plain == null) {
      // 尝试明文解析（少数接口直接返回明文 JSON 字符串）
      try {
        final decoded = jsonDecode(data);
        return JmResponse(
          code: code,
          msg: msg,
          data: decoded,
          raw: envelope,
          cookies: _cookiesOf(resp),
        );
      } on FormatException {
        throw JmHttpException(0, '响应解密失败');
      }
    }
    try {
      final decoded = jsonDecode(plain);
      return JmResponse(
        code: code,
        msg: msg,
        data: decoded,
        raw: envelope,
        cookies: _cookiesOf(resp),
      );
    } on FormatException {
      throw JmHttpException(0, '解密后 JSON 解析失败');
    }
  }

  // ---------- Transport ----------

  /// GET API 请求。
  Future<JmResponse> get(
    String path, [
    Map<String, dynamic> params = const <String, dynamic>{},
    bool withLang = true,
  ]) async {
    await _ensureReady();
    return _do('GET', path, params: params, withLang: withLang);
  }

  /// POST 表单 API 请求。
  Future<JmResponse> postForm(
    String path, [
    Map<String, dynamic> params = const <String, dynamic>{},
    bool withLang = false,
  ]) async {
    await _ensureReady();
    final body = buildQuery(params, withLang: false);
    return _do(
      'POST',
      path,
      params: const <String, dynamic>{},
      body: body,
      contentType: 'application/x-www-form-urlencoded',
      withLang: withLang,
    );
  }

  /// POST JSON 请求。
  Future<JmResponse> postJson(String path, Object payload) async {
    await _ensureReady();
    return _do(
      'POST',
      path,
      body: jsonEncode(payload),
      contentType: 'application/json',
    );
  }

  /// `/chapter_view_template` 请求（特殊签名，对齐 qt GetHeader2）。
  Future<JmResponse> getScramble(String epsId) async {
    await _ensureReady();
    final url = _apiUrl('chapter_view_template', <String, dynamic>{
      'id': epsId,
      'mode': 'vertical',
      'page': '0',
      'app_img_shunt': 'NaN',
    });
    final resp = await _send(
      'GET',
      Uri.parse(url),
      headers: _scrambleHeaders(),
    );
    if (resp == null) throw JmHttpException(0, 'scramble 请求失败');
    final body = await _readText(resp);
    // 该接口返回 HTML（var scramble_id = NNNN;），不走加密信封
    return JmResponse(code: 200, msg: '', data: body, raw: <String, dynamic>{});
  }

  /// Web 端 GET（注册/验证码等，Web 域名）。
  Future<({int status, String body, Map<String, String> cookies})> webGet(
    String path, {
    Map<String, String>? headers,
  }) async {
    await _ensureReady();
    final url = path.startsWith('http')
        ? Uri.parse(path)
        : Uri.parse('${JmDomain.webUrl.value}$path');
    final req = await _client.openUrl('GET', url);
    _webHeaders().forEach((k, v) => req.headers.set(k, v));
    headers?.forEach((k, v) => req.headers.set(k, v));
    final resp = await req.close().timeout(const Duration(seconds: 20));
    return (
      status: resp.statusCode,
      body: await _readText(resp),
      cookies: _cookiesOf(resp),
    );
  }

  /// Web 端 POST 表单（注册/找回等，Web 域名，对齐 qt RegisterReq 等）。
  Future<({int status, String body, Map<String, String> cookies})> webPost(
    String path,
    Map<String, dynamic> form, {
    String? referer,
  }) async {
    await _ensureReady();
    final url = path.startsWith('http')
        ? Uri.parse(path)
        : Uri.parse('${JmDomain.webUrl.value}$path');
    final req = await _client.openUrl('POST', url);
    _webHeaders(
      contentType: 'application/x-www-form-urlencoded',
      referer: referer ?? url.toString(),
    ).forEach((k, v) => req.headers.set(k, v));
    req.add(utf8.encode(buildQuery(form, withLang: false)));
    final resp = await req.close().timeout(const Duration(seconds: 20));
    return (
      status: resp.statusCode,
      body: await _readText(resp),
      cookies: _cookiesOf(resp),
    );
  }

  /// 图片下载（图片域名轮询 + 失败自动切换，对齐 qt DownloadBookReq）。
  ///
  /// [path] 形如 `/media/photos/{epsId}/{name}` 或完整 URL。
  /// `_3x4` 封面失败时自动回退无后缀版本（对齐 qt resetUrl 逻辑）。
  Future<List<int>> fetchImage(String rawUrl) async {
    await _ensureReady();
    final is3x4 = rawUrl.contains('_3x4');
    final attemptMax = JmDomain.picUrlList.value.length;
    Object? lastCause;

    for (var attempt = 0; attempt < attemptMax; attempt++) {
      var urlStr = rawUrl;
      if (!urlStr.startsWith('http')) {
        final base = imgHost;
        urlStr = base.endsWith('/')
            ? '$base${urlStr.substring(1)}'
            : '$base$urlStr';
      }
      try {
        if (enableDoh) await dohResolve(Uri.parse(urlStr).host);
        final req = await _client
            .openUrl('GET', Uri.parse(urlStr))
            .timeout(const Duration(seconds: 30));
        final h = _imgHeaders();
        h.remove('Content-Type');
        h.forEach((k, v) => req.headers.set(k, v));
        final resp = await req.close().timeout(const Duration(seconds: 30));
        if (resp.statusCode == 200) {
          final builder = BytesBuilder(copy: false);
          await for (final chunk in resp) {
            builder.add(chunk);
          }
          final bytes = builder.takeBytes();
          // 空白图检测（对齐 qt SPACE_PIC：出现空白图片则回源）
          if (bytes.isNotEmpty &&
              bytes.length < 3000 &&
              !urlStr.contains('?')) {
            continue;
          }
          return bytes;
        }
        await resp.drain<void>().catchError((_) {});
        lastCause = 'HTTP ${resp.statusCode}';
      } catch (e) {
        lastCause = e;
      }
      // _3x4 封面失败 → 尝试无后缀原图
      if (is3x4) {
        final noSuffix = rawUrl.replaceAll('_3x4', '');
        try {
          final base = imgHost;
          final u2 = noSuffix.startsWith('http')
              ? noSuffix
              : (base.endsWith('/')
                    ? '$base${noSuffix.substring(1)}'
                    : '$base$noSuffix');
          final req = await _client
              .openUrl('GET', Uri.parse(u2))
              .timeout(const Duration(seconds: 30));
          final h = _imgHeaders();
          h.remove('Content-Type');
          h.forEach((k, v) => req.headers.set(k, v));
          final resp = await req.close().timeout(const Duration(seconds: 30));
          if (resp.statusCode == 200) {
            final builder = BytesBuilder(copy: false);
            await for (final chunk in resp) {
              builder.add(chunk);
            }
            return builder.takeBytes();
          }
          await resp.drain<void>().catchError((_) {});
        } catch (_) {}
      }
      // 轮询下一个图片域名
      final list = JmDomain.picUrlList.value;
      if (list.isEmpty) break;
      _imgRotate = (_imgRotate + 1) % list.length;
      imgIndex = _imgRotate + 1;
    }
    throw JmHttpException(0, '图片下载失败: $rawUrl', lastCause);
  }

  /// 测速（对齐 qt SpeedTestPingReq：HEAD 请求计时）。
  Future<int> pingHost(
    String host, {
    Duration timeout = const Duration(seconds: 5),
  }) async {
    final sw = Stopwatch()..start();
    try {
      final uri = Uri.parse(host.startsWith('http') ? host : 'https://$host');
      final req = await _client.openUrl('HEAD', uri).timeout(timeout);
      final resp = await req.close().timeout(timeout);
      await resp.drain<void>().catchError((_) {});
      sw.stop();
      return sw.elapsedMilliseconds;
    } catch (_) {
      return -1;
    }
  }

  /// 首次使用前确保已初始化。
  Future<void> _ensureReady() async {
    if (!_initialized) {
      await init(language: lang, doh: enableDoh);
    }
  }

  void dispose() {
    _http?.close();
    _http = null;
  }
}
