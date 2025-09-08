import 'package:flutter/material.dart';
import '../singleton.dart';

class ManageScreen extends StatefulWidget {
  const ManageScreen({super.key});

  @override
  State<ManageScreen> createState() => _ManageScreenState();
}

class _ManageScreenState extends State<ManageScreen> {
  final singleton = Singleton();
  double size = 1;
  @override
  Widget build(BuildContext context) {
    return Padding(
        padding: const EdgeInsets.all(16.0),
        child: Center(
          child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const Text(
                  "Symptom Log",
                  style: TextStyle(fontSize: 40.0, fontWeight: FontWeight.bold),
                ),
                IconButton(
                  onPressed: () {
                    Navigator.pushNamed(context, '/logScreen');
                  },
                  icon: Transform.scale(
                    scale: size,
                    child: Image.asset(
                      'images/GOLD-6487-CareerGuide-Batch04-Images-GraphCharts-01-Line.jpg',
                      height: 200,
                      width: 200,
                    ),
                  ),
                ),
                const Text(
                  "Log your symptoms!",
                  style: TextStyle(fontSize: 20.0, fontWeight: FontWeight.bold),
                ),
                const Text(
                  "Medication",
                  style: TextStyle(fontSize: 40.0, fontWeight: FontWeight.bold),
                ),
                IconButton(
                  onPressed: () {
                    Navigator.pushNamed(context, '/scheduleScreen');
                  },
                  icon: Transform.scale(
                    scale: size,
                    child: Image.asset(
                      "images/ecddfe31-e5bf-4385-ba75-64b241852e0b.png",
                      height: 200,
                      width: 200,
                    ),
                  ),
                ),
                const Text(
                  "Set reminders to take medicine!",
                  style: TextStyle(fontSize: 20.0, fontWeight: FontWeight.bold),
                ),
              ]),
        ));
  }
}
