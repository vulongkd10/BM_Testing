#!/usr/bin/env python3
# ==============================================================================
# Script: discover_ff1_device.py
# Location: testing/scripts/discover_ff1_device.py
# Purpose: Auto-discover active FF1 devices on local network via mDNS _ff1._tcp protocol per ffos-user specification
# Supports ignore filtering from testing/configurations/ignored_devices.json
# ==============================================================================

import os, sys, subprocess, time, json, urllib.request

def load_ignored_devices():
    script_dir = os.path.dirname(os.path.abspath(__file__))
    repo_root = os.path.abspath(os.path.join(script_dir, ".."))
    config_file = os.path.join(repo_root, "configurations", "ignored_devices.json")
    
    ignored = set()
    if os.path.exists(config_file):
        try:
            with open(config_file, "r") as f:
                data = json.load(f)
                items = data.get("ignored_devices", [])
                for item in items:
                    item_str = str(item).strip().lower()
                    if item_str:
                        ignored.add(item_str)
                        if item_str.endswith(".local"):
                            ignored.add(item_str[:-6])
                        else:
                            ignored.add(f"{item_str}.local")
        except Exception as e:
            print(f"[DISCOVERY] Warning loading ignored_devices.json: {e}", file=sys.stderr)
    return ignored

def is_ignored(device_identifier, ignored_set):
    if not device_identifier:
        return False
    dev_str = str(device_identifier).strip().lower()
    if dev_str in ignored_set:
        return True
    if dev_str.endswith(".local") and dev_str[:-6] in ignored_set:
        return True
    return False

def discover_mdns_ff1():
    print("[DISCOVERY] Browsing mDNS service _ff1._tcp on local network...", file=sys.stderr)
    cmd = "dns-sd -B _ff1._tcp local."
    p = subprocess.Popen(cmd, shell=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    time.sleep(2.5)
    p.terminate()
    stdout, _ = p.communicate()
    
    instances = []
    for line in stdout.splitlines():
        if "_ff1._tcp." in line and "Add" in line:
            parts = line.split()
            if len(parts) >= 7:
                inst_name = parts[-1]
                if inst_name not in instances:
                    instances.append(inst_name)
    return instances

def verify_ff1(host):
    target = f"{host}.local" if not host.endswith(".local") else host
    url = f"http://{target}:1111/api/status"
    try:
        req = urllib.request.Request(url)
        with urllib.request.urlopen(req, timeout=3) as resp:
            data = json.loads(resp.read().decode("utf-8"))
            return target, data
    except Exception:
        return None, None

def main():
    ignored_set = load_ignored_devices()
    if ignored_set:
        print(f"[DISCOVERY] Loaded ignored devices list ({len(ignored_set)} rules): {list(ignored_set)}", file=sys.stderr)

    env_ip = os.getenv("FF1_DEVICE_IP") or os.getenv("SMOKE_FF1_HUB_IP")
    if env_ip:
        if is_ignored(env_ip, ignored_set):
            print(f"[DISCOVERY] Manual FF1_DEVICE_IP={env_ip} is in ignored_devices list! Skipping...", file=sys.stderr)
        else:
            target, status = verify_ff1(env_ip)
            if target:
                dev_id = status.get("device_id", "")
                if is_ignored(dev_id, ignored_set):
                    print(f"[DISCOVERY] Device at {target} (ID: {dev_id}) is in ignored_devices list! Skipping...", file=sys.stderr)
                else:
                    print(f"[DISCOVERY] Verified manual FF1 device: {target} (Device ID: {dev_id})", file=sys.stderr)
                    print(target)
                    sys.exit(0)

    instances = discover_mdns_ff1()
    if instances:
        print(f"[DISCOVERY] Found {len(instances)} mDNS FF1 instances: {instances}", file=sys.stderr)
        for inst in instances:
            if is_ignored(inst, ignored_set):
                print(f"[DISCOVERY] Skipping ignored FF1 instance: {inst}", file=sys.stderr)
                continue
                
            target, status = verify_ff1(inst)
            if target:
                dev_id = status.get("device_id", "")
                if is_ignored(dev_id, ignored_set):
                    print(f"[DISCOVERY] Skipping ignored FF1 device ID: {dev_id} at {target}", file=sys.stderr)
                    continue
                print(f"[DISCOVERY] Verified active un-ignored FF1 device: {target} (Device ID: {dev_id})", file=sys.stderr)
                print(target)
                sys.exit(0)

    print("[DISCOVERY] Error: No active un-ignored FF1 device found via mDNS _ff1._tcp!", file=sys.stderr)
    sys.exit(1)

if __name__ == "__main__":
    main()
