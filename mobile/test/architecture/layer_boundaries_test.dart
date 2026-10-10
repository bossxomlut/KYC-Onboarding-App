import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('domain stays pure and presentation cannot reach infrastructure', () {
    final violations = <String>[];
    for (final file in Directory('lib').listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.dart'))) {
      final path = file.path.replaceAll('\\', '/');
      final imports = RegExp(r'''(?:import|export)\s+['"]([^'"]+)['"]''').allMatches(file.readAsStringSync()).map((m) => m.group(1)!);
      for (final dependency in imports) {
        if (path.contains('/domain/') && (dependency.startsWith('package:') && !dependency.startsWith('package:kyc_onboarding/') || dependency.contains('/data/') || dependency.contains('/presentation/') || dependency.contains('/network/') || dependency.contains('/security/'))) {
          violations.add('$path imports $dependency');
        }
        if (path.contains('/presentation/') && (dependency.contains('/data/') || dependency.contains('/repositories/') || dependency.contains('/network/') || dependency.contains('/security/') || RegExp(r'^package:(dio|image_picker|flutter_secure_storage|path_provider)/').hasMatch(dependency))) {
          violations.add('$path imports $dependency');
        }
        if (path.contains('/core/') && dependency.contains('/features/')) {
          violations.add('$path imports feature $dependency');
        }
      }
    }
    expect(violations, isEmpty, reason: violations.join('\n'));
  });
}
