import 'package:flutter/material.dart';
import 'package:parkinson/Firebase/firebase_cloud.dart';

import '../singleton.dart';

class LogScreen extends StatefulWidget {
  const LogScreen({super.key});

  @override
  State<LogScreen> createState() => _LogScreenState();
}

class _LogScreenState extends State<LogScreen> {
  final singleton = Singleton();
  double textLogSize = 20;
  late List<List<String>> log;

  String time(int index) {
    String temp = "Time: ";
    return temp + log[index][0];
  }

  String symptom(int index) {
    String temp = "Symptom: ";
    return temp + log[index][1];
  }

  String severity(int index) {
    String temp = "Severity: ";
    return temp + log[index][2];
  }

  // ["5:30, 23 June 2023", "...", "..."],
  // ["4:24, 23 July 2024", "...", "..."],
  // ["7:54, 23 August 2025", "...", "..."],
  // ["9:12, 23 August 2026", "...", "..."],
  // ["12:36, 23 September 2027", "...", "..."],
  // ["10:09, 23 October 2028", "...", "..."],
  Map<String, String> monthMap = {
    'January': "01",
    'February': "02",
    'March': "03",
    'April': "04",
    'May': "05",
    'June': "06",
    'July': "07",
    'August': "08",
    'September': "09",
    'October': "10",
    'November': "11",
    'December': "12"
  };

  void sortTime() {
    //'1969-07-20 20:18:04Z'
    //time[0] = 10:09,
    // ["10:09, 23 October 2028", "...", "..."],
    List<List<String>> dTime = [];
    for (int i = 0; i < log.length; i++) {
      List<String> time = log[i][0].split(' ');
      dTime.add([
        "${time[3]}-${monthMap[time[2]]}-${time[1]} ${time[0].substring(0, time[0].length - 1)}:00",
        '$i'
      ]);
    }
    dTime.sort((a, b) {
      DateTime dateTimeA = DateTime.parse(a[0]);
      DateTime dateTimeB = DateTime.parse(b[0]);
      return dateTimeA.compareTo(dateTimeB);
    });

    sortLog(dTime.reversed.toList());
  }

  void sortLog(t) {
    List<List<String>> tempList = [];
    tempList.addAll(log);
    setState(() {
      log.clear();
      for (int i = 0; i < tempList.length; i++) {
        log.add(tempList[int.parse(t[i][1])]);
      }
    });
  }

  @override
  void initState() {
    super.initState();
    FirebaseCloud().idList(true);
    log = singleton.log;
    sortTime();
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
                    child: singleton
                            .log.isEmpty // Check if the data source is empty
                        ? const Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  "Currently No Symptoms Recorded",
                                  style: TextStyle(
                                      fontSize: 20,
                                      fontWeight: FontWeight.bold),
                                ),
                                SizedBox(height: 50),
                              ],
                            ),
                          )
                        : ListView.builder(
                            itemCount: singleton.log.length,
                            itemBuilder: (BuildContext context, int index) {
                              Widget logColumn = Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      time(index),
                                      style: TextStyle(
                                          fontSize: textLogSize,
                                          fontWeight: FontWeight.bold),
                                    ),
                                    Text(
                                      severity(index),
                                      style: TextStyle(
                                          fontSize: textLogSize,
                                          fontWeight: FontWeight.bold),
                                    ),
                                    Text(
                                      symptom(index),
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
                                    title: logColumn,
                                    onTap: () {
                                      showDialog<String>(
                                          context: context,
                                          builder: (BuildContext c) =>
                                              AlertDialog(
                                                content: logColumn,
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
                                                              index, "logs");
                                                      Navigator.pop(c, 'Ok');
                                                      Navigator.pushNamed(
                                                          context,
                                                          '/logScreen');
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
            Navigator.popAndPushNamed(context, '/editLogScreen');
          },
        ),
      ),
    );
  }
}
