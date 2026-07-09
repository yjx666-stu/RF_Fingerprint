#!/bin/bash

set -e

CAPTURE_DIR="/home/elf/rf_fingerprint/live_capture/video_demo_device1_auth_10s_1seg_auto"
OUT_DIR="/home/elf/rf_fingerprint/live_auth_monitor/video_demo_device1_auth_10s_1seg_auto"

echo "============================================================"
echo "LoRa RF Fingerprint Demo: device1 legal authentication"
echo "Mode: 10s capture + 1 segment authentication"
echo "============================================================"

echo "[1/5] Cleaning old files..."
rm -rf "$CAPTURE_DIR"
rm -rf "$OUT_DIR"

echo "[2/5] Start 10s IQ capture..."
python3 /home/elf/rf_fingerprint/scripts/uhd_continuous_recorder.py \
  --uhd_args "type=b200,serial=31D7705" \
  --freq 852.125e6 \
  --rate 2e6 \
  --gain 35 \
  --antenna RX2 \
  --segment_seconds 10 \
  --duration 11 \
  --out_dir "$CAPTURE_DIR"

echo "[3/5] Capture finished. Start authentication..."
python3 /home/elf/rf_fingerprint/scripts/trigger_auth_monitor.py \
  --capture_dir "$CAPTURE_DIR" \
  --out_dir "$OUT_DIR" \
  --claimed_device device1 \
  --authorized_devices device1 \
  --min_samples 20000000 \
  --min_file_size_bytes 160000000 \
  --fixed_session_mean_hz -3070.126984 \
  --session_mode \
  --stop_after_pass_segments 1 \
  --stop_after_mismatch_segments 5 \
  --max_active_segments 1 \
  --make_event_summary \
  --reset_state

echo "[4/5] Event summary:"
cat "$OUT_DIR/event_summary.json"

echo
echo "[5/5] Session state:"
cat "$OUT_DIR/session_state.json"

echo
echo
echo "============================================================"
echo "Final Result"
echo "============================================================"

# TODO: device1 legal demo should use the same claimed-device clean verifier
# after its auth_events.csv is confirmed:
# python3 /home/elf/rf_fingerprint/scripts/final_verify_claimed_device.py \
#   --auth_events_csv "$OUT_DIR/auth_events.csv" \
#   --claimed_device device1 \
#   --json_out "$OUT_DIR/final_verify_claimed_device.json" \
#   --print_final

python3 - <<PY2
import csv
import json
from pathlib import Path

summary_path = Path("$OUT_DIR/event_summary.json")
state_path = Path("$OUT_DIR/session_state.json")
events_path = Path("$OUT_DIR/auth_events.csv")

def load_json(path):
    if not path.exists():
        return {}
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except Exception:
        return {}

def last_event_vote(path):
    if not path.exists():
        return ""
    try:
        with path.open("r", newline="", encoding="utf-8-sig") as f:
            rows = list(csv.DictReader(f))
        if not rows:
            return ""
        return str(rows[-1].get("vote_pred", "") or "").strip()
    except Exception:
        return ""

summary = load_json(summary_path)
state = load_json(state_path)

AUTH_RESULT = str(summary.get("event_result", "") or "")
CLAIMED_DEVICE = str(summary.get("claimed_device", "") or "device1")
RFFI_RESULT = (
    str(summary.get("dominant_vote_pred", "") or summary.get("dominant_vote", "") or "").strip()
    or str(state.get("last_vote_pred", "") or "").strip()
    or last_event_vote(events_path)
    or "unknown"
)
STOP_REASON = str(state.get("stop_reason", "") or "")

if AUTH_RESULT == "auth_pass":
    print(f"识别通过！为已注册设备{CLAIMED_DEVICE}")
    print("身份合法")
else:
    print(f"识别未通过！未注册设备{RFFI_RESULT}")
    print("身份非法")

print("------------------------------------------------------------")
print(f"认证结果: {AUTH_RESULT}")
print(f"声明设备: {CLAIMED_DEVICE}")
print(f"射频指纹识别结果: {RFFI_RESULT}")
print(f"停止原因: {STOP_REASON}")
PY2

echo "============================================================"
