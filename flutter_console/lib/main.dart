// 恒泰普瑞控制器 · 竖屏控制台
// 仪表盘 / GNSS 天空图 / 行驶统计 / 参数设置
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import 'app_state.dart';
import 'ble_service.dart';
import 'gnss_service.dart';
import 'htpr_protocol.dart';
import 'pages_extra.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AppState.I.init();
  runApp(const HtprApp());
}

class HtprApp extends StatelessWidget {
  const HtprApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '恒泰普瑞 控制台',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFF4DA3FF), brightness: Brightness.dark),
        scaffoldBackgroundColor: const Color(0xFF0F1420),
      ),
      home: const HomeShell(),
    );
  }
}

// ============================================================ 外壳
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});
  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _idx = 0;
  @override
  void initState() {
    super.initState();
    BleService.I.addListener(_u);
    AppState.I.addListener(_u);
    GnssService.I.addListener(_u);
  }

  void _u() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    const pages = [DashboardPage(), GpsPage(), StatsPage(), SettingsPage()];
    return Scaffold(
      body: SafeArea(child: pages[_idx]),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _idx,
        onDestinationSelected: (i) => setState(() => _idx = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.speed), label: '仪表'),
          NavigationDestination(icon: Icon(Icons.satellite_alt), label: 'GPS'),
          NavigationDestination(icon: Icon(Icons.insights), label: '统计'),
          NavigationDestination(icon: Icon(Icons.tune), label: '设置'),
        ],
      ),
    );
  }
}

// ============================================================ 仪表盘
class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});
  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  @override
  void initState() {
    super.initState();
    BleService.I.addListener(_u);
    AppState.I.addListener(_u);
    GnssService.I.addListener(_u);
  }

  void _u() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final s = AppState.I;
    final b = BleService.I;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _ConnBar(),
        const SizedBox(height: 10),

        // ---------- 半圆形表盘（180°）----------
        Container(
          height: 300,
          decoration: BoxDecoration(
            color: const Color(0xFF16203A),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0xFF2A3550)),
          ),
          child: LayoutBuilder(builder: (ctx, c) {
            final cy = c.maxHeight * 0.70; // 半圆基线
            final r = math.min((c.maxWidth - 36) / 2, cy - 26);
            return Stack(
              children: [
                Positioned.fill(
                  child: CustomPaint(
                    painter: SpeedometerPainter(
                      speed: s.speed,
                      maxSpeed: s.gaugeMax,
                      throttlePct: s.throttlePct,
                      cy: cy,
                      r: r,
                      fontFamily: DefaultTextStyle.of(ctx).style.fontFamily,
                    ),
                  ),
                ),
                // 速度来源徽标（放左下角，不占表盘）
                Positioned(
                  left: 14,
                  bottom: 12,
                  child: _SourceBadge(
                      kind: s.speedSrcKind, note: s.speedSourceNote),
                ),
                // 右下角小字：电机转速
                Positioned(
                  right: 16,
                  bottom: 12,
                  child: Text(
                    '${b.realtime?.rpm(s.rpmDivider.round()) ?? 0} rpm',
                    style: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF7E92B8)),
                  ),
                ),
                // 大数字（半圆内、指针下方空白区）
                Positioned(
                  left: 0,
                  right: 0,
                  top: cy + 24,
                  child: Center(
                    child: Text.rich(TextSpan(children: [
                        TextSpan(
                          text: s.speed.toStringAsFixed(1),
                          style: const TextStyle(
                            fontSize: 52,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFFEAF3FF),
                            height: 1.0,
                            letterSpacing: -1.5,
                          ),
                        ),
                        const TextSpan(
                          text: ' km/h',
                          style: TextStyle(
                              fontSize: 15, color: Color(0xFF8EA0C4)),
                        ),
                      ]),
                    ),
                  ),
                ),
              ],
            );
          }),
        ),
        const SizedBox(height: 14),
        Row(children: [
          Expanded(
              child: _ValCard(
                  label: '电压',
                  value: s.voltage.toStringAsFixed(1),
                  unit: 'V',
                  color: const Color(0xFF7FC4FF),
                  progress: s.socPct / 100.0,
                  sub:
                      '${s.cellCount}S · ${(s.cellCount > 0 ? s.voltage / s.cellCount : 0).toStringAsFixed(2)}V/串')),
          const SizedBox(width: 12),
          Expanded(
              child: _ValCard(
                  label: '油门',
                  value: s.throttlePct.toStringAsFixed(0),
                  unit: '%',
                  color: const Color(0xFF8FF0C0),
                  progress: s.throttlePct / 100.0,
                  sub: '转把 ${s.throttleV.toStringAsFixed(1)}V')),
        ]),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(
              child: _ValCard(
                  label: '电量',
                  value: s.socPct.toStringAsFixed(0),
                  unit: '%',
                  color: const Color(0xFFFFD479),
                  progress: s.socPct / 100.0,
                  sub: '${s.cellCount}串三元锂')),
          const SizedBox(width: 12),
          Expanded(
              child: _ValCard(
                  label: '电流',
                  value: s.current.toStringAsFixed(1),
                  unit: 'A',
                  color: s.current >= 10
                      ? const Color(0xFFFF5D5D)
                      : const Color(0xFFFF9A8B),
                  progress: (s.current / 25.0).clamp(0.0, 1.0),
                  sub: '功率 ${(s.voltage * s.current).toStringAsFixed(0)}W')),
        ]),
        const SizedBox(height: 12),
        const _ControlCard(),
        const SizedBox(height: 8),
      ],
    );
  }
}

