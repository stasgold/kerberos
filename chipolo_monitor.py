#!/usr/bin/env python3
"""
Chipolo Tag Monitor
Monitors specific Chipolo POP tags by their unique GATT identity (3e73c002).
Tags are defined in config.json with their hardware IDs and friendly names.

Requirements:
    pip install bleak

Usage:
    python chipolo_monitor.py [--config config.json]
"""

import asyncio
import json
import logging
import argparse
from datetime import datetime
from pathlib import Path
from dataclasses import dataclass, field
from bleak import BleakScanner, BleakClient
from bleak.backends.device import BLEDevice
from bleak.backends.scanner import AdvertisementData

# ─── Chipolo BLE fingerprint ──────────────────────────────────────────────────
CHIPOLO_SERVICE_UUIDS = {
    "0000fe2c-0000-1000-8000-00805f9b34fb",
    "0000fe65-0000-1000-8000-00805f9b34fb",
    "0000fee0-0000-1000-8000-00805f9b34fb",
    "0000fee1-0000-1000-8000-00805f9b34fb",
}
CHIPOLO_MANUFACTURER_IDS = {0x05D9, 0x0157}


# ─── Data structures ──────────────────────────────────────────────────────────
@dataclass
class TagConfig:
    name: str
    hardware_id: str          # hex string from 3e73c002, colon-separated uppercase
    description: str = ""


@dataclass
class TagState:
    config: TagConfig
    last_seen: datetime | None = None
    last_address: str | None = None
    present: bool = False
    rssi: int | None = None
    seen_count: int = 0
    absent_count: int = 0


# ─── Config loading ───────────────────────────────────────────────────────────
def load_config(path: str) -> dict:
    with open(path) as f:
        return json.load(f)


def build_tag_states(cfg: dict) -> dict[str, TagState]:
    """Returns dict keyed by hardware_id → TagState"""
    states = {}
    for t in cfg["tags"]:
        tc = TagConfig(
            name=t["name"],
            hardware_id=t["id"].upper(),
            description=t.get("description", ""),
        )
        states[tc.hardware_id] = TagState(config=tc)
    return states


# ─── Logging setup ────────────────────────────────────────────────────────────
def setup_logging(log_file: str):
    fmt = "%(asctime)s  %(levelname)-7s  %(message)s"
    logging.basicConfig(
        level=logging.INFO,
        format=fmt,
        handlers=[
            logging.StreamHandler(),
            logging.FileHandler(log_file),
        ],
    )


log = logging.getLogger(__name__)


# ─── Chipolo advertisement detection ─────────────────────────────────────────
def is_chipolo(device: BLEDevice, adv: AdvertisementData) -> bool:
    name = (device.name or "").lower()
    if "chipolo" in name:
        return True
    if "chipolo" in (adv.local_name or "").lower():
        return True
    adv_uuids = {u.lower() for u in adv.service_uuids}
    if adv_uuids & CHIPOLO_SERVICE_UUIDS:
        return True
    svc_uuids = {u.lower() for u in adv.service_data}
    if svc_uuids & CHIPOLO_SERVICE_UUIDS:
        return True
    for cid in adv.manufacturer_data:
        if cid in CHIPOLO_MANUFACTURER_IDS:
            return True
    return False


# ─── GATT identity read ───────────────────────────────────────────────────────
async def read_hardware_id(
    address: str,
    identity_char: str,
    timeout: float = 10.0,
) -> str | None:
    """
    Connect to a Chipolo tag and read its unique hardware ID from 3e73c002.
    Returns colon-separated uppercase hex string (first 16 bytes), or None on failure.
    """
    try:
        async with BleakClient(address, timeout=timeout) as client:
            data = await client.read_gatt_char(identity_char)
            # First 16 bytes are the unique ID; last byte is a version/flag
            return data[:16].hex(":").upper()
    except Exception as e:
        log.debug(f"GATT read failed for {address}: {e}")
        return None


# ─── Status display ───────────────────────────────────────────────────────────
def print_status(states: dict[str, TagState]):
    now = datetime.now()
    print("\n" + "═" * 60)
    print(f"  Tag Status  —  {now.strftime('%Y-%m-%d %H:%M:%S')}")
    print("═" * 60)
    for hw_id, state in states.items():
        icon = "🟢" if state.present else "🔴"
        name = state.config.name.upper()
        addr = state.last_address or "—"
        rssi = f"{state.rssi} dBm" if state.rssi is not None else "—"
        seen = state.last_seen.strftime("%H:%M:%S") if state.last_seen else "never"
        print(f"  {icon}  {name:<10}  addr={addr:<20}  rssi={rssi:<10}  last={seen}")
    print("═" * 60 + "\n")


