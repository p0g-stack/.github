import 'dart:io';

import 'package:p0g_stack_hub/stack_lock.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'fixtures.dart';

String _hex(String digit) => List.filled(40, digit).join();

late Directory _temp;
late Fixture _fixture;

/// Runs the checker as the CLI does, returning one string per diagnostic.
List<String> _run(Fixture fixture, {String? lockPath}) {
  final check = StackCheck(
    workspace: fixture.dir,
    lockFile: lockPath ?? fixture.lockPath,
    frbDir: p.join(fixture.dir, 'flutter_rust_bridge'),
  );
  if (!check.load()) return [for (final problem in check.problems) '$problem'];
  check.resolve();
  check.run();
  return [for (final problem in check.problems) '$problem'];
}

ProcessResult _cli(Fixture fixture) =>
    Process.runSync(Platform.resolvedExecutable, [
      'run',
      'tool/check_pins.dart',
      '--workspace',
      fixture.dir,
      '--lock',
      fixture.lockPath,
      '--frb',
      p.join(fixture.dir, 'flutter_rust_bridge'),
    ], workingDirectory: Directory.current.path);

void main() {
  setUpAll(() {
    _temp = Directory.systemTemp.createTempSync('stack-lock-');
    _fixture = Fixture.build(p.join(_temp.path, 'ws'));
  });

  tearDownAll(() => _temp.deleteSync(recursive: true));

  test('a consistent snapshot has no diagnostics', () {
    expect(_run(_fixture), isEmpty);
  });

  test('the CLI exits 0 on a consistent snapshot', () {
    final result = _cli(_fixture);
    expect(result.exitCode, 0, reason: '${result.stdout}${result.stderr}');
    expect('${result.stdout}', contains('stack.lock.json: ok'));
  });

  test('one changed consumer pin fails with the exact expected/actual', () {
    final changed = '0123456789abcdef0123456789abcdef01234567';
    final core = File(p.join(_fixture.dir, 'demo', 'core', 'pubspec.yaml'))
        .readAsStringSync();
    final pinned = _fixture.shas['squadron_process']!;
    final commit = _fixture.commit(
      'demo',
      'core/pubspec.yaml',
      core.replaceFirst(pinned, changed),
      message: 'pin a squadron commit the lock does not name',
    );
    final lock = _fixture.readLock();
    (lock['repos'] as Map<String, dynamic>)['demo'] = commit;
    _fixture.writeLock(lock);

    final problems = _run(_fixture);
    expect(
      problems,
      equals([
        'demo:core/pubspec.yaml squadron_process.ref expected=$pinned actual=$changed',
      ]),
    );

    final result = _cli(_fixture);
    expect(result.exitCode, 1);
    expect(
      '${result.stdout}',
      contains(
        'demo:core/pubspec.yaml squadron_process.ref expected=$pinned actual=$changed',
      ),
    );

    // Restore the snapshot for the other tests.
    lock['repos']['demo'] = _fixture.shas['demo'];
    _fixture.writeLock(lock);
    expect(_run(_fixture), isEmpty);
  });

  test('a missing locked object fails and is not read as HEAD', () {
    final missing = _hex('b');
    final lock = _fixture.readLock();
    (lock['repos'] as Map<String, dynamic>)['webui-packages'] = missing;
    _fixture.writeLock(lock);

    final problems = _run(_fixture);
    expect(
      problems,
      contains(
        'webui-packages:- commit expected=$missing actual=<missing object>',
      ),
    );
    // The consumer of that pin is reported against the lock, not skipped.
    expect(
      problems,
      contains(
        'flutter_p0g:lib/src/webui/webui_packages.dart kWebuiPackagesCommit '
        'expected=$missing actual=${_fixture.shas['webui-packages']}',
      ),
    );

    lock['repos']['webui-packages'] = _fixture.shas['webui-packages'];
    _fixture.writeLock(lock);
    expect(_run(_fixture), isEmpty);
  });

  test('a missing repository is a failure, not a skip', () {
    final missing = _hex('c');
    final lock = _fixture.readLock();
    (lock['repos'] as Map<String, dynamic>)['flasher-web'] = missing;
    _fixture.writeLock(lock);

    expect(
      _run(_fixture),
      contains(
        'flasher-web:- checkout expected=$missing actual=<missing repository>',
      ),
    );

    (lock['repos'] as Map<String, dynamic>).remove('flasher-web');
    _fixture.writeLock(lock);
    expect(_run(_fixture), isEmpty);
  });

  test('a lock without helperRef fails before any file is read', () {
    final lock = _fixture.readLock()..remove('helperRef');
    _fixture.writeLock(lock);

    expect(
      _run(_fixture),
      equals([
        '.github:stack.lock.json helperRef expected=full commit actual=<missing>',
      ]),
    );

    final result = _cli(_fixture);
    expect(result.exitCode, 1);
    _fixture.writeLock(
      _fixture.readLock()..['helperRef'] = _fixture.shas['helperRef'],
    );
    expect(_run(_fixture), isEmpty);
  });

  test('a missing required field in a locked file fails', () {
    final file = File(
      p.join(_fixture.dir, 'flutter_p0g', 'lib', 'src', 'frb', 'frb.dart'),
    );
    final commit = _fixture.commit(
      'flutter_p0g',
      'lib/src/frb/frb.dart',
      file.readAsStringSync().replaceFirst(
        RegExp(r"^const kFrbCommit = .*\n", multiLine: true),
        '',
      ),
      message: 'drop the frb pin',
    );
    final lock = _fixture.readLock();
    (lock['repos'] as Map<String, dynamic>)['flutter_p0g'] = commit;
    _fixture.writeLock(lock);

    expect(
      _run(_fixture),
      contains(
        'flutter_p0g:lib/src/frb/frb.dart kFrbCommit expected=full commit actual=<missing>',
      ),
    );

    (lock['repos'] as Map<String, dynamic>)['flutter_p0g'] =
        _fixture.shas['flutter_p0g'];
    _fixture.writeLock(lock);
    expect(_run(_fixture), isEmpty);
  });

  test('a kit whose producer comment names another commit fails', () {
    final path = p.join(
      _fixture.dir,
      'flutter_p0g',
      'lib',
      'src',
      'artifact_pins.dart',
    );
    final source = File(path).readAsStringSync();
    final other = _hex('d');
    final commit = _fixture.commit(
      'flutter_p0g',
      'lib/src/artifact_pins.dart',
      source.replaceFirst(
        '// kit-$flutterVersion-${_fixture.shas['flutter-aera']}',
        '// kit-$flutterVersion-$other',
      ),
      message: 'name the wrong kit producer',
    );
    final lock = _fixture.readLock();
    (lock['repos'] as Map<String, dynamic>)['flutter_p0g'] = commit;
    _fixture.writeLock(lock);

    expect(
      _run(_fixture),
      contains(
        'flutter_p0g:lib/src/artifact_pins.dart '
        'aeraKitPins.$flutterVersion.linux-arm64-debug.producer '
        'expected=${_fixture.shas['flutter-aera']} actual=$other',
      ),
    );

    (lock['repos'] as Map<String, dynamic>)['flutter_p0g'] =
        _fixture.shas['flutter_p0g'];
    _fixture.writeLock(lock);
    expect(_run(_fixture), isEmpty);
  });
}