class _ConnBar extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final b = BleService.I;
    final ok = b.connected;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
        color: const Color(0xFF172033),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF2A3550)),
      ),
      child: Row(children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: ok ? const Color(0xFF35D07F) : const Color(0xFF6E82A8),
            boxShadow: ok
                ? [const BoxShadow(color: Color(0xFF35D07F), blurRadius: 8)]
                : null,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                ok
                    ? (b.deviceName.isEmpty ? '已连接' : b.deviceName)
                    : (b.connecting ? '连接中…' : '未连接'),
                style:
                    const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
              ),
              Text(
                ok
                    ? '${b.frameCount} 帧 · ${b.hz.toStringAsFixed(1)} Hz · RSSI ${b.rssi}'
                    : (b.error ?? '点击右侧按钮连接控制器'),
                style: TextStyle(
                  fontSize: 12,
                  color: (b.error != null && !ok)
                      ? const Color(0xFFFF5D5D)
                      : const Color(0xFF8EA0C4),
                ),
              ),
            ],
          ),
        ),
        FilledButton(
          onPressed: () async {
            if (ok) {
              await BleService.I.disconnect();
            } else {
              await BleService.I.connect(address: AppState.I.deviceAddress);
            }
          },
          child: Text(ok ? '断开' : '连接'),
        ),
      ]),
    );
  }
}

class _ValCard extends StatelessWidget {
  final String label, unit, sub, value;
  final Color color;
  final double? progress;
  const _ValCard({
    required this.label,
    required this.value,
    required this.unit,
    required this.color,
    required this.sub,
    this.progress,
  });
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: const Color(0xFF172033),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF2A3550)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: const TextStyle(color: Color(0xFF8EA0C4), fontSize: 13)),
          const SizedBox(height: 4),
          Text.rich(TextSpan(children: [
              TextSpan(
                  text: value,
                  style: TextStyle(
                      fontSize: 30,
                      fontWeight: FontWeight.w700,
                      color: color,
                      height: 1.05)),
              TextSpan(
                  text: ' $unit',
                  style: const TextStyle(
                      fontSize: 14, color: Color(0xFF8EA0C4))),
            ]),
          ),
          const SizedBox(height: 2),
          Text(sub,
              style: const TextStyle(color: Color(0xFF6E82A8), fontSize: 11)),
          if (progress != null) ...[
            const SizedBox(height: 9),
            ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(
                value: progress!.clamp(0.0, 1.0),
                minHeight: 4,
                backgroundColor: const Color(0xFF243050),
                valueColor: AlwaysStoppedAnimation<Color>(color),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ---------------------------------------------------------- 速度来源徽标
class _SourceBadge extends StatelessWidget {
  final SpeedSrc kind;
  final String note;
  const _SourceBadge({required this.kind, required this.note});

  @override
  Widget build(BuildContext context) {
    final (label, fg, bg, icon) = switch (kind) {
      SpeedSrc.gnss => (
          'GNSS',
          const Color(0xFF8FF0C0),
          const Color(0xFF17331F),
          Icons.satellite_alt
        ),
      SpeedSrc.rpm => (
          '转速',
          const Color(0xFF9EC5FF),
          const Color(0xFF1B2A4A),
          Icons.sync
        ),
      SpeedSrc.none => (
          '无源',
          const Color(0xFF8EA0C4),
          const Color(0xFF2A3550),
          Icons.remove_circle_outline
        ),
    };
    final text = kind == SpeedSrc.none ? '无速度源' : '$label · $note';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration:
          BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 11, color: fg),
        const SizedBox(width: 5),
        Text(text,
            style: TextStyle(
                fontSize: 10.5, color: fg, fontWeight: FontWeight.w600)),
      ]),
    );
  }
}

