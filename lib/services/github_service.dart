import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

/// 仓库元信息（Star 数 + 简介，简介来自 GitHub API 的 description，
/// 不再在应用内硬编码）。
class RepoMeta {
  const RepoMeta({this.stars, this.description});

  final int? stars;
  final String? description;
}

/// 最新 Release 信息。
///
/// 本仓库 rolling release 的 tag 固定为 `latest`，版本号在 APK 资产名中
/// （如 `JMComic-Flutter-v0.1.0-arm64-v8a.apk`），因此从资产名解析版本。
class ReleaseInfo {
  const ReleaseInfo({
    required this.version,
    required this.title,
    required this.body,
    required this.apkUrl,
    required this.htmlUrl,
  });

  /// 从资产名解析出的版本号（如 0.1.0）。
  final String version;

  /// Release 名称（如 "JMComic-Flutter 最新构建"）。
  final String title;

  /// Release 说明（更新内容，Markdown 文本）。
  final String body;

  /// 更新 APK 下载地址（优先 arm64-v8a，其次 universal）。
  final String apkUrl;

  /// Release 页面地址。
  final String htmlUrl;
}

/// GitHub 公开仓库信息、版本检测与更新包下载。
///
/// API 直连优先、gh-proxy.com 前缀加速回退；APK 下载默认走 gh-proxy
/// 前缀（`https://gh-proxy.com/<原始URL>`，见其文档
/// github-accelerator，支持 Release 资产与 REST API）。
class GithubService {
  GithubService._();

  static const String owner = 'Ming-QWQ520';
  static const String repo = 'JMComic-Flutter';
  static const String _proxy = 'https://gh-proxy.com/';

  static Uri _directApi(String path) => Uri.https('api.github.com', path);

  static Uri _proxiedApi(String path) =>
      Uri.parse('$_proxy' 'https://api.github.com/$path');

  /// API GET：直连优先失败后走 gh-proxy 加速；两者都失败返回 null。
  static Future<Map<String, dynamic>?> _apiJson(String path) async {
    const headers = <String, String>{
      'Accept': 'application/vnd.github+json',
      'User-Agent': 'JMComic-Flutter',
    };
    for (final uri in <Uri>[_directApi(path), _proxiedApi(path)]) {
      try {
        final resp = await http
            .get(uri, headers: headers)
            .timeout(const Duration(seconds: 12));
        if (resp.statusCode == 200) {
          return jsonDecode(utf8.decode(resp.bodyBytes))
              as Map<String, dynamic>;
        }
      } catch (_) {
        // 换下一条通道重试
      }
    }
    return null;
  }

  /// 拉取仓库元信息（Star 数 + 简介）；失败返回 null（静默降级）。
  ///
  /// 使用 REST API：`GET /repos/{owner}/{repo}`，匿名 60 次/小时/IP
  /// 足够"每次冷启动请求一次"的频率。
  static Future<RepoMeta?> fetchRepoMeta() async {
    final data = await _apiJson('/repos/$owner/$repo');
    if (data == null) return null;
    return RepoMeta(
      stars: data['stargazers_count'] is int
          ? data['stargazers_count'] as int
          : int.tryParse('${data['stargazers_count']}'),
      description: (data['description'] ?? '') as String,
    );
  }

  /// 获取最新 Release（用于检测更新）；失败返回 null。
  static Future<ReleaseInfo?> fetchLatestRelease() async {
    final data = await _apiJson('/repos/$owner/$repo/releases/latest');
    if (data == null) return null;
    final assets = (data['assets'] as List? ?? <dynamic>[])
        .whereType<Map<String, dynamic>>()
        .toList();
    // 优先 arm64-v8a（绝大多数现代手机），其次 universal。
    Map<String, dynamic> apk = <String, dynamic>{};
    for (final a in assets) {
      if ((a['name'] as String? ?? '').contains('arm64-v8a')) {
        apk = a;
        break;
      }
    }
    if (apk.isEmpty) {
      for (final a in assets) {
        if ((a['name'] as String? ?? '').contains('universal')) {
          apk = a;
          break;
        }
      }
    }
    if (apk.isEmpty) return null;
    final apkName = apk['name'] as String? ?? '';
    final m = RegExp(r'v(\d[\w.\-]*)').firstMatch(apkName);
    final version = m?.group(1) ?? '';
    if (version.isEmpty) return null;
    return ReleaseInfo(
      version: version,
      title: (data['name'] ?? 'Release') as String,
      body: (data['body'] ?? '') as String,
      apkUrl: apk['browser_download_url'] as String,
      htmlUrl:
          (data['html_url'] ?? 'https://github.com/$owner/$repo/releases')
              as String,
    );
  }

  /// 版本号比较：a 大于 b 返回 true（按点分段数值比较，非数字段按 0）。
  static bool isNewerVersion(String a, String b) {
    List<int> parse(String v) => v
        .split(RegExp(r'[.+\-]'))
        .map((e) => int.tryParse(e) ?? 0)
        .toList();
    final pa = parse(a);
    final pb = parse(b);
    for (var i = 0; i < pa.length && i < pb.length; i++) {
      if (pa[i] != pb[i]) return pa[i] > pb[i];
    }
    return pa.length > pb.length;
  }

  /// 下载更新 APK（gh-proxy 前缀加速，失败回退直连），实时回调进度
  /// 0.0~1.0。成功返回本地文件，失败（网络中断/内容不完整）返回 null。
  static Future<File?> downloadUpdate({
    required String url,
    required String savePath,
    void Function(double progress)? onProgress,
  }) async {
    final client = http.Client();
    try {
      final candidates = <Uri>[
        if (url.startsWith('https://github.com/'))
          Uri.parse('$_proxy$url')
        else
          Uri.parse(url),
        Uri.parse(url),
      ];
      http.StreamedResponse? resp;
      for (final uri in candidates) {
        try {
          final req = http.Request('GET', uri);
          final r =
              await client.send(req).timeout(const Duration(seconds: 30));
          if (r.statusCode == 200) {
            resp = r;
            break;
          }
        } catch (_) {
          // 换下一条通道
        }
      }
      if (resp == null) return null;
      final total = resp.contentLength ?? 0;
      final file = File(savePath);
      final sink = file.openWrite();
      var received = 0;
      try {
        await for (final chunk in resp.stream) {
          received += chunk.length;
          sink.add(chunk);
          if (total > 0) onProgress?.call(received / total);
        }
        await sink.flush();
      } finally {
        await sink.close();
      }
      if (total > 0 && received < total) {
        // 下载不完整：删除残留，视为失败。
        try {
          file.deleteSync();
        } catch (_) {}
        return null;
      }
      return file;
    } catch (_) {
      try {
        final f = File(savePath);
        if (f.existsSync()) f.deleteSync();
      } catch (_) {}
      return null;
    } finally {
      client.close();
    }
  }
}
