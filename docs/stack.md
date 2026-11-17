# The stack

What each repository is, what it owns, and which contracts the others consume.
Current pin values are never copied here; every repository has a `PINS.md`
with its own pins, and the bump order across repositories is
[flutter-bump.md](flutter-bump.md).

The one snapshot that names values is [`stack.lock.json`](../stack.lock.json):
the Flutter/Dart versions and one full SHA per owner, read as consumers pin
them. `tool/check_pins.dart` checks every repository against it through
`git show <locked-sha>:<path>` ([check-stack](../.github/workflows/check-stack.yml)),
so a pin that drifts from the snapshot fails there rather than in an app
build.

`webSdkProducer` records the full flutter-webui commit that produced the
patched SDK. It may precede the `repos.flutter-webui` Dart/client source pin,
but must be its ancestor (or equal). Both commits must have the same
`web_ui/` tree, matching `kWebSdkTree`; the release tag, engine and Flutter
version must match their recorded pins. A source-only host update therefore
does not force a rebuild of unchanged SDK patches.

A pin need not be on a repository's `main`: a track that later moved on keeps
its own branch. The 3.47.9 checkpoint pins `flutter-webui` at the tip of
`webuix660-3.47.9` (72df180), because `main` went on to 3.50.0. Pins on a
branch are as durable as `main` only while that branch exists; do not delete a
track branch that the lock names.

## Languages and names

- A repository that is one Dart package uses the package name with
  underscores: `squadron_process`, `flutter_p0g`.
- Multi-package, multi-language or non-Dart repositories use hyphens:
  `flutter-webui`, `flutter-aera`, `webui-packages`, `webui-termux-api`,
  `flasher-web`.
- `flutter-webui` is all Dart; its root channel is a Dart AOT snapshot
  (`flutter_webui_root`) run by `dartaotruntime` through a POSIX `sh`
  launcher.
- `flutter-aera` stays Rust: it hosts the engine, and the Dart VM lives inside
  the engine.

## Layers

| Layer | What it does | Owner |
|---|---|---|
| Embedders | run a stock Flutter app and answer the engine's platform channels; parity with Linux GTK / flutter-pi, not Android | `flutter-webui`, `flutter-aera` |
| Tool | `flutter_p0g` on `flutter_tools`: `create .` adds `webui/` and `aera/`; `build web|webui|aera`, `run`, `install`, `precache`, `devices`, `logs` | `flutter_p0g` |
| Artifacts | patched web SDK, engines, Mesa, AERA runtime kits, the Android Dart kit, the app-plane APK, released by hash | the embedder and tool CI |
| Platform plugins | `*_webui` packages and the app plane | `webui-packages`, `webui-termux-api` |
| Places | a Squadron service in another, elevated process over a socket, plus that place's facts | `squadron_process` |
| App kit | Mason bricks: `p0g_app` (pub workspace `core/` pure Dart, `app/` Flutter, `cli/` Dart executable, optional `rust/`), `service`, `strategy`, `p0g_lints` | `bricks` |
| Apps | generated from `p0g_app` | `demo`, `flasher-web` |
| Device lab | the runs behind every supported-hosts claim | `devicelab` |

## Contracts

Each contract has one owner; the others consume it. A change lands in the
owner's documentation first.

| Contract | Owner | Consumers | Where it is written |
|---|---|---|---|
| WebUI root channel v1 | `flutter-webui` (`packages/flutter_webui_root`) | `bricks` (WebUI launcher), `webui-packages`, apps | `docs/root-channel.md` |
| Process place (`ProcessLauncher`, `EndpointStore`, socket channel, neutral facts map) | `squadron_process` | `bricks`, apps | `docs/launchers.md` |
| WebUI launch (`WebUiLauncher`, `WebUiSessionStore`) | `bricks` (`p0g_app`) | `demo`, `flasher-web` | the brick's `app/lib/places/` |
| Squadron channel-factory patch | `squadron_process` | `bricks`, apps | `third_party/squadron/PIN` and `patches/` |
| p0g facts keys (`root`, `block_devices`, `usb.native`, `usb.web`, `process.spawn`, `fs.persistent`, `net`) and their checks | `bricks` | apps | the generated app's `core/lib/src/facts/` |
| App shape (`core/`, `app/`, `cli/`, optional `rust/`), places, objectives, strategies, logging | `bricks` | `demo`, `flasher-web`, `flutter_p0g` | the `p0g_app` brick, `README.md` |
| Platform folders `webui/` and `aera/`, and each build output (module zip, `.aerap`, `build/web`) | `flutter_p0g` | apps, `flutter-webui`, `flutter-aera` | `README.md` |
| frb patch series | `flutter_p0g` | apps with `rust/`, `bricks` | `patches/frb/`, `README.md` |
| `web_ui` patch series | `flutter-webui` | `flutter_p0g` (builds with it) | `web_ui/patches`, `web_ui/VERSION` |
| AERA host contract (host API 2 is AERA's; API 3 is this patch series) | `flutter-aera` | `flutter_p0g`, `devicelab`, apps | `spec/host.md`, `spec/aerap.md` |
| App plane client | `webui-packages` | `flutter-webui` pre-check, apps | `docs/plugins.md` |

Notes the older documents get wrong:

- **The root channel is not a file under `webroot/`.** The page runs
  `sh <moddir>/flutter_webui/root start` through the manager's bridge; that
  prints the session (`protocol`, `version`, `port`, `token`, `pid`, `boot`,
  `started`) and records it in KernelSU's module config as `webui.session`.
  The page then opens one WebSocket on `127.0.0.1` with that token. Nothing of
  the channel is served to the page.
- **The frb patch series is two patches, not three.** `0001-build-web-no-threads`
  and `0003-web-worker-init` exist; `0002` (JSPI) is planned and not written.
  The series applies to flutter_rust_bridge `848e438`, master just after
  v2.14.0-beta.2, not to the tag.
- **The AERA build command is `flutter_p0g build aera`** (output: a `.aerap`),
  like `build webui` (a module zip) and `build web` (an ordinary web build).

## App conventions that cross repositories

- `core/` never imports `package:flutter`: the CLI runs on the plain Dart VM.
- Places: a service is a Squadron service; it runs in Squadron's own place
  (isolate, Web Worker) or in the process place, started through a launcher.
- Facts are decided where they run, so the page and a root process report
  different facts. Never branch on `kIsWeb` or `Platform`; use a strategy whose
  `available(facts)` decides.
- Device writes plan first, ask for a `Confirmation`, then write and return a
  `Receipt`.
- Logging is `package:logging`, with one `StrategyRun` record per objective
  run on `objective.<name>`.

## Publications

`github.com/p0g-stack` hosts this hub (`.github`), the repositories above and
the forks the stack carries. Nothing here publishes a device log, screenshot
or local archive: evidence rows link to the public run or observation that
produced them. Forked repositories keep their upstream licence, description
and provenance; `certify` stays archived.
