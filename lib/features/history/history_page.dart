import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/services/history_service.dart';
import 'package:intl/intl.dart';

class HistoryPage extends StatelessWidget {
  const HistoryPage({super.key});
  @override
  Widget build(BuildContext context) {
    final service = context.read<HistoryService>();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Read History'),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete),
            onPressed: () async {
              final ok = await showDialog<bool>(
                context: context,
                builder: (_) => AlertDialog(
                  title: const Text('Clear History?'),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('No')),
                    TextButton(onPressed: () => Navigator.pop(context, true),  child: const Text('Yes')),
                  ],
                ),
              );
              if (ok == true) {
                await service.clear();
                (context as Element).reassemble(); // force rebuild
              }
            },
          )
        ],
      ),
      body: FutureBuilder<List<HistoryEntry>>(
        future: service.getHistory(),
        builder: (context, snap) {
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          final hist = snap.data!;
          if (hist.isEmpty) return const Center(child: Text('No history yet.'));
          return ListView.builder(
            itemCount: hist.length,
            itemBuilder: (_, i) {
              final e = hist[i];
              return ListTile(
                title: Text(e.text, maxLines: 2, overflow: TextOverflow.ellipsis),
                subtitle: Text(DateFormat.yMd().add_jm().format(e.timestamp)),
                onTap: () {
                  // Optionally re-read or share
                },
              );
            },
          );
        },
      ),
    );
  }
}
