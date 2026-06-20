#!/usr/bin/env python3
"""
BLE Device Scanner with Chipolo Tag Detection
Scans for all nearby BLE devices and identifies Chipolo trackers.

Requirements:
    pip install bleak
"""

import asyncio
import struct
from bleak import BleakScanner
from bleak.backends.device import BLEDevice
from bleak.backends.scanner import AdvertisementData

# ─── Chipolo Detection ───────────────────────────────────────────────────────
# Known Chipolo BLE identifiers
CHIPOLO_NAME_PREFIXES = ["chipolo"]

# Confirmed from live scan of Chipolo POP devices:
#   0xFE2C  – assigned to Chipolo (older POP / ONE firmware)
#   0xFE65  – assigned to Chipolo (current POP firmware, carries structured payload)
CHIPOLO_SERVICE_UUIDS = {
    "0000fe2c-0000-1000-8000-00805f9b34fb",  # Chipolo POP (classic)
    "0000fe65-0000-1000-8000-00805f9b34fb",  # Chipolo POP (current)
    "0000fee0-0000-1000-8000-00805f9b34fb",  # Chipolo ONE (legacy)
    "0000fee1-0000-1000-8000-00805f9b34fb",  # Chipolo ONE (legacy)
}

# Chipolo manufacturer IDs (Bluetooth SIG assigned company IDs)
CHIPOLO_MANUFACTURER_IDS = {
    0x05D9,  # Chipolo d.o.o.
    0x0157,  # Chipolo (alternate)
}

# ─── Bluetooth SIG Company ID lookup (partial) ───────────────────────────────
COMPANY_IDS: dict[int, str] = {
    0x0006: "Microsoft",
    0x004C: "Apple Inc.",
    0x0075: "Samsung Electronics",
    0x00E0: "Google",
    0x0499: "Ruuvi Innovations",
    0x05D9: "Chipolo d.o.o.",
    0x0157: "Chipolo",
    0x0059: "Nordic Semiconductor ASA",
    0x0131: "Tile Inc.",
    0x01DA: "Estimote",
    0x0171: "Amazon.com Services LLC",
    0x0183: "Exposure Notifications (Google/Apple)",
}


def get_company_name(company_id: int) -> str:
    return COMPANY_IDS.get(company_id, f"Unknown (0x{company_id:04X})")


def is_chipolo(device: BLEDevice, adv: AdvertisementData) -> tuple[bool, str]:
    """
    Returns (is_chipolo, reason) by checking name, service UUIDs,
    manufacturer data, and service data patterns.
    """
    # Check device name
    name = (device.name or "").lower()
    if "chipolo" in name:
        return True, "Device name contains 'Chipolo'"

    # Check advertised local name
    local_name = (adv.local_name or "").lower()
    if "chipolo" in local_name:
        return True, "Advertised name contains 'Chipolo'"

    # Check service UUIDs (advertised list)
    adv_uuids = {u.lower() for u in adv.service_uuids}
    matched_uuids = adv_uuids & CHIPOLO_SERVICE_UUIDS
    if matched_uuids:
        short = ", ".join(f"0x{u[4:8].upper()}" for u in matched_uuids)
        return True, f"Matched service UUID(s): {short}"

    # Check service data keys (even without UUID in the advertised list)
    svc_data_uuids = {u.lower() for u in adv.service_data}
    matched_svc = svc_data_uuids & CHIPOLO_SERVICE_UUIDS
    if matched_svc:
        short = ", ".join(f"0x{u[4:8].upper()}" for u in matched_svc)
        return True, f"Matched service data UUID(s): {short}"

    # Check manufacturer data
    for company_id in adv.manufacturer_data:
        if company_id in CHIPOLO_MANUFACTURER_IDS:
            return True, f"Matched Chipolo manufacturer ID: 0x{company_id:04X}"

    return False, ""


def decode_chipolo_service_data(uuid: str, data: bytes) -> list[str]:
    """
    Decode Chipolo-specific service data payloads.

    FE65 payload (13 bytes observed):
      [0]      Protocol / packet type  (0x01 = advertisement)
      [1]      Firmware major version
      [2]      Firmware minor version
      [3]      Flags byte  (bit 0 = button pressed, bit 1 = lost mode active)
      [4..9]   Partial device ID / counter (6 bytes)
      [10..12] Additional state bytes

    FE2C payload (3 bytes observed):
      [0..2]   Rolling counter / status bytes
    """
    lines = []
    if uuid == "0000fe65-0000-1000-8000-00805f9b34fb" and len(data) >= 4:
        pkt_type  = data[0]
        fw_major  = data[1]
        fw_minor  = data[2]
        flags     = data[3]
        btn_pressed   = bool(flags & 0x01)
        lost_mode     = bool(flags & 0x02)
        lines.append(f"[Chipolo FE65] Packet type : 0x{pkt_type:02X}")
        lines.append(f"[Chipolo FE65] Firmware    : {fw_major}.{fw_minor}")
        lines.append(f"[Chipolo FE65] Flags       : 0x{flags:02X}  "
                     f"(button={'YES' if btn_pressed else 'no'}, "
                     f"lost_mode={'YES' if lost_mode else 'no'})")
        if len(data) >= 10:
            device_id = data[4:10].hex(":").upper()
            lines.append(f"[Chipolo FE65] Device ID   : {device_id}")
        if len(data) > 10:
            extra = data[10:].hex(" ").upper()
            lines.append(f"[Chipolo FE65] Extra bytes : {extra}")
    elif uuid == "0000fe2c-0000-1000-8000-00805f9b34fb":
        counter = int.from_bytes(data, "big")
        lines.append(f"[Chipolo FE2C] Status/counter: 0x{data.hex().upper()} ({counter})")
    return lines


