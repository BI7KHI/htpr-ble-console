// 统计页 + 设置页
import 'package:flutter/material.dart';

import 'app_state.dart';
import 'ble_service.dart';
import 'htpr_protocol.dart';

// ============================================================ 统计页
class StatsPage extends StatefulWidget {
  const StatsPage({super.key});
  @override
  State<StatsPage> createState() => _StatsPageState();
}

class _StatsPageState extends State<StatsPage> {
  @override
  void initState() {
    super.initState();
    AppState.I.addListener(_u);
  }

  void _u() {
    if (mounted) setState(() {});
  }

  String _dur(Duration d) {
    final h = d.inHours, m = d.inMinutes % 60, s = d.inSeconds % 60;
    return h > 0
        ? '${h}h${m.toString().padLeft(2, '0')}m'
        : '${m}m${s.toString().padLeft(2, '0')}s';
  }

  @override
  Widget build(BuildContext context) {
    final s = AppState.I;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(children: [
          const Text('行驶统计',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
          const Spacer(),
          TextButton.icon(
            onPressed: () => AppState.I.resetTrip(),
            icon: const Icon(Icons.refresh, size: 18),
            label: const Text('清零本次'),
          ),
        ]),
        const SizedBox(height: 4),
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: 1.6,
          children: [
            _st('本次里程', s.tripKm.toStringAsFixed(2), 'km'),
            _st('累计里程', s.totalKm.toStringAsFixed(2), 'km'),
            _st('最高时速', s.maxSpeed.toStringAsFixed(1), 'km/h'),
            _st('平均时速', s.avgSpeed.toStringAsFixed(1), 'km/h'),
            _st('运行时长', _dur(s.runTime), ''),
            _st('累计能耗', s.energyWh.toStringAsFixed(1), 'Wh'),
          ],
        ),
        const SizedBox(height: 18),
        const Text('实时曲线',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        Container(
          height: 230,
          padding: const EdgeInsets.fromLTRB(8, 14, 14, 8),
          decoration: BoxDecoration(
            color: const Color(0xFF172033),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFF2A3550)),
          ),
          child: CustomPaint(
            painter: LineChartPainter(series: [
              ChartSeries(s.history.map((e) => e.speed).toList(),
                  const Color(0xFF4DA3FF), '时速'),
              ChartSeries(s.history.map((e) => e.voltage).toList(),
                  const Color(0xFFFFD479), '电压'),
            ], fontFamily: DefaultTextStyle.of(context).style.fontFamily),
          ),
        ),
        const SizedBox(height: 10),
        const Row(children: [
          _Legend(color: Color(0xFF4DA3FF), text: '时速 km/h'),
          SizedBox(width: 18),
          _Legend(color: Color(0xFFFFD479), text: '电压 V'),
        ]),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFF172033),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFF2A3550)),
          ),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('电量 / 续航',
                style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            _row('当前 SOC', '${s.socPct.toStringAsFixed(1)}%'),
            _row('当前电压', '${s.voltage.toStringAsFixed(2)} V'),
            _row('单体电压',
                '${(s.cellCount > 0 ? s.voltage / s.cellCount : 0).toStringAsFixed(3)} V'),
            _row('实时功率', '${(s.voltage * s.current).toStringAsFixed(0)} W'),
            _row('估算续航', '${s.rangeKm.toStringAsFixed(1)} km'),
          ]),
        ),
      ],
    );
  }

  Widget _row(String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(children: [
          Text(k,
              style: const TextStyle(color: Color(0xFF8EA0C4), fontSize: 13)),
          const Spacer(),
          Text(v,
              style:
                  const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
        ]),
      );

  Widget _st(String label, String v, String unit) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFF172033),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFF2A3550)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(label,
                style:
                    const TextStyle(color: Color(0xFF8EA0C4), fontSize: 12.5)),
            const SizedBox(height: 2),
            Text.rich(TextSpan(children: [
                TextSpan(
                    text: v,
                    style: const TextStyle(
                        fontSize: 25, fontWeight: FontWeight.w700)),
                TextSpan(
                    text: ' $unit',
                    style: const TextStyle(
                        fontSize: 12, color: Color(0xFF8EA0C4))),
              ]),
            ),
          ],
        ),
      );
}

