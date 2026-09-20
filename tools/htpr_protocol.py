# -*- coding: utf-8 -*-
"""
恒泰普瑞「全能机内置蓝牙控制器」通信协议参考实现
逆向自官方微信小程序 wx0ebd16ecb71fee37 (V1MMWX 包, 模块 D:/wook/恒泰/utils/index.js)
================================================================================
BLE 传输层 : Nordic UART Service (NUS)
    notify  6e400003-b5a3-f393-e0a9-e50e24dcca9e   设备 -> 手机
    write   6e400002-b5a3-f393-e0a9-e50e24dcca9e   手机 -> 设备 (writeNoResponse)

帧格式: 固定 67 字节, 约 2Hz 交替下发两种帧
    [0][1]   帧头  0xCA 0xAC(遥测) / 0xC9 0x9C(仪表)
    [2][3]   命令字 BE  0x9605(遥测) / 0x9405(仪表)
    [4..64]  数据区 (遥测帧为密文, 仪表帧为明文)
    [65]     校验 = sum(bytes[0..64]) & 0xFF
    [66]     帧尾 0xCC

遥测帧(A: caac9605..) 的 [4..65] 经过滚动混淆, 必须先解密:
    for o in 4..65:
        b = (b - 54) & 0xFF; b ^= 43; b = (b - o) & 0xFF; b ^= 101; b = (b - o) & 0xFF
    加密为逆运算:
        b = (b + o) & 0xFF; b ^= 101; b = (b + o) & 0xFF; b ^= 43; b = (b + 54) & 0xFF
仪表帧(B: c99c9405..) 为明文, 无需解密.
"""
from __future__ import annotations
from dataclasses import dataclass, field
from typing import Optional, List

NUS_SERVICE = "6e400001-b5a3-f393-e0a9-e50e24dcca9e"
NUS_RX_CHAR = "6e400002-b5a3-f393-e0a9-e50e24dcca9e"   # 手机 -> 设备
NUS_TX_CHAR = "6e400003-b5a3-f393-e0a9-e50e24dcca9e"   # 设备 -> 手机

FRAME_LEN = 67
HDR_REALTIME = (0xCA, 0xAC)
HDR_DASHBOARD = (0xC9, 0x9C)

# ---------------------------------------------------------------- 编解码底层

def decrypt(payload: bytes) -> bytes:
    """遥测帧 [4..65] 解密 (原地作用于副本)"""
    r = bytearray(payload)
    for o in range(4, 66):
        b = r[o]
        b = (b - 54) & 0xFF
        b ^= 43
        b = (b - o) & 0xFF
        b ^= 101
        b = (b - o) & 0xFF
        r[o] = b
    return bytes(r)


def encrypt(payload: bytes) -> bytes:
    """下发命令前, [4..65] 加密"""
    r = bytearray(payload)
    for o in range(4, 66):
        b = r[o]
        b = (b + o) & 0xFF
        b ^= 101
        b = (b + o) & 0xFF
        b ^= 43
        b = (b + 54) & 0xFF
        r[o] = b
    return bytes(r)


def checksum(frame: bytes) -> int:
    return sum(frame[:65]) & 0xFF


def verify(frame: bytes) -> bool:
    return len(frame) >= FRAME_LEN and frame[65] == checksum(frame) and frame[66] == 0xCC


def u8(f, i):  return f[i]
def u16be(f, i): return (f[i] << 8) | f[i + 1]

# ---------------------------------------------------------------- 字段解析

@dataclass
class Dashboard:
    """仪表帧 c99c9405 (明文) —— 提供 电压 / 转把电压"""
    voltage: float = 0.0          # V   = BE(63,64)/100
    throttle_voltage: float = 0.0 # V   = BE(37,38)/200
    serial: int = 0               # 机型序号    byte10
    is_ota: bool = False
    current_regulation: int = 0   # byte39
    code_table: int = 0           # byte40
    motion: int = 0               # byte51
    layout: int = 0               # byte42
    vehicle_model_id: int = 0     # byte48
    raw: bytes = b""
    decrypted: bytes = b""
    ok: bool = False

    def __str__(self):
        return "电压=%.1fV 转把=%.1fV 校验=%s" % (self.voltage, self.throttle_voltage, self.ok)


