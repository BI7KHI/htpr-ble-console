# -*- coding: utf-8 -*-
"""
BLE 桥接层
==========
在后台线程里跑 asyncio 事件循环，负责：
  * 扫描/连接 恒泰普瑞 蓝牙控制器 (Nordic UART Service)
  * 订阅 notify，解析 67 字节帧
  * 以线程安全方式暴露「最新状态」给 Flask

同时提供 demo 回放模式：不连设备，直接回放 captures/*.json，
便于前端联调与回归测试。
"""
from __future__ import annotations

import asyncio
import collections
import json
import os
import threading
import time
from typing import Any, Dict, Optional

import htpr_protocol as P

try:
    from bleak import BleakClient, BleakScanner
    HAVE_BLEAK = True
except Exception:                                   # pragma: no cover
    HAVE_BLEAK = False

DEFAULT_ADDRESS = "D0:0C:5E:53:31:C0"
NAME_PREFIX = "恒泰普瑞"


class BleBridge:
    """线程安全的 BLE <-> Web 桥"""

    def __init__(self, address: str = DEFAULT_ADDRESS):
        self.address = address
        self._thread: Optional[threading.Thread] = None
        self._loop: Optional[asyncio.AbstractEventLoop] = None
        self._client = None
        self._lock = threading.Lock()
        self._rssi: Optional[int] = None
        self._state: Dict[str, Any] = self._blank_state()
        self.log = collections.deque(maxlen=300)
        self._demo_task = None
        self._want = False          # 用户意图：是否希望保持连接
        self._reconnects = 0

    # ------------------------------------------------------------------ 工具
    @staticmethod
    def _blank_state() -> Dict[str, Any]:
        return {
            "connected": False, "connecting": False, "error": None,
            "address": None, "name": None, "rssi": None,
            "demo": False, "frames": 0, "last_ts": None, "hz": None,
            # 仪表帧 (C9 9C 94 05)
            "voltage": None, "throttle_voltage": None,
            "serial": None, "dashboard_ok": None,
            # 遥测帧 (CA AC 96 05)
            "ampere": None, "rotationalspeed": None, "rpm": None,
            "motion1": None, "motion2": None, "torque": None,
            "realtime_ok": None,
            "raw_dashboard": None, "raw_realtime": None,
        }

    def _log(self, msg: str) -> None:
        line = "%s  %s" % (time.strftime("%H:%M:%S"), msg)
        self.log.append(line)
        print("[bridge]", line, flush=True)

    def _patch(self, **kv) -> None:
        with self._lock:
            self._state.update(kv)

    # ------------------------------------------------------------- 对外接口
    def state(self) -> Dict[str, Any]:
        with self._lock:
            st = dict(self._state)
        st["log"] = list(self.log)[-40:]
        return st

    def connect(self, address: Optional[str] = None) -> None:
        self._ensure_loop()
        addr = address or self.address
        self.address = addr
        self._want = True
        self._reconnects = 0
        self._patch(connecting=True, error=None, manual_disconnect=False)
        asyncio.run_coroutine_threadsafe(self._connect(addr), self._loop)

    def disconnect(self) -> None:
        self._want = False
        if self._loop:
            asyncio.run_coroutine_threadsafe(self._disconnect(), self._loop)

    def start_demo(self, pattern: str = "steady2.json", loop: bool = True) -> None:
        """回放 captures/<pattern>，用于无设备时联调前端"""
        self._ensure_loop()
        self._demo_task = asyncio.run_coroutine_threadsafe(self._demo(pattern, loop), self._loop)

    # ------------------------------------------------------------ asyncio 侧
    def _ensure_loop(self) -> None:
        if self._loop and self._loop.is_running():
            return
        self._loop = asyncio.new_event_loop()
        self._thread = threading.Thread(target=self._loop.run_forever, daemon=True)
        self._thread.start()

    async def _disconnect(self) -> None:
        if self._demo_task:
            self._demo_task.cancel()
            self._demo_task = None
        c, self._client = self._client, None
        if c:
            try:
                await c.stop_notify(P.NUS_TX_CHAR)
            except Exception:
                pass
            try:
                await c.disconnect()
            except Exception:
                pass
        st = self._blank_state()
        st["address"] = self.address
        with self._lock:
            self._state.update(st)
        self._log("已断开")

    async def _connect(self, addr: str) -> None:
        if not HAVE_BLEAK:
            self._patch(connecting=False, error="未安装 bleak")
            return
        await self._disconnect()
        self._patch(connecting=True, error=None)
        try:
            dev = None
            for attempt in range(1, 4):
                self._log("扫描 %s ... (第 %d 次)" % (addr, attempt))
                try:
                    dev = await BleakScanner.find_device_by_address(addr, timeout=12)
                except Exception:
                    dev = None
                if dev is not None:
                    break
                # 退而求其次：按名称前缀扫描（设备有时地址解析慢）
                found = await BleakScanner.discover(timeout=8, return_adv=True)
                for a, (d, _adv) in found.items():
                    if a.upper() == addr.upper() or (d.name or "").startswith(NAME_PREFIX):
                        dev, addr = d, a
                        break
                if dev is not None:
                    break
                await asyncio.sleep(1.5)
            if dev is None:
                self._patch(connecting=False, error="未发现设备（可能已被手机小程序占用，请先在小程序里断开）")
                self._log("未发现设备")
                return
            name = getattr(dev, "name", None)
            self._log("连接 %s (%s)" % (addr, name))
            client = BleakClient(dev, timeout=25,
                                 disconnected_callback=self._on_disconnected)
            await client.connect()
            self._client = client
            await client.start_notify(P.NUS_TX_CHAR, self._on_notify)
            self._patch(connected=True, connecting=False, address=addr, name=name, error=None)
            self._log("已连接，等待数据…")
        except Exception as e:
            self._patch(connecting=False, connected=False, error="%s: %s" % (type(e).__name__, e))
            self._log("连接失败 %r" % (e,))

    # ------------------------------------------------------------- 帧处理
    def _apply_frame(self, payload: bytes) -> None:
        try:
            now = time.time()
            with self._lock:
                self._state["frames"] += 1
                self._state["last_ts"] = now
                self._state["connected"] = True
                prev = self._state.get("_last_t")
                if prev:
                    dt = now - prev
                    if dt > 0:
                        self._state["hz"] = round(1.0 / dt, 2)
                self._state["_last_t"] = now

            if len(payload) < P.FRAME_LEN:
                return
            if tuple(payload[:2]) == P.HDR_REALTIME:
                r = P.parse_realtime(payload)
                self._patch(ampere=r.ampere, rotationalspeed=r.rotationalspeed,
                            rpm=r.rpm(), motion1=r.motion1, motion2=r.motion2,
                            torque=r.torque, realtime_ok=r.ok,
                            raw_realtime=payload.hex())
            elif tuple(payload[:2]) == P.HDR_DASHBOARD:
                d = P.parse_dashboard(payload)
                self._patch(voltage=round(d.voltage, 1),
                            throttle_voltage=round(d.throttle_voltage, 1),
                            serial=d.serial, dashboard_ok=d.ok,
                            raw_dashboard=payload.hex())
        except Exception as e:      # pragma: no cover
            self._log("解析异常 %r" % (e,))

    def _on_disconnected(self, _client) -> None:
        self._patch(connected=False)
        self._log("⚠ 连接已断开")
        if self._want:
            asyncio.run_coroutine_threadsafe(self._auto_reconnect(), self._loop)

    async def _auto_reconnect(self, delay: float = 3.0) -> None:
        self._reconnects += 1
        if self._reconnects > 1000:
            self._log("重连次数过多，停止")
            self._want = False
            return
        await asyncio.sleep(delay)
        if not self._want:
            return
        c = self._client
        if c is not None and getattr(c, "is_connected", False):
            return
        self._log("自动重连（第 %d 次）…" % self._reconnects)
        await self._connect(self.address)

    def _on_notify(self, _sender, data: bytearray) -> None:
        self._apply_frame(bytes(data))

    def _on_notify_demo(self, _s, data: bytearray) -> None:
        self._apply_frame(bytes(data))

    # --------------------------------------------------------------- demo
    async def _demo(self, pattern: str, loop: bool) -> None:
        here = os.path.dirname(os.path.abspath(__file__))
        path = os.path.join(here, "captures", pattern)
        if not os.path.exists(path):
            self._patch(error="演示文件不存在: %s" % pattern)
            return
        frames = [bytes.fromhex(r["hex"]) for r in json.load(open(path, encoding="utf-8"))]
        st = self._blank_state()
        st.update(connected=True, demo=True, address="DEMO", name="回放 %s" % pattern)
        with self._lock:
            self._state.update(st)
        self._log("演示模式：回放 %s（%d 帧）" % (pattern, len(frames)))
        try:
            while True:
                for f in frames:
                    self._apply_frame(f)
                    await asyncio.sleep(0.5)
                if not loop:
                    break
        finally:
            self._demo_task = None
