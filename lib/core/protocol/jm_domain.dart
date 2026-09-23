/// JMComic-qt 域名体系（还原自 tonquer/JMComic-qt GlobalConfig）。
///
/// 包含：Web/API/图片域名列表、CDN 与代理线路、DoH 解析地址、
/// 远程配置(newsvr-*.txt)更新机制与 k=v 配置解析。
library;

/// 单个全局配置项（对齐 qt 的 GlobalItem）。
class JmDomainItem<T> {
  JmDomainItem(this.defValue) : value = defValue;

  T defValue;
  T value;

  bool get isSame => value == defValue;

  void setValue(dynamic v) {
    if (v == null) return;
    if (defValue is List && v is String) {
      final list = v
          .split(',')
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList();
      value = list as T;
      return;
    }
    if (v is T) {
      value = v;
      return;
    }
    if (defValue is int) {
      final p = int.tryParse(v.toString());
      if (p != null) value = p as T;
    } else if (defValue is String) {
      value = v.toString() as T;
    }
  }
}

/// JMComic-qt 全局域名配置。
class JmDomain {
  JmDomain._();

  // ---------- 版本 ----------
  /// 配置版本号（远程配置版本高于本地时才更新）。
  static final JmDomainItem<int> ver = JmDomainItem<int>(91);

  /// 远程配置版本时间。
  static final JmDomainItem<String> verTime =
      JmDomainItem<String>('2026-9-21');

  // ---------- Web 域名（注册/找回等网页操作） ----------
  static final JmDomainItem<String> webUrl =
      JmDomainItem<String>('https://comic18j-jjeg.cc');

  static final JmDomainItem<List<String>> urlList = JmDomainItem<List<String>>(<
      String>[
    'https://comic18j-jjeg.cc',
    'https://18comic.vip',
    'https://jmcomic.me',
    'https://18comic.tw',
    'https://jmcomic-zzz.org',
    'https://comic18j-hbd.online',
    'https://comic18j-jjeg.club',
  ]);

  /// 移动 APP API 域名列表（对齐 qt Url2List）。
  static final JmDomainItem<List<String>> apiUrlList =
      JmDomainItem<List<String>>(<String>[
    'https://www.cdnhjk.net',
    'https://www.cdngwc.cc',
    'https://www.cdngwc.net',
    'https://www.cdngwc.club',
  ]);

  /// 反代 API 域名（走代理时替换 host 用）。
  static final JmDomainItem<String> proxyApiDomain2 =
      JmDomainItem<String>('jm2-api.jpacg.cc');

  /// 反代图片域名。
  static final JmDomainItem<String> proxyImgDomain2 =
      JmDomainItem<String>('jm2-img.jpacg.cc');

  /// 图片域名列表（对齐 qt PicUrlList）。
  static final JmDomainItem<List<String>> picUrlList =
      JmDomainItem<List<String>>(<String>[
    'https://cdn-msp.jmapiproxy1.cc',
    'https://cdn-msp.jmapiproxy3.cc',
    'https://cdn-msp.jmapinodeudzn.net',
    'https://cdn-msp.jmdanjonproxy.xyz',
  ]);

  /// 自动加速图片域名（对齐 qt ImgAutoUrl）。
  static final JmDomainItem<List<String>> imgAutoUrl =
      JmDomainItem<List<String>>(<String>[
    'cdn-msp2.jmapiproxy1.cc',
    'cdn-msp2.jmapiproxy3.cc',
    'cdn-msp2.jmapinodeudzn.net',
    'cdn-msp3.jmapinodeudzn.net',
    'cdn-msp3.jmapiproxy1.cc',
    'cdn-msp3.jmapiproxy3.cc',
  ]);

  /// CDN API 域名（线路 5）。
  static final JmDomainItem<String> cdnApiUrl =
      JmDomainItem<String>('https://www.cdngwc.cc');

  /// CDN 图片域名（线路 5）。
  static final JmDomainItem<String> cdnImgUrl =
      JmDomainItem<String>('https://cdn-msp.jmapiproxy3.cc');

  /// 代理 API 域名（线路 6）。
  static final JmDomainItem<String> proxyApiUrl =
      JmDomainItem<String>('https://www.cdnhjk.net');

