import 'package:flutter/material.dart';
import 'package:parkinson/Community/otherProfile.dart';
import 'package:parkinson/navbar.dart';

class TopicScreen extends StatefulWidget {
  const TopicScreen({super.key});

  @override
  State<TopicScreen> createState() => _TopicScreenState();
}

class _TopicScreenState extends State<TopicScreen> {
  String image = "images/711128.png";

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () {
              Navigator.of(context).pushReplacement(MaterialPageRoute(
                builder: (context) => const Navbar(),
              ));
            },
          ),
        ),
        body: Padding(
          padding: const EdgeInsets.all(16.0),
          child: SingleChildScrollView(
            child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    margin: const EdgeInsets.all(1.0),
                    padding: const EdgeInsets.all(16.0),
                    decoration:
                        BoxDecoration(border: Border.all(color: Colors.black)),
                    child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: <Widget>[
                              const Text(
                                "Title Text",
                                style: TextStyle(
                                    color: Colors.black,
                                    fontSize: 20,
                                    fontWeight: FontWeight.bold),
                              ),
                              const SizedBox(width: 5),
                              IconButton(
                                  // splashRadius: 1,
                                  iconSize: 15,
                                  icon: const Icon(Icons.thumb_up_rounded),
                                  color: Colors.black,
                                  onPressed: () {}),
                            ],
                          ),
                          const Text(
                            "Description",
                            style: TextStyle(
                                color: Colors.black,
                                fontSize: 15,
                                fontWeight: FontWeight.normal),
                          ),
                          const SizedBox(height: 10),
                          const Row(
                            mainAxisAlignment: MainAxisAlignment.start,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Text(
                                "Asked   1 year, 5 months ago",
                                style: TextStyle(
                                    color: Colors.black,
                                    fontSize: 10,
                                    fontWeight: FontWeight.normal),
                              ),
                              SizedBox(width: 10),
                              Text(
                                "Viewed   25 times",
                                style: TextStyle(
                                    color: Colors.black,
                                    fontSize: 10,
                                    fontWeight: FontWeight.normal),
                              ),
                            ],
                          ),
                        ]),
                  ),
                  const SizedBox(height: 10),
                  Container(
                      margin: const EdgeInsets.all(1.0),
                      padding: const EdgeInsets.all(16.0),
                      decoration: BoxDecoration(
                          border: Border.all(color: Colors.black)),
                      child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                CircleAvatar(
                                  backgroundColor: Colors.transparent,
                                  radius: 15.0,
                                  child: IconButton(
                                    onPressed: () {
                                      Navigator.of(context)
                                          .push(MaterialPageRoute(
                                        builder: (context) =>
                                            const OtherProfileScreen(),
                                      ));
                                    },
                                    icon: Transform.scale(
                                      scale: 2,
                                      child: Image.asset(
                                        image,
                                        height: 100,
                                        width: 100,
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 5),
                                const Text(
                                  "[Name]",
                                  style: TextStyle(
                                      color: Colors.black,
                                      fontSize: 15,
                                      fontWeight: FontWeight.bold),
                                ),
                              ],
                            ),
                            const SizedBox(height: 5),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: <Widget>[
                                const Flexible(
                                  child: Text(
                                    "To treat parkisonsons you should try to stimulate levodopa. Nerve cells use levodopa to make dopamine to replenish the brain's dwindling supply.",
                                    style: TextStyle(
                                        color: Colors.black,
                                        fontSize: 13,
                                        fontWeight: FontWeight.normal),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      IconButton(
                                          iconSize: 20,
                                          icon: const Icon(Icons.add),
                                          //When the add icon is pressed, the user can add comments to the original response
                                          color: Colors.black,
                                          onPressed: () {}),
                                      const SizedBox(height: 5),
                                      IconButton(
                                          iconSize: 20,
                                          icon: const Icon(Icons.arrow_forward),
                                          color: Colors.black,
                                          onPressed: () {}),
                                    ]),
                              ],
                            ),
                          ])),
                ]),
          ),
        ),
        floatingActionButton: Ink(
            decoration: const ShapeDecoration(
              color: Colors.lightBlue,
              shape: CircleBorder(),
            ),
            child: IconButton(
                iconSize: 25,
                icon: const Icon(Icons.add),
                color: Colors.white,
                //When this add button is pressed, the user can add a new response to the topic.
                onPressed: () async {})));
  }
}
