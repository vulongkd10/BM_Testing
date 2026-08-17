#!/usr/bin/env python3
import os, sys, socket, subprocess, concurrent.futures

def check_ssh_access(ip):
    user = os.getenv("FFOS_REMOTE_USER", "feralfile")
    password = os.getenv("FFOS_REMOTE_PASS", "portal")
    cmd = f"sshpass -p '{password}' ssh -o StrictHostKeyChecking=no -o ConnectTimeout=2 {user}@{ip} echo OK"
    try:
        res = subprocess.run(cmd, shell=True, capture_output=True, text=True, timeout=3)
        if res.returncode == 0 and "OK" in res.stdout:
            return True
    except Exception:
        pass
    return False

def check_ip(ip):
    for port in [1111, 22]:
        s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        s.settimeout(0.3)
        res = s.connect_ex((ip, port))
        s.close()
        if res == 0:
            if check_ssh_access(ip):
                return ip
    return None

def get_local_subnets():
    subnets = set()
    try:
        output = subprocess.check_output("ifconfig", text=True)
        for line in output.splitlines():
            if "inet " in line and "127.0.0.1" not in line:
                parts = line.strip().split()
                ip = parts[1]
                if ip.count(".") == 3:
                    ip_parts = ip.split(".")
                    subnet = ".".join(ip_parts[:3])
                    subnets.add(subnet)
    except Exception:
        subnets.add("192.168.31")
    return list(subnets)

def discover_device():
    env_ip = os.getenv("FF1_DEVICE_IP") or os.getenv("SMOKE_FF1_HUB_IP")
    if env_ip:
        if check_ssh_access(env_ip):
            return env_ip
        else:
            print(f"[DISCOVERY] Warning: Manual FF1_DEVICE_IP={env_ip} specified but SSH check failed.", file=sys.stderr)

    subnets = get_local_subnets()
    for subnet in subnets:
        print(f"[DISCOVERY] Scanning local subnet {subnet}.x for active FF1 devices...", file=sys.stderr)
        target_ips = [f"{subnet}.{i}" for i in range(1, 255)]
        with concurrent.futures.ThreadPoolExecutor(max_workers=50) as executor:
            results = executor.map(check_ip, target_ips)
            for ip in results:
                if ip:
                    return ip
    return None

if __name__ == "__main__":
    ip = discover_device()
    if ip:
        print(f"[DISCOVERY] Found active FF1 device at IP: {ip}", file=sys.stderr)
        print(ip)
        sys.exit(0)
    else:
        print("[DISCOVERY] Error: No active FF1 device found on local network!", file=sys.stderr)
        sys.exit(1)
