import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'offline_queue.dart';

/// Single shared offline queue instance for the whole app.
final offlineQueueProvider = Provider<OfflineQueue>((ref) => OfflineQueue());
