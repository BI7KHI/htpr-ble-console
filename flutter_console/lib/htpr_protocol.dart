// 恒泰普瑞「全能机内置蓝牙控制器」协议实现 (Dart)
// 逆向自官方微信小程序 wx0ebd16ecb71fee37
// 与 htpr_protocol.py / PROTOCOL.md 完全一致
import 'dart:typed_data';

class HtprProtocol {
  // Nordic UART Service
  static const String nusService = '6e400001-b5a3-f393-e0a9-e50e24dcca9e';
  static const String nusWriteChar = '6e400002-b5a3-f393-e0a9-e50e24dcca9e'; // 手机 -> 设备
  static const String nusNotifyChar = '6e400003-b5a3-f393-e0a9-e50e24dcca9e'; // 设备 -> 手机

  static const int frameLen = 67;
  static const int hdrRealtime0 = 0xCA, hdrRealtime1 = 0xAC; // 遥测帧
  static const int hdrDash0 = 0xC9, hdrDash1 = 0x9C; // 仪表帧

  /// [4..65] 滚动混淆解密
  static Uint8List decrypt(Uint8List src) {
    final r = Uint8List.fromList(src);
    for (int o = 4; o <= 65 && o < r.length; o++) {
      int b = r[o];
      b = (b - 54) & 0xFF;
      b ^= 43;
      b = (b - o) & 0xFF;
      b ^= 101;
      b = (b - o) & 0xFF;
      r[o] = b;
    }
    return r;
  }

  /// [4..65] 加密（下发命令用）
  static Uint8List encrypt(Uint8List src) {
    final r = Uint8List.fromList(src);
    for (int o = 4; o <= 65 && o < r.length; o++) {
      int b = r[o];
      b = (b + o) & 0xFF;
      b ^= 101;
      b = (b + o) & 0xFF;
      b ^= 43;
      b = (b + 54) & 0xFF;
      r[o] = b;
    }
    return r;
  }

  static int checksum(Uint8List f) {
    int s = 0;
    for (int i = 0; i < 65 && i < f.length; i++) {
      s += f[i];
    }
    return s & 0xFF;
  }

  static bool verify(Uint8List f) =>
      f.length >= frameLen && f[65] == checksum(f) && f[66] == 0xCC;

  static int u8(Uint8List f, int i) => f[i];
  static int u16be(Uint8List f, int i) => (f[i] << 8) | f[i + 1];

  /// 解析收到的 67 字节帧 -> Dashboard / Realtime
  static Object? parse(Uint8List raw) {
    if (raw.length < 2) return null;
    if (raw[0] == hdrRealtime0 && raw[1] == hdrRealtime1) {
      return parseRealtime(raw);
    }
    if (raw[0] == hdrDash0 && raw[1] == hdrDash1) {
      return parseDashboard(raw);
    }
    return null;
  }

  /// 仪表帧 C9 9C 94 05 —— 电压 / 转把电压
  static Dashboard parseDashboard(Uint8List raw) {
    final f = decrypt(raw);
    return Dashboard(
      raw: raw,
      decrypted: f,
      ok: verify(f),
      voltage: u16be(f, 63) / 100.0,
      throttleVoltage: u16be(f, 37) / 200.0,
      serial: u8(f, 10),
      vehicleModelId: u8(f, 48),
      motion3: u8(f, 51),
      funcSettings: u16be(f, 44), // 16 位功能设置字（含强制超速 bit9）
      currentRegulation: u8(f, 39),
      codeTable: u8(f, 40),
      lockByte: u8(f, 41),
    );
  }

  /// 遥测帧 CA AC 96 05 —— 电流 / 转速
  static Realtime parseRealtime(Uint8List raw) {
    final f = decrypt(raw);
    return Realtime(
      raw: raw,
      decrypted: f,
      ok: verify(f),
      ampere: u16be(f, 19) / 10.0,
      rotationalspeed: 20 * u16be(f, 21),
      study: u8(f, 23),
      motion1: u8(f, 11),
      motion2: u8(f, 12),
      reverseSpeed: u8(f, 13),
      torque: u8(f, 14),
      currentRegulation: u8(f, 15),
      maximumCurrent: u8(f, 16),
      em: u8(f, 17),
      em2: u8(f, 18),
      run: u8(f, 24),
      modSwitch: u8(f, 25),
    );
  }

