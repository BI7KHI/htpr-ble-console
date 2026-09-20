// BLE 服务层：连接恒泰普瑞控制器，解析帧，断线自动重连
import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';

import 'htpr_protocol.dart';

class BleService extends ChangeNotifier {
  static final BleService I = BleService._();
  BleService._();

  // ---------------- 可配置 ----------------
  String targetNamePrefix = '恒泰普瑞';
  String targetAddress = ''; // 空则按名称扫描

  // ---------------- 状态 ----------------
  bool connected = false;
  bool connecting = false;
  String? error;
  String deviceName = '';
  String deviceId = '';
  int rssi = 0;

  Dashboard? dashboard;
  Realtime? realtime;
  int frameCount = 0;
  double hz = 0;
  DateTime? lastFrameAt;

  final List<String> logs = [];
  void _log(String s) {
    final t = DateTime.now();
    final line =
        '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}:${t.second.toString().padLeft(2, '0')}  $s';
    logs.add(line);
    if (logs.length > 400) logs.removeAt(0);
  }

  BluetoothDevice? _device;
  StreamSubscription? _connSub;
  StreamSubscription? _notifySub;
  StreamSubscription? _scanSub;
  Timer? _reconnectTimer;
  bool _wantConnected = false;
  int _reconnectCount = 0;
  bool _busy = false;

  // ---------------- 权限 ----------------
  Future<bool> ensurePermissions() async {
    if (!Platform.isAndroid) return true;
    final need = <Permission>[
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
    ];
    final st = await need.request();
    final ok = st.values.every((s) => s.isGranted || s.isLimited);
    if (!ok) {
      _log('缺少蓝牙权限，请在系统设置中授予「附近的设备」权限');
      return false;
    }
    return true;
  }

  // ---------------- 连接 ----------------
  Future<void> connect({String? address}) async {
    if (address != null && address.isNotEmpty) targetAddress = address;
    if (!await ensurePermissions()) {
      error = '缺少蓝牙权限';
      notifyListeners();
      return;
    }
    _wantConnected = true;
    _reconnectCount = 0;
    await _connectFlow();
  }

  Future<void> _connectFlow() async {
    if (_busy) return;
    _busy = true;
    connecting = true;
    connected = false;
    error = null;
    notifyListeners();
    try {
      if (!await FlutterBluePlus.isSupported) {
        throw Exception('本机不支持蓝牙');
      }
      final adapter = await FlutterBluePlus.adapterState
          .firstWhere((s) => s == BluetoothAdapterState.on)
          .timeout(const Duration(seconds: 8), onTimeout: () {
        throw Exception('蓝牙未开启');
      });
      if (adapter != BluetoothAdapterState.on) {
        throw Exception('蓝牙未开启');
      }

      _log('扫描设备…');
      BluetoothDevice? dev;

      // 若已知地址，先尝试直连（设备可能在广播）
      final scanDone = Completer<void>();
      _scanSub?.cancel();
      _scanSub = FlutterBluePlus.onScanResults.listen((results) {
        for (final r in results) {
          final name = r.advertisementData.advName.isNotEmpty
              ? r.advertisementData.advName
              : r.device.platformName;
          final id = r.device.remoteId.str.toUpperCase();
          final addrHit = targetAddress.isNotEmpty &&
              id == targetAddress.toUpperCase();
          final nameHit = name.startsWith(targetNamePrefix);
          if (addrHit || (targetAddress.isEmpty && nameHit)) {
            dev = r.device;
            rssi = r.rssi;
            deviceName = name;
            if (!scanDone.isCompleted) scanDone.complete();
            return;
          }
        }
      });

      await FlutterBluePlus.startScan(timeout: const Duration(seconds: 20));
      try {
        await scanDone.future.timeout(const Duration(seconds: 20));
      } catch (_) {}
      await FlutterBluePlus.stopScan();
      await _scanSub?.cancel();
      _scanSub = null;

      if (dev == null) {
        throw Exception('未发现设备（可能已被手机小程序占用，请先在小程序里断开）');
      }

      deviceId = dev!.remoteId.str;
      _log('发现 $deviceName ($deviceId)  RSSI=$rssi');
      await _connectDevice(dev!);
    } catch (e) {
      error = '$e';
      _log('连接失败: $e');
      connected = false;
      _scheduleReconnect();
    } finally {
      _busy = false;
      connecting = false;
      notifyListeners();
    }
  }

