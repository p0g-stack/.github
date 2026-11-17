/// Checks that the p0g-stack compatibility set recorded in `stack.lock.json`
/// is what the repositories actually pin.
///
/// Every file is read with `git show <locked-sha>:<path>` from the sibling
/// checkout, so the check covers the recorded snapshot, never a branch head.
/// A missing repository, commit, file or required field is a failure; nothing
/// is skipped implicitly.
library;

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:toml/toml.dart';
import 'package:yaml/yaml.dart';

/// One mismatch, in the diagnostic format of plan section 8.3:
/// `repo:path field expected=<value> actual=<value>`.
final class Diagnostic {
  const Diagnostic(
    this.repo,
    this.path,
    this.field,
    this.expected,
    this.actual,
  );

  final String repo;
  final String path;
  final String field;
  final String expected;
  final String actual;

  @override
  String toString() => '$repo:$path $field expected=$expected actual=$actual';
}

/// A git checkout of one locked repository.
final class GitRepo {
  GitRepo(this.name, this.dir);

  final String name;
  final String dir;

  ProcessResult _git(List<String> args) => Process.runSync(
    'git',
    ['-C', dir, ...args],
    stdoutEncoding: utf8,
    stderrEncoding: utf8,
  );

  bool get exists => Directory(dir).existsSync();

  /// The full commit SHA of [rev], or null when the object is absent.
  String? commit(String rev) {
    final r = _git(['rev-parse', '--verify', '--quiet', '$rev^{commit}']);
    return r.exitCode == 0 ? (r.stdout as String).trim() : null;
  }

  /// The file [path] at [rev], or null when it does not exist there.
  String? show(String rev, String path) {
    final r = _git(['show', '$rev:$path']);
    return r.exitCode == 0 ? r.stdout as String : null;
  }

  /// The tree id of the directory [path] at [rev], or null when it does not
  /// exist there or is not a directory.
  String? tree(String rev, String path) {
    final r = _git(['rev-parse', '--verify', '--quiet', '$rev:$path']);
    if (r.exitCode != 0) return null;
    final id = (r.stdout as String).trim();
    final type = _git(['cat-file', '-t', id]);
    return type.exitCode == 0 && (type.stdout as String).trim() == 'tree'
        ? id
        : null;
  }

  /// Every tracked path at [rev].
  List<String>? lsTree(String rev) {
    final r = _git(['ls-tree', '-r', '--name-only', rev]);
    if (r.exitCode != 0) return null;
    return const LineSplitter()
        .convert(r.stdout as String)
        .where((l) => l.isNotEmpty)
        .toList();
  }
}

final class _Pin {
  const _Pin(this.version, this.target, this.url, this.sha256, this.comment);

  final String version;
  final String target;
  final String url;
  final String sha256;

  /// The comment line directly above the version key (`// kit-<v>-<sha>`).
  final String? comment;
}

final class _GitDep {
  const _GitDep(this.name, this.url, this.path, this.ref, this.file);

  final String name;
  final String? url;
  final String? path;
  final String? ref;
  final String file;
}

/// Repositories whose SHAs consumers pin and whose absence from the lock is a
/// failure (plan 8.1). `flasher-web` joins after acceptance and is optional.
const requiredRepos = <String>[
  'bricks',
  'demo',
  'flasher-web',
  'flutter-aera',
  'flutter-webui',
  'flutter_p0g',
  'squadron_process',
  'webui-packages',
  'webui-termux-api',
];

const _frbUrl = 'https://github.com/fzyzcjy/flutter_rust_bridge';

/// The p0g-stack repositories a git dependency can point at, by URL.
const _ownerUrls = <String, String>{
  'https://github.com/p0g-stack/bricks': 'bricks',
  'https://github.com/p0g-stack/flutter-aera': 'flutter-aera',
  'https://github.com/p0g-stack/flutter-webui': 'flutter-webui',
  'https://github.com/p0g-stack/flutter_p0g': 'flutter_p0g',
  'https://github.com/p0g-stack/squadron_process': 'squadron_process',
  'https://github.com/p0g-stack/webui-packages': 'webui-packages',
  'https://github.com/p0g-stack/webui-termux-api': 'webui-termux-api',
};

final _sha40 = RegExp(r'^[0-9a-f]{40}$');
final _sha64 = RegExp(r'^[0-9a-f]{64}$');

/// Runs every check for [lockFile] against the sibling checkouts under
/// [workspace]. [frbDir] is a checkout of upstream flutter_rust_bridge from
/// which only the locked commit is read.
final class StackCheck {
  StackCheck({required this.workspace, required this.lockFile, this.frbDir});

  final String workspace;
  final String lockFile;
  final String? frbDir;

  final problems = <Diagnostic>[];
  final _repos = <String, GitRepo>{};

  late final Map<String, dynamic> _lock;
  late final Map<String, String> _lockedRepos;
  late final Map<String, dynamic> _flutter;

  String get flutterVersion => _flutter['version'] as String;
  String get flutterEngine => _flutter['engine'] as String;
  String get flutterDart => _flutter['dart'] as String;
  String get helperRef => _lock['helperRef'] as String;

  void _problem(
    String repo,
    String path,
    String field,
    Object? expected,
    Object? actual,
  ) {
    problems.add(
      Diagnostic(
        repo,
        path,
        field,
        '$expected',
        actual == null ? '<missing>' : '$actual',
      ),
    );
  }

