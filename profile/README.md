# p0g-stack

Flutter on Android root surfaces that Flutter does not target on its own: a
manager-served WebUI (KernelSU, KernelSU Next, WebUI X) whose page drives a
root process, and AERA Recovery's plugin host. One app template puts the same
Flutter app on the browser, in a module, and in recovery.

This repository is the public entry point: what each repository owns, how the
pins move, and what has actually been verified.

## Repositories

| Repository | What it is |
|---|---|
| [flutter-webui](https://github.com/p0g-stack/flutter-webui) | Embedder for KernelSU WebUI and WebUI X: a channel-intercepting binding over stock `web_ui`, host detection, the root channel, fake hosts |
| [flutter-aera](https://github.com/p0g-stack/flutter-aera) | Embedder for AERA Recovery: engine hosting, GL/Vulkan renderers, the AERA bridge, standard channel handlers, a host simulator; builds the engine and runtime kits |
| [flutter_p0g](https://github.com/p0g-stack/flutter_p0g) | Tooling on `flutter_tools`: `create`, `build web`, `build webui`, `build aera`, `run`, `install`, `precache`, `devices`, `logs` |
| [bricks](https://github.com/p0g-stack/bricks) | Mason app, service and strategy templates for Flutter, Dart and Rust (`p0g_app`, `service`, `strategy`), and `p0g_lints` |
| [squadron_process](https://github.com/p0g-stack/squadron_process) | Run Squadron services in another process over a socket, with launcher rules and the Squadron channel-factory patch |
| [webui-packages](https://github.com/p0g-stack/webui-packages) | `*_webui` plugin packages and the app-plane client for the WebUI platform |
| [webui-termux-api](https://github.com/p0g-stack/webui-termux-api) | Fork of Termux:API that ships as the app-plane APK |
| [demo](https://github.com/p0g-stack/demo) | Cross-target reference app for p0g-stack, generated from `p0g_app` |
| [devicelab](https://github.com/p0g-stack/devicelab) | Device and emulator qualification for p0g-stack |
| [flasher-web](https://github.com/p0g-stack/flasher-web) | Flutter web and Dart CLI for full-OTA export and fastboot flashing: the real app that consumes the stack |
| [dotfiles](https://github.com/p0g-stack/dotfiles) | Shared p0g-stack agent rules and skills |

Forks carry upstream work this stack needs: `flutter_file_picker` (file
system access handles), `nusb` (USB error and lifecycle evidence),
`android_bootable_recovery` and `android_external_lvgl` (the AERA trees).
Forked repositories keep their upstream licences and descriptions.

`certify` is archived. The `surfaces` line is dissolved: its crates,
transports, CLI, templates and UI are replaced by the repositories above.

## How it fits

| Layer | What it does | Owner |
|---|---|---|
| Embedders | run a stock Flutter app against a host; parity with Linux GTK / flutter-pi, not Android | `flutter-webui`, `flutter-aera` |
| Tool | adds the `webui/` and `aera/` platform folders, builds each target, installs and pre-caches the artifacts | `flutter_p0g` |
| Artifacts | patched web SDK, engines, Mesa, AERA runtime kits, the Android Dart kit, the app-plane APK, released by hash | embedder and tool CI |
| Plugins | `*_webui` packages on the app plane | `webui-packages`, `webui-termux-api` |
| Places | a Squadron service in another, elevated process over a socket | `squadron_process` |
| App kit | the pub workspace (`core/`, `app/`, `cli/`, optional `rust/`), feature bricks, facts and strategies | `bricks` |
| Apps | generated from `p0g_app` | `demo`, `flasher-web` |

## Docs

- [docs/stack.md](docs/stack.md): the layers, the naming rules, and the
  contracts each repository owns.
- [docs/flutter-bump.md](docs/flutter-bump.md): the cross-repository bump
  order, and the pin locations each step moves.
- [docs/support.md](docs/support.md): what has been verified, on what host,
  with evidence links.

## Licence

Authored code is LGPL-3.0-or-later (`LICENSE`), with a linking exception in
`LICENSE.exception` in each authored repository. Forks and copied code keep
their original licences; for example `flasher-web`'s OTA payload crate is
Apache-2.0. No repository relicenses upstream code.
