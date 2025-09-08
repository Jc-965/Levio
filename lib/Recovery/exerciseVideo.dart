import 'package:flutter/material.dart';
import 'package:youtube_player_iframe/youtube_player_iframe.dart';
import 'package:parkinson/singleton.dart';

class ExerciseVideo extends StatefulWidget {
  const ExerciseVideo({super.key});

  @override
  State<ExerciseVideo> createState() => _ExerciseVideoState();
}

class _ExerciseVideoState extends State<ExerciseVideo> {
  final singleton = Singleton();
  late YoutubePlayerController _controller;
  bool recording = false;
  bool isButtonDisabled = true;

  @override
  void initState() {
    super.initState();
    _controller = YoutubePlayerController.fromVideoId(
      videoId: singleton.currentURL,
      autoPlay: false,
      params: const YoutubePlayerParams(showFullscreenButton: true),
    );
  }

  @override
  void dispose() {
    _controller.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return YoutubePlayerScaffold(
      controller: _controller,
      aspectRatio: 16 / 9,
      builder: (context, player) {
        return Scaffold(
            appBar: AppBar(
              leading: IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () {
                  dispose();
                  Navigator.pushNamed(context, '/exerciseScreen');
                },
              ),
            ),
            body: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Center(
                  child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Text(
                          singleton.exercises[singleton.currentURL]![0],
                          style: TextStyle(
                              color: singleton.themeColor[singleton.colorMode]
                                  [1],
                              fontSize: 30,
                              fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 20),
                        player,
                        const SizedBox(height: 20),
                        Visibility(
                          visible: !recording,
                          child: ElevatedButton(
                            onPressed: () {
                              setState(() {
                                recording = true;
                              });
                            },
                            child: Text(
                              'Record',
                              style: TextStyle(
                                  color: singleton
                                      .themeColor[singleton.colorMode][1],
                                  fontSize: 25,
                                  fontWeight: FontWeight.bold),
                            ),
                          ),
                        ),
                        Visibility(
                            visible: !recording,
                            child: const SizedBox(height: 20)),
                        Visibility(
                          visible: !recording,
                          child: ElevatedButton(
                            onPressed: isButtonDisabled
                                ? null
                                : () {
                                    showDialog<String>(
                                        context: context,
                                        builder: (BuildContext context) =>
                                            AlertDialog(
                                              content: Column(
                                                  mainAxisSize:
                                                      MainAxisSize.min,
                                                  children: [
                                                    Text(
                                                      'Score percentage: x%',
                                                      style: TextStyle(
                                                          color: singleton
                                                                  .themeColor[
                                                              singleton
                                                                  .colorMode][1]),
                                                    ),
                                                    Text('Tips:',
                                                        style: TextStyle(
                                                            color: singleton
                                                                    .themeColor[
                                                                singleton
                                                                    .colorMode][1])),
                                                    Text('1. Tip number one',
                                                        style: TextStyle(
                                                            color: singleton
                                                                    .themeColor[
                                                                singleton
                                                                    .colorMode][1])),
                                                    Text('2. Tip number two',
                                                        style: TextStyle(
                                                            color: singleton
                                                                    .themeColor[
                                                                singleton
                                                                    .colorMode][1])),
                                                    Text('3. Tip number three',
                                                        style: TextStyle(
                                                            color: singleton
                                                                    .themeColor[
                                                                singleton
                                                                    .colorMode][1])),
                                                  ]),
                                              actions: <Widget>[
                                                TextButton(
                                                  onPressed: () async {
                                                    Navigator.pop(
                                                        context, 'Ok');
                                                  },
                                                  child: Text('Ok',
                                                      style: TextStyle(
                                                          color: singleton
                                                                  .themeColor[
                                                              singleton
                                                                  .colorMode][1])),
                                                ),
                                              ],
                                            ));
                                  },
                            child: Text(
                              'AI Analyis',
                              style: TextStyle(
                                  color: singleton
                                      .themeColor[singleton.colorMode][1],
                                  fontSize: 25,
                                  fontWeight: FontWeight.bold),
                            ),
                          ),
                        ),
                        Visibility(
                          visible: recording,
                          child: Container(
                              color: Colors.grey,
                              child: const Icon(Icons.image,
                                  size: 200, color: Colors.black)),
                        ),
                        const SizedBox(height: 20),
                        Visibility(
                            visible: recording,
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                              children: [
                                ElevatedButton(
                                    onPressed: () {
                                      showDialog<String>(
                                          context: context,
                                          builder: (BuildContext context) =>
                                              AlertDialog(
                                                content: Text('Video Saved',
                                                    style: TextStyle(
                                                        color: singleton
                                                                    .themeColor[
                                                                singleton
                                                                    .colorMode]
                                                            [1])),
                                                actions: <Widget>[
                                                  TextButton(
                                                    onPressed: () async {
                                                      setState(() {
                                                        isButtonDisabled =
                                                            false;
                                                        recording = false;
                                                      });
                                                      Navigator.pop(
                                                          context, 'Ok');
                                                    },
                                                    child: const Text('Ok'),
                                                  ),
                                                ],
                                              ));
                                    },
                                    child: Text(
                                      'Save',
                                      style: TextStyle(
                                          color: singleton.themeColor[
                                              singleton.colorMode][13],
                                          fontSize: 25,
                                          fontWeight: FontWeight.bold),
                                    )),
                                ElevatedButton(
                                    onPressed: () {
                                      setState(() {
                                        recording = false;
                                      });
                                    },
                                    child: Text(
                                      'Cancel',
                                      style: TextStyle(
                                          color: singleton.themeColor[
                                              singleton.colorMode][7],
                                          fontSize: 25,
                                          fontWeight: FontWeight.bold),
                                    )),
                              ],
                            ))
                      ]),
                )));
      },
    );
    // return Scaffold(
    //     appBar: AppBar(
    //       leading: IconButton(
    //         icon: const Icon(Icons.arrow_back),
    //         onPressed: () {
    //           dispose();
    //           Navigator.pushNamed(context, '/exerciseScreen');
    //         },
    //       ),
    //     ),
    //     body: Padding(
    //         padding: const EdgeInsets.all(16.0),
    //         child: Center(
    //           child: Column(
    //               mainAxisAlignment: MainAxisAlignment.center,
    //               crossAxisAlignment: CrossAxisAlignment.center,
    //               children: [
    //                 Text(
    //                   singleton.exercises[singleton.currentURL]![0],
    //                   style: TextStyle(
    //                       color: singleton.themeColor[singleton.colorMode][1],
    //                       fontSize: 30,
    //                       fontWeight: FontWeight.bold),
    //                 ),
    //                 const SizedBox(height: 20),
    //                 // YoutubePlayer(
    //                 //   controller: _controller,
    //                 //   aspectRatio: 16 / 9,
    //                 // ),
    //                 YoutubePlayerScaffold(
    //                   controller: _controller,
    //                   aspectRatio: 16 / 9,
    //                   builder: (context, player) {
    //                     return player;
    //                   },
    //                 ),
    //                 const SizedBox(height: 20),
    //                 Visibility(
    //                   visible: !recording,
    //                   child: ElevatedButton(
    //                     onPressed: () {
    //                       setState(() {
    //                         recording = true;
    //                       });
    //                     },
    //                     child: Text(
    //                       'Record',
    //                       style: TextStyle(
    //                           color: singleton.themeColor[singleton.colorMode]
    //                               [1],
    //                           fontSize: 25,
    //                           fontWeight: FontWeight.bold),
    //                     ),
    //                   ),
    //                 ),
    //                 Visibility(
    //                     visible: !recording, child: const SizedBox(height: 20)),
    //                 Visibility(
    //                   visible: !recording,
    //                   child: ElevatedButton(
    //                     onPressed: isButtonDisabled
    //                         ? null
    //                         : () {
    //                             showDialog<String>(
    //                                 context: context,
    //                                 builder: (BuildContext context) =>
    //                                     AlertDialog(
    //                                       content: Column(
    //                                           mainAxisSize: MainAxisSize.min,
    //                                           children: [
    //                                             Text(
    //                                               'Score percentage: x%',
    //                                               style: TextStyle(
    //                                                   color: singleton
    //                                                           .themeColor[
    //                                                       singleton
    //                                                           .colorMode][1]),
    //                                             ),
    //                                             Text('Tips:',
    //                                                 style: TextStyle(
    //                                                     color: singleton
    //                                                                 .themeColor[
    //                                                             singleton
    //                                                                 .colorMode]
    //                                                         [1])),
    //                                             Text('1. Tip number one',
    //                                                 style: TextStyle(
    //                                                     color: singleton
    //                                                                 .themeColor[
    //                                                             singleton
    //                                                                 .colorMode]
    //                                                         [1])),
    //                                             Text('2. Tip number two',
    //                                                 style: TextStyle(
    //                                                     color: singleton
    //                                                                 .themeColor[
    //                                                             singleton
    //                                                                 .colorMode]
    //                                                         [1])),
    //                                             Text('3. Tip number three',
    //                                                 style: TextStyle(
    //                                                     color: singleton
    //                                                                 .themeColor[
    //                                                             singleton
    //                                                                 .colorMode]
    //                                                         [1])),
    //                                           ]),
    //                                       actions: <Widget>[
    //                                         TextButton(
    //                                           onPressed: () async {
    //                                             Navigator.pop(context, 'Ok');
    //                                           },
    //                                           child: Text('Ok',
    //                                               style: TextStyle(
    //                                                   color: singleton
    //                                                           .themeColor[
    //                                                       singleton
    //                                                           .colorMode][1])),
    //                                         ),
    //                                       ],
    //                                     ));
    //                           },
    //                     child: Text(
    //                       'AI Analyis',
    //                       style: TextStyle(
    //                           color: singleton.themeColor[singleton.colorMode]
    //                               [1],
    //                           fontSize: 25,
    //                           fontWeight: FontWeight.bold),
    //                     ),
    //                   ),
    //                 ),
    //                 Visibility(
    //                   visible: recording,
    //                   child: Container(
    //                       color: Colors.grey,
    //                       child: const Icon(Icons.image,
    //                           size: 200, color: Colors.black)),
    //                 ),
    //                 const SizedBox(height: 20),
    //                 Visibility(
    //                     visible: recording,
    //                     child: Row(
    //                       mainAxisAlignment: MainAxisAlignment.spaceEvenly,
    //                       children: [
    //                         ElevatedButton(
    //                             onPressed: () {
    //                               showDialog<String>(
    //                                   context: context,
    //                                   builder: (BuildContext context) =>
    //                                       AlertDialog(
    //                                         content: Text('Video Saved',
    //                                             style: TextStyle(
    //                                                 color: singleton.themeColor[
    //                                                         singleton.colorMode]
    //                                                     [1])),
    //                                         actions: <Widget>[
    //                                           TextButton(
    //                                             onPressed: () async {
    //                                               setState(() {
    //                                                 isButtonDisabled = false;
    //                                                 recording = false;
    //                                               });
    //                                               Navigator.pop(context, 'Ok');
    //                                             },
    //                                             child: const Text('Ok'),
    //                                           ),
    //                                         ],
    //                                       ));
    //                             },
    //                             child: Text(
    //                               'Save',
    //                               style: TextStyle(
    //                                   color: singleton
    //                                       .themeColor[singleton.colorMode][13],
    //                                   fontSize: 25,
    //                                   fontWeight: FontWeight.bold),
    //                             )),
    //                         ElevatedButton(
    //                             onPressed: () {
    //                               setState(() {
    //                                 recording = false;
    //                               });
    //                             },
    //                             child: Text(
    //                               'Cancel',
    //                               style: TextStyle(
    //                                   color: singleton
    //                                       .themeColor[singleton.colorMode][7],
    //                                   fontSize: 25,
    //                                   fontWeight: FontWeight.bold),
    //                             )),
    //                       ],
    //                     ))
    //               ]),
    //         )));
  }
}
