// Builds a throwaway workspace of the locked repositories, so the checker is
// exercised against real git objects: every file is read with
// `git show <locked-sha>:<path>`, exactly as in CI.
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

const flutterVersion = '3.47.9';
const flutterFramework = 'c197ca5199e9ee5661e865596c9c07294dfab51c';
const flutterEngine = '89c39edfdfae2949f6806e4a315c0c08522238b7';
const flutterDart = '3.13.7';
const frbVersion = '2.14.0-beta.2';
const arm64KitSha =
    '31c2131acd5966a50e96b9438c6e48d63126be806fcbe4da747479ae6a56caed';
const x64KitSha =
    '89502b18226472ee3d981eda915f1afee9b5643af67c8da9a1beeb8338ad52aa';
const webSdkSha =
    'c961ec08b216b5f7a554a6e426003246d17edfd5db922689d710d990363d7ae7';
const appPlaneSha =
    '659cdd703e418a052a94459d7d85dfc307347b3961e8f58790ea9fc7df84949b';

final class Fixture {
  Fixture(this.dir, this.shas);

  /// The workspace root: one directory per repository, plus `.github`.
  final String dir;

  /// The locked commit of each repository.
  final Map<String, String> shas;

  String get lockPath => p.join(dir, '.github', 'stack.lock.json');

  String repoDir(String repo) => p.join(dir, repo);

  Map<String, dynamic> readLock() =>
      jsonDecode(File(lockPath).readAsStringSync()) as Map<String, dynamic>;

  void writeLock(Map<String, dynamic> lock) {
    final file = File(lockPath);
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(
      '${const JsonEncoder.withIndent('  ').convert(lock)}\n',
    );
  }

  /// Writes [path] in [repo] and commits it; returns the new commit.
  String commit(
    String repo,
    String path,
    String content, {
    String message = 'change',
  }) {
    final file = File(p.join(repoDir(repo), path));
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(content);
    git(repo, ['add', '-A']);
    git(repo, ['commit', '-qm', message]);
    return git(repo, ['rev-parse', 'HEAD'])!;
  }

  String? git(String repo, List<String> args) {
    final result = Process.runSync(
      'git',
      ['-C', repoDir(repo), ...args],
      environment: _identity,
      stdoutEncoding: utf8,
      stderrEncoding: utf8,
    );
    if (result.exitCode != 0) {
      throw StateError('git ${args.join(' ')} in $repo: ${result.stderr}');
    }
    return (result.stdout as String).trim();
  }

  static const _identity = {
    'GIT_AUTHOR_NAME': 'fixture',
    'GIT_AUTHOR_EMAIL': 'fixture@example.invalid',
    'GIT_COMMITTER_NAME': 'fixture',
    'GIT_COMMITTER_EMAIL': 'fixture@example.invalid',
    'GIT_AUTHOR_DATE': '2026-01-01T00:00:00Z',
    'GIT_COMMITTER_DATE': '2026-01-01T00:00:00Z',
  };

