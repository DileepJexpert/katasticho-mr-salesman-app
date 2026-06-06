import 'package:flutter/material.dart';

import '../shared/field_widgets.dart';

class PartiesScreen extends StatelessWidget {
  const PartiesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return PageScaffold(
      title: 'Parties',
      subtitle:
          'Doctors, hospitals, chemists, retailers, distributors, and stockists.',
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.info_outline,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text(
                    'Party / contact lookup will connect to the ERP contacts endpoint in a future release. Visits and collections are already tracked per visit.',
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
