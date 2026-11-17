// Checks the recorded p0g-stack compatibility set.
//
//   dart run tool/check_pins.dart --workspace .. --lock stack.lock.json
//
// `--workspace` is the directory holding the sibling checkouts (this hub's
// parent). `--lock` defaults to `stack.lock.json` beside this package.
// `--frb` names a flutter_rust_bridge checkout; only the locked commit is
// read from it, and it defaults to `<workspace>/flutter_rust_bridge`.
//
// Prints one line per mismatch, `repo:path field expected=<value>
// actual=<value>`, and exits 1. A missing repository, commit, file or field
// is a mismatch; nothing is skipped.
import 'dart:io';

import 'package:args/args.dart';
import 'package:p0g_stack_hub/stack_lock.dart';
import 'package:path/path.dart' as p;

void main(List<String> arguments) {
  final parser = ArgParser()
    ..addOption('workspace', help: 'Directory holding the sibling checkouts.')
    ..addOption('lock', help: 'Lock file to check (default: stack.lock.json).')
    ..addOption(
      'frb',
      help: 'flutter_rust_bridge checkout (default: <workspace>/flutter_rust_bridge).',
    )
    ..addFlag('help', abbr: 'h', negatable: false);

  final ArgResults args;
  try {
    args = parser.parse(arguments);
  } on FormatException catch (e) {
    stderr.writeln(e.message);
    stderr.writeln(parser.usage);
    exit(64);
  }
  if (args['help'] as bool) {
    stdout.writeln(
      'usage: dart run tool/check_pins.dart --workspace <dir> [--lock <file>] [--frb <dir>]',
    );
    stdout.writeln(parser.usage);
    return;
  }

  final here = p.dirname(p.dirname(Platform.script.toFilePath()));
  final workspace = p.normalize(
    p.absolute((args['workspace'] as String?) ?? p.join(here, '..')),
  );
  final lock = p.normalize(
    p.absolute((args['lock'] as String?) ?? p.join(here, 'stack.lock.json')),
  );
  final frb = args['frb'] as String?;

  final check = StackCheck(
    workspace: workspace,
    lockFile: lock,
    frbDir: frb == null ? null : p.normalize(p.absolute(frb)),
  );
  if (!check.load()) {
    _report(check);
    return;
  }
  check.resolve();
  check.run();
  _report(check);
}

void _report(StackCheck check) {
  for (final problem in check.problems) {
    stdout.writeln(problem);
  }
  final count = check.problems.length;
  stdout.writeln(
    count == 0
        ? 'stack.lock.json: ok (${check.flutterVersion}, ${check.flutterEngine.substring(0, 7)})'
        : 'stack.lock.json: $count problem(s)',
  );
  exit(count == 0 ? 0 : 1);
}
