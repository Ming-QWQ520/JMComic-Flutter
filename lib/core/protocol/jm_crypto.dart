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
  static const String backupHostCode = 'X+bnzYIcwF6C7Rd3T7njPM0aeKgOoB+o/+lwS/'
      'klMzdv/yrVPk0UikahXv/MGxHqaSCwOCfGQjX0QpMpSxvr4+vsg/4ohUY8jspsJ7gSoQU5A'
      'NBMM99J2WtKxGgIBLq9PjCaS/34KK9HSiLJdaXz40oGSEHkBl8L0tTfPRC+dmPlp2CJ/97a'
      'nZkSqForX+hTFgVoS0BZl/gXUQdF2njjAjgJwg13qbTJd3QB0CExaztlrC1Z1QGhXNjxM0Z'
      'k5v8i8JoPtTe7LWW55r96oLJrDOG60uspZxlV+Jp3FOdRXFH++Mann1Vo88iv9kbTa1f1Fk'
      'aUCEgPpxNKmnCpnNUhNgCZExIlg7RcQQ6Ru+ys1D4+GAhA3Z1gUDMsYIit/bD8H30ZoBip5'
      '9iW0Nx4haPYM5Pb9GyYRAkIJfQRP46w1JQXMPir0MCxMnvFahb0xzOULRx+WBrOe/oMKD1D'
      'sohhxw==';

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
  /// [encrypted] 为 Base64 密文字符串；[ts] 为请求时的时间戳；
  /// [isAd] 标记广告类接口（使用不带时间戳的固定密钥）。
  /// 依次尝试 tokenSecret / contentSecret 两个密钥，解密成功且为合法 JSON 才返回。
  static String? decryptData(String encrypted, String ts, bool isAd) {
    final secrets = <String>[tokenSecret, contentSecret];
    for (final s in secrets) {
      final keyHex = isAd ? md5Hex(s) : md5Hex(ts + s);
      final plain = decryptBase64Aes(encrypted, keyHex);
      if (plain == null) continue;
      final t = plain.trimLeft();
      if (t.startsWith('{') || t.startsWith('[')) return plain;
    }
    return null;
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