class _Legend extends StatelessWidget {
  final Color color;
  final String text;
  const _Legend({required this.color, required this.text});
  @override
  Widget build(BuildContext context) => Row(children: [
        Container(width: 14, height: 3, color: color),
        const SizedBox(width: 6),
        Text(text,
            style: const TextStyle(fontSize: 12, color: Color(0xFF8EA0C4))),
      ]);
}

class ChartSeries {
  final List<double> data;
  final Color color;
  final String name;
  ChartSeries(this.data, this.color, this.name);
}

class LineChartPainter extends CustomPainter {
  final List<ChartSeries> series;
  /// 字体族由外部注入（CustomPainter 取不到 Theme）
  final String? fontFamily;
  LineChartPainter({required this.series, this.fontFamily});

  @override
  void paint(Canvas canvas, Size sz) {
    final grid = Paint()
      ..color = const Color(0xFF243050)
      ..strokeWidth = 1;
    for (int i = 0; i <= 4; i++) {
      final y = sz.height * i / 4;
      canvas.drawLine(Offset(0, y), Offset(sz.width, y), grid);
    }
    const leftPad = 40.0;
    final w = sz.width - leftPad;
    int si = 0;
    for (final s in series) {
      if (s.data.length < 2) {
        si++;
        continue;
      }
      double mx = 0;
      for (final v in s.data) {
        if (v > mx) mx = v;
      }
      if (mx <= 0) mx = 1;
      mx *= 1.15;
      final path = Path();
      for (int i = 0; i < s.data.length; i++) {
        final x = leftPad + w * (i / (s.data.length - 1));
        final y = sz.height - (s.data[i] / mx) * sz.height;
        if (i == 0) {
          path.moveTo(x, y);
        } else {
          path.lineTo(x, y);
        }
      }
      canvas.drawPath(
          path,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2
            ..color = s.color);
      final tp = TextPainter(
        text: TextSpan(
            text: mx.toStringAsFixed(0),
            style: TextStyle(
                color: s.color, fontSize: 10.5, fontFamily: fontFamily)),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(2, 2 + si * 14));
      si++;
    }
  }

  @override
  bool shouldRepaint(covariant LineChartPainter old) => true;
}

