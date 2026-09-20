// 用真实 Widget 渲染各页面并导出 PNG。
//   · 作为 README 截图来源
//   · 同时回归 UI：任何 RenderFlex overflow / 异常都会让测试失败
//
// 生成： flutter test --update-goldens test/screenshots_test.dart
// 校验： flutter test test/screenshots_test.dart
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:permission_handler/permission_handler.dart' as ph;

import 'package:htpr_console/app_state.dart';
import 'package:htpr_console/ble_service.dart';
import 'package:htpr_console/gnss_service.dart';
import 'package:htpr_console/htpr_protocol.dart';
import 'package:htpr_console/main.dart';

/// 组装一帧结构合法、校验位正确的**加密**帧（与真机字节流一致）
Uint8List _frame(int a, int b, int c, int d, Map<int, int> u8s,
    Map<int, int> u16s) {
  final p = Uint8List(67);
  p[0] = a;
  p[1] = b;
  p[2] = c;
  p[3] = d;
  u8s.forEach((k, v) => p[k] = v & 0xFF);
  u16s.forEach((k, v) {
    p[k] = (v >> 8) & 0xFF;
    p[k + 1] = v & 0xFF;
  });
  p[65] = HtprProtocol.checksum(p);
  p[66] = 0xCC;
  return HtprProtocol.encrypt(p);
}

void _seedTelemetry() {
  final s = AppState.I;
  s.gaugeMax = 60;
  s.voltage = 47.62;
  s.throttleV = 2.85;
  s.throttlePct = 60.3;
  s.socPct = 78;
  s.current = 6.4;
  s.rpm = 3100;
  s.rotRaw = 760;
  s.controllerSpeed = 26.4;
  s.gpsSpeed = 27.1;
  s.speed = 26.8;
  s.speedSource = '转速';
  s.speedSourceNote = '驱动中';
  s.isCoasting = false;
  s.calibK = 0.006132;
  s.calibSamples = 42;
  s.tripKm = 12.37;
  s.totalKm = 486.20;
  s.maxSpeed = 41.6;
  s.runTime = const Duration(minutes: 47, seconds: 12);
  s.energyWh = 318.4;

  // 曲线数据
  final t0 = DateTime.now().subtract(const Duration(minutes: 2));
  s.history.clear();
  for (var i = 0; i < 118; i++) {
    final v = 19 + 11 * math.sin(i / 9.0) + 3.5 * math.sin(i / 2.3);
    s.history.add(Sample(
      t0.add(Duration(milliseconds: i * 1000)),
      v.clamp(0.0, 45.0),
      47.9 - i * 0.0035,
      (3.5 + 6 * math.sin(i / 7.0)).abs(),
    ));
  }

  final b = BleService.I;
  b.connected = true;
  b.connecting = false;
  b.error = null;
  b.deviceName = '恒泰普瑞 D00C5E';
  b.deviceId = 'D0:0C:5E:53:31:C0';
  b.frameCount = 5482;
  b.hz = 2.0;
  b.rssi = -58;
  b.dashboard = HtprProtocol.parseDashboard(_frame(
    0xC9, 0x9C, 0x94, 0x05,
    {48: 7, 51: 7, 39: 12, 40: 3, 41: 0xCC},
    {63: 4762, 37: 570, 44: 0x0000},
  ));
  b.realtime = HtprProtocol.parseRealtime(_frame(
    0xCA, 0xAC, 0x96, 0x05,
    {11: 3, 12: 5, 13: 0, 14: 0, 15: 12, 16: 20, 17: 0, 18: 0, 23: 0, 24: 1, 25: 0},
    {19: 64, 21: 38},
  ));

  final g = GnssService.I;
  g.running = true;
  g.usedCount = 11;
  g.satCount = 18;
  g.accuracy = 2.8;
  g.lat = 31.230416;
  g.lon = 121.473701;
  g.alt = 12.4;
  g.bearing = 87.0;
  g.gpsSpeedMs = 27.1 / 3.6;
  g.satellites = <Sat>[
    Sat(svid: 3, constellation: 'GPS', az: 42, el: 63, cn0: 44, used: true),
    Sat(svid: 6, constellation: 'GPS', az: 118, el: 37, cn0: 39, used: true),
    Sat(svid: 12, constellation: 'GPS', az: 205, el: 71, cn0: 47, used: true),
    Sat(svid: 17, constellation: 'GPS', az: 292, el: 24, cn0: 31, used: true),
    Sat(svid: 22, constellation: 'GPS', az: 15, el: 48, cn0: 42, used: true),
    Sat(svid: 71, constellation: 'GAL', az: 78, el: 55, cn0: 41, used: true),
    Sat(svid: 74, constellation: 'GAL', az: 168, el: 29, cn0: 34, used: true),
    Sat(svid: 80, constellation: 'GAL', az: 248, el: 66, cn0: 45, used: true),
    Sat(svid: 9, constellation: 'GLO', az: 268, el: 51, cn0: 38, used: true),
    Sat(svid: 14, constellation: 'GLO', az: 331, el: 33, cn0: 30, used: true),
    Sat(svid: 21, constellation: 'GLO', az: 132, el: 78, cn0: 43, used: true),
    Sat(svid: 24, constellation: 'BDS', az: 55, el: 82, cn0: 46, used: true),
    Sat(svid: 28, constellation: 'BDS', az: 190, el: 44, cn0: 40, used: true),
    Sat(svid: 31, constellation: 'BDS', az: 305, el: 61, cn0: 37, used: true),
    Sat(svid: 42, constellation: 'BDS', az: 100, el: 18, cn0: 26, used: false),
    Sat(svid: 55, constellation: 'BDS', az: 220, el: 12, cn0: 22, used: false),
    Sat(svid: 58, constellation: 'GAL', az: 340, el: 20, cn0: 25, used: false),
    Sat(svid: 65, constellation: 'GPS', az: 148, el: 15, cn0: 24, used: false),
  ];
}