  /// Loads the lock and resolves every locked commit. Returns false when the
  /// lock itself is unusable.
  bool load() {
    final file = File(lockFile);
    if (!file.existsSync()) {
      _problem('.github', 'stack.lock.json', 'file', 'present', null);
      return false;
    }
    final Object? decoded;
    try {
      decoded = jsonDecode(file.readAsStringSync());
    } on FormatException catch (e) {
      _problem('.github', 'stack.lock.json', 'json', 'valid JSON', e.message);
      return false;
    }
    if (decoded is! Map<String, dynamic>) {
      _problem('.github', 'stack.lock.json', 'document', 'object', null);
      return false;
    }
    _lock = decoded;
    if (_lock['schema'] != 1) {
      _problem('.github', 'stack.lock.json', 'schema', 1, _lock['schema']);
      return false;
    }
    final flutter = _lock['flutter'];
    if (flutter is! Map<String, dynamic>) {
      _problem('.github', 'stack.lock.json', 'flutter', 'object', null);
      return false;
    }
    _flutter = flutter;
    for (final field in ['version', 'framework', 'engine', 'dart']) {
      if (flutter[field] is! String || (flutter[field] as String).isEmpty) {
        _problem('.github', 'stack.lock.json', 'flutter.$field', 'value', null);
        return false;
      }
    }
    final repos = _lock['repos'];
    if (repos is! Map<String, dynamic>) {
      _problem('.github', 'stack.lock.json', 'repos', 'object', null);
      return false;
    }
    _lockedRepos = repos.map((k, v) => MapEntry(k, '$v'));
    if (_lock['helperRef'] is! String ||
        !_sha40.hasMatch(_lock['helperRef'] as String)) {
      _problem(
        '.github',
        'stack.lock.json',
        'helperRef',
        'full commit',
        _lock['helperRef'],
      );
      return false;
    }
    for (final name in requiredRepos) {
      if (!_lockedRepos.containsKey(name)) {
        _problem(
          '.github',
          'stack.lock.json',
          'repos.$name',
          'full commit',
          null,
        );
      }
    }
    for (final entry in _lockedRepos.entries) {
      if (!_sha40.hasMatch(entry.value)) {
        _problem(
          '.github',
          'stack.lock.json',
          'repos.${entry.key}',
          'full commit',
          entry.value,
        );
      }
    }
    return problems.isEmpty;
  }

  /// Resolves each locked repository and commit. Repositories that fail here
  /// are not read further.
  void resolve() {
    for (final entry in _lockedRepos.entries) {
      final repo = GitRepo(entry.key, p.join(workspace, entry.key));
      _repos[entry.key] = repo;
      if (!repo.exists) {
        _problem(
          entry.key,
          '-',
          'checkout',
          entry.value,
          '<missing repository>',
        );
        continue;
      }
      final head = repo.commit(entry.value);
      if (head == null) {
        _problem(entry.key, '-', 'commit', entry.value, '<missing object>');
      } else if (head != entry.value) {
        _problem(entry.key, '-', 'commit', entry.value, head);
      }
    }
  }

  GitRepo? _repo(String name) {
    final repo = _repos[name];
    if (repo == null ||
        !repo.exists ||
        repo.commit(_lockedRepos[name]!) == null)
      return null;
    return repo;
  }

  String _locked(String name) => _lockedRepos[name]!;

  /// Reads [path] at the locked commit of [repo]. Records a diagnostic and
  /// returns null when the file is missing.
  String? _read(String repo, String path) {
    final git = _repo(repo);
    if (git == null) return null;
    final text = git.show(_locked(repo), path);
    if (text == null) _problem(repo, path, 'file', 'present', null);
    return text;
  }

  /// Runs every content check. Only call after [load] and [resolve].
  void run() {
    _checkFlutterP0g();
    _checkFlutterWebui();
    _checkFlutterAera();
    _checkSquadronProcess();
    _checkBricks();
    _checkApp('demo');
    _checkApp('flasher-web');
    _checkWebuiPackages();
    _checkWebuiTermuxApi();
    _checkFrb();
    _checkWorkflowSdks();
  }

  // --- flutter_p0g -------------------------------------------------------