  Future<void> _connectDevice(BluetoothDevice dev) async {
    _device = dev;
    await _connSub?.cancel();
    _connSub = dev.connectionState.listen((s) {
      final isConn = s == BluetoothConnectionState.connected;
      if (connected != isConn) {
        connected = isConn;
        if (!isConn) {
          _log('⚠ 连接断开');
          if (_wantConnected) _scheduleReconnect();
        }
        notifyListeners();
      }
    });

    _log('连接中…');
    await dev.connect(
        timeout: const Duration(seconds: 20),
        license: License.nonprofit,
        autoConnect: false);
    connected = dev.isConnected;
    _reconnectCount = 0;
    _log('已连接，发现服务…');

    final services = await dev.discoverServices();
    BluetoothCharacteristic? tx;
    for (final s in services) {
      if (s.uuid.str.toLowerCase() == HtprProtocol.nusService) {
        for (final c in s.characteristics) {
          if (c.uuid.str.toLowerCase() == HtprProtocol.nusNotifyChar) tx = c;
        }
      }
    }
    if (tx == null) {
      await dev.disconnect();
      throw Exception('未找到 NUS 特征值');
    }

    await tx.setNotifyValue(true);
    await _notifySub?.cancel();
    _notifySub = tx.onValueReceived.listen((v) {
      if (v.isNotEmpty) _onFrame(Uint8List.fromList(v));
    });
    _log('已订阅通知，等待数据…');
    notifyListeners();
  }

  // ---------------- 帧处理 ----------------
  void _onFrame(Uint8List raw) {
    try {
      final now = DateTime.now();
      if (lastFrameAt != null) {
        final dt = now.difference(lastFrameAt!).inMilliseconds;
        if (dt > 0) hz = 1000.0 / dt;
      }
      lastFrameAt = now;
      frameCount++;
      final obj = HtprProtocol.parse(raw);
      if (obj is Dashboard) {
        dashboard = obj;
      } else if (obj is Realtime) {
        realtime = obj;
      }
      notifyListeners();
    } catch (e) {
      _log('解析异常 $e');
    }
  }

  // ---------------- 断线重连 ----------------
  void _scheduleReconnect() {
    if (!_wantConnected) return;
    _reconnectTimer?.cancel();
    _reconnectCount++;
    final delay = Duration(seconds: _reconnectCount > 6 ? 15 : 3);
    _log('${delay.inSeconds}s 后自动重连（第 $_reconnectCount 次）…');
    _reconnectTimer = Timer(delay, () {
      if (_wantConnected && !connected) _connectFlow();
    });
  }

  Future<void> disconnect() async {
    _wantConnected = false;
    _reconnectTimer?.cancel();
    await _scanSub?.cancel();
    await _notifySub?.cancel();
    await _connSub?.cancel();
    try {
      await _device?.disconnect();
    } catch (_) {}
    _device = null;
    connected = false;
    notifyListeners();
    _log('已断开');
  }

  // ---------------- 下发命令 ----------------
  Future<void> _send(Uint8List frame) async {
    final dev = _device;
    if (dev == null || !dev.isConnected) {
      error = '未连接';
      notifyListeners();
      return;
    }
    final services = await dev.discoverServices();
    for (final s in services) {
      if (s.uuid.str.toLowerCase() != HtprProtocol.nusService) continue;
      for (final c in s.characteristics) {
        if (c.uuid.str.toLowerCase() != HtprProtocol.nusWriteChar) continue;
        await c.write(frame.toList(), withoutResponse: true);
        _log('已下发: ${HtprProtocol.hex(frame).substring(0, 16)}…');
        return;
      }
    }
    throw Exception('未找到写入特征值');
  }

  bool get canWrite => connected && dashboard != null;

  /// 强制超速开关
  Future<void> setOverspeed(bool on) async {
    final d = dashboard;
    if (d == null) throw Exception('尚未收到仪表帧');
    final func = HtprProtocol.withOverspeed(d.funcSettings, on);
    final frame = HtprProtocol.buildC0002(
      template: d.raw,
      func: func,
      motion3: d.motion3,
      locked: d.lockByte == 0xCC,
    );
    await _send(frame);
  }

  /// 写入三档限速 motion1 / motion2（1~8），motion3 通过 C0002
  Future<void> setGears({
    int? motion1,
    int? motion2,
    int? motion3,
  }) async {
    final d = dashboard;
    final r = realtime;
    if (d != null && (motion1 != null || motion2 != null)) {
      final f = HtprProtocol.buildC0602(
        template: r?.raw ?? d.raw,
        motion1: motion1 ?? r?.motion1 ?? 1,
        motion2: motion2 ?? r?.motion2 ?? 1,
        currentLimit: r?.currentRegulation ?? 0,
        run: r?.run ?? 0,
        modSwitch: r?.modSwitch ?? 0,
      );
      await _send(f);
    }
    if (d != null && motion3 != null) {
      final f = HtprProtocol.buildC0002(
        template: d.raw,
        func: d.funcSettings,
        motion3: motion3,
        locked: d.lockByte == 0xCC,
      );
      await _send(f);
    }
  }

  void clearLog() {
    logs.clear();
    notifyListeners();
  }
}
