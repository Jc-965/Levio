import 'package:flutter/material.dart';
import 'package:parkinson/Firebase/firebase_cloud.dart';

import '../singleton.dart';

class EditLogScreen extends StatefulWidget {
  const EditLogScreen({super.key});

  @override
  State<EditLogScreen> createState() => _EditLogScreenState();
}

class _EditLogScreenState extends State<EditLogScreen> {
  final singleton = Singleton();
  String severity = '';
  String symptoms = '';
  String month = 'January';
  String day = '01';
  String year = '2024';
  String hour = '01';
  String minute = '00';

  List<String> hours = [
    '01',
    '02',
    '03',
    '04',
    '05',
    '06',
    '07',
    '08',
    '09',
    '10',
    '11',
    '12',
    '13',
    '14',
    '15',
    '16',
    '17',
    '18',
    '19',
    '20',
    '21',
    '22',
    '23',
  ];

  List<String> minutes = [
    '00',
    '01',
    '02',
    '03',
    '04',
    '05',
    '06',
    '07',
    '08',
    '09',
    '10',
    '11',
    '12',
    '13',
    '14',
    '15',
    '16',
    '17',
    '18',
    '19',
    '20',
    '21',
    '22',
    '23',
    '24',
    '25',
    '26',
    '27',
    '28',
    '29',
    '30',
    '31',
    '32',
    '33',
    '34',
    '35',
    '36',
    '37',
    '38',
    '39',
    '40',
    '40',
    '41',
    '42',
    '43',
    '44',
    '45',
    '46',
    '47',
    '48',
    '49',
    '50',
    '51',
    '52',
    '53',
    '54',
    '55',
    '56',
    '57',
    '58',
    '59',
  ];
  List<String> days = [
    '01',
    '02',
    '03',
    '04',
    '05',
    '06',
    '07',
    '08',
    '09',
    '10',
    '11',
    '12',
    '13',
    '14',
    '15',
    '16',
    '17',
    '18',
    '19',
    '20',
    '21',
    '22',
    '23',
    '24',
    '25',
    '26',
    '27',
    '28',
    '29',
    '30',
    '31'
  ];

  List<List<String>> date = [
    [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December'
    ],
    [
      '01',
      '02',
      '03',
      '04',
      '05',
      '06',
      '07',
      '08',
      '09',
      '10',
      '11',
      '12',
      '13',
      '14',
      '15',
      '16',
      '17',
      '18',
      '19',
      '20',
      '21',
      '22',
      '23',
      '24',
      '25',
      '26',
      '27',
      '28',
      '29',
      '30',
      '31'
    ],
    [
      '2024',
      '2025',
      '2026',
      '2027',
      '2028',
      '2029',
      '2030',
      '2031',
      '2032',
      '2033'
    ]
  ];

  List<List<String>> symptomLog = [];

  void calcDate() {
    int d = date[1].length;

    if (month == 'February' &&
        (year == '2024' || year == '2028' || year == '2032')) {
      d = 29;
    } else if (month == 'February') {
      d = 28;
    } else if (month == 'April' ||
        month == 'June' ||
        month == 'September' ||
        month == 'November') {
      d = 30;
    }

    setState(() {
      days.clear();
      for (int i = 0; i < d; i++) {
        days.add(date[1][i]);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(
              Icons.arrow_back,
            ),
            onPressed: () async {
              Navigator.popAndPushNamed(context, '/logScreen');
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
                    const Text(
                      "Symptom Details",
                      style: TextStyle(
                          fontSize: 35.0, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 20),
                    TextField(
                      decoration: const InputDecoration(
                        labelText: 'Severity',
                        // You can customize other properties like labelStyle, hintStyle, etc.
                      ),
                      onChanged: (text) {
                        severity = text;
                      },
                    ),
                    const SizedBox(height: 20),
                    TextField(
                      decoration: const InputDecoration(
                        labelText: 'Symptom',
                        // You can customize other properties like labelStyle, hintStyle, etc.
                      ),
                      onChanged: (text) {
                        symptoms = text;
                      },
                    ),
                    const SizedBox(width: 20),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        DropdownButton<String>(
                          value: month, // Initially selected item (can be null)
                          onChanged: (String? newValue) {
                            setState(() {
                              month = newValue!; // Update the selected item
                            });
                            calcDate();
                          },
                          items: date[0]
                              .map<DropdownMenuItem<String>>((String item) {
                            return DropdownMenuItem<String>(
                              value: item,
                              child: Text(
                                item,
                              ),
                            );
                          }).toList(),
                        ),
                        const SizedBox(width: 20),
                        DropdownButton<String>(
                          value: day, // Initially selected item (can be null)
                          onChanged: (String? newValue) {
                            setState(() {
                              day = newValue!; // Update the selected item
                            });
                          },
                          items:
                              days.map<DropdownMenuItem<String>>((String item) {
                            return DropdownMenuItem<String>(
                              value: item,
                              child: Text(
                                item,
                              ),
                            );
                          }).toList(),
                        ),
                        const SizedBox(width: 20),
                        DropdownButton<String>(
                          value: year, // Initially selected item (can be null)
                          onChanged: (String? newValue) {
                            setState(() {
                              year = newValue!; // Update the selected item
                            });
                            calcDate();
                          },
                          items: date[2]
                              .map<DropdownMenuItem<String>>((String item) {
                            return DropdownMenuItem<String>(
                              value: item,
                              child: Text(
                                item,
                              ),
                            );
                          }).toList(),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          DropdownButton<String>(
                            value:
                                hour, // Initially selected item (can be null)
                            onChanged: (String? newValue) {
                              setState(() {
                                hour = newValue!; // Update the selected item
                              });
                            },
                            items: hours
                                .map<DropdownMenuItem<String>>((String item) {
                              return DropdownMenuItem<String>(
                                value: item,
                                child: Text(
                                  item,
                                ),
                              );
                            }).toList(),
                          ),
                          const SizedBox(width: 20),
                          DropdownButton<String>(
                            value:
                                minute, // Initially selected item (can be null)
                            onChanged: (String? newValue) {
                              setState(() {
                                minute = newValue!; // Update the selected item
                              });
                            },
                            items: minutes
                                .map<DropdownMenuItem<String>>((String item) {
                              return DropdownMenuItem<String>(
                                value: item,
                                child: Text(
                                  item,
                                ),
                              );
                            }).toList(),
                          ),
                        ]),
                    const SizedBox(height: 20),
                    Center(
                        child: ElevatedButton(
                      onPressed: () {
                        String time = "$hour:$minute, $day $month $year";
                        singleton.addLogList(time, symptoms, severity);
                        FirebaseCloud().createLogs(time, symptoms, severity);
                        showDialog<String>(
                            context: context,
                            builder: (BuildContext c) => AlertDialog(
                                  content: const Text('Submitted!'),
                                  actions: <Widget>[
                                    TextButton(
                                      onPressed: () async {
                                        Navigator.pop(c, 'Ok');
                                        Navigator.pushNamed(
                                            context, '/editLogScreen');
                                      },
                                      child: const Text(
                                        'Ok',
                                      ),
                                    ),
                                  ],
                                ));
                      },
                      child: Text(
                        'Submit',
                        style: TextStyle(
                            color: singleton.themeColor[singleton.colorMode]
                                [13],
                            fontSize: 25,
                            fontWeight: FontWeight.bold),
                      ),
                    )),
                  ]),
            )));
  }
}
