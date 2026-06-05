import 'package:flutter/material.dart';

import '../shared/field_widgets.dart';

class ExpensesScreen extends StatelessWidget {
  const ExpensesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return PageScaffold(
      title: 'Expenses',
      subtitle:
          'Capture travel, food, lodging, samples support, and misc expenses.',
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              children: [
                DropdownButtonFormField<String>(
                  decoration: const InputDecoration(labelText: 'Expense type'),
                  items: const [
                    DropdownMenuItem(value: 'TRAVEL', child: Text('Travel')),
                    DropdownMenuItem(value: 'FOOD', child: Text('Food')),
                    DropdownMenuItem(value: 'LODGING', child: Text('Lodging')),
                    DropdownMenuItem(value: 'MISC', child: Text('Misc')),
                  ],
                  onChanged: (_) {},
                ),
                const SizedBox(height: 12),
                const TextField(
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(labelText: 'Amount'),
                ),
                const SizedBox(height: 12),
                const TextField(
                  minLines: 2,
                  maxLines: 4,
                  decoration: InputDecoration(labelText: 'Notes'),
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: () {},
                  icon: const Icon(Icons.cloud_upload),
                  label: const Text('Queue expense'),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