  /// Builds a consistent snapshot in [root].
  static Fixture build(String root) {
    final shas = <String, String>{};

    void write(String repo, String path, String content) {
      final file = File(p.join(root, repo, path));
      file.parent.createSync(recursive: true);
      file.writeAsStringSync(content);
    }

    void init(String repo) {
      Directory(p.join(root, repo)).createSync(recursive: true);
      Process.runSync('git', ['init', '-q', p.join(root, repo)]);
    }

    String commit(String repo, {String message = 'fixture'}) {
      final result = Process.runSync(
        'git',
        ['-C', p.join(root, repo), 'commit', '-qm', message],
        environment: _identity,
        stdoutEncoding: utf8,
        stderrEncoding: utf8,
      );
      if (result.exitCode != 0)
        throw StateError('commit in $repo: ${result.stderr}');
      final head = Process.runSync('git', [
        '-C',
        p.join(root, repo),
        'rev-parse',
        'HEAD',
      ]);
      return (head.stdout as String).trim();
    }

    String add(String repo) =>
        Process.runSync('git', [
              '-C',
              p.join(root, repo),
              'add',
              '-A',
            ]).exitCode ==
            0
        ? ''
        : throw StateError('git add in $repo');

    // flutter-webui
    init('flutter-webui');
    write('flutter-webui', 'web_ui/VERSION', '$flutterVersion\n');
    write('flutter-webui', 'web_ui/pubspec.yaml', 'name: flutter_webui\n');
    write(
      'flutter-webui',
      'packages/flutter_webui_client/pubspec.yaml',
      'name: flutter_webui_client\n',
    );
    write(
      'flutter-webui',
      '.github/workflows/ci.yaml',
      _workflow(flutter: flutterVersion),
    );
    add('flutter-webui');
    shas['flutter-webui'] = commit('flutter-webui');

    // webui-termux-api, with the app-plane tag flutter_p0g pins.
    init('webui-termux-api');
    write(
      'webui-termux-api',
      'app/build.gradle',
      "versionName '0.53.0-webui.9'\n",
    );
    write(
      'webui-termux-api',
      '.github/workflows/webui_release.yml',
      'name: webui-release\n# pushes tag webui-v<versionName>\n',
    );
    add('webui-termux-api');
    shas['webui-termux-api'] = commit('webui-termux-api');
    Process.runSync('git', [
      '-C',
      p.join(root, 'webui-termux-api'),
      'tag',
      'webui-v0.53.0-webui.9',
    ], environment: _identity);

    // webui-packages
    init('webui-packages');
    write(
      'webui-packages',
      'packages/clipboard_webui/pubspec.yaml',
      'name: clipboard_webui\n'
          'dependencies:\n'
          '  flutter_webui_client:\n'
          '    git:\n'
          '      url: https://github.com/p0g-stack/flutter-webui\n'
          '      path: packages/flutter_webui_client\n'
          '      ref: ${shas['flutter-webui']}\n',
    );
    write(
      'webui-packages',
      '.github/workflows/ci.yaml',
      _workflow(flutter: flutterVersion),
    );
    add('webui-packages');
    shas['webui-packages'] = commit('webui-packages');

    // flutter_rust_bridge: only the two Cargo.toml files the checker reads.
    init('flutter_rust_bridge');
    write(
      'flutter_rust_bridge',
      'Cargo.toml',
      '[workspace]\nmembers = ["frb_codegen", "frb_macros", "frb_rust"]\nresolver = "2"\n\n'
          '[workspace.package]\nversion = "$frbVersion"\nedition = "2021"\n',
    );
    write(
      'flutter_rust_bridge',
      'frb_rust/Cargo.toml',
      '[package]\nname = "flutter_rust_bridge"\nversion.workspace = true\nedition.workspace = true\n',
    );
    add('flutter_rust_bridge');
    shas['flutter_rust_bridge'] = commit('flutter_rust_bridge');

    // flutter-aera: the engine pin table, the fetch script and the Kit env.
    init('flutter-aera');
    write(
      'flutter-aera',
      'spec/engine-pin.md',
      '# Engine pin\n\n'
          '| What | Value |\n'
          '| --- | --- |\n'
          '| Flutter release | $flutterVersion (stable) |\n'
          '| Framework git revision | `$flutterFramework` |\n'
          '| Dart SDK | $flutterDart |\n',
    );
    write(
      'flutter-aera',
      'ci/fetch-engine.sh',
      '#!/bin/sh\nrev=$flutterEngine\ntag=engine-89c39ed-0d7f3ed2\n',
    );
    write(
      'flutter-aera',
      '.github/workflows/kit.yml',
      _workflow(flutterVersionEnv: flutterVersion),
    );
    write(
      'flutter-aera',
      '.github/workflows/mesa-debug.yml',
      _workflow(flutterVersionEnv: flutterVersion),
    );
    add('flutter-aera');
    shas['flutter-aera'] = commit('flutter-aera');

    // flutter_p0g: first commit is the helper baseline (helperRef), second the
    // pinned state that pins the others.
    init('flutter_p0g');
    write(
      'flutter_p0g',
      'packages/patched_source/pubspec.yaml',
      'name: patched_source\n',
    );
    write(
      'flutter_p0g',
      'lib/src/frb/frb.dart',
      "const kFrbCommit = '${shas['flutter_rust_bridge']}';\n",
    );
    add('flutter_p0g');
    final helperRef = commit('flutter_p0g', message: 'helper baseline');
    shas['helperRef'] = helperRef;

    final webuiTree = Process.runSync('git', [
      '-C',
      p.join(root, 'flutter-webui'),
      'rev-parse',
      '${shas['flutter-webui']}:web_ui',
    ]);
    final webuiShort = shas['flutter-webui']!.substring(0, 7);
    write(
      'flutter_p0g',
      'lib/src/webui/flutter_webui.dart',
      "const kFlutterWebuiRepo = 'https://github.com/p0g-stack/flutter-webui';\n"
          "const kFlutterWebuiCommit = '${shas['flutter-webui']}';\n"
          "const kWebSdkRelease = 'web-sdk-$flutterVersion-${flutterEngine.substring(0, 7)}-$webuiShort';\n"
          "const kWebSdkTree = '${(webuiTree.stdout as String).trim()}';\n"
          "const kWebSdkEngine = '$flutterEngine';\n"
          "const kWebSdkSha256 = '$webSdkSha';\n"
          "const kWebSdkUrl =\n"
          "    '\$kFlutterWebuiRepo/releases/download/\$kWebSdkRelease/flutter-webui-web-sdk.tar.xz';\n",
    );
    write(
      'flutter_p0g',
      'lib/src/webui/webui_packages.dart',
      "const kWebuiPackagesCommit = '${shas['webui-packages']}';\n",
    );
    write(
      'flutter_p0g',
      'lib/src/webui/app_plane.dart',
      "const kAppPlaneRepo = 'https://github.com/p0g-stack/webui-termux-api';\n"
          "const kAppPlaneTag = 'webui-v0.53.0-webui.9';\n"
          "const kAppPlaneAsset = 'webui-termux-api_v0.53.0-webui.9.apk';\n"
          "const kAppPlaneSha256 = '$appPlaneSha';\n",
    );
    write(
      'flutter_p0g',
      'lib/src/artifact_pins.dart',
      "import 'package:flutter_tools/src/base/common.dart';\n\n"
          'final class PinnedArtifact {\n'
          '  const PinnedArtifact(this.url, this.sha256);\n'
          '  final String url;\n'
          '  final String sha256;\n'
          '}\n\n'
          'const Map<String, Map<String, PinnedArtifact>> dartAndroidKitPins = {\n'
          '  // dart-android-$flutterDart-$helperRef\n'
          "  '$flutterDart': {\n"
          "    'arm64-v8a': PinnedArtifact(\n"
          "      'https://api.github.com/repos/p0g-stack/flutter_p0g/releases/assets/1',\n"
          "      '2ecff73f4cf0205ec16ed54f81dc94b57b7709bcd1681691859f211b351fcd01',\n"
          '    ),\n'
          "    'x86_64': PinnedArtifact(\n"
          "      'https://api.github.com/repos/p0g-stack/flutter_p0g/releases/assets/2',\n"
          "      'a82bc739280110274e16499158f94e62aca652fb453d29af7f2ec9bff25ceac3',\n"
          '    ),\n'
          '  },\n'
          '};\n\n'
          'const Map<String, Map<String, PinnedArtifact>> aeraKitPins = {\n'
          '  // kit-$flutterVersion-${shas['flutter-aera']}\n'
          "  '$flutterVersion': {\n"
          "    'linux-arm64-debug': PinnedArtifact(\n"
          "      'https://github.com/p0g-stack/flutter-aera/releases/download/kit-$flutterVersion-${shas['flutter-aera']}"
          "/flutter-aera-kit-linux-arm64-debug-$flutterVersion.tar.xz',\n"
          "      '$arm64KitSha',\n"
          '    ),\n'
          "    'linux-x64-debug': PinnedArtifact(\n"
          "      'https://github.com/p0g-stack/flutter-aera/releases/download/kit-$flutterVersion-${shas['flutter-aera']}"
          "/flutter-aera-kit-linux-x64-debug-$flutterVersion.tar.xz',\n"
          "      '$x64KitSha',\n"
          '    ),\n'
          '  },\n'
          '};\n',
    );
    write(
      'flutter_p0g',
      'pubspec.yaml',
      'name: flutter_p0g\nenvironment:\n  sdk: ^3.13.0\n  flutter: $flutterVersion\n',
    );
    write(
      'flutter_p0g',
      '.github/workflows/ci.yml',
      _workflow(flutter: flutterVersion),
    );
    add('flutter_p0g');
    shas['flutter_p0g'] = commit('flutter_p0g');

    // squadron_process pins the helper.
    init('squadron_process');
    write(
      'squadron_process',
      'pubspec.yaml',
      'name: squadron_process\n'
          'dependencies:\n'
          '  patched_source:\n'
          '    git:\n'
          '      url: https://github.com/p0g-stack/flutter_p0g\n'
          '      ref: $helperRef\n'
          '      path: packages/patched_source\n',
    );
    write(
      'squadron_process',
      '.github/workflows/test.yml',
      'jobs:\n  test:\n    steps:\n      - uses: dart-lang/setup-dart@v1\n        with:\n          sdk: $flutterDart\n',
    );
    add('squadron_process');
    shas['squadron_process'] = commit('squadron_process');

    // bricks: commit A carries the brick; commit B adds the lints pin that
    // names commit A (as in the real repo, where p0g_lints lags bricks).
    init('bricks');
    const brick = 'bricks/p0g_app/__brick__/{{name.snakeCase()}}';
    write(
      'bricks',
      '$brick/pubspec.yaml',
      'name: x_workspace\n'
          'dev_dependencies:\n'
          '  patched_source:\n'
          '    git:\n'
          '      url: https://github.com/p0g-stack/flutter_p0g\n'
          '      path: packages/patched_source\n'
          '      ref: $helperRef\n',
    );
    for (final member in ['core', 'app', 'cli']) {
      write(
        'bricks',
        '$brick/$member/pubspec.yaml',
        _consumerPubspec(shas, withFrb: member == 'core'),
      );
    }
    write(
      'bricks',
      '$brick/{{#rust}}rust{{/rust}}/Cargo.toml',
      '[package]\nname = "x_native"\nversion = "0.1.0"\n\n[dependencies]\n'
          'flutter_rust_bridge = { version = "=$frbVersion", default-features = false, features = ["anyhow"] }\n',
    );
    write(
      'bricks',
      '.github/workflows/ci.yaml',
      _workflow(flutter: flutterVersion, flutterP0g: shas['flutter_p0g']),
    );
    add('bricks');
    final bricksBase = commit('bricks');
    write(
      'bricks',
      '$brick/analysis_options.yaml',
      _analysisOptions(bricksBase),
    );
    add('bricks');
    shas['bricks'] = commit('bricks');

    // demo: the generated app, pinning every owner.
    init('demo');
    write('demo', 'pubspec.yaml', 'name: demo_workspace\npublish_to: none\n');
    for (final member in ['core', 'app', 'cli']) {
      write(
        'demo',
        '$member/pubspec.yaml',
        _consumerPubspec(shas, withFrb: member == 'core'),
      );
    }
    write('demo', 'analysis_options.yaml', _analysisOptions(bricksBase));
    write(
      'demo',
      'rust/Cargo.toml',
      '[package]\nname = "demo_native"\nversion = "0.1.0"\n\n[dependencies]\n'
          'flutter_rust_bridge = { version = "=$frbVersion", default-features = false, features = ["anyhow"] }\n',
    );
    write('demo', 'tool/regen.sh', '#!/usr/bin/env bash\nset -euo pipefail\n');
    write(
      'demo',
      '.github/workflows/ci.yml',
      _workflow(
        flutter: flutterVersion,
        flutterP0g: shas['flutter_p0g'],
        bricks: shas['bricks'],
        aeraKit:
            'https://github.com/p0g-stack/flutter-aera/releases/download/'
            'kit-$flutterVersion-${shas['flutter-aera']}/flutter-aera-kit-linux-arm64-debug-$flutterVersion.tar.xz',
        aeraKitSha: arm64KitSha,
      ),
    );
    add('demo');
    shas['demo'] = commit('demo');

    // flasher-web: the second app from the same brick, with the same pins and
    // no AERA kit.
    init('flasher-web');
    write(
      'flasher-web',
      'pubspec.yaml',
      'name: flasher_web_workspace\npublish_to: none\n',
    );
    for (final member in ['core', 'app', 'cli']) {
      write(
        'flasher-web',
        '$member/pubspec.yaml',
        _consumerPubspec(shas, withFrb: member == 'core'),
      );
    }
    write('flasher-web', 'analysis_options.yaml', _analysisOptions(bricksBase));
    write(
      'flasher-web',
      'rust/Cargo.toml',
      '[package]\nname = "flasher_web_native"\nversion = "0.1.0"\n\n[dependencies]\n'
          'flutter_rust_bridge = { version = "=$frbVersion", default-features = false, features = ["anyhow"] }\n',
    );
    write(
      'flasher-web',
      'tool/regen.sh',
      '#!/usr/bin/env bash\nset -euo pipefail\n',
    );
    write(
      'flasher-web',
      '.github/workflows/ci.yml',
      _workflow(
        flutter: flutterVersion,
        flutterP0g: shas['flutter_p0g'],
        bricks: shas['bricks'],
      ),
    );
    add('flasher-web');
    shas['flasher-web'] = commit('flasher-web');

    final fixture = Fixture(root, shas);
    fixture.writeLock({
      'schema': 1,
      'flutter': {
        'version': flutterVersion,
        'framework': flutterFramework,
        'engine': flutterEngine,
        'dart': flutterDart,
      },
      'repos': {
        for (final repo in [
          'bricks',
          'demo',
          'flasher-web',
          'flutter-aera',
          'flutter-webui',
          'flutter_p0g',
          'squadron_process',
          'webui-packages',
          'webui-termux-api',
        ])
          repo: shas[repo],
      },
      'helperRef': helperRef,
    });
    return fixture;
  }

