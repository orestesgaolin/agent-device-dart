import 'package:agent_device/agent_device.dart';
import 'package:test/test.dart';

void main() {
  test('package version is exported', () {
    expect(packageVersion, isNotEmpty);
  });
}