  void _checkFlutterP0g() {
    const webuiPath = 'lib/src/webui/flutter_webui.dart';
    const packagesPath = 'lib/src/webui/webui_packages.dart';
    const appPlanePath = 'lib/src/webui/app_plane.dart';
    const frbPath = 'lib/src/frb/frb.dart';
    const pinsPath = 'lib/src/artifact_pins.dart';

    final webui = _read('flutter_p0g', webuiPath);
    if (webui != null) {
      _expectConst(
        'flutter_p0g',
        webuiPath,
        'kFlutterWebuiCommit',
        _locked('flutter-webui'),
        webui,
      );
      _expectConst(
        'flutter_p0g',
        webuiPath,
        'kWebSdkEngine',
        flutterEngine,
        webui,
      );
      final webuiShort = _locked('flutter-webui').substring(0, 7);
      final engineShort = flutterEngine.substring(0, 7);
      final release = _constString(webui, 'kWebSdkRelease');
      final expectedRelease =
          'web-sdk-$flutterVersion-$engineShort-$webuiShort';
      if (release != expectedRelease) {
        _problem(
          'flutter_p0g',
          webuiPath,
          'kWebSdkRelease',
          expectedRelease,
          release,
        );
      }
      final tree = _constString(webui, 'kWebSdkTree');
      final ownerTree = _repo('flutter-webui')
          ?.tree(_locked('flutter-webui'), 'web_ui');
      if (tree == null || ownerTree == null || tree != ownerTree) {
        _problem(
          'flutter_p0g',
          webuiPath,
          'kWebSdkTree',
          ownerTree ?? '<flutter-webui web_ui tree>',
          tree,
        );
      }
      final sha = _constString(webui, 'kWebSdkSha256');
      if (sha == null || !_sha64.hasMatch(sha)) {
        _problem('flutter_p0g', webuiPath, 'kWebSdkSha256', 'sha256', sha);
      }
    }

    final packages = _read('flutter_p0g', packagesPath);
    if (packages != null) {
      _expectConst(
        'flutter_p0g',
        packagesPath,
        'kWebuiPackagesCommit',
        _locked('webui-packages'),
        packages,
      );
    }

    final appPlane = _read('flutter_p0g', appPlanePath);
    if (appPlane != null) {
      final tag = _constString(appPlane, 'kAppPlaneTag');
      final asset = _constString(appPlane, 'kAppPlaneAsset');
      final sha = _constString(appPlane, 'kAppPlaneSha256');
      if (tag == null) {
        _problem('flutter_p0g', appPlanePath, 'kAppPlaneTag', 'value', null);
      } else {
        final owner = _repo('webui-termux-api');
        final at = owner?.commit(tag);
        if (at == null) {
          _problem(
            'flutter_p0g',
            appPlanePath,
            'kAppPlaneTag',
            _locked('webui-termux-api'),
            '<no such tag>',
          );
        } else if (at != _locked('webui-termux-api')) {
          _problem(
            'flutter_p0g',
            appPlanePath,
            'kAppPlaneTag',
            _locked('webui-termux-api'),
            at,
          );
        }
        final versionName = tag.startsWith('webui-v')
            ? tag.substring('webui-v'.length)
            : tag;
        final expectedAsset = 'webui-termux-api_v$versionName.apk';
        if (asset != expectedAsset) {
          _problem(
            'flutter_p0g',
            appPlanePath,
            'kAppPlaneAsset',
            expectedAsset,
            asset,
          );
        }
      }
      if (sha == null || !_sha64.hasMatch(sha)) {
        _problem('flutter_p0g', appPlanePath, 'kAppPlaneSha256', 'sha256', sha);
      }
    }

    final frb = _read('flutter_p0g', frbPath);
    final frbCommit = frb == null ? null : _constString(frb, 'kFrbCommit');
    if (frb != null && (frbCommit == null || !_sha40.hasMatch(frbCommit))) {
      _problem('flutter_p0g', frbPath, 'kFrbCommit', 'full commit', frbCommit);
    }

    final pins = _read('flutter_p0g', pinsPath);
    if (pins != null) {
      _checkAeraKitPins(pinsPath, pins);
      _checkDartKitPins(pinsPath, pins);
    }

    // The helper package tree the lock names is the one the tool ships.
    final tool = _repo('flutter_p0g');
    if (tool != null) {
      final atLock = tool.tree(
        _locked('flutter_p0g'),
        'packages/patched_source',
      );
      if (atLock == null) {
        _problem(
          'flutter_p0g',
          'packages/patched_source',
          'tree',
          'present',
          null,
        );
      }
      final atRef = tool.tree(helperRef, 'packages/patched_source');
      if (atRef == null) {
        _problem(
          'flutter_p0g',
          'packages/patched_source',
          'tree@helperRef',
          atLock,
          '<helperRef not in flutter_p0g>',
        );
      } else if (atLock != atRef) {
        _problem(
          'flutter_p0g',
          'packages/patched_source',
          'tree@helperRef',
          atLock,
          atRef,
        );
      }
    }

    final pubspec = _read('flutter_p0g', 'pubspec.yaml');
    if (pubspec != null) {
      final env = _yamlMap(pubspec, 'flutter_p0g', 'pubspec.yaml');
      final flutter = env?['environment'] is Map
          ? (env!['environment'] as Map)['flutter']
          : null;
      if ('$flutter' != flutterVersion) {
        _problem(
          'flutter_p0g',
          'pubspec.yaml',
          'environment.flutter',
          flutterVersion,
          flutter,
        );
      }
    }
  }

