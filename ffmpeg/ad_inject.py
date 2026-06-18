#!/usr/bin/env python3
"""
Ad injector for live HLS streams.

Reads adSchedule from inputs.json and injects EXT-X-DATERANGE tags
into live HLS manifests at configured intervals.

Usage: python ad_inject.py <stream_name>
"""

import json
import os
import sys
import time
from datetime import datetime, timezone


def load_config(project_root):
    """Load inputs.json from project root."""
    config_path = os.path.join(project_root, "inputs.json")
    if not os.path.exists(config_path):
        print(f"ERROR: inputs.json not found at {config_path}")
        sys.exit(1)
    with open(config_path, "r") as f:
        return json.load(f)


def build_daterange_tag(ad_url, duration, break_id, start_date):
    """Build EXT-X-DATERANGE tag string for HLS interstitial."""
    return (
        f'#EXT-X-DATERANGE:ID="{break_id}",'
        f'CLASS="com.apple.hls.interstitial",'
        f'START-DATE="{start_date}",'
        f'DURATION={duration:.1f},'
        f'X-ASSET-URI="{ad_url}",'
        f'X-RESUME-OFFSET=0'
    )


def inject_tag_into_manifest(manifest_path, tag):
    """Inject EXT-X-DATERANGE tag into manifest after #EXT-X-TARGETDURATION."""
    # Single read — avoids race with FFmpeg rewrite
    try:
        with open(manifest_path, "r") as f:
            content = f.read()
    except Exception as e:
        print(f"  WARN: Failed to read {manifest_path}: {e}")
        return False

    # Skip if this exact tag is already present
    if tag in content:
        return True  # Already there

    lines = content.splitlines(keepends=True)

    # Find injection point: after #EXT-X-TARGETDURATION
    inject_idx = None
    for i, line in enumerate(lines):
        if line.strip().startswith("#EXT-X-TARGETDURATION"):
            inject_idx = i + 1
            break

    if inject_idx is None:
        for i, line in enumerate(lines):
            if line.strip().startswith("#EXTM3U"):
                inject_idx = i + 1
                break

    if inject_idx is None:
        print(f"  WARN: Could not find injection point in {manifest_path}")
        return False

    lines.insert(inject_idx, tag + "\n")

    # Atomic write: write to temp, then rename
    tmp_path = manifest_path + ".tmp"
    try:
        with open(tmp_path, "w") as f:
            f.writelines(lines)
        os.replace(tmp_path, manifest_path)
    except Exception as e:
        print(f"  WARN: Write failed: {e}")
        return False
    return True


def main():
    if len(sys.argv) < 2:
        print("Usage: python ad_inject.py <stream_name>")
        sys.exit(1)

    stream_name = sys.argv[1]
    script_dir = os.path.dirname(os.path.abspath(__file__))
    project_root = os.path.dirname(script_dir)

    config = load_config(project_root)
    ad_schedule = config.get("adSchedule", {})

    if not ad_schedule.get("enabled", False):
        print("Ad injection disabled in inputs.json (adSchedule.enabled = false)")
        sys.exit(0)

    interval = ad_schedule.get("interval", 60)
    ad_url = ad_schedule.get("adUrl", "/hls/ad/index.m3u8")
    duration = ad_schedule.get("duration", 10)
    lead_time = ad_schedule.get("leadTime", 15)

    print(f"Ad injector started for '{stream_name}'")
    print(f"  Interval: {interval}s")
    print(f"  Lead time: {lead_time}s")
    print(f"  Ad URL:   {ad_url}")
    print(f"  Duration: {duration}s")
    print()

    poll_interval = 0.5  # seconds — must be faster than FFmpeg manifest rewrite (~4s)
    manifest_path = os.path.join(project_root, "hls", stream_name, "stream.m3u8")
    print(f"  Manifest: {manifest_path}")
    print(f"  Exists:   {os.path.exists(manifest_path)}")
    print()

    last_break_start = time.time()
    active_tag = None
    active_tag_id = None
    active_tag_expiry = 0
    break_count = 0

    while True:
        try:
            if not os.path.exists(manifest_path):
                time.sleep(poll_interval)
                continue

            now = time.time()

            # If ad is active, keep re-injecting until it expires
            if active_tag and now < active_tag_expiry:
                inject_tag_into_manifest(manifest_path, active_tag)
                time.sleep(poll_interval)
                continue

            # If ad just expired, log it and reset
            if active_tag and now >= active_tag_expiry:
                print(f"[{stream_name}] Ad break #{break_count} ended")
                active_tag = None
                active_tag_id = None

            # Schedule the next break ahead of playback so the player has time to see it.
            next_break_start = last_break_start + interval
            time_until_break = next_break_start - now

            if time_until_break <= lead_time:
                break_count += 1
                break_id = f"ad-{stream_name}-{break_count:03d}"
                break_start_iso = datetime.fromtimestamp(next_break_start, timezone.utc).strftime("%Y-%m-%dT%H:%M:%S.000Z")
                active_tag = build_daterange_tag(ad_url, duration, break_id, break_start_iso)
                active_tag_id = break_id
                active_tag_expiry = next_break_start + duration + lead_time
                inject_tag_into_manifest(manifest_path, active_tag)
                print(f"[{stream_name}] Ad break #{break_count} scheduled for {break_start_iso} ({duration}s)")
                last_break_start = next_break_start

            time.sleep(poll_interval)

        except KeyboardInterrupt:
            print("\nAd injector stopped.")
            break
        except Exception as e:
            print(f"ERROR: {e}")
            time.sleep(poll_interval)


if __name__ == "__main__":
    main()
