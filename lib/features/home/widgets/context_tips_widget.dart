import 'package:flutter/material.dart';

class ContextTipsWidget extends StatefulWidget {
  const ContextTipsWidget({super.key});
  @override
  _ContextTipsWidgetState createState() => _ContextTipsWidgetState();
}

class _ContextTipsWidgetState extends State<ContextTipsWidget> {
  final tips = [
    'Try saying “Describe Scene”',
    'Tap SOS in an emergency',
    'Use voice: “Read Text”',
  ];
  int idx = 0;

  @override
  void initState() {
    super.initState();
    Future.doWhile(() async {
      await Future.delayed(const Duration(seconds: 5));
      if (!mounted) return false;
      setState(() => idx = (idx + 1) % tips.length);
      return true;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      margin: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        color: Colors.blue.shade50,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const Icon(Icons.lightbulb_outline),
          const SizedBox(width: 8),
          Expanded(child: Text(tips[idx])),
        ],
      ),
    );
  }
}
