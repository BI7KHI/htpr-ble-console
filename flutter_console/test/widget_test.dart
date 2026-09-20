// 恒泰普瑞控制台 - 基础测试
import 'package:flutter_test/flutter_test.dart';
import 'package:htpr_console/htpr_protocol.dart';
import 'dart:typed_data';

void main() {
  test('协议加解密可逆', () {
    final f = Uint8List.fromList(List.generate(67, (i) => i * 3 % 256));
    final enc = HtprProtocol.encrypt(f);
    final dec = HtprProtocol.decrypt(enc);
    expect(dec.sublist(4, 66), equals(f.sublist(4, 66)));
  });

  test('功能字 bit9 强制超速 读写', () {
    const w = 0x0320;
    expect(HtprProtocol.overspeedEnabled(w), isTrue);
    final off = HtprProtocol.withOverspeed(w, false);
    expect(HtprProtocol.overspeedEnabled(off), isFalse);
    final on = HtprProtocol.withOverspeed(off, true);
    expect(HtprProtocol.overspeedEnabled(on), isTrue);
  });
}