# ─── Main monitor loop ────────────────────────────────────────────────────────
def save_config(path: str, cfg: dict):
    with open(path, "w") as f:
        json.dump(cfg, f, indent=2)


async def monitor(config_path: str):
    cfg = load_config(config_path)
    setup_logging(cfg.get("log_file", "chipolo_monitor.log"))

    scan_cfg = cfg.get("scan", {})
    interval        = scan_cfg.get("interval_seconds", 30)
    conn_timeout    = scan_cfg.get("connection_timeout_seconds", 10)
    absent_thresh   = scan_cfg.get("absent_threshold_seconds", 120)
    identity_char   = cfg.get(
        "identity_characteristic",
        "3e73c002-8ff8-4b17-b3ca-e6892ca6f268",
    )

    states = build_tag_states(cfg)

    log.info("Chipolo monitor started")
    log.info(f"Tracking {len(states)} tag(s): "
             f"{', '.join(s.config.name for s in states.values())}")
    log.info(f"Scan interval: {interval}s  |  Absent threshold: {absent_thresh}s")

    # Queue of Chipolo candidates found during a scan
    candidates: list[tuple[BLEDevice, AdvertisementData]] = []

    def on_advertisement(device: BLEDevice, adv: AdvertisementData):
        if is_chipolo(device, adv):
            candidates.append((device, adv))

    while True:
        candidates.clear()
        log.info("Scanning for Chipolo advertisements ...")

        scanner = BleakScanner(detection_callback=on_advertisement)
        await scanner.start()
        await asyncio.sleep(interval)
        await scanner.stop()

        # Deduplicate by address (keep strongest RSSI)
        best: dict[str, tuple[BLEDevice, AdvertisementData]] = {}
        for device, adv in candidates:
            prev = best.get(device.address)
            if prev is None or (adv.rssi or -999) > (prev[1].rssi or -999):
                best[device.address] = (device, adv)

        log.info(f"Found {len(best)} Chipolo candidate(s) — connecting to identify ...")

        # Mark all tags as not-yet-confirmed this cycle
        confirmed_this_cycle: set[str] = set()

        for address, (device, adv) in best.items():
            hw_id = await read_hardware_id(address, identity_char, conn_timeout)
            if hw_id is None:
                log.debug(f"Could not read ID from {address}")
                continue

            state = states.get(hw_id)
            if state is None:
                log.info(f"[NEW TAG]   Unknown Chipolo found  addr={address}  id={hw_id}")
                # Add to config and save
                new_tag = {
                    "name": f"unknown_{hw_id[:5].lower()}",
                    "id": hw_id,
                    "description": f"Auto-discovered at {address}",
                }
                cfg["tags"].append(new_tag)
                save_config(config_path, cfg)
                tc = TagConfig(
                    name=new_tag["name"],
                    hardware_id=hw_id,
                    description=new_tag["description"],
                )
                state = TagState(config=tc)
                states[hw_id] = state
                log.info(f"[SAVED]     Added '{tc.name}' (id={hw_id}) to {config_path}")

            # Known tag confirmed present
            now = datetime.now()
            was_present = state.present
            state.present      = True
            state.last_seen    = now
            state.last_address = address
            state.rssi         = adv.rssi
            state.seen_count  += 1
            confirmed_this_cycle.add(hw_id)

            if not was_present:
                log.info(f"[APPEARED]  {state.config.name}  addr={address}  rssi={adv.rssi} dBm")
            else:
                log.info(f"[PRESENT]   {state.config.name}  addr={address}  rssi={adv.rssi} dBm")

        # Check for absent tags
        now = datetime.now()
        for hw_id, state in states.items():
            if hw_id in confirmed_this_cycle:
                continue
            if state.last_seen is not None:
                elapsed = (now - state.last_seen).total_seconds()
                if elapsed >= absent_thresh and state.present:
                    state.present = False
                    state.absent_count += 1
                    log.warning(
                        f"[ABSENT]    {state.config.name}  "
                        f"last seen {elapsed:.0f}s ago  "
                        f"(gone {state.absent_count}x total)"
                    )
            elif state.present:
                state.present = False

        print_status(states)


# ─── Entry point ──────────────────────────────────────────────────────────────
if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Chipolo Tag Monitor")
    parser.add_argument(
        "--config",
        default="config.json",
        help="Path to config.json (default: config.json)",
    )
    args = parser.parse_args()

    if not Path(args.config).exists():
        print(f"Config file not found: {args.config}")
        raise SystemExit(1)

    try:
        asyncio.run(monitor(args.config))
    except KeyboardInterrupt:
        print("\nMonitor stopped.")
