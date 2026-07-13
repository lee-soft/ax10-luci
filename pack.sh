#!/bin/sh
# Pack this package into an .ipk (the opkg "gzipped-tar of ./debian-binary
# ./control.tar.gz ./data.tar.gz" format this router's old opkg wants — NOT ar).
# For a from-source package, its build/ must have populated data/ first.
set -e
HERE="$(cd "$(dirname "$0")" && pwd)"
OUT="${OUT:-$HERE/dist}"; rm -rf "$OUT"; mkdir -p "$OUT"

name=$(awk -F': *' '/^Package:/{print $2; exit}' "$HERE/control")
ver=$(awk  -F': *' '/^Version:/{print $2; exit}' "$HERE/control")
arch=$(awk -F': *' '/^Architecture:/{print $2; exit}' "$HERE/control")
[ -n "$name" ] && [ -n "$ver" ] && [ -n "$arch" ] || { echo "control missing Package/Version/Architecture" >&2; exit 1; }

tmp=$(mktemp -d); cdir=$(mktemp -d)
( cd "$HERE/data" && tar --owner=0 --group=0 -czf "$tmp/data.tar.gz" . )
cp "$HERE/control" "$cdir/control"
for s in preinst postinst prerm postrm conffiles; do
    [ -f "$HERE/$s" ] && { cp "$HERE/$s" "$cdir/$s"; chmod 755 "$cdir/$s"; }
done
( cd "$cdir" && tar --owner=0 --group=0 -czf "$tmp/control.tar.gz" . )
echo "2.0" > "$tmp/debian-binary"

ipk="${name}_${ver}_${arch}.ipk"
( cd "$tmp" && tar --owner=0 --group=0 -czf "$OUT/$ipk" ./debian-binary ./data.tar.gz ./control.tar.gz )
rm -rf "$tmp" "$cdir"
echo "built $OUT/$ipk ($(wc -c < "$OUT/$ipk") bytes)"
