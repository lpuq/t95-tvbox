#!/usr/bin/env python3
"""Bit-bang the FD6551/FD650 2-wire protocol on the T95 front-panel pins
(PI11/PI12) from userspace, to find which pin is clock and whether the chip
ACKs. Run as root with the i2c-gpio device unbound:
    echo i2c-front-panel > /sys/bus/platform/drivers/i2c-gpio/unbind
Usage: fd6551-probe.py            probe both orientations, report ACKs
       fd6551-probe.py CLK DAT    use that orientation, light all segments
"""
import sys, time
import gpiod
from gpiod.line import Direction, Value, Drive, Bias

CHIP = "/dev/gpiochip0"
PI11, PI12 = 8 * 32 + 11, 8 * 32 + 12
T = 20e-6  # half bit period; the chip is static, slow is fine


class Bus:
    def __init__(self, clk, dat):
        self.clk, self.dat = clk, dat
        cfg = gpiod.LineSettings(direction=Direction.OUTPUT, drive=Drive.OPEN_DRAIN,
                                 bias=Bias.PULL_UP, output_value=Value.ACTIVE)
        self.req = gpiod.request_lines(CHIP, consumer="fd6551-probe", config={(clk, dat): cfg})

    def set(self, line, v):
        self.req.set_value(line, Value.ACTIVE if v else Value.INACTIVE)
        time.sleep(T)

    def get(self, line):
        return self.req.get_value(line) == Value.ACTIVE

    def start(self):
        self.set(self.dat, 1); self.set(self.clk, 1)
        self.set(self.dat, 0); self.set(self.clk, 0)

    def stop(self):
        self.set(self.dat, 0); self.set(self.clk, 1); self.set(self.dat, 1)

    def byte(self, b):
        for i in range(7, -1, -1):
            self.set(self.dat, (b >> i) & 1)
            self.set(self.clk, 1); self.set(self.clk, 0)
        self.set(self.dat, 1)          # release data for the ACK bit
        self.set(self.clk, 1)
        ack = not self.get(self.dat)   # chip pulls data low = ACK
        self.set(self.clk, 0)
        return ack

    def write(self, cmd, data):
        self.start()
        a1 = self.byte(cmd)
        a2 = self.byte(data)
        self.stop()
        return a1, a2

    def idle_levels(self):
        return self.get(self.clk), self.get(self.dat)

    def close(self):
        self.req.release()


def name(l):
    return {PI11: "PI11", PI12: "PI12"}[l]


if len(sys.argv) == 3:
    clk, dat = (PI11, PI12) if sys.argv[1].upper() == "PI11" else (PI12, PI11)
    bus = Bus(clk, dat)
    print(f"clk={name(clk)} dat={name(dat)} idle(clk,dat)={bus.idle_levels()}")
    print("display on, full brightness :", bus.write(0x48, 0x01))
    for d in range(4):
        print(f"digit {d} all segments      :", bus.write(0x68 + 2 * d, 0xFF))
    print("all icons                   :", bus.write(0x66, 0xFF))
    bus.close()
    sys.exit(0)

for clk, dat in ((PI11, PI12), (PI12, PI11)):
    bus = Bus(clk, dat)
    print(f"clk={name(clk)} dat={name(dat)} idle(clk,dat)={bus.idle_levels()}")
    for cmd in (0x48, 0x68, 0x66):
        print(f"  cmd 0x{cmd:02x}: ack(cmd, data) = {bus.write(cmd, 0x00 if cmd != 0x48 else 0x01)}")
    bus.close()