  static String _consumerPubspec(
    Map<String, String> shas, {
    required bool withFrb,
  }) {
    final buffer = StringBuffer()
      ..writeln('name: x')
      ..writeln('dependencies:')
      ..writeln('  squadron_process:')
      ..writeln('    git:')
      ..writeln('      url: https://github.com/p0g-stack/squadron_process')
      ..writeln('      ref: ${shas['squadron_process']}')
      ..writeln('  flutter_webui_client:')
      ..writeln('    git:')
      ..writeln('      url: https://github.com/p0g-stack/flutter-webui')
      ..writeln('      path: packages/flutter_webui_client')
      ..writeln('      ref: ${shas['flutter-webui']}');
    if (withFrb) {
      buffer
        ..writeln('  flutter_rust_bridge:')
        ..writeln('    git:')
        ..writeln('      url: https://github.com/fzyzcjy/flutter_rust_bridge')
        ..writeln('      path: frb_dart')
        ..writeln('      ref: ${shas['flutter_rust_bridge']}');
    }
    return buffer.toString();
  }

  static String _analysisOptions(String bricksRef) =>
      'analyzer:\n  exclude:\n    - "**/*.g.dart"\n'
      'plugins:\n'
      '  p0g_lints:\n'
      '    git:\n'
      '      url: https://github.com/p0g-stack/bricks\n'
      '      path: packages/p0g_lints\n'
      '      ref: $bricksRef\n';

