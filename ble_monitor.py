import asyncio
import csv
import logging
from datetime import datetime
from bleak import BleakScanner

# ── Log setup ─────────────────────────────────────────────────────────────────
LOG_FILE = "ble_monitor.csv"

CSV_COLUMNS = [
    "timestamp", "detection_mode", "address", "name", "local_name",
    "rssi_dbm", "tx_power", "service_uuids", "service_data", "mfg_data",
]

# Human-readable console logger (separate from CSV file)
_console = logging.getLogger("ble_monitor.console")
_console.setLevel(logging.INFO)
_ch = logging.StreamHandler()
_ch.setFormatter(logging.Formatter("%(asctime)s.%(msecs)03d  %(message)s", datefmt="%Y-%m-%d %H:%M:%S"))
_console.addHandler(_ch)
_console.propagate = False

# CSV writer — open once, keep file handle open for the session
_csv_file = open(LOG_FILE, "a", newline="", encoding="utf-8")
_csv_writer = csv.writer(_csv_file, quoting=csv.QUOTE_ALL)

# Write header only if file is empty
if _csv_file.tell() == 0:
    _csv_writer.writerow(CSV_COLUMNS)
    _csv_file.flush()


def _now() -> str:
    return datetime.now().strftime("%Y-%m-%d %H:%M:%S.%f")[:-3]


def log_packet(detection_mode: str, device, advertising_data) -> None:
    rssi = advertising_data.rssi
    mfg = {f"0x{cid:04X}": data.hex() for cid, data in advertising_data.manufacturer_data.items()}
    svc_data = {str(u): d.hex() for u, d in advertising_data.service_data.items()}
    svc_uuids = "|".join(advertising_data.service_uuids or [])

    row = [
        _now(),
        detection_mode,
        device.address,
        device.name or "",
        advertising_data.local_name or "",
        rssi,
        advertising_data.tx_power if advertising_data.tx_power is not None else "",
        svc_uuids,
        str(svc_data) if svc_data else "",
        str(mfg) if mfg else "",
    ]
    _csv_writer.writerow(row)
    _csv_file.flush()

    # Pretty-print to console
    _console.info(
        f"[{detection_mode}]  {device.address}  "
        f"name={device.name or advertising_data.local_name or '—'}  "
        f"RSSI={rssi} dBm"
    )


# Chipolo identifiers (used for tagging only, not filtering)
CHIPOLO_CUSTOM_UUID = "0000fe65-0000-1000-8000-00805f9b34fb"
GOOGLE_FMD_UUID     = "0000fe2c-0000-1000-8000-00805f9b34fb"


def detect_mode(device, advertising_data) -> str:
    """Return a tag describing why this packet matched (or 'OTHER')."""
    name = (device.name or advertising_data.local_name or "").lower()
    if "chipolo" in name:
        return "NAME"
    if CHIPOLO_CUSTOM_UUID in advertising_data.service_data:
        return "FE65_PROPRIETARY"
    if GOOGLE_FMD_UUID in advertising_data.service_data:
        return "FE2C_GOOGLE_FMD"
    return "OTHER"


def callback(device, advertising_data):
    log_packet(detect_mode(device, advertising_data), device, advertising_data)


async def main():
    _console.info(f"Initializing BLE Sniffer — logging ALL advertisements to {LOG_FILE}")
    _console.info("Chipolo packets will be tagged NAME / FE65_PROPRIETARY / FE2C_GOOGLE_FMD; all others as OTHER.")

    scanner = BleakScanner(detection_callback=callback)
    await scanner.start()

    while True:
        await asyncio.sleep(1)


if __name__ == "__main__":
    try:
        asyncio.run(main())
    except KeyboardInterrupt:
        _console.info("Tracker stopped by user.")
        _csv_file.close()