@dataclass
class Realtime:
    """遥测帧 caac9605 (密文) —— 提供 电流 / 转速 等"""
    ampere: float = 0.0            # A   = BE(19,20)/10
    rotationalspeed: int = 0       # raw = 20*BE(21,22)
    study: int = 0                 # byte23
    motion1: int = 0               # byte11
    motion2: int = 0               # byte12
    reverse_speed: int = 0         # byte13
    torque: int = 0                # byte14
    current_regulation: int = 0    # byte15
    maximum_current: int = 0       # byte16
    em: int = 0                    # byte17
    em2: int = 0                   # byte18
    run: int = 0                   # byte24
    mod_switch: int = 0            # byte25
    raw: bytes = b""
    decrypted: bytes = b""
    ok: bool = False

    def rpm(self, divider: int = 25) -> int:
        """小程序显示值 = floor(rotationalspeed / a)，a 默认 25 (b=4 为另一车型)"""
        return self.rotationalspeed // divider

    def __str__(self):
        return "电流=%.1fA 转速raw=%d (显示 %d rpm) 校验=%s" % (
            self.ampere, self.rotationalspeed, self.rpm(), self.ok)


def parse_dashboard(frame: bytes) -> Dashboard:
    f = decrypt(frame)             # 同样需要解密 (小程序 ab2hex 对所有 c99c/caac 帧调用 decrypt)
    d = Dashboard(raw=frame, decrypted=f)
    if len(f) < FRAME_LEN:
        return d
    d.ok = verify(f)
    d.throttle_voltage = u16be(f, 37) / 200.0
    d.voltage = u16be(f, 63) / 100.0
    d.serial = u8(f, 10)
    d.is_ota = (u8(f, 9) == 2 and u8(f, 10) == 100)
    d.current_regulation = u8(f, 39)
    d.code_table = u8(f, 40)
    d.motion = u8(f, 51)
    d.layout = u8(f, 42)
    d.vehicle_model_id = u8(f, 48)
    return d


def parse_realtime(frame: bytes) -> Realtime:
    f = decrypt(frame)             # 密文，先解密
    r = Realtime(raw=frame, decrypted=f)
    if len(f) < FRAME_LEN:
        return r
    r.ok = verify(f)
    r.ampere = u16be(f, 19) / 10.0
    r.rotationalspeed = 20 * u16be(f, 21)
    r.study = u8(f, 23)
    r.motion1 = u8(f, 11)
    r.motion2 = u8(f, 12)
    r.reverse_speed = u8(f, 13)
    r.torque = u8(f, 14)
    r.current_regulation = u8(f, 15)
    r.maximum_current = u8(f, 16)
    r.em = u8(f, 17)
    r.em2 = u8(f, 18)
    r.run = u8(f, 24)
    r.mod_switch = u8(f, 25)
    return r


def parse(frame: bytes):
    """按帧头自动分派"""
    if len(frame) >= 2 and tuple(frame[:2]) == HDR_REALTIME:
        return parse_realtime(frame)
    if len(frame) >= 2 and tuple(frame[:2]) == HDR_DASHBOARD:
        return parse_dashboard(frame)
    return None

# ---------------------------------------------------------------- 下发命令

def build_command(hex_cmd_with_body: str) -> bytes:
    """构造下发帧: 设置校验 -> 加密。body 由 serializers 生成。
    例: build_command("c99c0002" + body_58hexchars)"""
    raw = bytearray.fromhex(hex_cmd_with_body)
    if len(raw) < FRAME_LEN:
        raw.extend(b"\x00" * (FRAME_LEN - len(raw)))
    raw = raw[:FRAME_LEN]
    raw[65] = checksum(raw)
    raw[66] = 0xCC
    return encrypt(bytes(raw))