def format_manufacturer_data(mfr_data: dict[int, bytes]) -> list[str]:
    lines = []
    for company_id, data in mfr_data.items():
        hex_str = data.hex(" ").upper()
        company = get_company_name(company_id)
        lines.append(f"    Company: {company}")
        lines.append(f"    Data   : {hex_str}")
        # Apple iBeacon detection
        if company_id == 0x004C and len(data) >= 2 and data[0] == 0x02 and data[1] == 0x15:
            try:
                uuid_bytes = data[2:18]
                uuid_hex = uuid_bytes.hex()
                uuid_str = f"{uuid_hex[0:8]}-{uuid_hex[8:12]}-{uuid_hex[12:16]}-{uuid_hex[16:20]}-{uuid_hex[20:]}"
                major = struct.unpack(">H", data[18:20])[0]
                minor = struct.unpack(">H", data[20:22])[0]
                tx_power = struct.unpack("b", data[22:23])[0]
                lines.append(f"    iBeacon UUID : {uuid_str}")
                lines.append(f"    iBeacon Major: {major}  Minor: {minor}  TX Power: {tx_power} dBm")
            except Exception:
                pass
    return lines


def print_device(device: BLEDevice, adv: AdvertisementData, chipolo: bool, reason: str):
    sep = "═" * 70 if chipolo else "─" * 70
    tag = "  *** CHIPOLO TAG DETECTED ***" if chipolo else ""
    print(f"\n{sep}{tag}")
    print(f"  Name        : {device.name or '(none)'}")
    if adv.local_name and adv.local_name != device.name:
        print(f"  Local Name  : {adv.local_name}")
    print(f"  Address     : {device.address}")
    print(f"  RSSI        : {adv.rssi} dBm")
    print(f"  TX Power    : {adv.tx_power if adv.tx_power is not None else 'N/A'} dBm")

    if adv.service_uuids:
        print(f"  Service UUIDs ({len(adv.service_uuids)}):")
        for uuid in adv.service_uuids:
            print(f"    {uuid}")

    if adv.service_data:
        print(f"  Service Data ({len(adv.service_data)}):")
        for uuid, data in adv.service_data.items():
            print(f"    UUID : {uuid}")
            print(f"    Data : {data.hex(' ').upper()}")
            decoded = decode_chipolo_service_data(uuid.lower(), data)
            for line in decoded:
                print(f"    {line}")

    if adv.manufacturer_data:
        print(f"  Manufacturer Data ({len(adv.manufacturer_data)} entr{'y' if len(adv.manufacturer_data)==1 else 'ies'}):")
        for line in format_manufacturer_data(adv.manufacturer_data):
            print(line)

    if chipolo:
        print(f"  Detection   : {reason}")

    # Raw metadata if available
    if hasattr(device, "details") and isinstance(device.details, dict):
        props = device.details.get("props", {})
        if props:
            for k, v in props.items():
                if k not in ("Address", "Name", "RSSI", "UUIDs", "ManufacturerData", "ServiceData", "TxPower"):
                    print(f"  {k:12}: {v}")


async def scan(duration: float = 10.0):
    print(f"Scanning for BLE devices ({duration}s) ...\n")

    devices_seen: dict[str, tuple[BLEDevice, AdvertisementData]] = {}

    def callback(device: BLEDevice, adv: AdvertisementData):
        devices_seen[device.address] = (device, adv)

    scanner = BleakScanner(detection_callback=callback)
    await scanner.start()
    await asyncio.sleep(duration)
    await scanner.stop()

    # Separate Chipolo tags from regular devices
    chipolo_devices = []
    other_devices = []

    for device, adv in devices_seen.values():
        found, reason = is_chipolo(device, adv)
        if found:
            chipolo_devices.append((device, adv, reason))
        else:
            other_devices.append((device, adv))

    # Print all regular devices first
    print(f"\nFound {len(devices_seen)} device(s) total "
          f"({len(chipolo_devices)} Chipolo, {len(other_devices)} other)\n")

    if other_devices:
        print("─" * 70)
        print("OTHER BLE DEVICES")
        for device, adv in sorted(other_devices, key=lambda x: -(x[1].rssi or -999)):
            print_device(device, adv, chipolo=False, reason="")

    if chipolo_devices:
        print("\n" + "═" * 70)
        print("CHIPOLO TAGS")
        for device, adv, reason in sorted(chipolo_devices, key=lambda x: -(x[1].rssi or -999)):
            print_device(device, adv, chipolo=True, reason=reason)

    if not chipolo_devices:
        print("\nNo Chipolo tags detected nearby.")

    print(f"\n{'─' * 70}")
    print(f"Scan complete. {len(devices_seen)} device(s) found.")


if __name__ == "__main__":
    import sys

    duration = 10.0
    if len(sys.argv) > 1:
        try:
            duration = float(sys.argv[1])
        except ValueError:
            print(f"Usage: python {sys.argv[0]} [scan_duration_seconds]")
            sys.exit(1)

    try:
        asyncio.run(scan(duration))
    except KeyboardInterrupt:
        print("\nScan interrupted by user.")
