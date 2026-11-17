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
| `demo` managers lab: mount, share, camera deny/deny/grant, paste/copy, file pick | Android 15 AVD, KernelSU / KernelSU Next, Mountify | `demo v0.1.39` | simulator | [observations/avd-35-x86_64/managers-2026-10-02.md](https://github.com/p0g-stack/devicelab/blob/main/observations/avd-35-x86_64/managers-2026-10-02.md) |
| `demo` `module.prop`, app plane, Hybrid Mount on real hardware | OnePlus phone, KernelSU Next, Hybrid Mount 4.2.0 | `demo v0.1.39`, app plane `0.53.0-webui.6` | physical | [observations/real-device/hybrid-mount-2026-10-02.md](https://github.com/p0g-stack/devicelab/blob/main/observations/real-device/hybrid-mount-2026-10-02.md) |
| `demo` `.aerap` in AERA Recovery | Cuttlefish x86_64, image `aera-cf-x86_64-90aeba8-242db857a00545f4` | `devicelab@e52cc62`, kit-3.47.5 | simulator | [aera-cf run 37582507317](https://github.com/p0g-stack/devicelab/actions/runs/37582507317), gate list in [aera/DEFICIENCIES.md](https://github.com/p0g-stack/devicelab/blob/main/aera/DEFICIENCIES.md) |
| `demo` `.aerap` on hardware (Adreno via DRM atomic commit) | OnePlus 15 "infiniti", image `aera-infiniti-arm64-040070f-b413b91c42e5fd41` | `Flutter-Demo-0.1.42.aerap` (Host API 3) | physical | [aera/DEFICIENCIES.md](https://github.com/p0g-stack/devicelab/blob/main/aera/DEFICIENCIES.md), "On hardware: infiniti" |
| flutter-aera kit and embedder inside the AERA image: settings, picker, lifecycle, volatile, back on/off, taps, D10 A/B, rotate, first-Home, D5 A/B, input slots | Cuttlefish x86_64, image `aera-cf-x86_64-90aeba8-242db857a00545f4` | `flutter-aera@5c54636`, recovery `90aeba8` | simulator | [aera/DEFICIENCIES.md](https://github.com/p0g-stack/devicelab/blob/main/aera/DEFICIENCIES.md), gate for the infiniti image, [lab-results run 37083192787](https://github.com/p0g-stack/devicelab/tree/lab-results/runs/20261003T011751Z-aera-cf-recovery-37083192787) |
| flutter-aera embedder on hardware: side-edge taps, Recents arming on a still press, rotation repaint, per-axis surface scale, touch slots | OnePlus 15 "infiniti", image `aera-infiniti-arm64-040070f-b413b91c42e5fd41` | patches 0015/0025/0029/F0001, embedder `flutter-aera@4803872` | physical | [aera/DEFICIENCIES.md](https://github.com/p0g-stack/devicelab/blob/main/aera/DEFICIENCIES.md), H1/H2/H3/D5/D9 on infiniti |
| AERA runtime kit `kit-3.47.5` (arm64 debug `12b9a131…`, x64 debug `89502b18…`) | assembled on GitHub-hosted arm64 and x64 runners | `flutter-aera` Kit workflow; tag re-uploaded with `--clobber` | built | [release kit-3.47.5](https://github.com/p0g-stack/flutter-aera/releases/tag/kit-3.47.5) ([Kit run 37586977375](https://github.com/p0g-stack/flutter-aera/actions/runs/37586977375); assets dated 2026-10-04) |
| AERA engine `engine-af7e796-0d7f3ed2` (4 zips, per-zip `.sha256`) | GitHub-hosted runners | `flutter-aera@64e2586` | built | [Engine run 37086019959](https://github.com/p0g-stack/flutter-aera/actions/runs/37086019959) |
| Patched web SDK `web-sdk-3.47.5-af7e796-93b29c6` | GitHub-hosted runner | `flutter-webui@93b29c6` | built | [web-sdk-release run 37085433752](https://github.com/p0g-stack/flutter-webui/actions/runs/37085433752) |
| `p0g_app` brick generates and builds an app | GitHub-hosted runner, Flutter 3.47.5 | `bricks@0154a7e` | built | [ci run 42962135983](https://github.com/p0g-stack/bricks/actions/runs/42962135983) |
| `squadron_process` process place | GitHub-hosted runner, Dart 3.13.4 | `squadron_process@020fea9` | built | [test run 37085895930](https://github.com/p0g-stack/squadron_process/actions/runs/37085895930) |
| `webui-packages` plugin packages | GitHub-hosted runner, Flutter 3.47.5 | `webui-packages@7bfff1a` | built | [ci run 37085907275](https://github.com/p0g-stack/webui-packages/actions/runs/37085907275) |
| `webui-termux-api` module APK (`assembleDebug`, Java 17) | GitHub-hosted runner, Gradle 8.9 / AGP 8.7.3 | `webui-termux-api@c8675d0` | built | [build run 44037007753](https://github.com/p0g-stack/webui-termux-api/actions/runs/44037007753) |
| `flutter_p0g` tool | GitHub-hosted runner, Flutter 3.47.5 | `flutter_p0g@5d376dd` | built | [ci run 42962612537](https://github.com/p0g-stack/flutter_p0g/actions/runs/42962612537) |
| `flasher-web` web build, CLI, Rust crates, Worker | GitHub-hosted runner, Flutter 3.47.9; Chromium through the e2e harness for the release page | `flasher-web@bfe7278`, `flutter_p0g@2612b4d`, `bricks@4db4a41` | browser | [ci run 44131481193](https://github.com/p0g-stack/flasher-web/actions/runs/44131481193): bootstrap reproducibility, all suites, fake-fastboot marker rejected in the release, read-only release-page smoke on the built artifacts |
| Patched web SDK `web-sdk-3.47.9-89c39ed-72df180` | GitHub-hosted runner | producer `flutter-webui@374766e` (ancestor of the pinned client `72df180`), engine `89c39ed`, Flutter 3.47.9 | built | [web-sdk-release run 44037794716](https://github.com/p0g-stack/flutter-webui/actions/runs/44037794716) |
| `webui-termux-api` module APK `0.53.0-webui.10` (targetSdk 37) | GitHub-hosted runner, Gradle/AGP as in the workflow | `webui-termux-api@7cab1c4` | built | [build run 44128324313](https://github.com/p0g-stack/webui-termux-api/actions/runs/44128324313), [WebUI Release run 44128867317](https://github.com/p0g-stack/webui-termux-api/actions/runs/44128867317) |
| `demo` candidate `0.1.63` artifacts: native APK (release-signed), web build, WebUI module lab zip, `.aerap`, AERA kit link | GitHub-hosted runners | `demo@f36beec`, `flutter_p0g@2612b4d`, kit `kit-3.47.9-0c28b4e` | built | [ci run 44131475043](https://github.com/p0g-stack/demo/actions/runs/44131475043): every artifact hash checked against its `candidate.json`, signing cert sha256 `03dd05c9…d846` |

The rows above are the whole claim. Two documents elsewhere still say less
than this table shows:

- `flutter-aera`'s README says "Not yet: a run inside an AERA image
  (devicelab's Cuttlefish build), a device run". Both have happened; see the
  two flutter-aera rows above. What is still missing there is an
  `example/` `.aerap`, not a run.
- The upstream submission table below records the actual PR state, not the
  "submitted, awaiting review" the old notes implied.

## Retired WebUI X hosts

WebUI X v438 Portable and v608 Play are retired, not unqualified targets.
Support follows the latest stable WebUI X (v660). The non-WebUI-X route is
KernelSU manager plus webui-termux-api. These rows preserve historical
evidence only; neither old APK remains in the active manager matrix.

| Retired target | Historical host | Source refs | Historical level | Evidence |
|---|---|---|---|---|
| `demo` module: root process, Back, app plane, shortcut, close timing, on WebUI X v608 as well as v438 | Android 15 AVD, KernelSU 3.3.0; WebUI X Portable v438 and WebUI X v608 (Play, sha256 `ae88a8ca…afb2`) | `demo v0.1.59` (`a3fc86f`), `flutter-webui@8951e5f` | simulator | [observations/avd-35-x86_64/webuix-v608-2026-10-05.md](https://github.com/p0g-stack/devicelab/blob/main/observations/avd-35-x86_64/webuix-v608-2026-10-05.md) (last section), [run 37289032287](https://github.com/p0g-stack/devicelab/actions/runs/37289032287), [run 37295018165](https://github.com/p0g-stack/devicelab/actions/runs/37295018165) |
| WebUI X v608 page extras: package list and info, `ksu://icon`, `webui.createShortcut` + pin dialog, SHELL refusal | Android 15 AVD, WebUI X v608 (Play); v438 and KernelSU 3.3.0 for contrast | `extras_lab v1.0.0` (`cdfd6048…`), `flutter-webui@60c0b77` | simulator | [webuix-v608-2026-10-05.md](https://github.com/p0g-stack/devicelab/blob/main/observations/avd-35-x86_64/webuix-v608-2026-10-05.md) ("flutter-webui 60c0b77 extras lab"), [run 37281608189](https://github.com/p0g-stack/devicelab/actions/runs/37281608189), [run 37283223230](https://github.com/p0g-stack/devicelab/actions/runs/37283223230) (extras-only runs: the job reports failure because no standard checklist ran; the case data is complete) |

## Upstream submissions (AERA Recovery)

State read from GitHub on 2026-11-17. Upstream `aera-16.0` is at `1cabc509`;
these were submitted against `92813466`. Recovery PRs #4–#16 were opened from
the org forks on 2026-10-05 and closed on 2026-10-06; #15 was merged the same
day. The rest stay carried locally as patches.

| PR | Patch | State |
|---|---|---|
| [#4](https://github.com/AERA-Recovery/android_bootable_recovery/pull/4) | 0010 prebuilt: pack libincfs.so | closed, unmerged |
| [#5](https://github.com/AERA-Recovery/android_bootable_recovery/pull/5) | 0013 minuitwrp: primary plane without an SDE topology | closed, unmerged |
| [#6](https://github.com/AERA-Recovery/android_bootable_recovery/pull/6) | 0014 prebuilt: pack task_profiles.json | closed, unmerged |
| [#7](https://github.com/AERA-Recovery/android_bootable_recovery/pull/7) | 0016 aeraui: take an RPC request whose writer hung up | closed, unmerged |
| [#8](https://github.com/AERA-Recovery/android_bootable_recovery/pull/8) | 0025 minuitwrp: start a contact where its slot last was | closed, unmerged |
| [#9](https://github.com/AERA-Recovery/android_bootable_recovery/pull/9) | 0026 aeraui: draw landscape on the software renderer | closed, unmerged |
| [#10](https://github.com/AERA-Recovery/android_bootable_recovery/pull/10) | R0001 aera_remote: create the virtual input device at start | closed, unmerged |
| [#11](https://github.com/AERA-Recovery/android_bootable_recovery/pull/11) | R0002 aera_remote: fresh screenshot per request | closed, unmerged |
| [#12](https://github.com/AERA-Recovery/android_bootable_recovery/pull/12) | R0003 aeraui: act on the Home and Menu keys | closed, unmerged |
| [#13](https://github.com/AERA-Recovery/android_bootable_recovery/pull/13) | C0001 aeraui: libwebp SSE2/SSE4.1 sources | closed, unmerged |
| [#14](https://github.com/AERA-Recovery/android_bootable_recovery/pull/14) | 0018 aeraui: shared file picker | closed, unmerged |
| [#15](https://github.com/AERA-Recovery/android_bootable_recovery/pull/15) | F0001 aeraui: arm the Recents swipe on movement | **merged** 2026-10-06 (`b251aa20`) |
| [#16](https://github.com/AERA-Recovery/android_bootable_recovery/pull/16) | H3 plugin_api: Host API 3 pixel plugins | closed, unmerged |
| [lvgl #6](https://github.com/AERA-Recovery/android_external_lvgl/pull/6) | lvgl 0002: `LV_DRAW_TRANSFORM_USE_MATRIX` 1→0 | closed (withdrawn), unmerged |
| [lvgl #7](https://github.com/AERA-Recovery/android_external_lvgl/pull/7) | lvgl 0003: oversized layer draw | closed (withdrawn), unmerged |

Two consequences that are decisions, not observations:

- The local series keeps F0001 even though upstream has it, because the
  local form also routes pixel-plugin input and is not the merged code.
- Host API 3 stays pinned at `92813466` and is not renumbered. Upstream
  declined it, and its Host API 2 now uses the same message kinds (12–14,
  68–75) and feature bits (2–4) for different things. A replacement is a
  separate track: see the AERA decision in the rework plan.

## Unverified

These are open, not proven:

- `flasher-web` on a physical phone over WebUSB or native USB: no real OTA
  has been flashed. Every run so far drives a fake fastboot transport and
  synthetic OTA packages.
- `flasher-web` in Android Chrome and in Edge: targeted, not yet exercised.
- AERA kits other than debug (profile and release): not produced.
- AERA audio on hardware (the device tree starts no `aera-audio-bridge`) and
  the recovery domain's permissive SELinux state: known gaps, no fix.
- AERA Host API 2 as extended upstream (background tasks, desktop surfaces,
  clipboard, native text fields, Files selection): read, not run. Do not
  reuse our message kinds 12–14 or 68–75, or feature bits 2–4, against it.
- `flutter_p0g install`, `devices` and `logs` on a real device: tested against
  a fake `adb` only.
- WebUI X v660 on physical devices and the newer upstream picker protocol:
  not qualified by Android AVD runs. Do not reuse colliding host-API identifiers.
- Predictive-back gestures: no evidence yet. The AVD's SystemUI keeps
  `EdgeBackGestureHandler` disabled (`navigation_mode=2`, TaskbarDelegate), so
  the swipe cases of the extras lab cannot run there; they need a device or
  another image. Physical-panel gesture behaviour is likewise unverified
  beyond the Infiniti taps in the row above.
- Manager versions beyond the exact versions named in the evidence rows
  are not covered by those rows.
- `demo`'s wasm build under `/demo/`: the published smoke covers the JS build
  only.
- `demo` release artifacts after `v0.1.59`: the physical and simulator rows
  above are bound to the versions they name, not to the newest release.
