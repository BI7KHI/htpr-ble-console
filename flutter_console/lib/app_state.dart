// 应用状态：标定参数、油门/电量换算、里程与时速统计
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'ble_service.dart';
import 'gnss_service.dart';

/// 速度来源方式
enum SpeedMode {
  gps,    // 纯 GNSS 真速
  fusion, // 融合：驱动时用转速(低延迟/隧道可用)，松油门后转 GNSS
  rpm,    // 纯转速推算（用 GPS 在线标定）
}

/// 速度来源分类（用于 UI 着色与文案）
enum SpeedSrc { gnss, rpm, none }

class Sample {
  final DateTime t;
  final double speed; // km/h
  final double voltage; // V
  final double current; // A
  Sample(this.t, this.speed, this.voltage, this.current);
}

class AppState extends ChangeNotifier {
  static final AppState I = AppState._();
  AppState._();

  // ---------------- 标定参数 ----------------
  double wheelInch = 27.5; // 轮径（英寸）27.5
  double rpmDivider = 25.0; // 官方 app 的转速系数 a
  double speedFactor = 1.0; // 速度微调系数
  double throttleMin = 0.8; // 转把最低电压
  double throttleMax = 4.2; // 转把最高电压
  int cellCount = 12; // 12 串
  double cellMin = 3.00; // 单体放电截止
  double cellMax = 4.20; // 单体充满
  String deviceAddress = 'D0:0C:5E:53:31:C0';

  // ---------------- 实时量 ----------------
  double voltage = 0, throttleV = 0, current = 0, rpm = 0;
  double throttlePct = 0, socPct = 0;

  /// 控制器推算时速（电机转速换算；带单向离合的轮毂滑行时会归零）
  double controllerSpeed = 0;
  /// GPS 真速 km/h
  double gpsSpeed = 0;
  /// 当前主速度（显示用，已按模式融合/平滑）
  double speed = 0;
  /// 速度来源短标签：GNSS / 转速 / 无
  String speedSource = '无';
  /// 来源补充说明（如「驱动中 · 低延迟」）
  String speedSourceNote = '等待数据';
  /// 当前是否处于滑行（油门松开或转速掉零）→ 融合模式改用 GNSS
  bool isCoasting = false;
  /// 仪表满量程 km/h
  double gaugeMax = 80;

  /// 速度方式（默认融合）
  SpeedMode speedMode = SpeedMode.fusion;

  /// 控制器转速原始值 BE(21,22)
  double rotRaw = 0;

  // ===== 在线动态标定：用 GPS 作真值反标定转速映射 =====
  // 模型：speed(km/h) = calibK * rotRaw
  double calibK = 0; // 0 表示尚未标定
  int calibSamples = 0;
  double _sumXY = 0.0;
  double _sumXX = 0.0;

  // —— 显示速度平滑 ——
  DateTime? _sfAt;
  double _hold = 0;
  int _zeroFrames = 0;


  // ---------------- 统计 ----------------
  double tripKm = 0; // 本次里程
  double totalKm = 0; // 累计里程
  double maxSpeed = 0;
  double _speedSum = 0;
  int _speedN = 0;
  Duration runTime = Duration.zero;
  double energyWh = 0;
  final List<Sample> history = [];
  DateTime? _lastTick;


  // ---------------- 初始化 ----------------
  Future<void> init() async {
    await load();
    BleService.I.addListener(_onBle);
    GnssService.I.addListener(_onGnss);
    Timer.periodic(const Duration(milliseconds: 200), (_) => _tick());
  }

  void _onBle() {
    final d = BleService.I.dashboard;
    final r = BleService.I.realtime;
    if (d != null) {
      voltage = d.voltage;
      throttleV = d.throttleVoltage;
      throttlePct = ((throttleV - throttleMin) / (throttleMax - throttleMin) * 100)
          .clamp(0, 100)
          .toDouble();
      final vpc = cellCount > 0 ? voltage / cellCount : 0;
      socPct = ((vpc - cellMin) / (cellMax - cellMin) * 100).clamp(0, 100).toDouble();
    }
    if (r != null) {
      current = r.ampere;
      rpm = r.rpm(rpmDivider.round()).toDouble();
      rotRaw = r.rotationalspeed.toDouble();
      controllerSpeed = effectiveK * rotRaw; // 转速推算速度
    }
    _updateCalibration();
    _pickSpeed();
    notifyListeners();
  }

