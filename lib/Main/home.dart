import 'package:flutter/material.dart';

import '../linechart.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Column(
      children: [
        SizedBox(height: 12),
        Expanded(child: LineChartSample1()),
      ],
    );
  }
}
