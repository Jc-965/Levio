import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'barchart.dart';
import 'singleton.dart';

class LineChartSample1 extends StatefulWidget {
  const LineChartSample1({super.key});

  @override
  State<StatefulWidget> createState() => LineChartSample1State();
}

class LineChartSample1State extends State<LineChartSample1> {
  late List<FlSpot> pointList;
  double lineBarY = 0;
  String chosenTime = "Month";
  final singleton = Singleton();
  late int symptomLength;
  List<String> time = ["Month", "Year"];
  late List<List<String>> log;

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

  Map<String, double> symptomsPerMonth = {
    'January': 0,
    'February': 0,
    'March': 0,
    'April': 0,
    'May': 0,
    'June': 0,
    'July': 0,
    'August': 0,
    'September': 0,
    'October': 0,
    'November': 0,
    'December': 0
  };

  List<String> year = ['2023', '2024', '2025', '2026', '2027', '2028'];

  void incrementMonth(m) {
    symptomsPerMonth[m] = symptomsPerMonth[m]! + 1;
  }

  List<FlSpot> createPoints() {
    double t = 0;
    List<FlSpot> points = [];

    for (int i = 0; i < log.length; i++) {
      if (chosenTime == "Month") {
        t = (month.indexOf(log[i][0].split(' ')[2])) / 1;
      } else {
        t = (year.indexOf(log[i][0].split(' ')[3])) / 1;
      }

      switch (t.floor()) {
        case 0:
          incrementMonth("January");
          break;
        case 1:
          incrementMonth("February");
          break;
        case 2:
          incrementMonth("March");
          break;
        case 3:
          incrementMonth("April");
          break;
        case 4:
          incrementMonth("May");
          break;
        case 5:
          incrementMonth("June");
          break;
        case 6:
          incrementMonth("July");
          break;
        case 7:
          incrementMonth("August");
          break;
        case 8:
          incrementMonth("September");
          break;
        case 9:
          incrementMonth("October");
          break;
        case 10:
          incrementMonth("November");
          break;
        case 11:
          incrementMonth("December");
          break;
      }

      //lineBarY = log.length / 1;
    }

    for (int i = 0; i < 12; i++) {
      points.add(FlSpot(i / 1, symptomsPerMonth[month[i]]!));
      if (symptomsPerMonth[month[i]]! > lineBarY) {
        lineBarY = symptomsPerMonth[month[i]]!;
      }
    }
    return points;
  }

  @override
  void initState() {
    super.initState();
    log = singleton.log; // Doing nothing
    pointList = createPoints();
    symptomLength = pointList.length;
  }

  LineChartData get sampleData1 => LineChartData(
        lineTouchData: lineTouchData1,
        gridData: gridData,
        titlesData: titlesData1,
        borderData: borderData,
        lineBarsData: lineBarsData1,
        minX: 0,
        maxX: 12,
        maxY: lineBarY + 1,
        minY: 0,
      );

  LineTouchData get lineTouchData1 => const LineTouchData(
        handleBuiltInTouches: true,
      );

  FlTitlesData get titlesData1 => FlTitlesData(
        bottomTitles: AxisTitles(
          sideTitles: bottomTitles,
        ),
        rightTitles: const AxisTitles(
          sideTitles: SideTitles(showTitles: false),
        ),
        topTitles: const AxisTitles(
          sideTitles: SideTitles(showTitles: false),
        ),
        leftTitles: AxisTitles(
          sideTitles: leftTitles(),
        ),
      );

  List<LineChartBarData> get lineBarsData1 => [
        lineChartBarData1_3,
      ];

  FlTitlesData get titlesData2 => FlTitlesData(
        bottomTitles: AxisTitles(
          sideTitles: bottomTitles,
        ),
        rightTitles: const AxisTitles(
          sideTitles: SideTitles(showTitles: false),
        ),
        topTitles: const AxisTitles(
          sideTitles: SideTitles(showTitles: false),
        ),
        leftTitles: AxisTitles(
          sideTitles: leftTitles(),
        ),
      );

  List<LineChartBarData> get lineBarsData2 => [];

  Widget leftTitleWidgets(double value, TitleMeta meta) {
    TextStyle style = const TextStyle(
      fontWeight: FontWeight.bold,
      fontSize: 14,
    );
    String text = value.toString();

    return Text(text, style: style, textAlign: TextAlign.center);
  }

