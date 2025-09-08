import 'package:flutter/material.dart';

//import '../Firebase/firebase_cloud.dart';
import '../Recovery/exercise.dart';
import '../Recovery/speech.dart';
import '../singleton.dart';

class RecoveryScreen extends StatefulWidget {
  const RecoveryScreen({super.key});

  @override
  State<RecoveryScreen> createState() => _RecoveryScreenState();
}

class _RecoveryScreenState extends State<RecoveryScreen> {
  final singleton = Singleton();
  double size = 2;
  double imageSize = 125;
  double spacing = 25;

  // @override
  // void initState() {
  //   FirebaseCloud().updateNums(singleton.postNum, singleton.exerNum);
  //   super.initState();
  // }

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
                  "Speeches",
                  style: TextStyle(fontSize: 40.0, fontWeight: FontWeight.bold),
                ),
                SizedBox(height: spacing),
                IconButton(
                  onPressed: () {
                    Navigator.of(context).push(MaterialPageRoute(
                        builder: (context) => const SpeechScreen()));
                  },
                  icon: Transform.scale(
                    scale: size,
                    child: Image.asset(
                      'images/GOLD-6487-CareerGuide-Batch04-Images-GraphCharts-01-Line.jpg',
                      height: imageSize,
                      width: imageSize,
                    ),
                  ),
                ),
                SizedBox(height: spacing),
                const Text(
                  "(Description)",
                  style: TextStyle(fontSize: 25.0, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 50),
                const Text(
                  "Exercises",
                  style: TextStyle(fontSize: 40.0, fontWeight: FontWeight.bold),
                ),
                SizedBox(height: spacing),
                IconButton(
                  onPressed: () {
                    Navigator.of(context).push(MaterialPageRoute(
                        builder: (context) => const ExerciseScreen()));
                  },
                  icon: Transform.scale(
                    scale: size,
                    child: Image.asset(
                      "images/ecddfe31-e5bf-4385-ba75-64b241852e0b.png",
                      height: imageSize,
                      width: imageSize,
                    ),
                  ),
                ),
                SizedBox(height: spacing),
                const Text(
                  "(Description)",
                  style: TextStyle(fontSize: 25.0, fontWeight: FontWeight.bold),
                ),
                //  Text(
                //   "Games",
                //   style: TextStyle(
                //       fontSize: 30.0,
                //       fontWeight: FontWeight.bold),
                // ),
                // const SizedBox(height: 20),
                // IconButton(
                //   onPressed: () {
                //     Navigator.of(context).pushReplacement(MaterialPageRoute(
                //         builder: (context) => const GamesScreen()));
                //   },
                //   icon: Transform.scale(
                //     scale: size,
                //     child: Image.asset(
                //       'images/GOLD-6487-CareerGuide-Batch04-Images-GraphCharts-01-Line.jpg',
                //       height: imageSize,
                //       width: imageSize,
                //     ),
                //   ),
                // ),
                //  Text(
                //   "Description",
                //   style: TextStyle(
                //       fontSize: 20.0,
                //       fontWeight: FontWeight.bold),
                // ),
              ]),
        ));
  }
}
