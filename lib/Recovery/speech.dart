import 'package:flutter/material.dart';
import 'package:parkinson/singleton.dart';

class SpeechScreen extends StatefulWidget {
  const SpeechScreen({super.key});

  @override
  State<SpeechScreen> createState() => _SpeechScreenState();
}

class _SpeechScreenState extends State<SpeechScreen> {
  final singleton = Singleton();
  late Map<String, List<String>> speeches;
  late List<String> urls;

  @override
  void initState() {
    super.initState();
    speeches = singleton.speeches;
    urls = singleton.speeches.keys.toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(
              Icons.arrow_back,
            ),
            onPressed: () {
              Navigator.pushNamed(context, '/');
            },
          ),
        ),
        body: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    "Speech",
                    style:
                        TextStyle(fontSize: 30.0, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(
                    height: 10,
                  ),
                  Expanded(
                    child: SizedBox(
                      height: 200,
                      child: ListView.builder(
                        itemCount: speeches.length,
                        itemBuilder: (BuildContext context, int index) {
                          Widget logColumn =
                              Row(mainAxisSize: MainAxisSize.min, children: [
                            Icon(
                              Icons.audiotrack_rounded,
                              size: 50,
                              color: singleton.themeColor[singleton.colorMode]
                                  [1],
                            ),
                            const SizedBox(width: 20),
                            Column(
                              mainAxisAlignment: MainAxisAlignment.start,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  singleton.speeches[urls[index]]![0],
                                  style: const TextStyle(
                                      fontSize: 20,
                                      fontWeight: FontWeight.bold),
                                ),
                                Text(
                                  singleton.speeches[urls[index]]![1],
                                  style: const TextStyle(fontSize: 15),
                                ),
                              ],
                            )
                          ]);
                          return Container(
                              margin: const EdgeInsets.all(10.0),
                              padding: const EdgeInsets.only(
                                  left: 6.0,
                                  top: 12.0,
                                  right: 12.0,
                                  bottom: 12.0),
                              decoration: BoxDecoration(
                                  border: Border.all(
                                      color: singleton
                                          .themeColor[singleton.colorMode][1])),
                              child: ListTile(
                                title: logColumn,
                                onTap: () {
                                  singleton.setCurrentUrl(urls[index]);
                                  Navigator.popAndPushNamed(
                                      context, '/speechAudio');
                                },
                              ));
                        },
                      ),
                    ),
                  ),
                ])));
  }
}