  void _checkAeraKitPins(String path, String source) {
    final pins = _artifactPins(source, 'aeraKitPins');
    final version = pins[flutterVersion];
    if (version == null) {
      _problem('flutter_p0g', path, 'aeraKitPins.$flutterVersion', 'kit', null);
      return;
    }
    final arm64 = version['linux-arm64-debug'];
    final x64 = version['linux-x64-debug'];
    if (arm64 == null) {
      _problem(
        'flutter_p0g',
        path,
        'aeraKitPins.$flutterVersion.linux-arm64-debug',
        'kit',
        null,
      );
    }
    if (x64 == null) {
      _problem(
        'flutter_p0g',
        path,
        'aeraKitPins.$flutterVersion.linux-x64-debug',
        'kit',
        null,
      );
    }
    for (final pin in [arm64, x64]) {
      if (pin == null) continue;
      if (!_sha64.hasMatch(pin.sha256)) {
        _problem(
          'flutter_p0g',
          path,
          'aeraKitPins.$flutterVersion.${pin.target}.sha256',
          'sha256',
          pin.sha256,
        );
      }
      final comment = pin.comment;
      final producer = comment == null
          ? null
          : RegExp(r'^//\s*kit-(\S+)-([0-9a-f]{40})$').firstMatch(comment);
      if (producer == null || producer.group(1) != flutterVersion) {
        _problem(
          'flutter_p0g',
          path,
          'aeraKitPins.$flutterVersion.${pin.target}.producer',
          '// kit-$flutterVersion-${_locked('flutter-aera')}',
          comment,
        );
      } else if (producer.group(2) != _locked('flutter-aera')) {
        _problem(
          'flutter_p0g',
          path,
          'aeraKitPins.$flutterVersion.${pin.target}.producer',
          _locked('flutter-aera'),
          producer.group(2),
        );
      }
    }
  }

  void _checkDartKitPins(String path, String source) {
    final pins = _artifactPins(source, 'dartAndroidKitPins');
    final version = pins[flutterDart];
    if (version == null) {
      _problem(
        'flutter_p0g',
        path,
        'dartAndroidKitPins.$flutterDart',
        'kit',
        null,
      );
      return;
    }
    for (final abi in ['arm64-v8a', 'x86_64']) {
      final pin = version[abi];
      if (pin == null) {
        _problem(
          'flutter_p0g',
          path,
          'dartAndroidKitPins.$flutterDart.$abi',
          'kit',
          null,
        );
        continue;
      }
      if (!_sha64.hasMatch(pin.sha256)) {
        _problem(
          'flutter_p0g',
          path,
          'dartAndroidKitPins.$flutterDart.$abi.sha256',
          'sha256',
          pin.sha256,
        );
      }
      final comment = pin.comment;
      final producer = comment == null
          ? null
          : RegExp(r'^//\s*dart-android-(\S+)-([0-9a-f]{40})$')
                .firstMatch(comment);
      if (producer == null || producer.group(1) != flutterDart) {
        _problem(
          'flutter_p0g',
          path,
          'dartAndroidKitPins.$flutterDart.$abi.producer',
          '// dart-android-$flutterDart-<flutter_p0g commit>',
          comment,
        );
      } else if (_repo('flutter_p0g')?.commit(producer.group(2)!) == null) {
        _problem(
          'flutter_p0g',
          path,
          'dartAndroidKitPins.$flutterDart.$abi.producer',
          'a flutter_p0g commit',
          producer.group(2),
        );
      }
    }
  }

  // --- flutter-webui -----------------------------------------------------

  void _checkFlutterWebui() {
    final version = _read('flutter-webui', 'web_ui/VERSION');
    if (version != null && version.trim() != flutterVersion) {
      _problem(
        'flutter-webui',
        'web_ui/VERSION',
        'version',
        flutterVersion,
        version.trim(),
      );
    }
    final ci = _read('flutter-webui', '.github/workflows/ci.yaml');
    if (ci != null)
      _checkWorkflowFlutter(ci, 'flutter-webui', '.github/workflows/ci.yaml');
  }

  // --- flutter-aera ------------------------------------------------------

  void _checkFlutterAera() {
    const enginePin = 'spec/engine-pin.md';
    final pin = _read('flutter-aera', enginePin);
    if (pin != null) {
      final framework = _tableValue(pin, 'Framework git revision');
      if (framework != _flutter['framework']) {
        _problem(
          'flutter-aera',
          enginePin,
          'Framework git revision',
          _flutter['framework'],
          framework,
        );
      }
      final dart = _tableValue(pin, 'Dart SDK');
      if (dart != flutterDart) {
        _problem('flutter-aera', enginePin, 'Dart SDK', flutterDart, dart);
      }
    }
    const fetch = 'ci/fetch-engine.sh';
    final script = _read('flutter-aera', fetch);
    if (script != null) {
      final rev = RegExp(
        r'^rev=([0-9a-f]{40})$',
        multiLine: true,
      ).firstMatch(script)?.group(1);
      if (rev != flutterEngine) {
        _problem('flutter-aera', fetch, 'rev', flutterEngine, rev);
      }
    }
    for (final file in [
      '.github/workflows/kit.yml',
      '.github/workflows/mesa-debug.yml',
    ]) {
      final yaml = _read('flutter-aera', file);
      if (yaml == null) continue;
      final doc = _yamlMap(yaml, 'flutter-aera', file);
      final version = doc?['env'] is Map
          ? (doc!['env'] as Map)['FLUTTER_VERSION']
          : null;
      if ('$version' != flutterVersion) {
        _problem(
          'flutter-aera',
          file,
          'env.FLUTTER_VERSION',
          flutterVersion,
          version,
        );
      }
    }
  }

  // --- squadron_process --------------------------------------------------

