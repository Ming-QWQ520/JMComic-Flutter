import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:encrypt/encrypt.dart';

import 'jm_domain.dart';

/// JMComic 协议密钥与加解密工具（还原自 tonquer/JMComic-qt + jmcomic 库标准实现）。
///
/// - 请求头签名：token = MD5("{ts}18comicAPP")，tokenparam = "{ts},{HeaderVer}"；
/// - `/chapter_view_template` 特殊：token 密钥改用 18comicAPPContent（否则 403）；
/// - 响应体解密：Base64(AES-256-ECB(PKCS7(JSON)))，
///   密钥 = MD5("{ts}185Hcomic3PAPP7R") 的 32 字节 hex 字符串 ASCII；
/// - 远程主机配置文件 (newsvr-*.txt) AES 解密。
class JmCrypto {
  JmCrypto._();

  /// Token 签名密钥（对齐 qt GetHeader）。
  static const String tokenSecret = '18comicAPP';

  /// tokenparam 中的版本号（对齐 qt GlobalConfig.HeaderVer）。
  static String get appVersion => JmDomain.headerVer.value;

  /// `/chapter_view_template` 专用 token 密钥（对齐 qt GetHeader2）。
  static const String scrambleTokenSecret = '18comicAPPContent';

  /// 响应数据解密密钥种子（jmcomic 库 APP_DATA_SECRET）。
  static const String dataSecret = '185Hcomic3PAPP7R';

  /// 远程主机配置文件 (newsvr-*.txt) 的 AES 解密种子。
  static const String hostSeed = 'diosfjckwpqpdfjkvnqQjsik';

  /// 移动端 UA（对齐 qt 默认 UA）。
  static const String userAgent =
      'Mozilla/5.0 (Linux; Android 7.1.2; DT1901A Build/N2G47O; wv) '
      'AppleWebKit/537.36 (KHTML, like Gecko) Version/4.0 Chrome/86.0.4240.198 Mobile Safari/537.36';

  /// Web 端 UA（注册/验证码等网页请求使用，对齐 qt GetWebHeader）。
  static const String webUserAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/114.0.0.0 Safari/537.36 Edg/114.0.1823.43';

  /// 远程主机配置文件地址（按顺序尝试）。
  static const List<String> hostConfigUrls = <String>[
    'https://rup4a04-c02.tos-cn-hongkong.bytepluses.com/newsvr-2025.txt',
    'https://rup4a04-c01.tos-ap-southeast-1.bytepluses.com/newsvr-2025.txt',
    'https://rup4a04-c03.tos-cn-beijing.bytepluses.com.cn/newsvr-2025.txt',
  ];

  /// APK 内置的兜底主机配置（加密 Base64）。
  /// 原文为 `{"Setting":[...],"Server":[...],"jm3_Server":[[host,線路名]...]}`。
  static const String backupHostCode = 'X+bnzYIcwF6C7Rd3T7njPDNH08zsH9zyqCrrjCr7qcnHb1LsmIZGIHtrN'
      'VR/GiraHE6OuhvrxEzwciVvhdU0I9OYcmWTxF1K7fLfcwkn7kMQg2DZ2qpE7dKGkqKCmQ'
      'ijaSUOswxL1/p9pSVe/vRYEzbB5pfcAB6Yz/zVVIendBJK629QiqQndRXM9bijtZuYJt'
      'Kw3YBAA26a+fy06dNszfw9v/4R8akVaSTWLOJc0nJy+9vm2t2W997vcqFL91iklKuKVE'
      'ZHTtdpaLTgWExXaLjtIz2zlVZfy3jYrzKZ7x+LL7o02c6WB4HV69s1VqCJYl+3l3RNwD'
      'jJ0iRNnG9p/caZL/y6sT8i78Wc38WZhOAxkDsOFiGNpvS3eojKA0wGhpTtWsuUrXgSZ7'
      'ilEPttJvOhrJGGRJJ7Ux4HgzDYO1A=';

  /// MD5 的小写 hex 表示。
  static String md5Hex(String s) => md5.convert(utf8.encode(s)).toString();

  /// 生成签名三元组 (ts, tokenparam, token)。
  ///
  /// - ts: 秒级 unix 时间戳字符串
  /// - tokenparam: "{ts},{HeaderVer}"
  /// - token: MD5("{ts}" + tokenSecret) 小写 hex
  static ({String ts, String tokenparam, String token}) randomToken() {
    final ts = (DateTime.now().millisecondsSinceEpoch ~/ 1000).toString();
    final tokenparam = '$ts,$appVersion';
    final token = md5Hex(ts + tokenSecret);
    return (ts: ts, tokenparam: tokenparam, token: token);
  }

  /// `/chapter_view_template` 专用签名（对齐 qt GetHeader2 / jmcomic 特殊逻辑）。
  static ({String ts, String tokenparam, String token}) scrambleToken() {
    final ts = (DateTime.now().millisecondsSinceEpoch ~/ 1000).toString();
    final tokenparam = '$ts,$appVersion';
    final token = md5Hex(ts + scrambleTokenSecret);
    return (ts: ts, tokenparam: tokenparam, token: token);
  }

  /// AES-256-ECB + PKCS7 解密 Base64 密文，密钥为 32 字节 hex 字符串的 ASCII 字节。
  static String? decryptBase64Aes(String b64, String keyHex) {
    try {
      final key = Key.fromUtf8(keyHex);
      final encrypter =
          Encrypter(AES(key, mode: AESMode.ecb, padding: 'PKCS7'));
      return encrypter.decrypt(Encrypted.fromBase64(b64));
    } catch (_) {
      return null;
    }
  }

  /// 解密接口响应 data 字段（对齐 qt ParseData → jmcomic decode_resp_data）。
  ///
  /// [encrypted] 为 Base64 密文字符串；[ts] 为请求 Tokenparam 中的时间戳。
  /// 密钥 = MD5("{ts}185Hcomic3PAPP7R")；解密成功且为合法 JSON 才返回。
  static String? decryptData(String encrypted, String ts) {
    final plain = decryptBase64Aes(encrypted, md5Hex(ts + dataSecret));
    if (plain != null && _looksJson(plain)) return plain;
    // 兜底：固定密钥（无时间戳派生），兼容特殊响应
    final fixed = decryptBase64Aes(encrypted, md5Hex(dataSecret));
    if (fixed != null && _looksJson(fixed)) return fixed;
    return null;
  }

  /// 判断解密结果是否以 JSON 起始。
  static bool _looksJson(String s) {
    final t = s.trimLeft();
    return t.startsWith('{') || t.startsWith('[');
  }

  /// 解密远程主机配置文件内容。
  ///
  /// 线上文件带 UTF-8 BOM 与换行，需先清理为合法 Base64，
  /// 再以 MD5(hostSeed) 的 32 字节 hex ASCII 作为 AES-256 密钥解密。
  static Map<String, dynamic>? decryptHostConfig(String text) {
    final clean = StringBuffer();
    for (final c in text.runes) {
      if (c == 0xef || c == 0xbb || c == 0xbf) continue;
      final ch = String.fromCharCode(c);
      if (ch == ' ' || ch == '\n' || ch == '\r' || ch == '\t') continue;
      clean.write(ch);
    }
    final keyHex = md5Hex(hostSeed);
    final plain = decryptBase64Aes(clean.toString(), keyHex);
    if (plain == null) return null;
    try {
      final decoded = json.decode(plain);
      if (decoded is Map<String, dynamic>) return decoded;
    } catch (_) {
      return null;
    }
    return null;
  }
}
