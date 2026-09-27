import 'package:flutter/foundation.dart';

/// Bumping [appRestartCount] remounts the whole app under a fresh
/// `ProviderScope` (new container and a new database connection). Used after a
/// database restore replaces the SQLite file underneath the running app.
final ValueNotifier<int> appRestartCount = ValueNotifier<int>(0);
