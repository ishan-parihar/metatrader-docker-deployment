#!/bin/bash
# Measures TCP RTT to the MT5 container's LIVE trade-server peer (ground truth
# vs any generic ping). Run after the terminal is logged in.
PEERS=$(docker exec mt5-terminal python3 - <<'PY' 2>/dev/null
import socket,struct
for line in open("/proc/net/tcp"):
    f=line.split()
    if len(f)>3 and f[3]=="01":
        ip,port=f[2].split(":")
        ip=socket.inet_ntoa(struct.pack("<I",int(ip,16))); port=int(port,16)
        if not ip.startswith(("127.","172.","10.","192.168.")): print(f"{ip}:{port}")
PY
)
[ -z "$PEERS" ] && { echo "terminal not connected yet — log in first"; exit 1; }
for P in $PEERS; do IP=${P%:*}; PT=${P#*:}
  RTT=$(python3 -c "
import socket,time
ts=[]
for _ in range(5):
    s=socket.socket(); s.settimeout(3); t=time.time()
    try: s.connect((\"$IP\",$PT)); ts.append((time.time()-t)*1000)
    except Exception: pass
    finally: s.close()
print(f\"{min(ts):.1f}/{sum(ts)/len(ts):.1f} ms (min/avg)\" if ts else \"unreachable\")")
  ORG=$(curl -s ipinfo.io/$IP | python3 -c "import json,sys;d=json.load(sys.stdin);print(d.get('city'),d.get('country'),d.get('org'))" 2>/dev/null)
  echo "$IP:$PT  RTT $RTT  [$ORG]"
done
