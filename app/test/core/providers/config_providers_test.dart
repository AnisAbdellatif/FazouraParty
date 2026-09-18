import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fazoura_party/core/providers/config_providers.dart';

void main() {
  test('debug server override is persisted and can be cleared', () async {
    SharedPreferences.setMockInitialValues({});
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await container
        .read(serverBaseUrlProvider.notifier)
        .setDebugOverride('http://10.0.2.2:4000');
    expect(container.read(serverBaseUrlProvider), 'http://10.0.2.2:4000');

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('fazoura.debug_server_url'), 'http://10.0.2.2:4000');

    await container.read(serverBaseUrlProvider.notifier).setDebugOverride(null);
    expect(prefs.getString('fazoura.debug_server_url'), isNull);
  });
}