// ============================================================ 设置页
class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});
  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {

  @override
  void initState() {
    super.initState();
    AppState.I.addListener(_u);
    BleService.I.addListener(_u);
  }

  void _u() {
    if (mounted) setState(() {});
  }

  Future<void> _do(Future<void> Function() f) async {
    try {
      await f();
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('已下发')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('失败: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppState.I;
    final b = BleService.I;
    final d = b.dashboard;
    final r = b.realtime;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // ---------------- 速度方式 / 在线标定 ----------------
        _card('速度方式', [
          const Text(
            '控制器转速字段在「松油门滑行」时不更新（官方小程序同样为 0，属固件限制）。'
            '因此：驱动时用转速（低延迟、隧道可用），松油门立刻转 GNSS 真速；'
            '同时用 GPS 作为真值在线反标定转速→速度的映射。',
            style: TextStyle(color: Color(0xFF8EA0C4), fontSize: 11.5),
          ),
          const SizedBox(height: 10),
          SegmentedButton<SpeedMode>(
            segments: const [
              ButtonSegment(
                  value: SpeedMode.gps, label: Text('GPS'), icon: Icon(Icons.gps_fixed, size: 16)),
              ButtonSegment(
                  value: SpeedMode.fusion, label: Text('融合'), icon: Icon(Icons.merge_type, size: 16)),
              ButtonSegment(
                  value: SpeedMode.rpm, label: Text('转速'), icon: Icon(Icons.sync, size: 16)),
            ],
            selected: {s.speedMode},
            onSelectionChanged: (v) => setState(() {
              s.speedMode = v.first;
              s.save();
            }),
          ),
          const SizedBox(height: 8),
          Text(
            s.speedMode == SpeedMode.gps
                ? 'GPS：纯 GNSS 真速，无定位时回退转速'
                : (s.speedMode == SpeedMode.fusion
                    ? '融合（推荐）：驱动用转速，松油门/滑行自动切 GNSS'
                    : '转速：仅用转速推算（已由 GPS 在线标定）'),
            style: const TextStyle(color: Color(0xFF6E82A8), fontSize: 11),
          ),
          const Divider(height: 24),
          _rowInfo('标定状态',
              s.calibrated ? '已标定 (${s.calibSamples} 样本)' : '未标定 (${s.calibSamples} 样本)'),
          _rowInfo('当前系数 K',
              '${s.effectiveK.toStringAsFixed(6)} km/h per raw'),
          _rowInfo('出厂系数 K0', '${s.factoryK.toStringAsFixed(6)} km/h per raw'),
          _rowInfo('比例 K/K0',
              s.factoryK > 0 ? '× ${(s.effectiveK / s.factoryK).toStringAsFixed(3)}' : '--'),
          const SizedBox(height: 4),
          const Text(
            '标定条件：驱动中(油门>12%) + GPS精度<20m + 速度>3km/h，'
            '采用过原点最小二乘拟合，自动剔除离群点。跑几次带 GPS 的骑行即可收敛。',
            style: TextStyle(color: Color(0xFF6E82A8), fontSize: 10.5),
          ),
          const SizedBox(height: 6),
          Row(children: [
            OutlinedButton.icon(
              onPressed: () => setState(() => s.resetCalibration()),
              icon: const Icon(Icons.restart_alt, size: 18),
              label: const Text('重置标定'),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Align(
                alignment: Alignment.centerLeft,
                child: Chip(
                  avatar: const Icon(Icons.sensors, size: 15),
                  label: Text('来源 ${s.speedSource} · ${s.speedSourceNote}',
                      style: const TextStyle(fontSize: 11.5)),
                ),
              ),
            ),
          ]),
        ]),
        const SizedBox(height: 14),

        // ---------------- 连接 ----------------
        _card('连接', [
          TextFormField(
            initialValue: s.deviceAddress,
            decoration: const InputDecoration(
              labelText: '蓝牙地址',
              hintText: '留空则按名称「恒泰普瑞」扫描',
              border: OutlineInputBorder(),
              isDense: true,
            ),
            onChanged: (v) {
              s.deviceAddress = v.trim();
              s.save();
            },
          ),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(
              child: FilledButton.icon(
                onPressed: () => b.connect(address: s.deviceAddress),
                icon: const Icon(Icons.bluetooth),
                label: const Text('连接'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => b.disconnect(),
                icon: const Icon(Icons.bluetooth_disabled),
                label: const Text('断开'),
              ),
            ),
          ]),
          const SizedBox(height: 6),
          const Text('模块只允许单连接。若手机小程序连着，请先在小程序里断开。',
              style: TextStyle(color: Color(0xFF6E82A8), fontSize: 11.5)),
        ]),
        const SizedBox(height: 14),

        // ---------------- 三档 / 超速 ----------------
        _card('三档限速 / 强制超速', [
          _rowInfo('当前 motion1', '${r?.motion1 ?? '--'}'),
          _rowInfo('当前 motion2', '${r?.motion2 ?? '--'}'),
          _rowInfo('当前 motion3', '${d?.motion3 ?? '--'}'),
          const Divider(height: 22),
          const Text('低速档 motion1',
              style: TextStyle(fontSize: 13, color: Color(0xFF8EA0C4))),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: List.generate(
                8,
                (i) => ChoiceChip(
                      label: Text('${i + 1}'),
                      selected: (r?.motion1 ?? -1) == i + 1,
                      onSelected: (_) => _do(() => b.setGears(motion1: i + 1)),
                    )),
          ),
          const SizedBox(height: 12),
          const Text('中速档 motion2',
              style: TextStyle(fontSize: 13, color: Color(0xFF8EA0C4))),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: List.generate(
                8,
                (i) => ChoiceChip(
                      label: Text('${i + 1}'),
                      selected: (r?.motion2 ?? -1) == i + 1,
                      onSelected: (_) => _do(() => b.setGears(motion2: i + 1)),
                    )),
          ),
          const SizedBox(height: 12),
          const Text('高速档 motion3',
              style: TextStyle(fontSize: 13, color: Color(0xFF8EA0C4))),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: List.generate(
                10,
                (i) => ChoiceChip(
                      label: Text('$i'),
                      selected: (d?.motion3 ?? -1) == i,
                      onSelected: (_) => _do(() => b.setGears(motion3: i)),
                    )),
          ),
          const Divider(height: 26),
          Material(
            color: Colors.transparent,
            child: SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('强制超速',
                  style: TextStyle(fontWeight: FontWeight.w600)),
              subtitle: const Text('功能字 bit9。开启后可突破限速，务必注意安全',
                  style: TextStyle(fontSize: 11.5)),
              value: d == null
                  ? false
                  : HtprProtocol.overspeedEnabled(d.funcSettings),
              onChanged: d == null ? null : (v) => _do(() => b.setOverspeed(v)),
            ),
          ),
        ]),
        const SizedBox(height: 14),

        // ---------------- 速度标定 ----------------
        _card('速度标定（27.5 寸轮组）', [
          _rowInfo('轮径', '${s.wheelInch.toStringAsFixed(1)} 英寸'),
          Slider(
            value: s.wheelInch,
            min: 12,
            max: 32,
            divisions: 80,
            label: '${s.wheelInch.toStringAsFixed(1)}"',
            onChanged: (v) => setState(() => s.wheelInch = v),
            onChangeEnd: (_) => s.save(),
          ),
          Wrap(spacing: 8, children: [
            for (final e in AppState.presetWheels.entries)
              ChoiceChip(
                label: Text(e.key),
                selected: (s.wheelInch - e.value).abs() < 0.05,
                onSelected: (_) {
                  setState(() => s.wheelInch = e.value);
                  s.save();
                },
              ),
          ]),
          const SizedBox(height: 10),
          _rowInfo('轮周长', '${s.wheelCircumferenceMm.toStringAsFixed(0)} mm'),
          _rowInfo('转速系数 a', s.rpmDivider.toStringAsFixed(0)),
          Slider(
            value: s.rpmDivider,
            min: 1,
            max: 60,
            divisions: 59,
            label: s.rpmDivider.toStringAsFixed(0),
            onChanged: (v) => setState(() => s.rpmDivider = v),
            onChangeEnd: (_) => s.save(),
          ),
          _rowInfo('速度微调', '× ${s.speedFactor.toStringAsFixed(2)}'),
          Slider(
            value: s.speedFactor,
            min: 0.5,
            max: 1.5,
            divisions: 100,
            label: '×${s.speedFactor.toStringAsFixed(2)}',
            onChanged: (v) => setState(() => s.speedFactor = v),
            onChangeEnd: (_) => s.save(),
          ),
          const Divider(height: 22),
          _rowInfo('仪表满量程', '${s.gaugeMax.toStringAsFixed(0)} km/h'),
          const SizedBox(height: 4),
          Wrap(
            spacing: 8,
            children: [
              for (final v in const [40.0, 60.0, 80.0, 100.0, 120.0])
                ChoiceChip(
                  label: Text(v.toStringAsFixed(0)),
                  selected: (s.gaugeMax - v).abs() < 0.5,
                  onSelected: (_) {
                    setState(() => s.gaugeMax = v);
                    s.save();
                  },
                ),
            ],
          ),
          const SizedBox(height: 6),
          const Text(
            '校准：控制器速度请用 GPS 实测对照微调；GPS 真速本身无需标定。',
            style: TextStyle(color: Color(0xFF6E82A8), fontSize: 11.5),
          ),
        ]),
        const SizedBox(height: 14),

        // ---------------- 油门 / 电池 ----------------
        _card('油门 / 电池标定', [
          _rowInfo('转把最低电压 (0%)', '${s.throttleMin.toStringAsFixed(2)} V'),
          Slider(
            value: s.throttleMin,
            min: 0,
            max: 2,
            divisions: 200,
            onChanged: (v) => setState(() => s.throttleMin = v),
            onChangeEnd: (_) => s.save(),
          ),
          _rowInfo('转把最高电压 (100%)', '${s.throttleMax.toStringAsFixed(2)} V'),
          Slider(
            value: s.throttleMax,
            min: 2,
            max: 5,
            divisions: 300,
            onChanged: (v) => setState(() => s.throttleMax = v),
            onChangeEnd: (_) => s.save(),
          ),
          const Divider(height: 22),
          _rowInfo('电池串数', '${s.cellCount} S'),
          Slider(
            value: s.cellCount.toDouble(),
            min: 6,
            max: 24,
            divisions: 18,
            label: '${s.cellCount}S',
            onChanged: (v) => setState(() => s.cellCount = v.round()),
            onChangeEnd: (_) => s.save(),
          ),
          _rowInfo('单体 0%', '${s.cellMin.toStringAsFixed(2)} V'),
          Slider(
            value: s.cellMin,
            min: 2.5,
            max: 3.6,
            divisions: 110,
            onChanged: (v) => setState(() => s.cellMin = v),
            onChangeEnd: (_) => s.save(),
          ),
          _rowInfo('单体 100%', '${s.cellMax.toStringAsFixed(2)} V'),
          Slider(
            value: s.cellMax,
            min: 3.8,
            max: 4.3,
            divisions: 50,
            onChanged: (v) => setState(() => s.cellMax = v),
            onChangeEnd: (_) => s.save(),
          ),
          const SizedBox(height: 4),
          const Text('默认 12 串三元锂：3.00V(0%) ~ 4.20V(100%)',
              style: TextStyle(color: Color(0xFF6E82A8), fontSize: 11.5)),
        ]),
        const SizedBox(height: 14),

        _card('数据', [
          Row(children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => AppState.I.resetTrip(),
                icon: const Icon(Icons.restore, size: 18),
                label: const Text('清零本次'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () {
                  AppState.I.totalKm = 0;
                  AppState.I.save();
                },
                icon: const Icon(Icons.delete_outline, size: 18),
                label: const Text('清零总里程'),
              ),
            ),
          ]),
          TextButton(
            onPressed: () => BleService.I.clearLog(),
            child: const Text('清空日志'),
          ),
        ]),
        const SizedBox(height: 14),

        _card('关于', [
          _rowInfo('应用', '恒泰普瑞控制台'),
          _rowInfo('版本', 'v6.0 (Android)'),
          _rowInfo('包名', 'com.htpr.htpr_console'),
          _rowInfo('目标设备', '恒泰普瑞 HTPR 控制器 · BLE NUS'),
          _rowInfo('通信协议', 'NUS 透传 · 67 字节定长加密帧'),
          _rowInfo('开源许可', 'MIT License'),
          const SizedBox(height: 10),
          const Text(
            '适用场景',
            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
          ),
          const SizedBox(height: 4),
          const Text(
            '电动自行车 / 电动滑板车 / 轮毂电机控制器的近场调试与骑行仪表。'
            '手机通过 BLE 直连控制器，实时读取电压、电流、电机转速与转把电压，'
            '并以半圆仪表呈现时速；同时可下发三档限速与强制超速指令，'
            '配套 GPS 在环标定让转速换算时速逼近真值。',
            style: TextStyle(
                color: Color(0xFF8EA0C4), fontSize: 11.5, height: 1.55),
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFF2A1B1B),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFF5A2E2E)),
            ),
            child: const Row(children: [
              Icon(Icons.warning_amber_rounded,
                  size: 16, color: Color(0xFFFFB4A8)),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  '安全提示：强制超速会绕过出厂限速，仅限封闭场地调试。'
                  '修改档位或超速前请抬起车轮，确认场地无人无车。',
                  style: TextStyle(
                      color: Color(0xFFFFB4A8), fontSize: 11, height: 1.45),
                ),
              ),
            ]),
          ),
          const SizedBox(height: 12),
          const Row(children: [
            Icon(Icons.code, size: 15, color: Color(0xFF7E92B8)),
            SizedBox(width: 8),
            Expanded(
              child: SelectableText(
                'https://github.com/BI7KHI/htpr-ble-console',
                style: TextStyle(fontSize: 11.5, color: Color(0xFF7FC4FF)),
              ),
            ),
          ]),
        ]),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _rowInfo(String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(children: [
          Expanded(
            child: Text(k,
                style: const TextStyle(
                    color: Color(0xFF8EA0C4), fontSize: 12.5)),
          ),
          Text(v,
              style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                  color: Color(0xFFEAF3FF))),
        ]),
      );

  Widget _card(String title, List<Widget> children) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFF172033),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFF2A3550)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style:
                    const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
            const SizedBox(height: 12),
            ...children,
          ],
        ),
      );
}
