import 'package:flutter/material.dart';
import '../Firebase/firebase_cloud.dart';

import '../singleton.dart';

class EditScheduleScreen extends StatefulWidget {
  const EditScheduleScreen({super.key});

  @override
  State<EditScheduleScreen> createState() => _EditScheduleScreenState();
}

class _EditScheduleScreenState extends State<EditScheduleScreen> {
  final singleton = Singleton();
  String name = '';
  String details = '';
  String day = "Monday";

  List<String> dayOfTheWeek = [
    "Monday",
    "Tuesday",
    "Wednesday",
    "Thursday",
    "Friday",
    "Saturday",
    "Sunday"
  ];

  List<String> daysChosen = [];
  List<bool> boolDay = [];

  String chosendays() {
    String word = "Every";
    if (daysChosen.length == 1) {
      return "$word ${daysChosen[0]}.";
    }

    if (daysChosen.length == 2) {
      return "$word ${daysChosen[0]} and ${daysChosen[1]}.";
    }

    if (daysChosen.length == 7) {
      return "Everyday";
    }

    if (daysChosen.length > 2) {
      for (int i = 0; i < daysChosen.length - 1; i++) {
        word = "$word ${daysChosen[i]},";
      }

      word += " and ${daysChosen[daysChosen.length - 1]}.";

      return word;
    }

    return "N/A";
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
              Navigator.popAndPushNamed(context, '/scheduleScreen');
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
                    "Medication",
                    style:
                        TextStyle(fontSize: 35.0, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 20),
                  TextField(
                    decoration: const InputDecoration(
                      labelText: 'Name',

                      // You can customize other properties like labelStyle, hintStyle, etc.
                    ),
                    onChanged: (text) {
                      name = text;
                    },
                  ),
                  const SizedBox(height: 20),
                  TextField(
                    decoration: const InputDecoration(
                      labelText: 'Details',

                      // You can customize other properties like labelStyle, hintStyle, etc.
                    ),
                    onChanged: (text) {
                      details = text;
                    },
                  ),
                  const SizedBox(height: 20),
                  Container(
                      margin: const EdgeInsets.all(1.0),
                      padding: const EdgeInsets.all(16.0),
                      decoration: BoxDecoration(
                          border: Border.all(color: Colors.black)),
                      child: Text(
                        chosendays(),
                        style: const TextStyle(
                            fontSize: 25.0, fontWeight: FontWeight.bold),
                      )),
                  Expanded(
                      child: SizedBox(
                          height: 200,
                          child: ListView.builder(
                            itemCount: dayOfTheWeek.length,
                            itemBuilder: (BuildContext context, int index) {
                              return Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  ElevatedButton(
                                    onPressed: () async {
                                      setState(() {
                                        if (!daysChosen
                                            .contains(dayOfTheWeek[index])) {
                                          daysChosen.add(dayOfTheWeek[index]);
                                        } else {
                                          daysChosen.removeAt(daysChosen
                                              .indexOf(dayOfTheWeek[index]));
                                        }
                                      });
                                    },
                                    child: Text(
                                      dayOfTheWeek[index],
                                      style: TextStyle(
                                          color: singleton.themeColor[
                                              singleton.colorMode][20],
                                          fontSize: 25,
                                          fontWeight: FontWeight.bold),
                                    ),
                                  )
                                ],
                              );
                            },
                          ))),
                  Center(
                      child: ElevatedButton(
                    onPressed: () {
                      singleton.addScheduleList(name, details, chosendays());
                      FirebaseCloud()
                          .createSchedule(name, details, chosendays());
                      showDialog<String>(
                          context: context,
                          builder: (BuildContext c) => AlertDialog(
                                content: const Text('Submitted!'),
                                actions: <Widget>[
                                  TextButton(
                                    onPressed: () async {
                                      Navigator.pop(c, 'Ok');
                                      Navigator.pushNamed(
                                          context, '/editScheduleScreen');
                                    },
                                    child: const Text('Ok'),
                                  ),
                                ],
                              ));
                    },
                    child: Text(
                      'Submit',
                      style: TextStyle(
                          color: singleton.themeColor[singleton.colorMode][13],
                          fontSize: 25,
                          fontWeight: FontWeight.bold),
                    ),
                  )),
                ])));
  }
}
