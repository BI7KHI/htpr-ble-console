// GNSS 服务：接收原生 GnssStatus 数据流
// 位置(经纬度/海拔/真速/方位/精度) + 卫星星空图数据(方位角/仰角/载噪比)
import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class Sat {
  final int svid;
  final String constellation;
  final double az; // 方位角 0-360，0=正北
  final double el; // 仰角 0-90，90=天顶
  final double cn0; // 载噪比 dB-Hz
  final bool used; // 是否参与定位
  Sat({
    required this.svid,
    required this.constellation,
    required this.az,
    required this.el,
    required this.cn0,
    required this.used,
  });

  /// 信号强度 0..1（20dB 以下算很弱，45dB 以上算很好）
  double get strength => ((cn0 - 20) / 25).clamp(0.0, 1.0);

  static Sat fromJson(Map<String, dynamic> j) => Sat(
        svid: (j['svid'] as num?)?.toInt() ?? 0,
        constellation: (j['const'] ?? '?').toString(),
        az: (j['az'] as num?)?.toDouble() ?? 0,
        el: (j['el'] as num?)?.toDouble() ?? 0,
        cn0: (j['cn0'] as num?)?.toDouble() ?? 0,
        used: j['used'] == true,
      );
}

class GnssService extends ChangeNotifier {
  static final GnssService I = GnssService._();
  GnssService._();

  static const _channel = EventChannel('htpr/gnss/stream');
  StreamSubscription? _sub;

  bool running = false;
  String? error;

  double lat = 0, lon = 0;
  double? alt;
  double gpsSpeedMs = 0; // 真速 m/s
  double? bearing; // 方位角
  double? accuracy; // 水平精度 m
  int lastFixMs = 0;

  List<Sat> satellites = [];
  int satCount = 0;
  int usedCount = 0;

  /// GPS 真速 km/h
  double get gpsSpeedKmh => gpsSpeedMs * 3.6;

  /// 定位质量
  bool get hasFix => usedCount >= 3 || (accuracy != null && accuracy! < 50);
  String get fixText {
    if (usedCount == 0 && lastFixMs == 0) return '未定位';
    if (usedCount < 3) return '搜星中 (\$usedCount 颗)';
    if (accuracy == null) return '已定位';
    if (accuracy! <= 5) return '极佳 ±${accuracy!.toStringAsFixed(1)}m';
    if (accuracy! <= 10) return '良好 ±${accuracy!.toStringAsFixed(1)}m';
    if (accuracy! <= 30) return '一般 ±${accuracy!.toStringAsFixed(1)}m';
    return '较差 ±${accuracy!.toStringAsFixed(0)}m';
  }

  /// 北斗/GPS/GLONASS/伽利略 分类计数
  Map<String, int> get byConst {
    final m = <String, int>{};
    for (final s in satellites) {
      m[s.constellation] = (m[s.constellation] ?? 0) + 1;
    }
    return m;
  }

  void start() {
    if (running) return;
    running = true;
    _sub = _channel.receiveBroadcastStream().listen((ev) {
      try {
        final j = jsonDecode(ev.toString()) as Map<String, dynamic>;
        if (j['error'] != null) {
          error = j['error'].toString();
          notifyListeners();
          return;
        }
        error = null;
        if (j['lat'] != null) {
          lat = (j['lat'] as num).toDouble();
          lon = (j['lon'] as num).toDouble();
          alt = (j['alt'] as num?)?.toDouble();
          gpsSpeedMs = (j['speed'] as num?)?.toDouble() ?? 0;
          bearing = (j['bearing'] as num?)?.toDouble();
          accuracy = (j['acc'] as num?)?.toDouble();
          lastFixMs = (j['time'] as num?)?.toInt() ?? 0;
        }
        if (j['sats'] != null) {
          final list = (j['sats'] as List)
              .map((e) => Sat.fromJson(Map<String, dynamic>.from(e as Map)))
              .toList();
          satellites = list;
          satCount = (j['count'] as num?)?.toInt() ?? list.length;
          usedCount = (j['usedCount'] as num?)?.toInt() ?? 0;
        }
        notifyListeners();
      } catch (_) {}
    }, onError: (e) {
      error = '$e';
      notifyListeners();
    });
  }

  void stop() {
    _sub?.cancel();
    _sub = null;
    running = false;
  }
}