  SideTitles leftTitles() => SideTitles(
        getTitlesWidget: leftTitleWidgets,
        showTitles: true,
        interval: 1,
        reservedSize: 40,
      );

  Widget bottomTitleWidgets(double value, TitleMeta meta) {
    TextStyle style = const TextStyle(
      fontWeight: FontWeight.bold,
      fontSize: 14,
    );
    late Widget text;
    if (chosenTime == "Month") {
      switch (value.toInt()) {
        case 0:
          text = Text('Jan', style: style);
          break;
        case 3:
          text = Text('Mar', style: style);
          break;
        case 6:
          text = Text('Jun', style: style);
          break;
        case 9:
          text = Text('Sep', style: style);
          break;
        case 12:
          text = Text('Dec', style: style);
          break;
        default:
          text = const Text('');
          break;
      }
    } else {
      switch (value.toInt()) {
        case 1:
          text = Text('2023', style: style);
          break;
        case 3:
          text = Text('2024', style: style);
          break;
        case 5:
          text = Text('2025', style: style);
          break;
        case 7:
          text = Text('2026', style: style);
          break;
        case 9:
          text = Text('2027', style: style);
          break;
        case 11:
          text = Text('2028', style: style);
          break;
        default:
          text = const Text('');
          break;
      }
    }

    return SideTitleWidget(
      axisSide: meta.axisSide,
      space: 10,
      child: text,
    );
  }

  SideTitles get bottomTitles => SideTitles(
        showTitles: true,
        reservedSize: 32,
        interval: 1,
        getTitlesWidget: bottomTitleWidgets,
      );

  FlGridData get gridData => const FlGridData(show: false);

  FlBorderData get borderData => FlBorderData(
        show: true,
        border: Border(
          bottom: BorderSide(
              color: singleton.themeColor[singleton.colorMode][8], width: 4),
          left: BorderSide(
              color: singleton.themeColor[singleton.colorMode][8], width: 4),
          right: const BorderSide(color: Colors.transparent),
          top: const BorderSide(color: Colors.transparent),
        ),
      );

  //Current chart being used
  LineChartBarData get lineChartBarData1_3 => LineChartBarData(
      isCurved: true,
      color: singleton.themeColor[singleton.colorMode][7],
      barWidth: 8,
      isStrokeCapRound: true,
      dotData: const FlDotData(show: false),
      belowBarData: BarAreaData(show: false),
      spots: pointList);

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          margin: const EdgeInsets.all(1.0),
          padding: const EdgeInsets.all(8.0),
          child: AspectRatio(
            aspectRatio: 1.23,
            child: Stack(
              children: <Widget>[
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Symptoms',
                          style: TextStyle(
                            color: singleton.themeColor[singleton.colorMode][6],
                            fontSize: 32,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 2,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        DropdownButton<String>(
                          value:
                              chosenTime, // Initially selected item (can be null)
                          onChanged: (String? newValue) {
                            setState(() {
                              chosenTime = newValue!;
                            });
                          },
                          items:
                              time.map<DropdownMenuItem<String>>((String item) {
                            return DropdownMenuItem<String>(
                              value: item,
                              child: Text(
                                item,
                                style: TextStyle(
                                    color: singleton
                                        .themeColor[singleton.colorMode][1]),
                              ),
                            );
                          }).toList(),
                        ),
                      ],
                    ),
                    const SizedBox(
                      height: 37,
                    ),
                    Expanded(
                      child: Padding(
                          padding: const EdgeInsets.only(right: 16, left: 6),
                          child: LineChart(
                            sampleData1,
                          )),
                    ),
                    const SizedBox(
                      height: 10,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        Container(
            margin: const EdgeInsets.all(1.0),
            padding: const EdgeInsets.all(8.0),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Medication',
                      style: TextStyle(
                        color: singleton.themeColor[singleton.colorMode][12],
                        fontSize: 32,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 2,
                      ),
                      textAlign: TextAlign.start,
                    ),
                    const SizedBox(width: 0),
                  ],
                ),
                const SizedBox(width: 20),
                const BarChartSample3(),
              ],
            ))
      ],
    );
  }
}
