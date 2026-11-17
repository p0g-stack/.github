# What is verified

Every row names the target, the host and version it ran on, the source refs
that produced it, the verification level, and the run or observation that
backs it. A claim without such a row is not a claim; say "unverified".

Levels, weakest class first: `built` (compiles, unit tests pass, artifact
assembles), `browser` (ran in a real browser), `simulator` (ran in an AVD or
a Cuttlefish VM), `physical` (ran on hardware). A lower level never stands in
for a higher one, and a simulator run never becomes a physical-device claim.

Evidence lives where it was produced: CI runs in the repository that ran
them, and observations in `devicelab/observations/` or the owning
repository's docs. Device logs, screenshots and local archives stay local;
rows link to the public record instead.

## Verified

| Target | Host and version | Source refs | Level | Evidence |
|---|---|---|---|---|
| `demo` web build (JS, single-threaded wasm-free page) | headless Chromium, Ubuntu, static server under `/demo/` | `demo@a3fc86f`, `flutter_p0g@e739ada`, Flutter 3.47.5 | browser | [ci run 37285804931](https://github.com/p0g-stack/demo/actions/runs/37285804931) (`web` job, Chromium smoke check) |
| `demo` published site | GitHub Pages, Chrome-class browser | `web` branch, built from `a3fc86f` | browser | <https://p0g-stack.github.io/demo/> ([pages run 37286481231](https://github.com/p0g-stack/demo/actions/runs/37286481231)) |
| `demo` WebUI module zip | assembled in CI, no run | `demo@a3fc86f`, `flutter_p0g@e739ada` | built | [ci run 37285804931](https://github.com/p0g-stack/demo/actions/runs/37285804931) (`module` job) |
| `demo` module page in a manager, root process, Back, shortcut | Android 15 AVD, KernelSU 3.3.0; WebUI X Portable v438 and v608 | `demo v0.1.56` (`8f9ed02`) | simulator | [observations/avd-35-x86_64/webuix-v608-2026-10-05.md](https://github.com/p0g-stack/devicelab/blob/main/observations/avd-35-x86_64/webuix-v608-2026-10-05.md), [run 37267308747](https://github.com/p0g-stack/devicelab/actions/runs/37267308747) |
| `demo` managers lab: mount, share, camera deny/deny/grant, paste/copy, file pick | Android 15 AVD, KernelSU / KernelSU Next, Mountify | `demo v0.1.39` | simulator | [observations/avd-35-x86_64/managers-2026-10-02.md](https://github.com/p0g-stack/devicelab/blob/main/observations/avd-35-x86_64/managers-2026-10-02.md) |
| `demo` `module.prop`, app plane, Hybrid Mount on real hardware | OnePlus phone, KernelSU Next, Hybrid Mount 4.2.0 | `demo v0.1.39`, app plane `0.53.0-webui.6` | physical | [observations/real-device/hybrid-mount-2026-10-02.md](https://github.com/p0g-stack/devicelab/blob/main/observations/real-device/hybrid-mount-2026-10-02.md) |
| `demo` `.aerap` in AERA Recovery | Cuttlefish x86_64, image `aera-cf-x86_64-90aeba8-242db857a00545f4` | `devicelab@e52cc62`, kit-3.47.5 | simulator | [aera-cf run 37582507317](https://github.com/p0g-stack/devicelab/actions/runs/37582507317), gate list in [aera/DEFICIENCIES.md](https://github.com/p0g-stack/devicelab/blob/main/aera/DEFICIENCIES.md) |
| `demo` `.aerap` on hardware (Adreno via DRM atomic commit) | OnePlus 15 "infiniti", image `aera-infiniti-arm64-040070f-b413b91c42e5fd41` | `Flutter-Demo-0.1.42.aerap` (Host API 3) | physical | [aera/DEFICIENCIES.md](https://github.com/p0g-stack/devicelab/blob/main/aera/DEFICIENCIES.md), "On hardware: infiniti" |
| AERA runtime kit `kit-3.47.5` (arm64 debug `12b9a131…`, x64 debug `89502b18…`) | assembled on GitHub-hosted arm64 and x64 runners | `flutter-aera` Kit workflow; tag re-uploaded with `--clobber` | built | [release kit-3.47.5](https://github.com/p0g-stack/flutter-aera/releases/tag/kit-3.47.5) ([Kit run 37586977375](https://github.com/p0g-stack/flutter-aera/actions/runs/37586977375); assets dated 2026-10-04) |
| AERA engine `engine-af7e796-0d7f3ed2` (4 zips, per-zip `.sha256`) | GitHub-hosted runners | `flutter-aera@64e2586` | built | [Engine run 37086019959](https://github.com/p0g-stack/flutter-aera/actions/runs/37086019959) |
| Patched web SDK `web-sdk-3.47.5-af7e796-93b29c6` | GitHub-hosted runner | `flutter-webui@93b29c6` | built | [web-sdk-release run 37085433752](https://github.com/p0g-stack/flutter-webui/actions/runs/37085433752) |
| `p0g_app` brick generates and builds an app | GitHub-hosted runner, Flutter 3.47.5 | `bricks@0154a7e` | built | [ci run 42962135983](https://github.com/p0g-stack/bricks/actions/runs/42962135983) |
| `squadron_process` process place | GitHub-hosted runner, Dart 3.13.4 | `squadron_process@020fea9` | built | [test run 37085895930](https://github.com/p0g-stack/squadron_process/actions/runs/37085895930) |
| `webui-packages` plugin packages | GitHub-hosted runner, Flutter 3.47.5 | `webui-packages@7bfff1a` | built | [ci run 37085907275](https://github.com/p0g-stack/webui-packages/actions/runs/37085907275) |
| `webui-termux-api` module APK (`assembleDebug`, Java 17) | GitHub-hosted runner, Gradle 8.9 / AGP 8.7.3 | `webui-termux-api@c8675d0` | built | [build run 44037007753](https://github.com/p0g-stack/webui-termux-api/actions/runs/44037007753) |
| `flutter_p0g` tool | GitHub-hosted runner, Flutter 3.47.5 | `flutter_p0g@5d376dd` | built | [ci run 42962612537](https://github.com/p0g-stack/flutter_p0g/actions/runs/42962612537) |
| `flasher-web` app, CLI, Rust crates, Worker | local Linux host, Flutter 3.47.5 | `flasher-web@0236a72` | built | its own suites; fake fastboot device only (not yet published) |

## Unverified

These are open, not proven:

- `flasher-web` on a physical phone over WebUSB or native USB: no real OTA
  has been flashed. Every run so far drives a fake fastboot transport and
  synthetic OTA packages.
- `flasher-web` in Android Chrome and in Edge: targeted, not yet exercised.
- AERA kits other than debug (profile and release): not produced.
- AERA audio on hardware (the device tree starts no `aera-audio-bridge`) and
  the recovery domain's permissive SELinux state: known gaps, no fix.
- `flutter_p0g install`, `devices` and `logs` on a real device: tested against
  a fake `adb` only.
- WebUI X v648 and the newer upstream picker protocol: unqualified. Do not
  port `ksu.pm()` or reuse colliding host-API identifiers before qualifying
  them.
- Predictive-back gestures, newer manager versions and physical-panel
  behaviour: no evidence yet.
- `demo`'s wasm build under `/demo/`: the published smoke covers the JS build
  only.
- `demo` release artifacts after `v0.1.59`: the physical and simulator rows
  above are bound to the versions they name, not to the newest release.
