import 'package:flutter/material.dart';
import 'package:parkinson/Firebase/firebase_cloud.dart';
import 'package:shared_preferences/shared_preferences.dart';

class Singleton extends ChangeNotifier {
  static final Singleton _instance = Singleton._internal();
  final Future<SharedPreferences> _prefs = SharedPreferences.getInstance();

  // passes the instantiation to the _instance object
  factory Singleton() => _instance;

  void notifyListenersSafe() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      notifyListenersSafe();
    });
  }

  // initialize our variables
  Singleton._internal();
  bool firstTime = false;
  int page = 0;
  List<List<String>> log = [
    // ["5:30, 23 June 2023", "...", "..."],
    // ["5:30, 23 July 2024", "...", "..."],
    // ["5:30, 23 August 2025", "...", "..."],
    // ["5:30, 23 August 2026", "...", "..."],
    // ["5:30, 23 September 2027", "...", "..."],
    // ["5:30, 23 October 2028", "...", "..."],
  ];
  List<List<String>> schedule = [
    // ["Xeltorin", "...", "Everyday"],
    // ["Provictil", "...", "Every Tuesday"],
    // ["Lanizapine", "...", "Every Monday and Wednesday"],
    // ["Daprimol", "...", "Every Friday, Saturday, and Sunday"],
    // ["Selextam", "...", "Every Wednesday"],
    // ["Fenitral", "...", "Every Monday and Thursday"],
    // ["Zolafine", "...", "Every Monday, Wednesday, Friday, and Sunday"],
  ];

  Map<String, List<String>> speeches = {
    // "url": ["Name", "Description"],
    "https://www2.cs.uic.edu/~i101/SoundFiles/BabyElephantWalk60.wav": [
      "Test Audio 1",
      "This is the first test audio"
    ],
    "https://www2.cs.uic.edu/~i101/SoundFiles/PinkPanther30.wav": [
      "Test Audio 2",
      "This is the second test audio"
    ]
  };

  Map<String, List<String>> exercises = {
    // "url": ["Name", "Description", "Thumbnail image url"],
    "AM3m9IPjkNE": [
      "Test Video 1",
      "This is the first test video",
    ],
    "_mKAqrA3weA": [
      "Test Video 2",
      "This is the second test video",
    ],
    "JxS5E-kZc2s": [
      "Test Video 3",
      "This is the third test video",
    ]
  };

  String currentURL = "";
  String name = "[Name]";
  String email = "[Email]";
  String image = "images/711128.png";
  int postNum = 0;
  int exerNum = 0;

  void setFirstTime(b) {
    firstTime = b;
    notifyListenersSafe();
  }

  void setUID(String uid) async {
    final SharedPreferences prefs = await _prefs;
    await prefs.setString('userID', uid);
  }

  Future<String> getUID() async {
    final SharedPreferences prefs = await _prefs;
    return prefs.getString('userID')!;
  }

  void setTheme(bool t) async {
    final SharedPreferences prefs = await _prefs;
    await prefs.setBool('theme', t);
  }

  Future<bool> getTheme() async {
    final SharedPreferences prefs = await _prefs;
    return prefs.getBool('theme')!;
  }

  void setSound(double s) async {
    final SharedPreferences prefs = await _prefs;
    await prefs.setDouble('sound', s);
  }

  Future<double> getSound() async {
    final SharedPreferences prefs = await _prefs;
    return prefs.getDouble('sound')!;
  }

  void setPage(int n) {
    page = n;
    notifyListenersSafe();
  }

  void setName(String n) {
    name = n;
    notifyListenersSafe();
  }

  void setImage(String i) {
    image = i;
    notifyListenersSafe();
  }

  void setEmail(String e) {
    email = e;
    notifyListenersSafe();
  }

  void setPostNum(int p) {
    postNum = p;
    notifyListenersSafe();
  }

  void setExerNum(int e) {
    exerNum = e;
    notifyListenersSafe();
  }

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

    sortLog(dTime.toList());
    notifyListenersSafe();
  }

  void sortLog(t) {
    List<List<String>> tempList = [];
    tempList.addAll(log);
    log.clear();
    for (int i = 0; i < tempList.length; i++) {
      log.add(tempList[int.parse(t[i][1])]);
    }
    notifyListenersSafe();
  }

  void addLogList(
    String time,
    String symptom,
    String severity,
  ) {
    List<String> logList = [time, symptom, severity];
    log.add(logList);
    sortTime();
    notifyListenersSafe();
  }

  void addScheduleList(String name, String details, String days) {
    List<String> scheduleList = [name, details, days];
    schedule.add(scheduleList);
    notifyListenersSafe();
  }

  //Receive list of IDs from user's document
  //Gets log/schedule documnt using the ID

  late List<String> logIDs;

  void setLogIDs(List<String> l) {
    log.clear();
    for (int i = 0; i < l.length; i++) {
      FirebaseCloud().getLogs(l[i]);
    }
    logIDs = l;
    notifyListenersSafe();
  }

  late List<String> scheduleIDs;

  void setScheduleIDs(List<String> s) {
    schedule.clear();
    for (int i = 0; i < s.length; i++) {
      FirebaseCloud().getSchedules(s[i]);
    }
    scheduleIDs = s;
    notifyListenersSafe();
  }

  List<String> month = [
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
  ];

  List<String> year = ['2023', '2024', '2025', '2026', '2027', '2028'];

  Map<String, double> medsPerDay = {
    'Monday': 0,
    'Tuesday': 0,
    'Wednesday': 0,
    'Thursday': 0,
    'Friday': 0,
    'Saturday': 0,
    'Sunday': 0
  };

  Set<String> medicationNames = {};

  late double barY;

  void calcBarY() {
    List<double> values = [];
    values = medsPerDay.values.toList();
    values.sort();
    barY = values[medsPerDay.length - 1] + 1;
  }

  void calcMeds() {
    for (int i = 0; i < schedule.length; i++) {
      if (!medicationNames.contains(schedule[i][0])) {
        if (schedule[i][2] == "Everyday") {
          for (var key in medsPerDay.keys) {
            final day = <String, double>{key: medsPerDay[key]! + 1};
            medsPerDay.addEntries(day.entries);
          }
        } else {
          for (var key in medsPerDay.keys) {
            if (schedule[i][2].contains(key)) {
              final day = <String, double>{key: medsPerDay[key]! + 1};
              medsPerDay.addEntries(day.entries);
            }
          }
        }
        medicationNames.add(schedule[i][0]);
      }
    }
    calcBarY();
  }

  late int colorMode;

  void switchColorTheme(bool b) {
    if (b) {
      colorMode = 1;
    } else {
      colorMode = 0;
    }
    setTheme(b);
    notifyListenersSafe();
  }

  List<List<Color>> themeColor = const [
    //Light mode
    [
      Color.fromARGB(255, 248, 246, 218), //background 0
      Color.fromARGB(200, 33, 17, 3), //normal text 1
      Color.fromARGB(255, 34, 116, 165), //floating button 2
      Color.fromARGB(255, 34, 116, 165), //button 3
      Color.fromARGB(230, 33, 17, 3), //subtitle 4
      Color.fromARGB(255, 33, 17, 3), //title 5
      Color.fromARGB(245, 33, 17, 3), //Line Graph title 6
      Color.fromARGB(255, 209, 96, 20), //Line Graph line 7
      Color.fromARGB(200, 33, 17, 3), //Line Graph axis 8
      Color.fromARGB(200, 33, 17, 3), //Line Graph tooltip text 9
      Color.fromARGB(108, 250, 248, 212), //Line Graph tool background 10
      Color.fromARGB(200, 33, 17, 3), //Line Graph axis border 11
      Color.fromARGB(245, 33, 17, 3), //Bar Graph title 12
      Color.fromARGB(255, 11, 110, 79), //Bar Graph bar 13
      Color.fromARGB(230, 33, 17, 3), //Bar Graph amount 14
      Color.fromARGB(230, 33, 17, 3), //Bar Graph day 15
      Color.fromARGB(255, 34, 116, 165), //Bar Graph gradient top 16
      Color.fromARGB(150, 34, 116, 165), //Bar Graph gradient bottom 17
      Color.fromARGB(230, 33, 17, 3), //Bar Graph axis 18
      Color.fromARGB(255, 11, 110, 79), //Navbar selected 19
      Color.fromARGB(255, 34, 116, 165), //Navbar unselected 20
      Color.fromARGB(255, 246, 243, 199), //Navbar background 21
      Color.fromARGB(255, 246, 243, 199), //Appbar background 22
      Color.fromARGB(230, 33, 17, 3), //Appbar text 23
      Color.fromARGB(230, 33, 17, 3), //Appbar icon 24
      Color.fromARGB(255, 205, 141, 85), //Audio bar 25
    ],
    //Dark mode
    [
      Color.fromARGB(255, 33, 17, 3), //background 0
      Color.fromARGB(255, 248, 246, 218), //normal text 1
      Color.fromARGB(255, 43, 158, 224), //floating button 2
      Color.fromARGB(255, 43, 158, 224), //button 3
      Color.fromARGB(255, 248, 246, 218), //subtitle 4
      Color.fromARGB(255, 248, 246, 218), //title 5
      Color.fromARGB(255, 248, 246, 218), //Line Graph title 6
      Color.fromARGB(255, 218, 100, 4), //Line Graph line 7
      Color.fromARGB(230, 216, 156, 104), //Line Graph axis 8
      Color.fromARGB(255, 248, 246, 218), //Line Graph tooltip text 9
      Color.fromARGB(108, 250, 248, 212), //Line Graph tool background 10
      Color.fromARGB(200, 33, 17, 3), //Line Graph axis border 11
      Color.fromARGB(255, 248, 246, 218), //Bar Graph title 12
      Color.fromARGB(255, 5, 183, 127), //Bar Graph bar 13
      Color.fromARGB(230, 248, 246, 218), //Bar Graph amount 14
      Color.fromARGB(230, 248, 246, 218), //Bar Graph day 15
      Color.fromARGB(255, 156, 219, 253), //Bar Graph gradient top 16
      Color.fromARGB(255, 87, 159, 200), //Bar Graph gradient bottom 17
      Color.fromARGB(230, 216, 156, 104), //Bar Graph axis 18
      Color.fromARGB(255, 42, 223, 164), //Navbar selected 19
      Color.fromARGB(255, 87, 179, 232), //Navbar unselected 20
      Color.fromARGB(255, 19, 9, 2), //Navbar background 21
      Color.fromARGB(255, 19, 9, 2), //Appbar background 22
      Color.fromARGB(255, 248, 246, 218), //Appbar text 23
      Color.fromARGB(255, 248, 246, 218), //Appbar icon 24
      Color.fromARGB(230, 216, 156, 104), //Audio bar 25
    ]
  ];

  void setCurrentUrl(url) {
    currentURL = url;
    notifyListenersSafe();
  }

  void deleteList(String listName, List<String> list, index) {
    String docID = list[index];
    FirebaseCloud().deleteDocument(listName, docID);
  }

  void deleteEntireList(int index, String listName) {
    if (listName == "logs") {
      log.removeAt(index);
      FirebaseCloud().deleteCloudList(index, listName);
      deleteList(listName, logIDs, index);
    }

    if (listName == "schedules") {
      schedule.removeAt(index);
      FirebaseCloud().deleteCloudList(index, listName);
      deleteList(listName, scheduleIDs, index);
    }
    notifyListenersSafe();
  }

  Future deleteAccount() async {
    int logLength = log.length;
    int scheduleLength = schedule.length;

    for (int i = 0; i < logLength; i++) {
      deleteEntireList(i, "logs");
    }

    for (int i = 0; i < scheduleLength; i++) {
      deleteEntireList(i, "schedules");
    }

    FirebaseCloud().deleteDocument("users", await getUID());

    await SharedPreferences.getInstance().then((prefs) async {
      await prefs.clear();
    });

    notifyListenersSafe();
  }
}
