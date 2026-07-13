#!/bin/sh
# Build luci-stack.tar.gz (the LuCI C backend) from source with the shared newstack
# glibc-2.26 toolchain. Components built from pinned source: json-c, rpcd (+ its file/sys
# plugins), rpcd-mod-luci (luci.so), uhttpd, luci-bwc. Runtime support libs come from the
# license-clean newstack luci-bundle; static Lua/json/config come from build/stack-files/.
#
# Env knobs (for local dev vs CI):
#   CROSS       toolchain prefix (default arm-buildroot-linux-gnueabi-)
#   BUNDLE_DIR  pre-extracted bundle dir (else downloaded from BUNDLE_URL)
#   SRCDIR      dir with <pkg>-src.tar.gz (else downloaded from SRCBASE)
set -e
HERE=$(cd "$(dirname "$0")" && pwd)
WORK="${WORK:-$HERE/work}"; OUT="${OUT:-$HERE/out}"
rm -rf "$WORK" "$OUT"; mkdir -p "$WORK" "$OUT"; cd "$WORK"

CROSS="${CROSS:-arm-buildroot-linux-gnueabi-}"; CC="${CROSS}gcc"
command -v "$CC" >/dev/null || { echo "FATAL: toolchain $CC not on PATH"; exit 1; }
TCSYSROOT=$("$CC" -print-sysroot 2>/dev/null)
echo ">> $($CC --version | head -1)"

# --- bundle (hdrfix + platform sysroot + old-ABI libs) ---
if [ -n "$BUNDLE_DIR" ]; then B="$BUNDLE_DIR"; else
  curl -fsSL "${BUNDLE_URL:-https://github.com/lee-soft/newstack/releases/download/luci-bundle-v2/luci-bundle.tar.gz}" -o b.tgz
  tar xzf b.tgz; B="$WORK/luci-bundle"
fi
HDRFIX="$B/hdrfix"; SRINC="$B/sysroot/include"; SRLIB="$B/sysroot/lib"; UBOX="$B/libubox2013"; UBUS="$B/ubus2013"
STAGING="$WORK/staging"; INC="$WORK/inc"; mkdir -p "$STAGING" "$INC"

# --- sources ---
get() { if [ -n "$SRCDIR" ]; then cp "$SRCDIR/$1-src.tar.gz" "$1.tgz"; else
        curl -fsSL "${SRCBASE:-https://github.com/lee-soft/ax10-luci/releases/download/luci-src-v2}/$1-src.tar.gz" -o "$1.tgz"; fi
      tar xzf "$1.tgz"; }
for s in json-c rpcd uhttpd rpcd-mod-luci; do get "$s"; done

COMMON="-I$HDRFIX -I$SRINC -I$INC -Wno-error"
LFLAGS="-L$UBOX -L$UBUS -L$SRLIB -L$STAGING/lib -Wl,-rpath-link,$UBOX:$UBUS:$SRLIB:$STAGING/lib"
ROOTS="$B/sysroot;$TCSYSROOT;$STAGING;$UBOX;$UBUS"

# 1) json-c (autotools; source tarball ships a pre-generated ./configure) -> staging
cd "$WORK/json-c"
./configure --host=arm-buildroot-linux-gnueabi --prefix="$STAGING" CC="$CC" CFLAGS="-Wno-error -Os" --enable-shared --disable-static >/dev/null
make -j"$(nproc)" >/dev/null; make install >/dev/null
ln -sf "$STAGING/include/json-c" "$INC/json-c"
cd "$WORK"

