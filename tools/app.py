# -*- coding: utf-8 -*-
"""
恒泰普瑞蓝牙控制器 — BLE 调试网页面板 (Flask)
=============================================
功能:
  * 扫描 / 连接 / 断开 控制器
  * 实时显示 电压 / 转把电压 / 转速 / 电流
  * 显示原始帧(hex)与校验结果，便于二次开发调试
  * 演示回放模式：不接设备也能联调前端

用法:
    pip install flask bleak
    python app.py                 # 连真实设备 D0:0C:5E:53:31:C0
    python app.py --address XX:XX:XX:XX:XX:XX
    python app.py --demo steady2.json     # 回放模式（无设备）
然后浏览器打开 http://127.0.0.1:5000
"""
from __future__ import annotations

import argparse
import os

from flask import Flask, jsonify, render_template, request

from ble_bridge import BleBridge, DEFAULT_ADDRESS

app = Flask(__name__)
app.config["JSON_AS_ASCII"] = False
bridge = BleBridge(DEFAULT_ADDRESS)


@app.route("/")
def index():
    return render_template("index.html", default_address=bridge.address)


@app.post("/api/connect")
def api_connect():
    body = request.get_json(silent=True) or {}
    addr = (body.get("address") or "").strip() or bridge.address
    bridge.connect(addr)
    return jsonify(ok=True, address=addr)


@app.post("/api/disconnect")
def api_disconnect():
    bridge.disconnect()
    return jsonify(ok=True)


@app.post("/api/demo")
def api_demo():
    body = request.get_json(silent=True) or {}
    bridge.start_demo(body.get("pattern") or "steady2.json")
    return jsonify(ok=True)


@app.get("/api/state")
def api_state():
    return jsonify(bridge.state())


@app.get("/api/captures")
def api_captures():
    here = os.path.dirname(os.path.abspath(__file__))
    d = os.path.join(here, "captures")
    files = []
    if os.path.isdir(d):
        files = sorted(f for f in os.listdir(d) if f.endswith(".json"))
    return jsonify(files=files)


def main() -> None:
    ap = argparse.ArgumentParser(description="恒泰普瑞 BLE 调试面板")
    ap.add_argument("--address", default=DEFAULT_ADDRESS, help="蓝牙 MAC 地址")
    ap.add_argument("--demo", default=None, help="启动即回放 captures/<文件名>")
    ap.add_argument("--host", default="127.0.0.1")
    ap.add_argument("--port", type=int, default=5000)
    ap.add_argument("--debug", action="store_true")
    args = ap.parse_args()

    bridge.address = args.address
    if args.demo:
        bridge.start_demo(args.demo)

    print("=" * 64)
    print("  恒泰普瑞蓝牙控制器 — 调试面板")
    print("  浏览器打开:  http://%s:%d" % (args.host, args.port))
    if args.demo:
        print("  模式: 演示回放  %s" % args.demo)
    else:
        print("  目标设备: %s" % args.address)
    print("=" * 64)
    app.run(host=args.host, port=args.port, threaded=True, debug=args.debug)


if __name__ == "__main__":
    main()