// ---------------------------------------------------------- 快速控制条
class _ControlCard extends StatelessWidget {
  const _ControlCard();

  Future<void> _do(BuildContext ctx, Future<void> Function() fn) async {
    try {
      await fn();
    } catch (e) {
      if (!ctx.mounted) return;
      ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
          content: Text('下发失败：$e'),
          duration: const Duration(seconds: 3),
          behavior: SnackBarBehavior.floating));
    }
  }

  @override
  Widget build(BuildContext context) {
    final b = BleService.I;
    final d = b.dashboard;
    final r = b.realtime;
    final can = b.canWrite;
    final over = d != null && HtprProtocol.overspeedEnabled(d.funcSettings);

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 10, 6),
      decoration: BoxDecoration(
        color: const Color(0xFF172033),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
            color: over ? const Color(0xFF6B3232) : const Color(0xFF2A3550)),
      ),
      child: Column(children: [
        Row(children: [
          const Icon(Icons.tune, size: 15, color: Color(0xFF8EA0C4)),
          const SizedBox(width: 8),
          const Text('档位限速',
              style: TextStyle(fontSize: 13, color: Color(0xFF8EA0C4))),
          const Spacer(),
          _chip('低速', r?.motion1),
          const SizedBox(width: 6),
          _chip('中速', r?.motion2),
          const SizedBox(width: 6),
          _chip('高速', d?.motion3),
        ]),
        const Divider(height: 16),
        Row(children: [
          Icon(Icons.warning_amber_rounded,
              size: 15,
              color: over ? const Color(0xFFFFB4A8) : const Color(0xFF8EA0C4)),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('强制超速',
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: over
                            ? const Color(0xFFFFB4A8)
                            : const Color(0xFFEAF3FF))),
                Text(
                  can
                      ? (over ? '已开启 · 已突破出厂限速，注意安全' : '关闭 · 按出厂限速运行')
                      : '连接控制器后可下发指令',
                  style: const TextStyle(
                      fontSize: 10.5, color: Color(0xFF6E82A8)),
                ),
              ],
            ),
          ),
          Switch(
            value: over,
            activeTrackColor: const Color(0xFF7A2E2E),
            onChanged:
                can ? (v) => _do(context, () => b.setOverspeed(v)) : null,
          ),
        ]),
      ]),
    );
  }

  Widget _chip(String name, int? v) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: const Color(0xFF1E2A44),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text('$name ${v ?? '--'}',
            style: const TextStyle(
                fontSize: 11,
                color: Color(0xFF9EC5FF),
                fontWeight: FontWeight.w600)),
      );
}