  void _checkSquadronProcess() {
    final pubspec = _read('squadron_process', 'pubspec.yaml');
    if (pubspec != null) {
      final doc = _yamlMap(pubspec, 'squadron_process', 'pubspec.yaml');
      final dep = doc?['dependencies'] is Map
          ? (doc!['dependencies'] as Map)['patched_source']
          : null;
      final git = dep is Map ? dep['git'] : null;
      final ref = git is Map ? git['ref'] : null;
      final path = git is Map ? git['path'] : null;
      if ('$path' != 'packages/patched_source') {
        _problem(
          'squadron_process',
          'pubspec.yaml',
          'patched_source.path',
          'packages/patched_source',
          path,
        );
      }
      if ('$ref' != helperRef) {
        _problem(
          'squadron_process',
          'pubspec.yaml',
          'patched_source.ref',
          helperRef,
          ref,
        );
      }
    }
    final test = _read('squadron_process', '.github/workflows/test.yml');
    if (test != null) {
      final doc = _yamlMap(
        test,
        'squadron_process',
        '.github/workflows/test.yml',
      );
      final sdk = _findKey(doc, 'sdk');
      if (sdk.isEmpty) {
        _problem(
          'squadron_process',
          '.github/workflows/test.yml',
          'sdk',
          flutterDart,
          null,
        );
      }
      for (final value in sdk) {
        if (value.contains(r'${{')) continue;
        if (value != flutterDart) {
          _problem(
            'squadron_process',
            '.github/workflows/test.yml',
            'sdk',
            flutterDart,
            value,
          );
        }
      }
    }
  }

  // --- bricks ------------------------------------------------------------

  void _checkBricks() {
    final repo = _repo('bricks');
    if (repo == null) return;
    final files = repo.lsTree(_locked('bricks'));
    if (files == null) {
      _problem('bricks', '-', 'ls-tree', 'tree', null);
      return;
    }
    const brick = 'bricks/p0g_app/__brick__/{{name.snakeCase()}}';
    for (final file in files.where((f) => f.startsWith('$brick/'))) {
      final relative = stripMustache(file.substring(brick.length + 1));
      if (relative.endsWith('pubspec.yaml') ||
          relative == 'analysis_options.yaml') {
        _checkConsumerManifest('bricks', file, relative);
      }
    }
    _checkConsumerManifest(
      'bricks',
      '$brick/{{#rust}}rust{{/rust}}/Cargo.toml',
      'rust/Cargo.toml',
    );
    // The lints plugin and the tool ref are pins too.
    final ci = _read('bricks', '.github/workflows/ci.yaml');
    if (ci != null) {
      final doc = _yamlMap(ci, 'bricks', '.github/workflows/ci.yaml');
      final ref = doc?['env'] is Map
          ? (doc!['env'] as Map)['FLUTTER_P0G_REF']
          : null;
      if ('$ref' != _locked('flutter_p0g')) {
        _problem(
          'bricks',
          '.github/workflows/ci.yaml',
          'env.FLUTTER_P0G_REF',
          _locked('flutter_p0g'),
          ref,
        );
      }
    }
  }

  // --- apps (demo, flasher-web) ------------------------------------------

  /// Both apps are generated from the `p0g_app` brick: their manifests pin
  /// the owners, their CI names the tool and the brick, and `demo` also pins
  /// the AERA kit.
  void _checkApp(String name) {
    final repo = _repo(name);
    if (repo == null) return;
    final files = repo.lsTree(_locked(name));
    if (files == null) {
      _problem(name, '-', 'ls-tree', 'tree', null);
      return;
    }
    for (final file in files) {
      if (file.endsWith('pubspec.yaml') || file == 'analysis_options.yaml') {
        _checkConsumerManifest(name, file, file);
      }
    }
    _checkConsumerManifest(name, 'rust/Cargo.toml', 'rust/Cargo.toml');

    const ci = '.github/workflows/ci.yml';
    const regen = 'tool/regen.sh';
    final workflow = _read(name, ci);
    final doc = workflow == null ? null : _yamlMap(workflow, name, ci);
    final env = doc?['env'] is Map
        ? doc!['env'] as Map
        : const <dynamic, dynamic>{};
    final tool = env['FLUTTER_P0G_REF'];
    if ('$tool' != _locked('flutter_p0g')) {
      _problem(name, ci, 'env.FLUTTER_P0G_REF', _locked('flutter_p0g'), tool);
    }
    if (name == 'demo') _checkDemoKit(ci, env);

    // BRICKS_REF: the workflow env, or a tool/regen.sh literal in older
    // layouts. At least one must name the locked bricks commit.
    final envRef = env['BRICKS_REF'];
    final script = _read(name, regen);
    final scriptRef = script == null
        ? null
        : RegExp(
            r'^BRICKS_REF=([0-9a-f]{40})$',
            multiLine: true,
          ).firstMatch(script)?.group(1);
    if (scriptRef == null && envRef == null) {
      _problem(name, regen, 'BRICKS_REF', _locked('bricks'), null);
    }
    if (scriptRef != null && scriptRef != _locked('bricks')) {
      _problem(name, regen, 'BRICKS_REF', _locked('bricks'), scriptRef);
    }
    if (envRef != null && '$envRef' != _locked('bricks')) {
      _problem(name, ci, 'env.BRICKS_REF', _locked('bricks'), envRef);
    }
  }

