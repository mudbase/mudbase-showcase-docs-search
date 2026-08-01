import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'config/env_config.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // Fail fast on a misconfigured build rather than surfacing a confusing
  // 404/401 the first time a screen reads an empty collection id.
  EnvConfig.assertConfigured();
  runApp(const ProviderScope(child: MudbaseShowcaseDocsSearchApp()));
}
