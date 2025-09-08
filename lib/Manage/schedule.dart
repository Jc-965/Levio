import 'package:flutter/material.dart';

import '../Firebase/firebase_cloud.dart';
import '../singleton.dart';

class ScheduleScreen extends StatefulWidget {
  const ScheduleScreen({super.key});

  @override
  State<ScheduleScreen> createState() => _ScheduleScreenState();
}

class _ScheduleScreenState extends State<ScheduleScreen> {
  final singleton = Singleton();
  double textLogSize = 20;

  String name(int index) {
    String temp = "Medication Name: ";
    return temp + singleton.schedule[index][0];
  }

  String detail(int index) {
    String temp = "Details: ";
    return temp + singleton.schedule[index][1];
  }

  String time(int index) {
    String temp = "Time to take medicine: ";
    return temp + singleton.schedule[index][2];
  }

  @override
  void initState() {
    super.initState();
    FirebaseCloud().idList(false);
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
            // Pop the current screen off the navigation stack
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
                Expanded(
                  child: SizedBox(
                    height: 200,
                    child: singleton.schedule
                            .isEmpty // Check if the data source is empty
                        ? const Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  "Currently No Medications Recorded",
                                  style: TextStyle(
                                      fontSize: 20,
                                      fontWeight: FontWeight.bold),
                                ),
                                SizedBox(height: 50),
                              ],
                            ),
                          )
                        : ListView.builder(
                            itemCount: singleton.schedule.length,
                            itemBuilder: (BuildContext context, int index) {
                              Widget scheduleColumn = Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      name(index),
                                      style: TextStyle(
                                          fontSize: textLogSize,
                                          fontWeight: FontWeight.bold),
                                    ),
                                    Text(
                                      detail(index),
                                      style: TextStyle(
                                          fontSize: textLogSize,
                                          fontWeight: FontWeight.bold),
                                    ),
                                    Text(
                                      time(index),
                                      style: TextStyle(
                                          fontSize: textLogSize,
                                          fontWeight: FontWeight.bold),
                                    ),
                                  ]);
                              return Container(
                                  margin: const EdgeInsets.all(10.0),
                                  padding: const EdgeInsets.all(16.0),
                                  decoration: BoxDecoration(
                                      border: Border.all(
                                          color: singleton.themeColor[
                                              singleton.colorMode][1])),
                                  child: ListTile(
                                    title: scheduleColumn,
                                    onTap: () {
                                      showDialog<String>(
                                          context: context,
                                          builder: (BuildContext c) =>
                                              AlertDialog(
                                                content: scheduleColumn,
                                                actions: <Widget>[
                                                  TextButton(
                                                    onPressed: () async {
                                                      Navigator.pop(c, 'Ok');
                                                    },
                                                    child: Text(
                                                      'Ok',
                                                      style: TextStyle(
                                                          fontSize: 20,
                                                          color: singleton
                                                                  .themeColor[
                                                              singleton
                                                                  .colorMode][13]),
                                                    ),
                                                  ),
                                                  IconButton(
                                                    iconSize: 30,
                                                    icon: const Icon(
                                                      Icons
                                                          .delete_outline_rounded,
                                                      color: Colors.red,
                                                    ),
                                                    color: Colors.white,
                                                    onPressed: () {
                                                      singleton
                                                          .deleteEntireList(
                                                              index,
                                                              "schedules");
                                                      Navigator.pop(c, 'Ok');
                                                      Navigator.pushNamed(
                                                          context,
                                                          '/scheduleScreen');
                                                    },
                                                  ),
                                                ],
                                              ));
                                    },
                                  ));
                            },
                          ),
                  ),
                ),
              ])),
      floatingActionButton: Ink(
        decoration: const ShapeDecoration(
          color: Colors.lightBlue,
          shape: CircleBorder(),
        ),
        child: IconButton(
          iconSize: 35,
          icon: const Icon(Icons.edit),
          color: Colors.white,
          onPressed: () {
            Navigator.popAndPushNamed(context, '/editScheduleScreen');
          },
        ),
      ),
    );
  }
}