  /// The demo's arm64 debug kit must be the one flutter_p0g's table records,
  /// built by the locked flutter-aera commit.
  void _checkDemoKit(String ci, Map env) {
    final kitSha = env['AERA_KIT_SHA256'];
    final kitUrl = env['AERA_KIT_URL'];
    final pins = _read('flutter_p0g', 'lib/src/artifact_pins.dart');
    final arm64 = pins == null
        ? null
        : _artifactPins(
            pins,
            'aeraKitPins',
          )[flutterVersion]?['linux-arm64-debug'];
    if (arm64 == null) {
      _problem(
        'demo',
        ci,
        'env.AERA_KIT_SHA256',
        'flutter_p0g aeraKitPins linux-arm64-debug',
        kitSha,
      );
      return;
    }
    if ('$kitSha' != arm64.sha256) {
      _problem('demo', ci, 'env.AERA_KIT_SHA256', arm64.sha256, kitSha);
    }
    final sourceTag = 'kit-$flutterVersion-${_locked('flutter-aera')}';
    final url = '$kitUrl';
    if (url != arm64.url && !url.contains('/$sourceTag/')) {
      _problem('demo', ci, 'env.AERA_KIT_URL', arm64.url, kitUrl);
    }
  }

  // --- webui-packages ----------------------------------------------------

  void _checkWebuiPackages() {
    final repo = _repo('webui-packages');
    if (repo == null) return;
    final files = repo.lsTree(_locked('webui-packages'));
    if (files == null) {
      _problem('webui-packages', '-', 'ls-tree', 'tree', null);
      return;
    }
    for (final file in files.where((f) => f.endsWith('pubspec.yaml'))) {
      _checkConsumerManifest('webui-packages', file, file);
    }
    const ci = '.github/workflows/ci.yaml';
    final workflow = _read('webui-packages', ci);
    if (workflow != null) _checkWorkflowFlutter(workflow, 'webui-packages', ci);
  }

  // --- webui-termux-api --------------------------------------------------

  void _checkWebuiTermuxApi() {
    // The locked SHA is what flutter_p0g's app-plane tag must resolve to; the
    // tag check runs in _checkFlutterP0g. Nothing else pins this repo by SHA.
    if (_lockedRepos['webui-termux-api'] == null) return;
    final repo = _repo('webui-termux-api');
    if (repo == null) return;
    final release = repo.show(
      _locked('webui-termux-api'),
      '.github/workflows/webui_release.yml',
    );
    if (release == null) return;
    if (!release.contains('webui-v')) {
      _problem(
        'webui-termux-api',
        '.github/workflows/webui_release.yml',
        'tag',
        'webui-v<version>',
        null,
      );
    }
  }

  // --- frb ---------------------------------------------------------------

  void _checkFrb() {
    final tool = _read('flutter_p0g', 'lib/src/frb/frb.dart');
    final frbCommit = tool == null ? null : _constString(tool, 'kFrbCommit');
    if (frbCommit == null) return; // already reported by _checkFlutterP0g
    final dir = frbDir ?? p.join(workspace, 'flutter_rust_bridge');
    final frb = GitRepo('flutter_rust_bridge', dir);
    if (!frb.exists) {
      _problem(
        'flutter_rust_bridge',
        '-',
        'checkout',
        frbCommit,
        '<missing repository>',
      );
      return;
    }
    if (frb.commit(frbCommit) == null) {
      _problem(
        'flutter_rust_bridge',
        '-',
        'commit',
        frbCommit,
        '<missing object>',
      );
      return;
    }
    final manifest = frb.show(frbCommit, 'frb_rust/Cargo.toml');
    if (manifest == null) {
      _problem(
        'flutter_rust_bridge',
        'frb_rust/Cargo.toml',
        'file',
        'present',
        null,
      );
      return;
    }
    String? version;
    try {
      version = _rustVersion(frb, frbCommit, manifest);
    } on FormatException catch (e) {
      _problem(
        'flutter_rust_bridge',
        'frb_rust/Cargo.toml',
        'version',
        'TOML',
        e.message,
      );
      return;
    }
    if (version == null) {
      _problem(
        'flutter_rust_bridge',
        'frb_rust/Cargo.toml',
        'version',
        'version or version.workspace',
        null,
      );
      return;
    }

    // Dart-side refs must be the same commit; Rust deps must be that version.
    for (final (repo, path) in [
      (
        'bricks',
        'bricks/p0g_app/__brick__/{{name.snakeCase()}}/core/pubspec.yaml',
      ),
      ('demo', 'core/pubspec.yaml'),
      ('flasher-web', 'core/pubspec.yaml'),
    ]) {
      final text = _read(repo, path);
      if (text == null) continue;
      final dep = _gitDeps(
        stripMustache(text),
        repo,
        path,
      ).where((d) => d.url == _frbUrl).toList();
      if (dep.isEmpty) {
        _problem(repo, path, 'flutter_rust_bridge.ref', frbCommit, null);
      }
      for (final d in dep) {
        if (d.ref != frbCommit)
          _problem(repo, path, 'flutter_rust_bridge.ref', frbCommit, d.ref);
      }
    }
    for (final (repo, path) in [
      (
        'bricks',
        'bricks/p0g_app/__brick__/{{name.snakeCase()}}/{{#rust}}rust{{/rust}}/Cargo.toml',
      ),
      ('demo', 'rust/Cargo.toml'),
      ('flasher-web', 'rust/Cargo.toml'),
    ]) {
      final text = _read(repo, path);
      if (text == null) continue;
      final declared = RegExp(
        r'^flutter_rust_bridge\s*=\s*\{[^}]*version\s*=\s*"([^"]+)"',
        multiLine: true,
      ).firstMatch(text)?.group(1);
      if (declared != '=$version') {
        _problem(
          repo,
          path,
          'flutter_rust_bridge.version',
          '=$version',
          declared,
        );
      }
    }
  }

