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

  /// 诊断信息：错误响应体片段 / 线路尝试记录。
  final String body;
  final Object? cause;

  @override
  String toString() {
    if (status != 0) return 'HTTP $status${body.isEmpty ? '' : ': $body'}';
    return '网络错误: ${body.isEmpty ? cause : body}';
  }
}

/// 一次请求尝试（URL + 诊断标签 + 是否强制 DoH 直连）。
class _Attempt {
  const _Attempt(this.url, this.tag, {this.forceDoh = false, this.apiPos = -1});

  final String url;
  final String tag;
  final bool forceDoh;

  /// 对应 apiUrlList 的位置（成功时用于记住首选线路；反代/DoH 尝试为 -1）。
  final int apiPos;
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
  ///
  /// ⚠ dart:io 约定：connectionFactory 返回的 socket 会被 HttpClient 直接
  /// 使用，**TLS 必须由工厂自己完成**（HttpClient 不会再握手）。若对
  /// https URL 返回普通 TCP socket，请求将以明文 HTTP 打到 443 端口，
  /// Cloudflare 会返回 400 "The plain HTTP request was sent to HTTPS port"
  /// ——这正是之前线上 400 错误的根因。
  Future<ConnectionTask<Socket>> _connectionFactory(
    Uri url,
    String? proxyHost,
    int? proxyPort,
  ) async {
    final ip = _dnsCache[url.host]; // DoH 解析结果（按目标 host 查）
    final host = proxyHost ?? url.host;
    final port = proxyPort ?? url.port;
    if (url.scheme == 'https') {
      return SecureSocket.startConnect(
        ip ?? host,
        port,
        // 仅 DoH IP 直连时无法按域名校验证书，需信任
        onBadCertificate: ip == null ? null : (_) => true,
        supportedProtocols: const <String>['http/1.1'],
      );
    }
    return Socket.startConnect(ip ?? host, port);
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

  /// 登录态失效回调（服务端 401 时触发，供 UI 层同步清除用户状态）。
  void Function()? onAuthExpired;

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
  /// [auth] 为 false 时不携带登录态（对齐 qt LoginReq2 pop authorization：
  /// 登录接口带过期 token 会被服务端拒绝）。
  Map<String, String> _apiHeaders(
    JmCryptoToken t, {
    String? contentType,
    bool auth = true,
  }) {
    return <String, String>{
      'tokenparam': t.tokenparam,
      'token': t.token,
      'accept-encoding': 'gzip',
      'version': JmCrypto.clientVersion,
      if (auth && _jwt.isNotEmpty) 'authorization': 'Bearer $_jwt',
      if (auth && _avs.isNotEmpty) 'cookie': 'AVS=$_avs',
      // null-aware 元素：contentType 为 null 时不产生该键
      'Content-Type': ?contentType,
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

  /// 编码 query（保留空值参数，自动补 lang，严格对齐 qt DictToUrl：
  /// qt 用 urlencode 生成 comicName=&skip= 等空参数，
  /// 服务端某些接口要求这些键存在——与 qt 逐字对齐以消除差异）。
  String buildQuery(Map<String, dynamic> params, {bool withLang = true}) {
    final parts = <String>[];
    params.forEach((k, v) {
      if (v == null) return;
      parts.add(
        '${Uri.encodeComponent(k)}=${Uri.encodeComponent(v.toString())}',
      );
    });
    if (withLang && lang.isNotEmpty && !params.containsKey('lang')) {
      parts.add('lang=${Uri.encodeComponent(lang)}');
    }
    return parts.join('&');
  }

  /// 指定主机的 URL 构造（与 qt 逐字对齐：`{host}/{path}/?{query}`）。
  String _apiUrlWithHost(
    String host,
    String path,
    Map<String, dynamic> params, {
    bool withLang = true,
  }) {
    var base = host;
    if (!base.endsWith('/')) base = '$base/';
    var p = path.startsWith('/') ? path.substring(1) : path;
    final query = buildQuery(params, withLang: withLang);
    var url = '$base$p';
    if (query.isNotEmpty) url += '/?$query';
    return url;
  }

  /// 官方反代线路 URL（对齐 qt 线路6 __DealHeaders：
  /// `https://jm2-api.jpacg.cc/<原域名>/<path>/?<query>`，
  /// 反代为独立 nginx，不经 Cloudflare 边缘，可绕过边缘侧拦截）。
  String _proxyApiUrl(
    String proxyHost,
    String apiHost,
    String path,
    Map<String, dynamic> params, {
    bool withLang = true,
  }) {
    var p = path.startsWith('/') ? path.substring(1) : path;
    final query = buildQuery(params, withLang: withLang);
    var url =
        'https://${JmDomain.urlHost(proxyHost)}/${JmDomain.urlHost(apiHost)}/$p/';
    if (query.isNotEmpty) url += '?$query';
    return url;
  }

  /// 构造本次请求的多级尝试序列（彻底修复 400/403/网络异常的核心）：
  ///
  /// 1. 全部普通 API 线路（Url2List，从用户所选线路轮转起）
  ///    + 远程 jm3_Server 补充线路（如 www.cdnutc.me）；
  /// 2. 官方反代线路（qt 线路6同款，绕过 Cloudflare 边缘）；
  /// 3. DoH 解析 IP 直连（绕过 DNS 污染/劫持，仅在前两步全部失败且未开 DoH 时）。
  ///
  /// 每次尝试都重新生成签名；任意一次成功即返回。
  List<_Attempt> _buildAttempts(
    String path,
    Map<String, dynamic> params, {
    bool withLang = true,
  }) {
    final out = <_Attempt>[];
    final hosts = <String>[];
    void addHost(String h) {
      final t = h.trim();
      if (t.isEmpty) return;
      final full = t.startsWith('http') ? t : 'https://$t';
      if (!hosts.contains(full)) hosts.add(full);
    }

    // 普通线路：从当前线路索引起轮转（对齐 qt ResetToSwitchNextUrl）
    final base = JmDomain.apiUrlList.value;
    if (base.isNotEmpty) {
      final start = (apiIndex - 1).clamp(0, base.length - 1);
      for (var i = 0; i < base.length; i++) {
        final pos = (start + i) % base.length;
        final h = base[pos];
        final before = hosts.length;
        addHost(h);
        if (hosts.length == before) continue; // 去重：已存在
        out.add(
          _Attempt(
            _apiUrlWithHost(h, path, params, withLang: withLang),
            JmDomain.urlHost(h),
            apiPos: pos,
          ),
        );
      }
    }
    // 远程 jm3_Server 补充线路（可能包含 Url2List 之外的新线路）
    for (final line in _hostConfig?.jm3Server ?? const <List<String>>[]) {
      if (line.isEmpty) continue;
      final h = line.first.trim();
      if (h.isEmpty) continue;
      final full = h.startsWith('http') ? h : 'https://$h';
      if (hosts.contains(full)) continue;
      addHost(h);
      out.add(
        _Attempt(
          _apiUrlWithHost(full, path, params, withLang: withLang),
          JmDomain.urlHost(full),
        ),
      );
    }
    // 官方反代线路（独立 nginx，不经 Cloudflare）
    final proxyHost = JmDomain.proxyApiDomain2.value.trim();
    if (proxyHost.isNotEmpty && hosts.isNotEmpty) {
      out.add(
        _Attempt(
          _proxyApiUrl(
            proxyHost,
            hosts.first,
            path,
            params,
            withLang: withLang,
          ),
          '${JmDomain.urlHost(proxyHost)}(反代)',
        ),
      );
    }
    // DoH 直连（绕过 DNS 污染；用户已开启 DoH 时无需重复）
    if (!enableDoh) {
      for (final h in hosts.take(2)) {
        out.add(
          _Attempt(
            _apiUrlWithHost(h, path, params, withLang: withLang),
            '${JmDomain.urlHost(h)}(DoH)',
            forceDoh: true,
          ),
        );
      }
    }
    return out;
  }

  // ---------- 核心请求 ----------

  /// 统一 API 请求入口。
  ///
  /// 按 [_buildAttempts] 的多级线路序列依次尝试（普通线路 → 反代 → DoH），
  /// 任意非 200（含 400/401/403/5xx）与网络错误都继续下一级（对齐 qt
  /// ResetToSwitchNextUrl 并扩展）；全部失败后抛出汇总诊断信息的异常。
  Future<JmResponse> _do(
    String method,
    String path, {
    Map<String, dynamic> params = const <String, dynamic>{},
    String? body,
    String? contentType,
    bool withLang = true,
    bool auth = true,
    Map<String, String>? extraHeaders,
  }) async {
    await _ensureReady();
    final attempts = _buildAttempts(path, params, withLang: withLang);
    final tried = <String>[];
    Object? lastCause;
    var dohWorked = false;

    for (final a in attempts) {
      // 每次尝试生成一次签名；请求头与响应解密使用同一个 ts（对齐 qt：
      // self.now 同时用于 GetHeader 与 ParseData，不可两次生成）。
      final t = JmCrypto.randomToken();
      try {
        final resp = await _send(
          method,
          Uri.parse(a.url),
          headers: {
            ..._apiHeaders(t, contentType: contentType, auth: auth),
            ...?extraHeaders,
          },
          body: body,
          forceDoh: a.forceDoh,
        );
        final r = await _decryptResponse(resp, ts: t.ts);
        if (a.apiPos >= 0) apiIndex = a.apiPos + 1;
        if (a.forceDoh) dohWorked = true;
        return r;
      } on JmApiException {
        // 业务错误（HTTP 200 但 code != 200），换域名无意义，直接抛给上层
        rethrow;
      } on JmHttpException catch (e) {
        tried.add(
          '${a.tag}=>${e.status}${e.body.isEmpty ? '' : '(${_short(e.body, 60)})'}',
        );
        lastCause = e;
        if (e.status == 401 && auth && _jwt.isNotEmpty) {
          // 登录态失效（token 过期）：清除旧 token，避免继续毒化后续请求
          _jwt = '';
          _avs = '';
          try {
            onAuthExpired?.call();
          } catch (_) {}
        }
      } catch (e) {
        tried.add('${a.tag}=>net');
        lastCause = e;
      }
    }
    if (dohWorked) enableDoh = true; // DoH 直连成功则本会话保持
    var hint = '';
    final off = JmClock.offsetSeconds;
    if (off.abs() > 120) hint = '（设备时间与服务器相差约${off.abs()}秒，已自动校准）';
    throw JmHttpException(0, '全部线路失败$hint [${tried.join(', ')}]', lastCause);
  }

  /// 底层 HTTP 发送（支持 DoH 预解析）。
  ///
  /// 任意非 2xx 状态码（含 400/401/403/5xx）都抛 JmHttpException（附带
  /// server/cf-ray/响应体片段诊断信息），由 [_do] 统一切线路重试。
  /// 所有响应（含错误响应）都会用 Date 头同步服务器时间（[JmClock]）。
  Future<HttpClientResponse> _send(
    String method,
    Uri url, {
    Map<String, String> headers = const <String, String>{},
    String? body,
    Duration timeout = const Duration(seconds: 20),
    bool forceDoh = false,
  }) async {
    if (enableDoh || forceDoh) await dohResolve(url.host);
    final req = await _client.openUrl(method, url).timeout(timeout);
    headers.forEach((k, v) => req.headers.set(k, v));
    if (body != null && body.isNotEmpty) {
      req.add(utf8.encode(body));
    }
    final resp = await req.close().timeout(timeout);
    // 服务器时间同步（错误响应同样携带 Date 头）
    try {
      JmClock.syncFromHeader(resp.headers.date);
    } catch (_) {}
    if (resp.statusCode < 200 || resp.statusCode > 299) {
      final snippet = await _errorSnippet(resp);
      throw JmHttpException(resp.statusCode, snippet);
    }
    return resp;
  }

  /// 读取错误响应的诊断片段（截断至 ~400 字符，附带 server / cf-ray 头）。
  Future<String> _errorSnippet(HttpClientResponse resp) async {
    final sb = StringBuffer();
    final srv = resp.headers.value('server');
    final ray = resp.headers.value('cf-ray');
    final mit = resp.headers.value('cf-mitigated');
    final diag = <String>[
      if (srv != null && srv.isNotEmpty) 'server=$srv',
      if (mit != null && mit.isNotEmpty) 'cf-mitigated=$mit',
      if (ray != null && ray.isNotEmpty) 'ray=${_short(ray, 12)}',
    ];
    if (diag.isNotEmpty) sb.write('[${diag.join(' ')}] ');
    try {
      final bytes = <int>[];
      await for (final chunk in resp) {
        bytes.addAll(chunk);
        if (bytes.length >= 400) break;
      }
      final text = utf8.decode(bytes.take(400).toList(), allowMalformed: true);
      sb.write(text);
    } catch (_) {}
    final s = sb.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
    return s.length <= 600 ? s : s.substring(0, 600);
  }

  /// 截断字符串便于诊断展示。
  static String _short(String s, int max) {
    final t = s.replaceAll(RegExp(r'\s+'), ' ').trim();
    return t.length <= max ? t : '${t.substring(0, max)}…';
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
      // 典型场景：源站异常时返回纯文本（如 mysql 连接失败），
      // 携带片段便于诊断，并由 _do 轮换下一线路重试。
      throw JmHttpException(0, '响应非 JSON: ${_short(body, 80)}');
    }

    // code 可能是数字或字符串（不同线路返回不一致），统一安全解析；
    // 直接 as num? 在字符串形态下会抛 TypeError，被上层误报为网络错误。
    final rawCode = envelope['code'];
    final int code = rawCode is num
        ? rawCode.toInt()
        : int.tryParse('$rawCode') ?? 0;
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
    bool auth = true,
  ]) async {
    await _ensureReady();
    return _do('GET', path, params: params, withLang: withLang, auth: auth);
  }

  /// POST 表单 API 请求。
  ///
  /// [auth] 为 false 时不携带登录态（登录接口本身，对齐 qt LoginReq2）。
  Future<JmResponse> postForm(
    String path, [
    Map<String, dynamic> params = const <String, dynamic>{},
    bool withLang = false,
    bool auth = true,
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
      auth: auth,
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
  ///
  /// 同样走多级线路尝试（普通线路 → 反代），避免单点失败。
  Future<JmResponse> getScramble(String epsId) async {
    await _ensureReady();
    final attempts = _buildAttempts('chapter_view_template', <String, dynamic>{
      'id': epsId,
      'mode': 'vertical',
      'page': '0',
      'app_img_shunt': 'NaN',
    }, withLang: false);
    Object? lastCause;
    for (final a in attempts.take(3)) {
      try {
        final resp = await _send(
          'GET',
          Uri.parse(a.url),
          headers: _scrambleHeaders(),
          forceDoh: a.forceDoh,
        );
        final body = await _readText(resp);
        // 该接口返回 HTML（var scramble_id = NNNN;），不走加密信封
        if (body.contains('scramble_id')) {
          return JmResponse(
            code: 200,
            msg: '',
            data: body,
            raw: const <String, dynamic>{},
          );
        }
        lastCause = JmHttpException(0, '排版响应异常: ${_short(body, 60)}');
      } catch (e) {
        lastCause = e;
      }
    }
    throw JmHttpException(0, '排版签名获取失败: $epsId', lastCause);
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
  /// [rawUrl] 形如 `/media/photos/{epsId}/{name}`、
  /// `https://cdn-msp.xxx/media/photos/...`（comic_read 下发的完整 URL）。
  ///
  /// 每次尝试都用当前 [imgHost] 替换 URL 的 host（对齐 qt useImgProxy：
  /// 服务端下发的域名未必可用，以用户所选线路为准），失败后轮询下一域名；
  /// `_3x4` 封面失败时自动回退无后缀版本（对齐 qt resetUrl 逻辑）。
  Future<List<int>> fetchImage(String rawUrl) async {
    await _ensureReady();
    final is3x4 = rawUrl.contains('_3x4');
    // 提取 URL 中的路径部分（host 之后），用于按线路重建 URL
    final pathPart = _extractImagePath(rawUrl);
    final attemptMax = JmDomain.picUrlList.value.length;
    Object? lastCause;

    Future<List<int>> tryOnce(String urlStr) async {
      if (enableDoh) await dohResolve(Uri.parse(urlStr).host);
      final req = await _client
          .openUrl('GET', Uri.parse(urlStr))
          .timeout(const Duration(seconds: 30));
      _imgHeaders().forEach((k, v) => req.headers.set(k, v));
      final resp = await req.close().timeout(const Duration(seconds: 30));
      if (resp.statusCode != 200) {
        await resp.drain<void>().catchError((_) {});
        throw JmHttpException(resp.statusCode, '图片 HTTP ${resp.statusCode}');
      }
      final builder = BytesBuilder(copy: false);
      await for (final chunk in resp) {
        builder.add(chunk);
      }
      final bytes = builder.takeBytes();
      // 空白图检测（对齐 qt SPACE_PIC：出现空白图片则视为失败回源）
      if (bytes.isEmpty || (bytes.length < 3000 && !urlStr.contains('?'))) {
        throw JmHttpException(0, '空白图');
      }
      return bytes;
    }

    for (var attempt = 0; attempt < attemptMax; attempt++) {
      final urlStr = _withImgHost(pathPart);
      try {
        return await tryOnce(urlStr);
      } on JmHttpException catch (e) {
        lastCause = e;
      } catch (e) {
        lastCause = e;
      }
      // _3x4 封面失败 → 尝试无后缀原图
      if (is3x4) {
        try {
          return await tryOnce(_withImgHost(pathPart.replaceAll('_3x4', '')));
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

  /// 提取图片 URL 的路径部分（host 之后，以 / 开头，保留 query）。
  String _extractImagePath(String raw) {
    if (raw.startsWith('http')) {
      final u = Uri.tryParse(raw);
      if (u != null && u.path.isNotEmpty) {
        var p = u.path;
        if (u.query.isNotEmpty) p += '?${u.query}';
        return p.startsWith('/') ? p : '/$p';
      }
      return raw;
    }
    return raw.startsWith('/') ? raw : '/$raw';
  }

  /// 用当前图片线路 host 拼接完整图片 URL。
  String _withImgHost(String path) {
    var base = imgHost;
    if (base.endsWith('/')) base = base.substring(0, base.length - 1);
    return '$base$path';
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
