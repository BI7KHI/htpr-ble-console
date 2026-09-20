# -*- coding: utf-8 -*-
"""
协议实现自检 / 回归测试
=======================
用 captures/ 里的真实抓包数据验证 htpr_protocol.py 的解析结果。
运行:  python selftest.py
预期:  所有帧校验通过, 且四组工况的数值与万用表实测一致。
"""
from __future__ import annotations

import collections
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
sys.stdout.reconfigure(encoding="utf-8", errors="replace")

import htpr_protocol as P

HERE = os.path.dirname(os.path.abspath(__file__))
CAP = os.path.join(HERE, "captures")

# 工况 -> (文件, 期望电压V, 期望转把V, 期望电流A, 期望转速rpm)
CASES = [
    ("静止(基线)",    "capture90.json",  None, 0.8, 0.0,  0),
    ("低速",          "steady1.json",    48.0, 1.5, 0.1,  76),
    ("高速空载",       "steady2.json",    47.7, 3.5, 1.25, 601),
    ("高速加阻",       "steady3.json",    None, 3.5, 7.2,  562),
]


def load(fn):
    return [bytes.fromhex(r["hex"]) for r in
            json.load(open(os.path.join(CAP, fn), encoding="utf-8"))]


def main() -> int:
    print("=" * 78)
    print("htpr_protocol.py 自检 —— 基于真实抓包数据")
    print("=" * 78)
    all_ok = True
    for label, fn, ev, et, ea, er in CASES:
        frames = load(fn)
        B = [f for f in frames if tuple(f[:2]) == P.HDR_DASHBOARD]
        A = [f for f in frames if tuple(f[:2]) == P.HDR_REALTIME]

        dash = [P.parse_dashboard(f) for f in B]
        real = [P.parse_realtime(f) for f in A]

        ok_b = sum(1 for d in dash if d.ok)
        ok_a = sum(1 for r in real if r.ok)

        # 取众数帧代表该工况的静态值
        mv = collections.Counter(round(d.voltage, 1) for d in dash).most_common(1)[0][0]
        mt = collections.Counter(round(d.throttle_voltage, 1) for d in dash).most_common(1)[0][0]
        rpm_lo = min(r.rpm() for r in real)
        rpm_hi = max(r.rpm() for r in real)
        amp_lo = min(r.ampere for r in real)
        amp_hi = max(r.ampere for r in real)

        chk_ok = (ok_b == len(B)) and (ok_a == len(A))
        all_ok &= chk_ok

        v_ok = (ev is None) or abs(mv - ev) <= 0.3
        t_ok = abs(mt - et) <= 0.1
        c_ok = amp_lo - 0.15 <= ea <= amp_hi + 0.15
        r_ok = rpm_lo - 6 <= er <= rpm_hi + 6
        all_ok &= (v_ok and t_ok and c_ok and r_ok)

        print("\n[%-10s] %s" % (label, fn))
        print("  帧数: 仪表 %d / 遥测 %d   校验通过: 仪表 %d/%d, 遥测 %d/%d  %s"
              % (len(B), len(A), ok_b, len(B), ok_a, len(A), "✓" if chk_ok else "✗"))
        print("  电压   = %5.1f V   %s" % (mv, "" if ev is None else
              ("(期望 %.1f) %s" % (ev, "✓" if v_ok else "✗"))))
        print("  转把   = %5.1f V   (期望 %.1f) %s" % (mt, et, "✓" if t_ok else "✗"))
        print("  电流   = %.1f~%.1f A (期望 %.2f) %s" % (amp_lo, amp_hi, ea, "✓" if c_ok else "✗"))
        print("  转速   = %d~%d rpm (期望 %d) %s" % (rpm_lo, rpm_hi, er, "✓" if r_ok else "✗"))

    print("\n" + "=" * 78)
    print("总计: %s" % ("全部通过 ✅" if all_ok else "存在失败 ❌"))
    print("=" * 78)
    return 0 if all_ok else 1


if __name__ == "__main__":
    sys.exit(main())
