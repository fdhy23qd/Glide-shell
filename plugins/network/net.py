#!/usr/bin/env python3
import os, socket, ssl, subprocess, sys, time, urllib.request
from urllib.parse import urlparse

raw = os.environ.get("QP_TEXT", "").strip()
cmd = sys.argv[1] if len(sys.argv) > 1 else ""
host = urlparse(raw if "://" in raw else "//" + raw).hostname or raw


def main():
    if cmd == "ping":
        r = subprocess.run(["ping", "-c", "3", "-W", "2", host], capture_output=True, text=True, timeout=20)
        if r.returncode != 0:
            raise SystemExit(f"{host}: недоступен")
        print(f"{host}\n" + "\n".join(r.stdout.strip().splitlines()[-2:]))
    elif cmd == "dns":
        addrs = sorted({i[4][0] for i in socket.getaddrinfo(host, None)})
        print(host + "\n" + "\n".join(addrs))
    elif cmd == "ssl":
        ctx = ssl.create_default_context()
        with socket.create_connection((host, 443), timeout=6) as s:
            with ctx.wrap_socket(s, server_hostname=host) as ss:
                cert = ss.getpeercert()
        left = (ssl.cert_time_to_seconds(cert["notAfter"]) - time.time()) / 86400
        subj = dict(x[0] for x in cert["subject"]).get("commonName", "?")
        issuer = dict(x[0] for x in cert["issuer"]).get("organizationName", "?")
        print(f"{host}\nCN: {subj}\nвыдан: {issuer}\nдо: {cert['notAfter']}\nосталось дней: {left:.0f}")
    elif cmd == "headers":
        url = raw if "://" in raw else "https://" + raw
        req = urllib.request.Request(url, method="HEAD", headers={"User-Agent": "glide-shell"})
        with urllib.request.urlopen(req, timeout=8) as r:
            print(f"HTTP {r.status} {url}")
            for k, v in r.headers.items():
                print(f"{k}: {v}")
    elif cmd == "myip":
        with urllib.request.urlopen("https://api.ipify.org", timeout=6) as r:
            print(r.read().decode().strip())
    elif cmd == "open":
        subprocess.Popen(["xdg-open", raw], start_new_session=True,
                         stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    else:
        raise SystemExit(f"неизвестная команда: {cmd}")


try:
    main()
except Exception as e:
    print(f"{type(e).__name__}: {e}", file=sys.stderr)
    sys.exit(1)
