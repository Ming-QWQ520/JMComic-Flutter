import 'package:encrypt/encrypt.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:jmcomic/core/protocol/jm_crypto.dart';
import 'package:jmcomic/core/protocol/jm_domain.dart';
import 'package:jmcomic/core/utils/scramble.dart';

void main() {
  group('JmCrypto（对齐 tonquer/JMComic-qt）', () {
    test('md5Hex 输出 32 位小写 hex', () {
      final r = JmCrypto.md5Hex('hello');
      expect(r, '5d41402abc4b2a76b9719d911017c592');
      expect(r.length, 32);
      expect(r, r.toLowerCase());
    });

    test('randomToken 与 Tokenparam 规范（token 密钥 = 18comicAPP）', () {
      final t = JmCrypto.randomToken();
      expect(t.tokenparam, '${t.ts},${JmCrypto.appVersion}');
      // 对齐 qt GetHeader: token = md5("{ts}18comicAPP")
      expect(t.token, JmCrypto.md5Hex('${t.ts}18comicAPP'));
      expect(JmCrypto.tokenSecret, '18comicAPP');
    });

    test('scrambleToken 使用 18comicAPPContent（chapter_view_template 专用）', () {
      final t = JmCrypto.scrambleToken();
      expect(t.token, JmCrypto.md5Hex('${t.ts}18comicAPPContent'));
      expect(JmCrypto.scrambleTokenSecret, '18comicAPPContent');
    });

    test('AES 密钥为 32 字节 hex 字符串形态', () {
      final keyHex = JmCrypto.md5Hex('test-seed');
      expect(keyHex.length, 32);
    });

    test('decryptData 使用请求 ts 派生密钥（jmcomic decode_resp_data 同款）', () {
      const ts = '1700000000';
      // 对齐 jmcomic 库：响应解密密钥 = md5("{ts}185Hcomic3PAPP7R")
      expect(JmCrypto.dataSecret, '185Hcomic3PAPP7R');
      final keyHex = JmCrypto.md5Hex(ts + JmCrypto.dataSecret);
      final encrypter = Encrypter(
        AES(Key.fromUtf8(keyHex), mode: AESMode.ecb, padding: 'PKCS7'),
      );
      const payload = '[{"id":"1","name":"x"}]';
      final cipherText = encrypter.encrypt(payload).base64;

      // 使用请求时间戳解密。
      expect(JmCrypto.decryptData(cipherText, ts), payload);
      // 传入错误时间戳必须解密失败（防止回归）。
      expect(JmCrypto.decryptData(cipherText, '1999999999'), isNull);
      // 无时间戳兜底固定密钥仍可用。
      final fixedKeyHex = JmCrypto.md5Hex(JmCrypto.dataSecret);
      final fixedCipher = Encrypter(
        AES(Key.fromUtf8(fixedKeyHex), mode: AESMode.ecb, padding: 'PKCS7'),
      ).encrypt(payload).base64;
      expect(JmCrypto.decryptData(fixedCipher, ts), payload);
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

  group('JmDomain（对齐 qt GlobalConfig）', () {
    test('默认域名与 qt Url2List / PicUrlList 一致', () {
      expect(JmDomain.apiUrlList.value.first, 'https://www.cdnhjk.net');
      expect(JmDomain.picUrlList.value.first, 'https://cdn-msp.jmapiproxy1.cc');
      expect(JmDomain.headerVer.value, '2.1.7');
    });

    test('getApiUrl / getImgUrl 索引语义（5=CDN，6=代理）', () {
      expect(JmDomain.getApiUrl(1), 'https://www.cdnhjk.net');
      expect(JmDomain.getApiUrl(5), JmDomain.cdnApiUrl.value);
      expect(JmDomain.getApiUrl(6), JmDomain.proxyApiUrl.value);
      expect(JmDomain.getImgUrl(5), JmDomain.cdnImgUrl.value);
      expect(JmDomain.getImgUrl(6), JmDomain.proxyImgUrl.value);
    });

    test('updateSettingFromText 版本判断（仅更新更高版本）', () {
      const text = 'Ver=92\nHeaderVer=2.1.8\nVerTime=2026-10-1';
      final applied = JmDomain.updateSettingFromText(text);
      expect(applied, isTrue);
      expect(JmDomain.ver.value, 92);
      expect(JmDomain.headerVer.value, '2.1.8');
      // 低版本不应回退
      const oldText = 'Ver=90\nHeaderVer=2.0.0';
      expect(JmDomain.updateSettingFromText(oldText), isFalse);
      expect(JmDomain.headerVer.value, '2.1.8');
      // 还原默认值，避免污染其它测试
      JmDomain.ver.setValue(91);
      JmDomain.headerVer.setValue('2.1.7');
    });

    test('updateSettingFromText 支持逗号分隔列表', () {
      const text = 'Ver=93\nUrl2List=https://a.cc,https://b.cc';
      expect(JmDomain.updateSettingFromText(text), isTrue);
      expect(JmDomain.apiUrlList.value, <String>['https://a.cc', 'https://b.cc']);
      // 还原默认
      JmDomain.apiUrlList.setValue(
          'https://www.cdnhjk.net,https://www.cdngwc.cc,https://www.cdngwc.net,https://www.cdngwc.club');
      JmDomain.ver.setValue(91);
    });
  });

  group('Scramble', () {
    test('needScramble 阈值判定', () {
      expect(Scramble.needScramble(422889, 220980), isTrue);
      expect(Scramble.needScramble(100000, 220980), isFalse);
    });

    test('scrambleNum 查表范围（对齐 qt GetSegmentationNum）', () {
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