  // ------------------------------------------------------------------ 下发命令
  //
  // 官方小程序写入流程（c99c0002）:
  //   1. 以上一帧仪表帧(9405)为模板
  //   2. hex[88..92]  = serializeFunctionSettings()  (byte44,45)
  //   3. hex[102..104]= motion3                      (byte51)
  //   4. hex[82..84]  = "cc"(锁) / "33"(解锁)         (byte41)
  //   5. byte65 = 校验
  //   6. 整帧 encrypt() 后 writeNoResponse
  //
  // 功能设置 16 位字各 bit（pos 越大越靠高位）:
  //   15 自动驻坡 | 14 静止允许入P档 | 13 相线仪表开关 | 12 防溜坡 | 11 陡坡缓降
  //   10 空挡选择 | 9 强制超速 | 8 TCS | 7 限速 | 6 P档 | 5 刹车电平 | 4 电子刹车
  //   0..3 起步模式

  static int _setBit(int word, int pos, bool on) {
    if (on) {
      return word | (1 << pos);
    }
    return word & ~(1 << pos);
  }

  static bool _getBit(int word, int pos) => ((word >> pos) & 1) == 1;

  static bool overspeedEnabled(int funcSettings) => _getBit(funcSettings, 9);

  static int withOverspeed(int funcSettings, bool on) =>
      _setBit(funcSettings, 9, on).toUint16();

  /// 构建 c99c0002 命令帧（含功能设置 / motion3 / 锁车）
  /// [template] 为最近收到的仪表帧（未解密）；[func] 为 16 位功能设置字
  static Uint8List buildC0002({
    required Uint8List template,
    required int func,
    required int motion3,
    required bool locked,
  }) {
    final f = Uint8List.fromList(decrypt(template)); // 先解密出明文再改
    f[44] = (func >> 8) & 0xFF;
    f[45] = func & 0xFF;
    f[51] = motion3 & 0xFF;
    f[41] = locked ? 0xCC : 0x33;
    f[0] = 0xC9;
    f[1] = 0x9C;
    f[2] = 0x00;
    f[3] = 0x02;
    f[65] = checksum(f);
    f[66] = 0xCC;
    return encrypt(f);
  }

  /// 构建 c99c0602 命令帧（三档限速 motion1 / motion2 等）
  static Uint8List buildC0602({
    required Uint8List template,
    required int motion1,
    required int motion2,
    required int currentLimit,
    required int run,
    required int modSwitch,
  }) {
    final f = Uint8List.fromList(decrypt(template)); // 用遥测帧模板
    f[11] = motion1 & 0xFF;
    f[12] = motion2 & 0xFF;
    f[15] = currentLimit & 0xFF;
    f[24] = run & 0xFF;
    f[25] = modSwitch & 0xFF;
    f[0] = 0xC9;
    f[1] = 0x9C;
    f[2] = 0x06;
    f[3] = 0x02;
    f[65] = checksum(f);
    f[66] = 0xCC;
    return encrypt(f);
  }

  static String hex(Uint8List b) =>
      b.map((x) => x.toRadixString(16).padLeft(2, '0')).join().toUpperCase();
}

extension on int {
  int toUint16() => this & 0xFFFF;
}

/// 仪表帧解析结果
class Dashboard {
  final Uint8List raw;
  final Uint8List decrypted;
  final bool ok;
  final double voltage; // V
  final double throttleVoltage; // V
  final int serial;
  final int vehicleModelId;
  final int motion3;
  final int funcSettings;
  final int currentRegulation;
  final int codeTable;
  final int lockByte;

  Dashboard({
    required this.raw,
    required this.decrypted,
    required this.ok,
    required this.voltage,
    required this.throttleVoltage,
    required this.serial,
    required this.vehicleModelId,
    required this.motion3,
    required this.funcSettings,
    required this.currentRegulation,
    required this.codeTable,
    required this.lockByte,
  });
}

/// 遥测帧解析结果
class Realtime {
  final Uint8List raw;
  final Uint8List decrypted;
  final bool ok;
  final double ampere; // A
  final int rotationalspeed; // 原始值
  final int study;
  final int motion1;
  final int motion2;
  final int reverseSpeed;
  final int torque;
  final int currentRegulation;
  final int maximumCurrent;
  final int em;
  final int em2;
  final int run;
  final int modSwitch;

  Realtime({
    required this.raw,
    required this.decrypted,
    required this.ok,
    required this.ampere,
    required this.rotationalspeed,
    required this.study,
    required this.motion1,
    required this.motion2,
    required this.reverseSpeed,
    required this.torque,
    required this.currentRegulation,
    required this.maximumCurrent,
    required this.em,
    required this.em2,
    required this.run,
    required this.modSwitch,
  });

  /// 转速原始值 -> 轮子 rpm（官方 app: rotationalspeed / a，a 默认 25）
  int rpm(int divider) => divider <= 0 ? rotationalspeed : rotationalspeed ~/ divider;
}
