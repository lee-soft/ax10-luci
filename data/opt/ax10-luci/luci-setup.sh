#!/bin/sh
# ax10-luci setup — the boot.sh "MODERN LuCI BACKEND" block as a package step.
# Extracts the cross-built 19.07 rpcd/uhttpd stack + the 21.02 UI tree, wires them
# up, and supervises rpcd + uhttpd via init-respawn (ax10-svc) — retiring webwatch.
# Idempotent (safe to re-run).
P=/tmp/opt/ax10-luci

# ---- 19.07 rpcd + uhttpd + our C modules (tarball paths live under /tmp) ----
/bin/gzip -dc "$P/luci-stack.tar.gz" | /bin/tar xf - -C /
mkdir -p /tmp/rpcd/exec
ln -sf libjson-c.so.4.0.0 /tmp/rpcd/lib2/libjson-c.so.4
ln -sf libjson-c.so.4.0.0 /tmp/luci/libjson-c.so.4
chmod +x /tmp/rpcd.bin /tmp/luci/uhttpd19 /tmp/luci/uhttpd_ubus.so /tmp/rpcd/lib/luci.so /tmp/rpcd/exec/* 2>/dev/null
chmod +x /tmp/luci-bwc 2>/dev/null
mkdir -p /var/lib/luci-bwc/if /var/lib/luci-bwc/radio

# ---- full LuCI 21.02 web UI tree ----
rm -rf /tmp/luci-app; mkdir -p /tmp/luci-app
/bin/gzip -dc "$P/luci-dist.tar.gz" | /bin/tar xf - -C /tmp/luci-app
ln -sf liblucihttp.so /tmp/luci-app/usr/lib/liblucihttp.so.0
cp /tmp/luci-app/file.so /tmp/rpcd/lib/file.so
cp /tmp/luci-app/usr/share/rpcd/acl.d/*.json /tmp/rpcd/acl.d/ 2>/dev/null
[ -f /tmp/luci-app/etc/config/luci ] && cp /tmp/luci-app/etc/config/luci /etc/config/luci
[ -f /etc/board.json ] || cat > /etc/board.json <<'BOARDJSON'
{ "model": { "id": "tplink,archer-ax10", "name": "TP-Link Archer AX10 (Broadcom BCM963178)" },
  "network": { "lan": { "ports": ["eth1","eth2","eth3","eth4"], "protocol": "static" },
               "wan": { "device": "eth0", "protocol": "dhcp" } } }
BOARDJSON
chmod +x /tmp/luci-app/www/cgi-bin/luci /tmp/luci-app/www/cgi-bin/luci.lua 2>/dev/null

# cgi-io helpers (syslog/download/upload/backup) — uhttpd strips LD_LIBRARY_PATH
# from CGI env, so each /cgi-bin/cgi-* is a wrapper that sets it + execs the real one.
mkdir -p /tmp/cgiio
cp /tmp/luci-app/usr/libexec/cgi-io /tmp/cgiio/cgi-io && chmod +x /tmp/cgiio/cgi-io
for m in cgi-exec cgi-download cgi-upload cgi-backup; do
    ln -sf cgi-io /tmp/cgiio/$m
    printf '#!/bin/sh\nexport LD_LIBRARY_PATH=/tmp/rpcd/lib2:/tmp/luci\nexec /tmp/cgiio/%s "$@"\n' "$m" > /tmp/luci-app/www/cgi-bin/$m
    chmod +x /tmp/luci-app/www/cgi-bin/$m
done

# ---- foreground launchers (env baked in) for init-respawn supervision ----
if [ -d /tmp/luci-app/www ]; then UHDOC=/tmp/luci-app/www; else UHDOC=/tmp/luci/www; fi
cat > "$P/run-rpcd" <<'RPCD'
#!/bin/sh
export LD_LIBRARY_PATH=/tmp/rpcd/lib2
exec /tmp/rpcd.bin -s /var/run/ubus.sock
RPCD
cat > "$P/run-uhttpd" <<UHTTPD
#!/bin/sh
export LD_LIBRARY_PATH=/tmp/luci:/tmp/rpcd/lib2:/tmp/luci-app/usr/lib
exec /tmp/luci/uhttpd19 -f -h $UHDOC -p 0.0.0.0:8080 -x /cgi-bin -u /ubus -U /var/run/ubus.sock
UHTTPD
chmod +x "$P/run-rpcd" "$P/run-uhttpd"

# ---- stop old boot.sh-launched instances + webwatch, then supervise via init ----
/usr/bin/killall rpcd.bin uhttpd19 2>/dev/null
for d in /proc/[0-9]*; do c=$(tr '\0' ' ' < "$d/cmdline" 2>/dev/null); case "$c" in *webwatch*) kill "${d#/proc/}" 2>/dev/null ;; esac; done
/tmp/opt/ax10-svc add luci-rpcd /bin/sh "$P/run-rpcd"
/bin/sleep 1
/tmp/opt/ax10-svc add luci-uhttpd /bin/sh "$P/run-uhttpd"
