import 'package:flutter/material.dart';

import '../field/field_sample_data.dart';
import '../shared/field_widgets.dart';

class SyncScreen extends StatelessWidget {
  const SyncScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return PageScaffold(
      title: 'Sync',
      subtitle: 'Offline work waits here until internet is available.',
      children: [
        ...sampleSyncTasks.map(
          (task) => Card(
            child: ListTile(
              leading: const Icon(Icons.cloud_upload_outlined),
              title: Text(task.title),
              subtitle: Text(task.subtitle),
              trailing: Chip(label: Text(task.status)),
            ),
          ),
        ),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: () {},
          icon: const Icon(Icons.sync),
          label: const Text('Sync now'),
        ),
      ],
    );
  }
}