  /// 代理图片域名（线路 6）。
  static final JmDomainItem<String> proxyImgUrl =
      JmDomainItem<String>('https://cdn-msp.jmapiproxy3.cc');

  /// APP 协议版本号（对齐 qt HeaderVer）。
  static final JmDomainItem<String> headerVer =
      JmDomainItem<String>('2.1.7');

  /// 远程配置地址（newsvr-2025.txt，可更新全部域名）。
  static final JmDomainItem<String> jmServerUrl = JmDomainItem<String>(
      'https://rup4a04-c02.tos-cn-hongkong.bytepluses.com/newsvr-2025.txt');

  /// DoH 解析地址列表（对齐 qt DohUrlList）。
  static final JmDomainItem<List<String>> dohUrlList =
      JmDomainItem<List<String>>(<String>[
    'https://parse.jpacg.cc/parse',
    'https://doh.pub/dns-query',
    'https://parse2.jpacg.cc/parse',
    'https://dot.pub/dns-query',
  ]);

  // ---------- 线路索引语义（对齐 qt GetApiUrl2/GetImgUrl2） ----------

  /// 是否 CDN 线路（索引 5）。
  static bool isCdnIndex(int index) => index == 5;

  /// 是否代理线路（索引 6）。
  static bool isProxyUrlIndex(int index) => index == 6;

  /// 按索引取 API 域名（1..4 普通线路，5 CDN，6 代理，>=7 取第一普通线路）。
  static String getApiUrl(int index) {
    final list = apiUrlList.value;
    if (isCdnIndex(index)) return cdnApiUrl.value;
    if (isProxyUrlIndex(index)) return proxyApiUrl.value;
    if (index >= 7) return list.isNotEmpty ? list.first : cdnApiUrl.value;
    if (index >= 1 && index <= list.length) return list[index - 1];
    return list.isNotEmpty ? list.first : cdnApiUrl.value;
  }

  /// 按索引取图片域名。
  static String getImgUrl(int index) {
    final list = picUrlList.value;
    if (isCdnIndex(index)) return cdnImgUrl.value;
    if (isProxyUrlIndex(index)) return proxyImgUrl.value;
    if (index >= 7) return list.isNotEmpty ? list.first : cdnImgUrl.value;
    if (index >= 1 && index <= list.length) return list[index - 1];
    return list.isNotEmpty ? list.first : cdnImgUrl.value;
  }

  // ---------- 远程配置更新 ----------

  /// 解析远程配置 k=v 文本（对齐 qt UpdateSetting）。
  ///
  /// 仅当远程版本号大于本地时应用；返回是否应用了更新。
  static bool updateSettingFromText(String text) {
    final allKvs = <String, String>{};
    for (var line in text.replaceAll('\r', '').split('\n')) {
      line = line.trim();
      if (line.isEmpty) continue;
      final idx = line.indexOf('=');
      if (idx <= 0) continue;
      allKvs[line.substring(0, idx)] = line.substring(idx + 1);
    }
    final remoteVer = int.tryParse(allKvs['Ver'] ?? '0') ?? 0;
    if (remoteVer <= ver.value) return false;
    allKvs.forEach((k, v) {
      final item = _items[k];
      if (item != null) item.setValue(v);
    });
    ver.setValue(remoteVer);
    return true;
  }

  /// 全部配置项注册表（用于远程更新）。
  static final Map<String, JmDomainItem<dynamic>> _items = <String,
      JmDomainItem<dynamic>>{
    'Ver': ver,
    'VerTime': verTime,
    'Url': webUrl,
    'UrlList': urlList,
    'Url2List': apiUrlList,
    'ProxyApiDomain2': proxyApiDomain2,
    'ProxyImgDomain2': proxyImgDomain2,
    'PicUrlList': picUrlList,
    'ImgAutoUrl': imgAutoUrl,
    'CdnApiUrl': cdnApiUrl,
    'CdnImgUrl': cdnImgUrl,
    'ProxyApiUrl': proxyApiUrl,
    'ProxyImgUrl': proxyImgUrl,
    'HeaderVer': headerVer,
    'JMServerUrl': jmServerUrl,
    'DohUrlList': dohUrlList,
  };

  /// 从 host 提取 URL 域名部分。
  static String urlHost(String url) {
    final u = Uri.tryParse(url);
    return u?.host ?? url;
  }
}