  String? _rustVersion(GitRepo frb, String commit, String manifest) {
    final map = TomlDocument.parse(manifest).toMap();
    final version = map['package'] is Map
        ? (map['package'] as Map)['version']
        : null;
    if (version is String) return version;
    if (version == null) return null;
    // version.workspace = true: the workspace root holds the value.
    final root = frb.show(commit, 'Cargo.toml');
    if (root == null) return null;
    final rootMap = TomlDocument.parse(root).toMap();
    final workspace = rootMap['workspace'];
    if (workspace is! Map) return null;
    final pkg = workspace['package'];
    return pkg is Map ? pkg['version'] as String? : null;
  }

  // --- CI SDKs -----------------------------------------------------------

  void _checkWorkflowSdks() {
    for (final (repo, dir) in [
      ('flutter_p0g', '.github/workflows'),
      ('demo', '.github/workflows'),
      ('flasher-web', '.github/workflows'),
      ('bricks', '.github/workflows'),
      ('flutter-aera', '.github/workflows'),
      ('flutter-webui', '.github/workflows'),
      ('webui-packages', '.github/workflows'),
      ('squadron_process', '.github/workflows'),
      ('webui-termux-api', '.github/workflows'),
    ]) {
      final git = _repo(repo);
      if (git == null) continue;
      final tree = git.lsTree(_locked(repo));
      if (tree == null) continue;
      final files = tree.where(
        (f) =>
            f.startsWith('$dir/') &&
            (f.endsWith('.yml') || f.endsWith('.yaml')),
      );
      for (final file in files) {
        final text = git.show(_locked(repo), file);
        if (text == null) continue;
        _checkWorkflowFlutter(text, repo, file);
      }
    }
  }

  void _checkWorkflowFlutter(String text, String repo, String path) {
    final doc = _yamlMap(text, repo, path);
    if (doc == null) return;
    for (final value in _findKey(doc, 'flutter-version')) {
      // An expression is resolved at run time, not a literal pin.
      if (value.contains(r'${{')) continue;
      if (value != flutterVersion) {
        _problem(repo, path, 'flutter-version', flutterVersion, value);
      }
    }
  }

  // --- shared ------------------------------------------------------------

  /// Checks one manifest's git dependencies against the lock, and the
  /// dependencies a generated app must carry.
  void _checkConsumerManifest(String repo, String path, String relative) {
    final text = _read(repo, path);
    if (text == null) return;
    final deps = relative.endsWith('.yaml')
        ? _gitDeps(stripMustache(text), repo, path)
        : const <_GitDep>[];
    for (final dep in deps) {
      final url = dep.url;
      if (url == null) {
        _problem(repo, path, '${dep.name}.url', 'a git URL', null);
        continue;
      }
      final owner = _ownerUrls[url];
      if (owner == null) continue;
      final expected =
          owner == 'flutter_p0g' && dep.path == 'packages/patched_source'
          ? helperRef
          : _locked(owner);
      if (dep.ref != expected) {
        _problem(repo, path, '${dep.name}.ref', expected, dep.ref);
      }
      if (owner == 'flutter_p0g' && dep.path != 'packages/patched_source') {
        _problem(
          repo,
          path,
          '${dep.name}.path',
          'packages/patched_source',
          dep.path,
        );
      }
    }

    // Required dependencies of a generated app (plan 8.3): the pure-Dart core
    // carries the places, the WebUI client and FRB; the CLI is also the root
    // process and carries the places. The GUI reaches them through the core.
    if (relative == 'core/pubspec.yaml' || relative == 'cli/pubspec.yaml') {
      for (final (name, owner) in [
        ('squadron_process', 'squadron_process'),
        if (relative == 'core/pubspec.yaml')
          ('flutter_webui_client', 'flutter-webui'),
      ]) {
        if (!deps.any((d) => d.name == name)) {
          _problem(repo, path, '$name.ref', _locked(owner), null);
        }
      }
      if (relative == 'core/pubspec.yaml' &&
          !deps.any((d) => d.name == 'flutter_rust_bridge')) {
        _problem(repo, path, 'flutter_rust_bridge.ref', _frbUrl, null);
      }
    }
    // analysis_options.yaml carries the lints plugin, which lives in bricks.
    if (relative == 'analysis_options.yaml') {
      final plugins = _yamlMap(stripMustache(text), repo, path)?['plugins'];
      if (plugins is! Map) {
        _problem(repo, path, 'p0g_lints.ref', 'git dependency on bricks', null);
      } else {
        final lints = plugins['p0g_lints'];
        final git = lints is Map ? lints['git'] : null;
        final url = git is Map ? git['url'] : null;
        final ref = git is Map ? git['ref'] : null;
        if ('$url' != 'https://github.com/p0g-stack/bricks') {
          _problem(
            repo,
            path,
            'p0g_lints.url',
            'https://github.com/p0g-stack/bricks',
            url,
          );
        } else if (ref == null || !_sha40.hasMatch('$ref')) {
          _problem(repo, path, 'p0g_lints.ref', 'full bricks commit', ref);
        } else if (_repo('bricks')?.commit('$ref') == null) {
          _problem(repo, path, 'p0g_lints.ref', 'a bricks commit', ref);
        }
      }
    }
  }

