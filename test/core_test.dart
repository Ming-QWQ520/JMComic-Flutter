import 'package:flutter_test/flutter_test.dart';

import 'package:jmcomic/api/jm_crypto.dart';
import 'package:jmcomic/utils/scramble.dart';

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
