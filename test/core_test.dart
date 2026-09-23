import 'package:encrypt/encrypt.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:jmcomic/core/protocol/jm_crypto.dart';
import 'package:jmcomic/core/utils/scramble.dart';

void main() {
  group('JmCrypto', () {
    test('md5Hex 输出 32 位小写 hex', () {
      final r = JmCrypto.md5Hex('hello');
      expect(r, '5d41402abc4b2a76b9719d911017c592');
      expect(r.length, 32);
      expect(r, r.toLowerCase());
    });

    test('randomToken 与 Tokenparam 规范', () {
      final t = JmCrypto.randomToken();
      expect(t.tokenparam, '${t.ts},${JmCrypto.appVersion}');
      expect(t.token, JmCrypto.md5Hex(t.ts + JmCrypto.tokenSecret));
    });

    test('AES 密钥为 32 字节 hex 字符串形态', () {
      final keyHex = JmCrypto.md5Hex('test-seed');
      expect(keyHex.length, 32);
    });

    test('decryptData 使用请求 ts 派生密钥（服务端同款加密流程）', () {
      const ts = '1700000000';
      final keyHex = JmCrypto.md5Hex(ts + JmCrypto.tokenSecret);
      final encrypter = Encrypter(
        AES(Key.fromUtf8(keyHex), mode: AESMode.ecb, padding: 'PKCS7'),
      );
      const payload = '[{"id":"1","name":"x"}]';
      final cipherText = encrypter.encrypt(payload).base64;

      // 使用请求时间戳解密（修复后 _decryptResponse 的行为）。
      expect(JmCrypto.decryptData(cipherText, ts, false), payload);
      // 传入错误时间戳必须解密失败（防止回归到 ts='' 的错误实现）。
      expect(JmCrypto.decryptData(cipherText, '1999999999', false), isNull);
      // 无时间戳兜底密钥仍可用。
      final fixedKeyHex = JmCrypto.md5Hex(JmCrypto.tokenSecret);
      final fixedCipher = Encrypter(
        AES(Key.fromUtf8(fixedKeyHex), mode: AESMode.ecb, padding: 'PKCS7'),
      ).encrypt(payload).base64;
      expect(JmCrypto.decryptData(fixedCipher, ts, false), payload);
    });

    test('广告接口 decryptData 使用固定密钥', () {
      final keyHex = JmCrypto.md5Hex(JmCrypto.tokenSecret);
      final cipherText = Encrypter(
        AES(Key.fromUtf8(keyHex), mode: AESMode.ecb, padding: 'PKCS7'),
      ).encrypt('{"ad":true}').base64;
      expect(JmCrypto.decryptData(cipherText, 'any-ts', true), '{"ad":true}');
    });

    test('backupHostCode 可解密为有效主机配置', () {
      final cfg = JmCrypto.decryptHostConfig(JmCrypto.backupHostCode);
      expect(cfg, isNotNull);
      final server = (cfg!['Server'] as List?)?.cast<String>() ?? <String>[];
      expect(server, isNotEmpty, reason: '内置兜底配置必须包含可用主机');
      for (final h in server) {
        expect(h, isNotEmpty);
      }
      final jm3 = cfg['jm3_Server'] as List?;
      expect(jm3, isNotNull);
      expect(jm3!.first, isA<List<dynamic>>());
    });
  });

  group('Scramble', () {
    test('needScramble 阈值判定', () {
      expect(Scramble.needScramble(422889, 220980), isTrue);
      expect(Scramble.needScramble(100000, 220980), isFalse);
    });

    test('scrambleNum 查表范围', () {
      const table = <int>[2, 4, 6, 8, 10, 12, 14, 16, 18, 20];
      for (var aid = 421926; aid < 421976; aid++) {
        final n = Scramble.scrambleNum(aid.toString(), '00001');
        expect(table.contains(n), isTrue, reason: 'aid=$aid n=$n');
      }
      for (var aid = 268850; aid < 268900; aid++) {
        final n = Scramble.scrambleNum(aid.toString(), '00001');
        expect(table.contains(n), isTrue, reason: 'aid=$aid n=$n');
      }
    });

    test('filenameFromUrl 提取文件名', () {
      expect(
        Scramble.filenameFromUrl(
            'https://cdn/media/photos/422889/00001.webp?t=1'),
        '00001',
      );
      expect(
        Scramble.filenameFromUrl('https://cdn/media/photos/422889/00123.jpg'),
        '00123',
      );
    });
  });
}
