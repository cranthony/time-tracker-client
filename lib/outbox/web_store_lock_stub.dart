import 'store_lock.dart';

/// Off the web, no browser lock: see [IsolateStoreLock].
StoreLock webStoreLock(String name) => const NoStoreLock();