// ============================================================ 表盘绘制
class SpeedometerPainter extends CustomPainter {
  final double speed, maxSpeed, throttlePct, cy, r;
  /// CustomPainter 取不到 Theme，字体族由外部注入（真机为 null → 系统默认字体）
  final String? fontFamily;
  SpeedometerPainter({
    required this.speed,
    required this.maxSpeed,
    required this.throttlePct,
    required this.cy,
    required this.r,
    this.fontFamily,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    const startA = math.pi; // 180° = 左
    const sweepA = math.pi; // 扫 180° → 右

    // 底色半圆
    canvas.drawArc(
        Rect.fromCircle(center: Offset(cx, cy), radius: r),
        startA,
        sweepA,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeWidth = 14
          ..color = const Color(0xFF243050));

    // 油门外弧（内侧细弧）
    final thrSweep = sweepA * (throttlePct / 100.0).clamp(0.0, 1.0);
    canvas.drawArc(
        Rect.fromCircle(center: Offset(cx, cy), radius: r - 13),
        startA,
        thrSweep,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeWidth = 5
          ..color = const Color(0xFF35D07F));

    // 速度主弧（渐变）
    final t = (speed / maxSpeed).clamp(0.0, 1.0);
    final arcRect = Rect.fromCircle(center: Offset(cx, cy), radius: r);
    canvas.drawArc(
        arcRect,
        startA,
        sweepA * t,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeWidth = 14
          ..shader = SweepGradient(
            colors: const [
              Color(0xFF4DA3FF),
              Color(0xFF35D07F),
              Color(0xFFFFD479),
              Color(0xFFFF5D5D),
            ],
            stops: const [0.0, 0.45, 0.75, 1.0],
            transform: const GradientRotation(math.pi),
          ).createShader(arcRect));

    // 刻度 + 数字（全部落在半圆内侧，不越界）
    for (int i = 0; i <= 8; i++) {
      final a = startA + sweepA * (i / 8);
      canvas.drawLine(
          Offset(cx + math.cos(a) * (r - 8), cy + math.sin(a) * (r - 8)),
          Offset(cx + math.cos(a) * (r - 18), cy + math.sin(a) * (r - 18)),
          Paint()
            ..color = const Color(0xFF3A4A70)
            ..strokeWidth = 2);
      final tp = TextPainter(
        text: TextSpan(
            text: '${(maxSpeed * i / 8).round()}',
            style: TextStyle(
                color: const Color(0xFF6E82A8),
                fontSize: 11,
                fontFamily: fontFamily)),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(
          canvas,
          Offset(cx + math.cos(a) * (r - 32) - tp.width / 2,
              cy + math.sin(a) * (r - 32) - tp.height / 2));
    }

    // 指针（只在半圆内扫动）
    final na = startA + sweepA * t;
    final needle = Path()
      ..moveTo(cx + math.cos(na + math.pi / 2) * 5,
          cy + math.sin(na + math.pi / 2) * 5)
      ..lineTo(cx + math.cos(na) * (r - 38),
          cy + math.sin(na) * (r - 38))
      ..lineTo(cx + math.cos(na - math.pi / 2) * 5,
          cy + math.sin(na - math.pi / 2) * 5)
      ..close();
    canvas.drawPath(needle, Paint()..color = const Color(0xFFEAF3FF));

    // 轴心
    canvas.drawCircle(
        Offset(cx, cy), 8, Paint()..color = const Color(0xFF16203A));
    canvas.drawCircle(
        Offset(cx, cy),
        8,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5
          ..color = const Color(0xFF4DA3FF));
  }

  @override
  bool shouldRepaint(covariant SpeedometerPainter o) =>
      o.speed != speed || o.throttlePct != throttlePct || o.r != r;
}

// ============================================================ GPS 页
class GpsPage extends StatefulWidget {
  const GpsPage({super.key});
  @override
  State<GpsPage> createState() => _GpsPageState();
}

class _GpsPageState extends State<GpsPage> {
  bool _permAsked = false;

  @override
  void initState() {
    super.initState();
    GnssService.I.addListener(_u);
    WidgetsBinding.instance.addPostFrameCallback((_) => _ensure());
  }

  void _u() {
    if (mounted) setState(() {});
  }

  Future<void> _ensure() async {
    if (_permAsked && GnssService.I.running) return;
    _permAsked = true;
    final st = await Permission.locationWhenInUse.request();
    if (st.isGranted || st.isLimited) {
      GnssService.I.start();
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('需要定位权限才能使用 GPS 真速')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final g = GnssService.I;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(children: [
          const Text('GPS 真速 / 星空图',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
          const Spacer(),
          TextButton.icon(
            onPressed: () {
              if (g.running) {
                g.stop();
              } else {
                _ensure();
              }
              setState(() {});
            },
            icon: Icon(g.running ? Icons.stop : Icons.play_arrow, size: 18),
            label: Text(g.running ? '停止' : '启动'),
          ),
        ]),
        if (g.error != null)
          Padding(
            padding: const EdgeInsets.only(top: 4, bottom: 8),
            child: Text(g.error!,
                style: const TextStyle(color: Color(0xFFFF5D5D), fontSize: 12)),
          ),
        const SizedBox(height: 8),
        Container(
          height: 340,
          decoration: BoxDecoration(
            color: const Color(0xFF0D1730),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0xFF2A3550)),
          ),
          child: CustomPaint(
            painter: SkyplotPainter(
                sats: g.satellites,
                fontFamily: DefaultTextStyle.of(context).style.fontFamily),
            child: g.satellites.isEmpty
                ? const Center(
                    child: Text('等待卫星数据…',
                        style: TextStyle(color: Color(0xFF6E82A8))))
                : null,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 4, children: [
          _chip('GPS', const Color(0xFF4DA3FF)),
          _chip('北斗 BDS', const Color(0xFFFF9A8B)),
          _chip('GLO', const Color(0xFFFFD479)),
          _chip('GAL', const Color(0xFFB58CFF)),
          _chip('实心=参与定位', const Color(0xFFEAF3FF)),
        ]),
        const SizedBox(height: 16),
        Row(children: [
          Expanded(
              child: _ValCard(
                  label: 'GPS 真速',
                  value: g.gpsSpeedKmh.toStringAsFixed(1),
                  unit: 'km/h',
                  color: const Color(0xFF8FF0C0),
                  sub: g.fixText)),
          const SizedBox(width: 12),
          Expanded(
              child: _ValCard(
                  label: '方位',
                  value:
                      g.bearing == null ? '--' : g.bearing!.toStringAsFixed(0),
                  unit: '°',
                  color: const Color(0xFF7FC4FF),
                  sub: g.bearing == null ? '--' : _dir(g.bearing!))),
        ]),
        const SizedBox(height: 12),
        _card('位置', [
          _row('纬度',
              g.lat == 0 && g.lon == 0 ? '--' : '${g.lat.toStringAsFixed(6)}°'),
          _row('经度',
              g.lat == 0 && g.lon == 0 ? '--' : '${g.lon.toStringAsFixed(6)}°'),
          _row('海拔', g.alt == null ? '--' : '${g.alt!.toStringAsFixed(1)} m'),
          _row('水平精度',
              g.accuracy == null ? '--' : '±${g.accuracy!.toStringAsFixed(1)} m'),
          _row('卫星', '${g.usedCount} 用于定位 / 共 ${g.satCount}'),
          _row('星座分布',
              g.byConst.entries.map((e) => '${e.key}:${e.value}').join('  ')),
        ]),
        const SizedBox(height: 14),
        _card('卫星列表', [
          if (g.satellites.isEmpty)
            const Text('--', style: TextStyle(color: Color(0xFF6E82A8)))
          else
            ...g.satellites.map((s) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: _constColor(s.constellation)),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(
                        width: 62,
                        child: Text('${s.constellation} ${s.svid}',
                            style: const TextStyle(fontSize: 12.5))),
                    Expanded(
                      child: Text(
                        '方位 ${s.az.toStringAsFixed(0)}°  仰角 ${s.el.toStringAsFixed(0)}°',
                        style: const TextStyle(
                            fontSize: 11, color: Color(0xFF8EA0C4)),
                      ),
                    ),
                    Text('${s.cn0.toStringAsFixed(0)} dB',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: s.used
                              ? const Color(0xFF8FF0C0)
                              : const Color(0xFF8EA0C4),
                        )),
                    if (s.used) ...[
                      const SizedBox(width: 6),
                      const Icon(Icons.check_circle,
                          size: 13, color: Color(0xFF35D07F)),
                    ],
                  ]),
                )),
        ]),
        const SizedBox(height: 24),
      ],
    );
  }

  static Color _constColor(String c) {
    switch (c) {
      case 'GPS':
        return const Color(0xFF4DA3FF);
      case 'BDS':
        return const Color(0xFFFF9A8B);
      case 'GLO':
        return const Color(0xFFFFD479);
      case 'GAL':
        return const Color(0xFFB58CFF);
      case 'QZSS':
        return const Color(0xFF6EE7F0);
      default:
        return const Color(0xFF8EA0C4);
    }
  }

  static String _dir(double b) {
    const d = ['北', '东北', '东', '东南', '南', '西南', '西', '西北'];
    return d[((b + 22.5) ~/ 45) % 8];
  }

  Widget _chip(String t, Color c) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: const Color(0xFF172033),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xFF2A3550)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(shape: BoxShape.circle, color: c)),
          const SizedBox(width: 5),
          Text(t, style: const TextStyle(fontSize: 11)),
        ]),
      );

  Widget _row(String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(children: [
          Text(k,
              style: const TextStyle(color: Color(0xFF8EA0C4), fontSize: 13)),
          const Spacer(),
          Flexible(
              child: Text(v,
                  textAlign: TextAlign.right,
                  style: const TextStyle(
                      fontWeight: FontWeight.w600, fontSize: 13))),
        ]),
      );

  Widget _card(String t, List<Widget> ch) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFF172033),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFF2A3550)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(t,
                style:
                    const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
            const SizedBox(height: 10),
            ...ch,
          ],
        ),
      );
}

