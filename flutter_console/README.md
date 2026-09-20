# flutter_console

「恒泰普瑞控制器 · BLE 调试控制台」的 Flutter / Android 工程源码。

- 中文文档、使用场景、技术架构与协议说明 → 见仓库根目录的 [`../README.md`](../README.md)
- 协议完整文档 → [`../tools/PROTOCOL.md`](../tools/PROTOCOL.md)

## 快速开始

```bash
flutter pub get
flutter analyze
flutter test          # 截图 + 布局回归
flutter build apk --release
```

## 代码导览

| 文件 | 职责 |
|---|---|
| `lib/main.dart` | 外壳 · 仪表盘页 · GNSS 页 · `SpeedometerPainter` / `SkyplotPainter` |
| `lib/pages_extra.dart` | 统计页 · 设置页 · `LineChartPainter` |
| `lib/app_state.dart` | 全局状态 · 速度三源融合 · GNSS 在线标定 · 里程能耗积分 |
| `lib/ble_service.dart` | BLE 扫描 / 连接 / NUS 订阅 / 断线重连 / 指令下发 |
| `lib/gnss_service.dart` | GNSS EventChannel 消费与定位质量判定 |
| `lib/htpr_protocol.dart` | 协议层：解密 / 加密 / 校验 / 解析 / 组帧 |
| `android/.../GnssBridge.kt` | 原生 `GnssStatus` 桥（卫星方位角 / 仰角 / 载噪比） |
