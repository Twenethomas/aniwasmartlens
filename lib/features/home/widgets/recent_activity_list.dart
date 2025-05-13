import 'package:flutter/material.dart';

class RecentActivityList extends StatelessWidget {
  final List<String> activities;
  const RecentActivityList({super.key, required this.activities});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: activities.map((act) {
        return ListTile(
          leading: const Icon(Icons.history, size: 24),
          title: Text(act),
          trailing: IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              // TODO: re-run this action
            },
          ),
        );
      }).toList(),
    );
  }
}
