# Bumping Flutter across the stack

When Flutter moves, bump in this order. Each step lands on `main` before the
next one starts. Per-repository pin locations are in `PINS.md` at each
repository root; this file is the cross-repository order and the reason for
it. Every repository that consumes a pin list also links here for the order,
so there is one operational copy.

## Where the stack is

| | Version | Framework / engine | Dart |
|---|---|---|---|
| In the repositories now ([`stack.lock.json`](../stack.lock.json)) | 3.47.9 | framework `c197ca5199e9ee5661e865596c9c07294dfab51c`, engine `89c39edfdfae2949f6806e4a315c0c08522238b7` | 3.13.7 |
| Before this bump | 3.47.5 | `af7e796` | 3.13.4 |

The 3.47.9 Linux archive is
`flutter_linux_3.47.9-stable.tar.xz`, SHA256
`25ed8c3c29d51a7353f2a944310b478af8214920639524b19c50a19e6c044c5a`.

Install a new version into its own directory and put that directory's `bin` on
`PATH` for qualification. Never `flutter upgrade` the active installation in
place: keep the old SDK available until the new one has passed.

## Order

| # | Repository | What moves | Produces | Proof the step is done |
|---|---|---|---|---|
| 1 | flutter-aera | `ci/fetch-engine.sh` `rev=` and the zip sha256s; `spec/engine-pin.md`; `FLUTTER_VERSION` in `kit.yml` and `mesa-debug.yml`; rebase `third_party/flutter-engine/patches`; re-vendor `vendor/flutter/flutter_embedder.h` | nothing | `tests/drift.rs` and `ci/fetch-engine.sh` pass; `ci/engine-tag.sh` prints the new tag |
| 2a | flutter-aera | our own engines (Engine workflow `engine.yml`, or `ci/build-engine.sh` + `ci/publish-engine.sh`) | release `engine-<rev:7>-<series:8>`, four zips with a `.sha256` each | `sha256sum -c` accepts every zip; `ci/fetch-engine.sh` then pins them |
| 2b | flutter-webui | `web_ui/VERSION`; rebase `web_ui/patches`; CI `flutter-version` | `web-sdk-<flutter>-<engine:7>-<commit:7>` (`web-sdk-release.yaml`, on push touching `web_ui/`) | `manifest.json` names the new Flutter and engine; rebuilding gives the same SHA256 |
| 2c | flutter_p0g | nothing for Dart itself (the Dart version comes from Flutter) | `dart-android-<dart>` (`dart-android-kit.yml`, then `dart-android-kit-release.yml` with that run id) | release assets pass `sha256sum -c`; `precache --dart-android` on the new Flutter succeeds |
| 3 | flutter-aera | the kit on the new engines (`kit.yml`) | release `kit-<flutter>` (debug arm64 and x64 today) | simulator smoke and the `viewPadding` check pass; record the kit SHA256 |
| 4 | squadron_process, webui-packages | CI SDK / `flutter-version`; webui-packages moves its flutter-webui `ref:` | nothing | their CI is green |
| 5 | flutter_p0g | `kFlutterWebuiCommit`, `kWebSdkRelease`/`kWebSdkSha256`/`kWebSdkTree`/`kWebSdkEngine`, `kWebuiPackagesCommit`, `kFrbCommit`; CI `flutter-version` | nothing | CI green; `build webui` and `build aera` on the counter app |
| 6 | bricks | the `p0g_app` brick's `ref:`s (`squadron_process`; flutter-webui equal to flutter_p0g's; frb equal to `kFrbCommit`); CI `flutter-version`; brick version bump | nothing | brick CI generates and builds an app |
| 7 | demo | `BRICKS_REF` then `tool/regen.sh`; `FLUTTER_P0G_REF`; `flutter-version` in all four jobs | release `v<x.y.n>`: zip, `app.apk`, `.aerap` | CI green; regen prints `matches p0g_app`; the managers lab walks the release |
| 8 | devicelab | `aera-cf.yml` `flutter-version`; `aera/kit/build-x64.sh` `FA_REV`; re-sync `aera/build/patches`; manager pins | nothing | the lab runs against the new kit and image |
| 9 | .github | `stack.lock.json`: the Flutter/Dart versions and one full SHA per owner, as consumers now pin them | nothing | `dart run tool/check_pins.dart --workspace .. --lock stack.lock.json` exits 0 and `check-stack` is green |

Steps 2a, 2b and 2c are independent and can run in parallel; step 3 needs 2a.

## Artifact identity

Artifacts are consumed by hash, so a bump that moves an artifact moves the
consumers' hashes in the same step:

- `kit-<flutter>-<flutter-aera commit>` is the identity: the Kit workflow
  uploads through `.github/scripts/immutable-release-upload.sh`, so a released
  asset is never replaced (identical bytes are skipped, different bytes fail
  the run). Consumers pass the kit by URL and SHA256: `flutter_p0g`'s
  `aeraKitPins` (the producer commit is the comment above the entry) and
  `demo`'s `AERA_KIT_URL`/`AERA_KIT_SHA256`. The older `kit-<flutter>` tags
  (e.g. `kit-3.47.5`) were re-uploaded with `--clobber`; they stay available
  but no new consumer pins them. Only debug kits are produced; nothing in
  this stack claims a profile or release kit.
- `devicelab`'s `aera-cf.yml` names a source-tagged kit and its SHA256; a
  lab run must record the SHA256 it used so its evidence can be re-checked.
  The publisher's `.sha256` file is a transport check, not an independent
  pin.
- The Android Dart kit (`dart-android-<dart version>`) is verified only when
  the expected hash is passed (`precache --dart-android-sha256=<hash>`); CI
  that relies on a kit should pass it.
- The patched web SDK is pinned by release name and SHA256
  (`kWebSdkRelease`, `kWebSdkSha256`) and is downloaded only when the pinned
  flutter-webui `web_ui/` tree and the installed engine match; otherwise
  `precache --webui` builds it locally.
- `engine-<rev:7>-<series:8>` names the patch series by hash, so a patch
  change is a new release rather than new bytes under the same name.

Do not replace a published artifact's bytes after a consumer pins its hash.
If an upload was wrong, cut a new tag and move the consumers.

## Rules

- One repository per commit; the dependent repositories move after the
  owner's `main` is green, never in parallel with it.
- Do not advance pins for documentation-only commits.
- A pin whose value you did not verify is a placeholder: read it from the
  owner (`git show <sha>:<path>`), not from a `latest` ref.
- The lock moves last, and only to what consumers pin: `stack.lock.json`
  names each owner SHA that the other repositories' manifests and workflows
  actually use, so a documentation-only owner commit does not move it.
- `flasher-web` follows the qualified stack; the stack does not follow it.
  Rebase it after the order above is green, not in the middle.
- Record evidence per [support.md](support.md) when a step produces an
  engineering claim.
