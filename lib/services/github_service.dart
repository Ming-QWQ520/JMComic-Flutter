import 'dart:convert';

import 'package:http/http.dart' as http;

/// GitHub 公开仓库信息（Star 数展示）。
class GithubService {
  GithubService._();

  /// 拉取仓库 Star 数；网络不可达 / 限流时返回 null（静默降级）。
  ///
  /// 使用 REST API：`GET /repos/{owner}/{repo}`，匿名 60 次/小时/IP
  /// 足够"每次冷启动请求一次"的频率；10 秒超时防止拖慢启动。
  static Future<int?> fetchStars(String owner, String repo) async {
    try {
      final resp = await http
          .get(
            Uri.https('api.github.com', '/repos/$owner/$repo'),
            headers: const <String, String>{
              'Accept': 'application/vnd.github+json',
              'User-Agent': 'JMComic-Flutter',
            },
          )
          .timeout(const Duration(seconds: 10));
      if (resp.statusCode != 200) return null;
      final data = jsonDecode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>;
      final stars = data['stargazers_count'];
      return stars is int ? stars : int.tryParse('$stars');
    } catch (_) {
      return null;
    }
  }
}
