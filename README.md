# ax10-luci

Modern **LuCI 21.02** web UI for the TP-Link Archer AX10, running a cross-built **19.07 rpcd +
uhttpd** on the firmware's 2013-vintage `ubusd`. Serves the web GUI on **:8080**. `rpcd` and
`uhttpd` are supervised by init-respawn via `ax10-svc` (this retires the old `webwatch`
keep-alive).

Part of the [archer-ax10](../../../archer-ax10) project. Depends on
[ax10-svc](../../../ax10-svc) and [ax10-wifi](../../../ax10-wifi) (so the wireless page can
actually apply changes).

## Install

```sh
opkg install ax10-luci        # pulls ax10-svc + ax10-wifi
```

Then browse to `http://<router>:8080` (log in with your web-GUI password — see the
[archer-ax10 README](../../../archer-ax10#password) on password mirroring).

## Contents

- `data/opt/ax10-luci/luci-stack.tar.gz` — the cross-built C stack (rpcd.bin, uhttpd19,
  luci.so, file.so, libjson-c, cgi-io, luci-bwc, and the 2013-ABI libubox/ubus).
- `data/opt/ax10-luci/luci-dist.tar.gz` — the LuCI 21.02 Lua + JS web UI tree.
- `data/opt/ax10-luci/luci-setup.sh` — extracts both, wires up json-c/liblucihttp symlinks,
  the cgi-io `LD_LIBRARY_PATH` wrappers, `board.json`, and registers rpcd + uhttpd with
  `ax10-svc`.

## Built from source

`luci-stack.tar.gz` (the C backend — `rpcd.bin`, `uhttpd19`, `luci.so`, `uhttpd_ubus.so`,
`luci-bwc`) is **built from source in CI** by `build/build.sh` inside the
[newstack](../../../newstack) glibc-2.26 toolchain image, from pinned OpenWrt-19.07 sources
(rpcd, uhttpd, rpcd-mod-luci, luci-bwc) + json-c 0.13, linked against the newstack
`luci-bundle` (the license-clean platform sysroot + the `hdrfix` ABI shims that let 19.07 code
build against the router's 2013 ubus ABI). Sources are mirrored to this repo's Releases; the
binaries are **not** committed. Validated on the router (serves LuCI on :8080).

`luci-dist.tar.gz` (the LuCI 21.02 Lua/JS web UI tree) is still **vendored** — building it from
source (assembling the UI + its Lua `.so` modules) is phase 2.

## License

MIT for the packaging (see LICENSE); bundled OpenWrt/LuCI binaries keep their upstream
licenses — see [THIRD-PARTY.md](../../../archer-ax10/THIRD-PARTY.md).