cmk() { # $1=dir  $2=extra cflags  $3=extra ldflags
  cd "$WORK/$1"
  # the 19.07 sources use -Werror; the old-ABI headers trip implicit-decl/const warnings
  # even though the symbols exist in the linked libs (the original was built -Wno-error).
  find . -name CMakeLists.txt -exec sed -i 's/-Werror//g' {} + 2>/dev/null || true
  rm -rf B; mkdir B; cd B
  cmake .. -DCMAKE_SYSTEM_NAME=Linux -DCMAKE_C_COMPILER="$CC" \
    -DIWINFO_SUPPORT=OFF \
    -DCMAKE_FIND_ROOT_PATH="$ROOTS" \
    -DCMAKE_FIND_ROOT_PATH_MODE_PROGRAM=NEVER \
    -DCMAKE_FIND_ROOT_PATH_MODE_LIBRARY=BOTH \
    -DCMAKE_FIND_ROOT_PATH_MODE_INCLUDE=BOTH \
    -DCMAKE_C_FLAGS="$COMMON $2" \
    -DCMAKE_EXE_LINKER_FLAGS="$LFLAGS $3" \
    -DCMAKE_SHARED_LINKER_FLAGS="$LFLAGS $3" \
    -DCMAKE_MODULE_LINKER_FLAGS="$LFLAGS $3" $4 >/dev/null
  make -j"$(nproc)"
  cd "$WORK"
}

# 2) rpcd -> rpcd (+ file.so, rpcsys.so)
cmk rpcd "-Os -Wall --std=gnu99 -g3 -Wmissing-declarations -DHAVE_SHADOW"
# 3) uhttpd -> uhttpd, uhttpd_ubus.so  (baked runtime rpaths; no TLS/Lua like the router build)
cmk uhttpd "-Os -Wall -Wmissing-declarations --std=gnu99 -g3 -DHAVE_SHADOW -DHAVE_UBUS -D_FILE_OFFSET_BITS=64" "-Wl,-rpath,/tmp/luci:/tmp/rpcd/lib2" "-DTLS_SUPPORT=OFF -DLUA_SUPPORT=OFF"
# 4) rpcd-mod-luci -> luci.so  (links libnl-tiny + libiwinfo; CMakeLists looks for the
#    wrong libnl name, so pass LIBNL_LIBS explicitly)
cmk rpcd-mod-luci/src "-Os -Wall --std=gnu99 -g3 -Wmissing-declarations -I$SRINC/libnl-tiny -I$WORK/rpcd/include" "-liwinfo" "-DLIBNL_LIBS=nl-tiny"
# 5) luci-bwc (single translation unit; "noiw" = includes iwinfo.h but calls nothing in it)
"$CC" -Os -I"$HDRFIX" -I"$SRINC" -o "$WORK/luci-bwc" "$HERE/luci-bwc-noiw.c" -ldl

# --- assemble the luci-stack payload ---
PKG="$WORK/pkg"; rm -rf "$PKG"; mkdir -p "$PKG/tmp/rpcd/lib" "$PKG/tmp/rpcd/lib2" "$PKG/tmp/luci"
cp -a "$HERE/stack-files/." "$PKG/"                                  # etc/config/rpcd, acl.d, exec, www
cp "$WORK/rpcd/B/rpcd"                    "$PKG/tmp/rpcd.bin"
cp "$WORK/rpcd-mod-luci/src/B/luci.so"    "$PKG/tmp/rpcd/lib/luci.so"
cp "$WORK/uhttpd/B/uhttpd"                "$PKG/tmp/luci/uhttpd19"
cp "$WORK/uhttpd/B/uhttpd_ubus.so"        "$PKG/tmp/luci/uhttpd_ubus.so"
cp "$WORK/luci-bwc"                       "$PKG/tmp/luci-bwc"
# runtime libs (old-ABI libubox/ubus from the bundle + our json-c)
cp "$UBOX/libubox.so" "$UBUS/libubus.so" "$UBOX/libblobmsg_json.so" "$STAGING/lib/libjson-c.so.4.0.0" "$PKG/tmp/rpcd/lib2/"
cp "$UBOX/libubox.so" "$UBOX/libblobmsg_json.so" "$UBOX/libjson_script.so" "$STAGING/lib/libjson-c.so.4.0.0" "$PKG/tmp/luci/"
"${CROSS}strip" "$PKG/tmp/rpcd.bin" "$PKG/tmp/luci/uhttpd19" "$PKG/tmp/rpcd/lib/luci.so" "$PKG/tmp/luci/uhttpd_ubus.so" "$PKG/tmp/luci-bwc" 2>/dev/null || true
( cd "$PKG" && tar --owner=0 --group=0 -czf "$OUT/luci-stack.tar.gz" . )
echo ">> built $OUT/luci-stack.tar.gz ($(tar tzf "$OUT/luci-stack.tar.gz" | wc -l) entries)"