  static String _workflow({
    String? flutter,
    String? flutterVersionEnv,
    String? flutterP0g,
    String? bricks,
    String? aeraKit,
    String? aeraKitSha,
  }) {
    final env = <String>[
      if (flutterVersionEnv != null) '  FLUTTER_VERSION: $flutterVersionEnv',
      if (flutterP0g != null) '  FLUTTER_P0G_REF: $flutterP0g',
      if (bricks != null) '  BRICKS_REF: $bricks',
      if (aeraKit != null) '  AERA_KIT_URL: $aeraKit',
      if (aeraKitSha != null) '  AERA_KIT_SHA256: $aeraKitSha',
    ];
    final buffer = StringBuffer()
      ..writeln('name: ci')
      ..writeln('on:')
      ..writeln('  push:')
      ..writeln('    branches: [main]');
    if (env.isNotEmpty) {
      buffer
        ..writeln('env:')
        ..writeln(env.join('\n'));
    }
    buffer
      ..writeln('jobs:')
      ..writeln('  test:')
      ..writeln('    runs-on: ubuntu-latest')
      ..writeln('    steps:')
      ..writeln('      - uses: actions/checkout@v4');
    if (flutter != null) {
      buffer
        ..writeln('      - uses: subosito/flutter-action@v2')
        ..writeln('        with:')
        ..writeln('          flutter-version: $flutter')
        ..writeln('          channel: stable');
    }
    return buffer.toString();
  }
}