  void _onGnss() {
    gpsSpeed = GnssService.I.gpsSpeedKmh; // GPS 真值（标定用 + GPS 页显示）
    notifyListeners();
  }

  /// 在线动态标定：仅在「驱动中 + GPS 良好 + 有一定速度」时采样，
  /// 用过原点最小二乘拟合 K，使 speed = K * rotRaw 逼近平滑的 GPS 真速。
  void _updateCalibration() {
    final g = GnssService.I;
    if (!g.hasFix) return;
    if ((g.accuracy ?? 999) > 20) return; // 精度太差别采
    if (gpsSpeed < 3.0) return; // 低速 GPS 噪声大
    if (throttlePct < 12) return; // 必须处于驱动状态（松油门后转速无效）
    if (rotRaw < 40) return; // 转速过小无意义
    final k = gpsSpeed / rotRaw;
    final ref = effectiveK;
    if (k < ref * 0.35 || k > ref * 3.0) return; // 离群剔除
    _sumXY += gpsSpeed * rotRaw;
    _sumXX += rotRaw * rotRaw;
    calibSamples++;
    if (_sumXX > 0) calibK = _sumXY / _sumXX;
  }

  void resetCalibration() {
    calibK = 0;
    calibSamples = 0;
    _sumXY = 0;
    _sumXX = 0;
    notifyListeners();
  }

  /// 转速推算 + 掉零保持（该字段低速时短窗口计数会间歇掉零）
  double _rpmWithHold(double v) {
    if (v > 0.3) {
      _hold = v;
      _zeroFrames = 0;
      return v;
    }
    _zeroFrames++;
    if (_hold > 0.3 && _zeroFrames <= 4) {
      _hold *= 0.85; // 惯性衰减
      return _hold;
    }
    _hold = 0;
    return 0;
  }

  /// 按当前模式计算目标速度，并做指数平滑（避免模式切换跳变）
  void _pickSpeed() {
    final now = DateTime.now();
    final dt = _sfAt == null
        ? 0.0
        : (now.difference(_sfAt!).inMilliseconds / 1000.0).clamp(0.0, 1.0);
    _sfAt = now;

    final g = GnssService.I;
    final gpsOk = g.hasFix && (g.accuracy ?? 999) < 25;
    final driving = rotRaw > 0.5; // 有转速读数 = 控制器在驱动
    // 油门完全松开（或转速掉零）→ 判为滑行，交给 GNSS
    final coasting = throttlePct < 3.0 || !driving;

    double target;
    String src, note;
    switch (speedMode) {
      case SpeedMode.gps:
        if (gpsOk) {
          target = gpsSpeed;
          src = 'GNSS';
          note = '卫星真速';
        } else {
          target = _rpmWithHold(controllerSpeed);
          src = '转速';
          note = '无定位';
        }
        break;
      case SpeedMode.rpm:
        target = _rpmWithHold(controllerSpeed);
        src = '转速';
        note = calibrated ? '已标定' : '未标定';
        break;
      case SpeedMode.fusion:
        if (!gpsOk) {
          target = _rpmWithHold(controllerSpeed);
          src = '转速';
          note = '无定位';
        } else if (coasting) {
          target = gpsSpeed; // ★ 松油门/滑行 → GNSS 真速
          src = 'GNSS';
          note = '滑行';
        } else {
          target = controllerSpeed; // ★ 驱动中 → 转速（低延迟）
          src = '转速';
          note = '驱动中';
        }
        break;
    }
    isCoasting = coasting;

    // 指数平滑：融合模式稍快，纯转速模式稍慢
    final tau = speedMode == SpeedMode.fusion ? 0.35 : 0.55;
    if (dt <= 0) {
      speed = target;
    } else {
      final a = 1 - math.exp(-dt / tau);
      speed = speed + (target - speed) * a;
    }
    speedSource = src;
    speedSourceNote = note;
  }

  /// 当前速度来源分类（UI 着色用）
  SpeedSrc get speedSrcKind => switch (speedSource) {
        'GNSS' => SpeedSrc.gnss,
        '转速' => SpeedSrc.rpm,
        _ => SpeedSrc.none,
      };

  double get circumferenceM => math.pi * wheelInch * 0.0254;

  /// 出厂/手动标定推算出的系数（未在线标定时使用）
  double get factoryK =>
      (1.0 / rpmDivider) * circumferenceM * 60.0 / 1000.0 * speedFactor;