  List<_GitDep> _gitDeps(String text, String repo, String path) {
    final doc = _yamlMap(text, repo, path);
    if (doc == null) return const [];
    final deps = <_GitDep>[];
    for (final section in [
      'dependencies',
      'dev_dependencies',
      'dependency_overrides',
    ]) {
      final block = doc[section];
      if (block is! Map) continue;
      for (final entry in block.entries) {
        final value = entry.value;
        if (value is! Map) continue;
        final git = value['git'];
        if (git is! Map) continue;
        deps.add(
          _GitDep(
            '${entry.key}',
            git['url'] == null ? null : '${git['url']}',
            git['path'] == null ? null : '${git['path']}',
            git['ref'] == null ? null : '${git['ref']}',
            path,
          ),
        );
      }
    }
    return deps;
  }

  Map<String, dynamic>? _yamlMap(String text, String repo, String path) {
    try {
      final node = loadYaml(text);
      return node is Map ? _plain(node) as Map<String, dynamic> : null;
    } on YamlException catch (e) {
      _problem(repo, path, 'yaml', 'valid YAML', e.message.split('\n').first);
      return null;
    }
  }

  static Object? _plain(Object? node) {
    if (node is Map) {
      return <String, dynamic>{
        for (final e in node.entries) '${e.key}': _plain(e.value),
      };
    }
    if (node is List) return [for (final v in node) _plain(v)];
    return node;
  }

  /// Every value stored under [key], at any depth.
  List<String> _findKey(Object? node, String key, [List<String>? out]) {
    final found = out ?? <String>[];
    if (node is Map) {
      for (final entry in node.entries) {
        if ('${entry.key}' == key) found.add('${entry.value}');
        _findKey(entry.value, key, found);
      }
    } else if (node is List) {
      for (final value in node) {
        _findKey(value, key, found);
      }
    }
    return found;
  }

  /// The `Current` cell of a `| label | ... |` row in engine-pin.md.
  String? _tableValue(String markdown, String label) {
    final row = RegExp(
      r'^\|\s*' + RegExp.escape(label) + r'\s*\|\s*`?([^`|]+?)`?\s*\|',
      multiLine: true,
    ).firstMatch(markdown);
    return row?.group(1)?.trim();
  }

  /// `const kName = 'value';`
  String? _constString(String source, String name) {
    final match = RegExp(
      r"^const\s+" + RegExp.escape(name) + r"\s*=\s*'([^']*)';",
      multiLine: true,
    ).firstMatch(source);
    return match?.group(1);
  }

  void _expectConst(
    String repo,
    String path,
    String name,
    String expected,
    String source,
  ) {
    final actual = _constString(source, name);
    if (actual != expected) _problem(repo, path, name, expected, actual);
  }

  /// Parses one `Map<String, Map<String, PinnedArtifact>>` literal, with the
  /// provenance comment line above each version key.
  Map<String, Map<String, _Pin>> _artifactPins(String source, String name) {
    final start = source.indexOf(
      'const Map<String, Map<String, PinnedArtifact>> $name = {',
    );
    final pins = <String, Map<String, _Pin>>{};
    if (start < 0) return pins;
    final lines = const LineSplitter().convert(source.substring(start));
    String? version;
    String? comment;
    String? target;
    String? url;
    String? pendingComment;
    var state = 0; // 0 outside, 1 in version, 2 after PinnedArtifact(
    for (final raw in lines.skip(1)) {
      final line = raw.trimRight();
      final trimmed = line.trim();
      if (trimmed == '};') break;
      if (trimmed.startsWith('//')) {
        pendingComment = trimmed;
        continue;
      }
      final versionMatch = RegExp(r"^'([^']+)': \{$").firstMatch(trimmed);
      if (versionMatch != null) {
        version = versionMatch.group(1);
        comment = pendingComment;
        pins[version!] = {};
        pendingComment = null;
        state = 1;
        continue;
      }
      if (version == null) continue;
      final targetMatch = RegExp(r"^'([^']+)': PinnedArtifact\($")
          .firstMatch(trimmed);
      if (targetMatch != null) {
        target = targetMatch.group(1);
        state = 2;
        continue;
      }
      if (state == 2) {
        final value = RegExp(r"^'([^']*)',$").firstMatch(trimmed)?.group(1);
        if (value == null) continue;
        if (url == null) {
          url = value;
        } else {
          pins[version]![target!] = _Pin(version, target, url, value, comment);
          url = null;
          state = 1;
        }
      }
    }
    return pins;
  }

  /// Mason sections and variables, removed so a brick template parses as
  /// YAML: section markers go, their content stays, variables become `x`.
  static String stripMustache(String text) {
    var out = text.replaceAllMapped(
      RegExp(r'\{\{\^[^}]*\}\}[\s\S]*?\{\{/[^}]*\}\}'),
      (_) => '',
    );
    out = out.replaceAll(RegExp(r'\{\{[#/][^}]*\}\}'), '');
    return out.replaceAll(RegExp(r'\{\{[^}]*\}\}'), 'x');
  }
}