/// flutter_test 自带字体没有中文字形，会渲染成方框；加载一个系统中文字体。
String? _cjkFamily;

Future<void> _loadCjkFont() async {
  const candidates = <String>[
    r'C:\Windows\Fonts\Deng.ttf',
    r'C:\Windows\Fonts\simhei.ttf',
    r'C:\Windows\Fonts\simfang.ttf',
    '/System/Library/Fonts/PingFang.ttc',
    '/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc',
  ];
  for (final path in candidates) {
    final f = File(path);
    if (!f.existsSync()) continue;
    try {
      final bytes = f.readAsBytesSync();
      final loader = FontLoader('CJK')
        ..addFont(Future<ByteData>.value(ByteData.view(bytes.buffer)));
      await loader.load();
      _cjkFamily = 'CJK';
      return;
    } catch (_) {
      // 换下一个候选字体
    }
  }
}

/// flutter_test 默认不加载 Material 图标字体，Icon 会渲染成方框。
Future<void> _loadMaterialIcons() async {
  final root = Platform.environment['FLUTTER_ROOT'];
  final cands = <String>[
    if (root != null)
      '$root/bin/cache/artifacts/material_fonts/materialicons-regular.otf',
    'C:/dev/flutter/bin/cache/artifacts/material_fonts/materialicons-regular.otf',
  ];
  for (final p in cands) {
    final f = File(p);
    if (!f.existsSync()) continue;
    try {
      final b = f.readAsBytesSync();
      final l = FontLoader('MaterialIcons')
        ..addFont(Future<ByteData>.value(ByteData.view(b.buffer)));
      await l.load();
      return;
    } catch (_) {}
  }
}

/// 与 HtprApp 完全一致的主题，仅补上 fontFamily 以便测试环境渲染中文
Widget _host() => MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFF4DA3FF), brightness: Brightness.dark),
        scaffoldBackgroundColor: const Color(0xFF0F1420),
        fontFamily: _cjkFamily,
      ),
      home: const HomeShell(),
    );

Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  const permChannel = MethodChannel('flutter.baseflow.com/permissions/methods');
  const gnssChannel = MethodChannel('htpr/gnss/stream');

  setUpAll(() async {
    await _loadCjkFont();
    await _loadMaterialIcons();
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    // 权限：一律视为已授予，避免测试环境弹原生框
    messenger.setMockMethodCallHandler(permChannel, (call) async {
      switch (call.method) {
        case 'checkServiceStatus':
          return true;
        case 'checkPermissionStatus':
          return 1 /* PermissionStatus.granted */;
        case 'requestPermissions':
          return <int, int>{
            ph.Permission.locationWhenInUse.value:
                1 /* PermissionStatus.granted */,
          };
        case 'shouldShowRequestPermissionRationale':
          return false;
        default:
          return null;
      }
    });
    // GNSS EventChannel：接受订阅但不推送事件
    messenger.setMockMethodCallHandler(gnssChannel, (call) async => null);
  });

  tearDown(() {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(permChannel, null);
    messenger.setMockMethodCallHandler(gnssChannel, null);
  });

  testWidgets('导出 4 个页面截图（同时回归布局溢出）', (tester) async {
    tester.view.physicalSize = const Size(780, 1688);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);

    _seedTelemetry();
    await tester.pumpWidget(_host());
    await _settle(tester);

    await expectLater(
        find.byType(MaterialApp), matchesGoldenFile('goldens/1_dashboard.png'));

    for (final entry in const [
      ('GPS', '2_gps'),
      ('统计', '3_stats'),
      ('设置', '4_settings'),
    ]) {
      await tester.tap(find.text(entry.$1));
      await _settle(tester);
      await expectLater(find.byType(MaterialApp),
          matchesGoldenFile('goldens/${entry.$2}.png'));
    }

    // 设置页下半部分（三档 / 超速 / 关于）
    await tester.drag(find.byType(ListView), const Offset(0, -1500));
    await _settle(tester);
    await expectLater(find.byType(MaterialApp),
        matchesGoldenFile('goldens/5_settings_2.png'));

    // 显示量程：实时预览 + 按峰值适配
    await tester.drag(find.byType(ListView), const Offset(0, -620));
    await _settle(tester);
    await expectLater(find.byType(MaterialApp),
        matchesGoldenFile('goldens/6_settings_range.png'));

    expect(tester.takeException(), isNull);
  });
}
