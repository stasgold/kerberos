#!/usr/bin/env python3
"""
Chipolo POP Presence Monitor
Detects when a Chipolo tag leaves the room by tracking advertising gaps.

Usage:
    # First run ble_scanner.py to discover device addresses, then:
    python3 ble_presence_monitor.py
    python3 ble_presence_monitor.py --timeout 8 --rssi -70

Requirements:
    pip install bleak
"""

import asyncio
import argparse
import contextlib
import time
from datetime import datetime
from dataclasses import dataclass, field
from bleak import BleakScanner
from bleak.backends.device import BLEDevice
from bleak.backends.scanner import AdvertisementData

# ─── Chipolo POP service UUIDs (confirmed from live scan) ────────────────────
CHIPOLO_SERVICE_UUIDS = {
    "0000fe65-0000-1000-8000-00805f9b34fb",  # Chipolo POP (current firmware)
    "0000fe2c-0000-1000-8000-00805f9b34fb",  # Chipolo POP (classic firmware)
    "0000fee0-0000-1000-8000-00805f9b34fb",  # Chipolo ONE (legacy)
    "0000fee1-0000-1000-8000-00805f9b34fb",  # Chipolo ONE (legacy)
}


def is_chipolo(device: BLEDevice, adv: AdvertisementData) -> bool:
    name = (device.name or adv.local_name or "").lower()
    if "chipolo" in name:
        return True
    adv_uuids = {u.lower() for u in (adv.service_uuids or [])}
    svc_uuids = {u.lower() for u in (adv.service_data or {}).keys()}
    return bool((adv_uuids | svc_uuids) & CHIPOLO_SERVICE_UUIDS)


@dataclass
class DeviceState:
    address: str
    name: str
    first_seen: float = field(default_factory=time.time)
    last_seen: float = field(default_factory=time.time)
    last_rssi: int = 0
    packet_count: int = 0
    present: bool = True
    gone_at: float | None = None

    def update(self, rssi: int):
        self.last_seen = time.time()
        self.last_rssi = rssi
        self.packet_count += 1
        if not self.present:
            away_s = self.gone_at and (time.time() - self.gone_at)
            away_str = f"  (was away {away_s:.0f}s)" if away_s else ""
            print(f"\n[{ts()}] ✓ RETURNED  {self.name!r:20s}  RSSI {rssi:+d} dBm{away_str}")
        self.present = True
        self.gone_at = None

    def mark_gone(self):
        if self.present:
            away_since = datetime.fromtimestamp(self.last_seen).strftime("%H:%M:%S")
            print(f"\n[{ts()}] ✗ GONE      {self.name!r:20s}  last seen {away_since}  "
                  f"RSSI was {self.last_rssi:+d} dBm")
        self.present = False
        if self.gone_at is None:
            self.gone_at = time.time()


def ts() -> str:
    return datetime.now().strftime("%H:%M:%S")


async def monitor(
    timeout_s: float = 8.0,
    rssi_threshold: int | None = None,
    check_interval: float = 1.0,
    scan_interval: float = 10.0,
):
    """
    timeout_s       : Seconds without a packet before declaring device gone.
    rssi_threshold  : Optional minimum RSSI (dBm).
    check_interval  : How often (seconds) to check for timed-out devices.
    scan_interval   : Stop and restart BLE scan every N seconds (default 10).
    """
    print(f"Chipolo POP Presence Monitor")
    print(f"  Gone timeout  : {timeout_s}s")
    print(f"  Scan interval : {scan_interval}s (restart cycle)")
    if rssi_threshold:
        print(f"  RSSI filter   : ignore packets weaker than {rssi_threshold} dBm")
    print(f"  Check rate    : every {check_interval}s")
    print(f"\nWaiting for Chipolo tags... (Ctrl-C to stop)\n")

    devices: dict[str, DeviceState] = {}

    def callback(device: BLEDevice, adv: AdvertisementData):
        if not is_chipolo(device, adv):
            return

        rssi = adv.rssi or 0
        if rssi_threshold is not None and rssi < rssi_threshold:
            return

        addr = device.address
        name = device.name or adv.local_name or addr

        if addr not in devices:
            devices[addr] = DeviceState(address=addr, name=name)
            print(f"[{ts()}] + NEW       {name!r:20s}  addr={addr}  "
                  f"RSSI={rssi:+d} dBm")
        else:
            prev_present = devices[addr].present
            devices[addr].update(rssi)
            if prev_present and devices[addr].packet_count % 10 == 0:
                print(f"[{ts()}]   present  {name!r:20s}  "
                      f"RSSI={rssi:+d} dBm  pkts={devices[addr].packet_count}")

    async def timeout_loop():
        while True:
            await asyncio.sleep(check_interval)
            now = time.time()
            for state in devices.values():
                if state.present and (now - state.last_seen) > timeout_s:
                    state.mark_gone()

    async def scan_loop():
        scanner = BleakScanner(detection_callback=callback)
        scan_count = 0
        while True:
            scan_count += 1
            print(f"[{ts()}] ▶ Scan #{scan_count} started")
            await scanner.start()
            await asyncio.sleep(scan_interval)
            await scanner.stop()
            print(f"[{ts()}] ■ Scan #{scan_count} done — restarting in 0.1s")
            await asyncio.sleep(0.1)

    timeout_task = asyncio.create_task(timeout_loop())
    scan_task = asyncio.create_task(scan_loop())

    try:
        await asyncio.gather(timeout_task, scan_task)
    except (asyncio.CancelledError, KeyboardInterrupt):
        pass
    finally:
        timeout_task.cancel()
        scan_task.cancel()
        with contextlib.suppress(asyncio.CancelledError):
            await asyncio.gather(timeout_task, scan_task)

    # Summary
    print(f"\n{'─' * 60}")
    print("Session summary:")
    for state in devices.values():
        status = "PRESENT" if state.present else "GONE"
        uptime = time.time() - state.first_seen
        print(f"  {state.name!r:22s}  {status:8s}  "
              f"packets={state.packet_count}  "
              f"tracked={uptime:.0f}s  "
              f"last_rssi={state.last_rssi:+d} dBm")


# ─── CLI ─────────────────────────────────────────────────────────────────────

def main():
    parser = argparse.ArgumentParser(
        description="Monitor Chipolo POP presence via BLE advertising gaps."
    )
    parser.add_argument(
        "--timeout", "-t", type=float, default=8.0,
        help="Seconds without a packet before 'gone' (default: 8)"
    )
    parser.add_argument(
        "--rssi", "-r", type=int, default=None,
        help="Ignore packets weaker than this dBm (e.g. -70). "
             "Simulates a smaller room radius. Default: no filter."
    )
    parser.add_argument(
        "--interval", "-i", type=float, default=10.0,
        help="Restart BLE scan every N seconds (default: 10)"
    )
    parser.add_argument(
        "--check", "-c", type=float, default=1.0,
        help="Timeout check interval in seconds (default: 1.0)"
    )
    args = parser.parse_args()

    try:
        asyncio.run(monitor(
            timeout_s=args.timeout,
            rssi_threshold=args.rssi,
            check_interval=args.check,
            scan_interval=args.interval,
        ))
    except KeyboardInterrupt:
        print("\nStopped.")


if __name__ == "__main__":
    main()