/// 卫星星空图（极坐标）：圆心=天顶，外圈=地平
class SkyplotPainter extends CustomPainter {
  final List<Sat> sats;
  /// 同 SpeedometerPainter：字体族外部注入
  final String? fontFamily;
  SkyplotPainter({required this.sats, this.fontFamily});

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2 + 6;
    final r = math.min(size.width, size.height) / 2 - 34;

    for (final f in [1.0, 0.66, 0.33]) {
      canvas.drawCircle(
          Offset(cx, cy),
          r * f,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1
            ..color = const Color(0xFF233052));
    }
    final grid = Paint()
      ..color = const Color(0xFF233052)
      ..strokeWidth = 1;
    canvas.drawLine(Offset(cx - r, cy), Offset(cx + r, cy), grid);
    canvas.drawLine(Offset(cx, cy - r), Offset(cx, cy + r), grid);

    void label(String t, double a) {
      final tp = TextPainter(
        text: TextSpan(
            text: t,
            style: TextStyle(
                color: const Color(0xFF6E82A8),
                fontSize: 12,
                fontWeight: FontWeight.w600,
                fontFamily: fontFamily)),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(
          canvas,
          Offset(cx + math.sin(a) * (r + 14) - tp.width / 2,
              cy - math.cos(a) * (r + 14) - tp.height / 2));
    }

    label('北', 0);
    label('东', math.pi / 2);
    label('南', math.pi);
    label('西', -math.pi / 2);
    // 仰角刻度
    final tp0 = TextPainter(
        text: TextSpan(
            text: '30° 60°',
            style: TextStyle(
                color: const Color(0xFF3A4A70),
                fontSize: 9,
                fontFamily: fontFamily)),
        textDirection: TextDirection.ltr)
      ..layout();
    tp0.paint(canvas, Offset(cx + 4, cy - r * 0.66 - 12));

    for (final s in sats) {
      final az = s.az * math.pi / 180;
      final el = s.el.clamp(0, 90) * math.pi / 180;
      final rr = r * (1 - el / (math.pi / 2));
      final x = cx + math.sin(az) * rr;
      final y = cy - math.cos(az) * rr;

      Color c;
      switch (s.constellation) {
        case 'GPS':
          c = const Color(0xFF4DA3FF);
          break;
        case 'BDS':
          c = const Color(0xFFFF9A8B);
          break;
        case 'GLO':
          c = const Color(0xFFFFD479);
          break;
        case 'GAL':
          c = const Color(0xFFB58CFF);
          break;
        case 'QZSS':
          c = const Color(0xFF6EE7F0);
          break;
        default:
          c = const Color(0xFF8EA0C4);
      }
      final rad = 5.0 + s.strength * 7.0;
      canvas.drawCircle(Offset(x, y), rad + 3,
          Paint()..color = c.withValues(alpha: 0.18));
      canvas.drawCircle(Offset(x, y), rad,
          Paint()..color = s.used ? c : c.withValues(alpha: 0.42));
      if (s.used) {
        canvas.drawCircle(
            Offset(x, y),
            rad,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1.6
              ..color = const Color(0xFFEAF3FF));
      }
      final tp = TextPainter(
        text: TextSpan(
            text: '${s.svid}',
            style: TextStyle(
                fontSize: 8.5,
                color: const Color(0xFF0C1220),
                fontWeight: FontWeight.w800,
                fontFamily: fontFamily)),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(x - tp.width / 2, y - tp.height / 2));
    }
  }

  @override
  bool shouldRepaint(covariant SkyplotPainter o) => true;
}