  /// 实际生效系数：在线标定样本足够则用标定值
  double get effectiveK =>
      (calibSamples >= 6 && calibK > 0) ? calibK : factoryK;

  /// 是否已完成在线标定
  bool get calibrated => calibSamples >= 6 && calibK > 0;

  /// 单位：km/h per raw-count
  double get kPerRaw => effectiveK;

  /// 200ms 定时器：积分里程/能耗，记录曲线
  void _tick() {
    final now = DateTime.now();
    if (_lastTick != null) {
      final dt = now.difference(_lastTick!).inMilliseconds / 1000.0;
      if (BleService.I.connected && dt > 0 && dt < 3) {
        final v = speed; // 已按模式归一化
        final dkm = v * dt / 3600.0;
        tripKm += dkm;
        totalKm += dkm;
        energyWh += voltage * current * dt / 3600.0;
        runTime += Duration(milliseconds: (dt * 1000).round());
        if (v > maxSpeed) maxSpeed = v;
        if (v > 0.5) {
          _speedSum += v;
          _speedN++;
        }
        if (history.isEmpty ||
            now.difference(history.last.t).inMilliseconds >= 900) {
          history.add(Sample(now, v, voltage, current));
          if (history.length > 3600) history.removeAt(0); // 约 1 小时
        }
      }
    }
    _lastTick = now;
  }

  double get avgSpeed => _speedN == 0 ? 0 : _speedSum / _speedN;

  /// 剩余续航粗估：按「实际已用 Ah」与当前 SOC 反推
  double get rangeKm {
    if (speed < 1) return 0;
    final packWh = cellCount * 3.7 * 10.0; // 12S ~44.4V 10Ah 级别，可自行改
    return packWh * (socPct / 100.0) / 20.0; // 按 20Wh/km 估算
  }

  void resetTrip() {
    tripKm = 0;
    maxSpeed = 0;
    _speedSum = 0;
    _speedN = 0;
    runTime = Duration.zero;
    energyWh = 0;
    history.clear();
    notifyListeners();
  }

  // ---------------- 持久化 ----------------
  Future<void> load() async {
    final sp = await SharedPreferences.getInstance();
    wheelInch = sp.getDouble('wheelInch') ?? wheelInch;
    rpmDivider = sp.getDouble('rpmDivider') ?? rpmDivider;
    speedFactor = sp.getDouble('speedFactor') ?? speedFactor;
    throttleMin = sp.getDouble('throttleMin') ?? throttleMin;
    throttleMax = sp.getDouble('throttleMax') ?? throttleMax;
    cellCount = sp.getInt('cellCount') ?? cellCount;
    cellMin = sp.getDouble('cellMin') ?? cellMin;
    cellMax = sp.getDouble('cellMax') ?? cellMax;
    totalKm = sp.getDouble('totalKm') ?? 0;
    speedMode = SpeedMode.values[(sp.getInt('speedMode') ?? SpeedMode.fusion.index)
        .clamp(0, SpeedMode.values.length - 1)];
    calibK = sp.getDouble('calibK') ?? 0;
    calibSamples = sp.getInt('calibSamples') ?? 0;
    deviceAddress = sp.getString('deviceAddress') ?? deviceAddress;
    gaugeMax = sp.getDouble('gaugeMax') ?? gaugeMax;
    notifyListeners();
  }

  Future<void> save() async {
    final sp = await SharedPreferences.getInstance();
    await sp.setDouble('wheelInch', wheelInch);
    await sp.setDouble('rpmDivider', rpmDivider);
    await sp.setDouble('speedFactor', speedFactor);
    await sp.setDouble('throttleMin', throttleMin);
    await sp.setDouble('throttleMax', throttleMax);
    await sp.setInt('cellCount', cellCount);
    await sp.setDouble('cellMin', cellMin);
    await sp.setDouble('cellMax', cellMax);
    await sp.setDouble('totalKm', totalKm);
    await sp.setInt('speedMode', speedMode.index);
    await sp.setDouble('calibK', calibK);
    await sp.setInt('calibSamples', calibSamples);
    await sp.setString('deviceAddress', deviceAddress);
    await sp.setDouble('gaugeMax', gaugeMax);
    notifyListeners();
  }

  /// 依据轮径给出常用周长参考
  double get wheelCircumferenceMm => circumferenceM * 1000;

  static const Map<String, double> presetWheels = {
    '26 寸': 26.0,
    '27.5 寸': 27.5,
    '29 寸': 29.0,
    '20 寸': 20.0,
  };
}
