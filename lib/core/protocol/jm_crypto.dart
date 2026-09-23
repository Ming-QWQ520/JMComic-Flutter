import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:encrypt/encrypt.dart';

/// JMComic 协议密钥与加解密工具。
///
/// 协议还原自 JMComic3 APP v2.1.8（参考 Ming-QWQ520/JMcomic-API 逆向实现）：
/// - 请求头 Token / Tokenparam 签名；
/// - 响应体 Base64(AES-256-ECB(PKCS7(JSON))) 解密；
/// - 远程主机配置文件解密。
class JmCrypto {
  JmCrypto._();

  /// 与 APK 内置版本一致，参与 Tokenparam 构造。
  static const String appVersion = '2.1.8';

  /// Token 签名与普通接口响应解密密钥种子。
  static const String tokenSecret = '185Hcomic3PAPP7R';

  /// 响应解密密钥第二候选。
  static const String contentSecret = '18comicAPPContent';

  /// 远程主机配置文件 (newsvr-*.txt) 的 AES 解密种子。
  static const String hostSeed = 'diosfjckwpqpdfjkvnqQjsik';

  /// APP WebView UA（服务端按 APP 流量识别）。
  static const String userAgent =
      'Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36';

  /// 远程主机配置文件地址（APK 内置，按顺序尝试）。
  static const List<String> hostConfigUrls = <String>[
    'https://rup4a04-c02.tos-cn-hongkong.bytepluses.com/newsvr-2025.txt',
    'https://rup4a04-c01.tos-ap-southeast-1.bytepluses.com/newsvr-2025.txt',
    'https://rup4a04-c03.tos-cn-beijing.bytepluses.com.cn/newsvr-2025.txt',
  ];

  /// APK 内置的兜底主机配置（加密 Base64）。
  /// 原文为 `{"Setting":[...],"Server":[...],"jm3_Server":[[host,線路名]...]}`。
  /// 与线上 newsvr-2025.txt 同步，主机变更时需更新。
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
  /// - tokenparam: "{ts},{appVersion}"
  /// - token: MD5("{ts}" + tokenSecret) 小写 hex
  static ({String ts, String tokenparam, String token}) randomToken() {
    final ts = (DateTime.now().millisecondsSinceEpoch ~/ 1000).toString();
    final tokenparam = '$ts,$appVersion';
    final token = md5Hex(ts + tokenSecret);
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

  /// 解密接口响应 data 字段。
  ///
  /// [encrypted] 为 Base64 密文字符串；[ts] 为请求 Tokenparam 中的时间戳；
  /// [isAd] 标记广告类接口（使用不带时间戳的固定密钥）。
  /// 常规接口依次尝试 md5(ts+密钥) / md5(密钥) 两组密钥，
  /// 解密成功且为合法 JSON 才返回。
  static String? decryptData(String encrypted, String ts, bool isAd) {
    final secrets = <String>[tokenSecret, contentSecret];
    if (isAd) {
      for (final s in secrets) {
        final plain = decryptBase64Aes(encrypted, md5Hex(s));
        if (plain != null && _looksJson(plain)) return plain;
      }
      return null;
    }
    for (final s in secrets) {
      final plain = decryptBase64Aes(encrypted, md5Hex(ts + s));
      if (plain != null && _looksJson(plain)) return plain;
    }
    for (final s in secrets) {
      final plain = decryptBase64Aes(encrypted, md5Hex(s));
      if (plain != null && _looksJson(plain)) return plain;
    }
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
