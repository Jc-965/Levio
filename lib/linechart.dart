import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'barchart.dart';
import 'singleton.dart';
import 'theme/app_theme.dart';
import 'widgets/modern_card.dart';
import 'utils/haptic_utils.dart';

class LineChartSample1 extends StatefulWidget {
  const LineChartSample1({super.key});

  @override
  State<StatefulWidget> createState() => LineChartSample1State();
}

class LineChartSample1State extends State<LineChartSample1>
    with SingleTickerProviderStateMixin {
  List<FlSpot> pointList = [];
  double lineBarY = 1;
  String chosenTime = "Month";
  final singleton = Singleton();
  final List<String> time = ["Month", "Year"];

  late AnimationController _animationController;
  late Animation<double> _animation;
  String _lastLogSignature = '';

  final List<String> month = [
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
    'December',
  ];

  final Map<String, int> monthToIndex = const {
    'January': 1,
    'February': 2,
    'March': 3,
    'April': 4,
    'May': 5,
    'June': 6,
    'July': 7,
    'August': 8,
    'September': 9,
    'October': 10,
    'November': 11,
    'December': 12,
  };

  List<String> get _yearWindow {
    final currentYear = DateTime.now().year;
    return List.generate(6, (index) => (currentYear - 5 + index).toString());
  }

  bool get _symptomChartHasData => singleton.log.isNotEmpty;

  bool get _medicationChartHasData => singleton.schedule.isNotEmpty;

  DateTime? _parseLogTimestamp(String value) {
    final parts = value.split(',');
    if (parts.length != 2) return null;

    final timePart = parts.first.trim().split(':');
    final datePart = parts.last.trim().split(' ');
    if (timePart.length != 2 || datePart.length != 3) return null;

    final hour = int.tryParse(timePart[0]);
    final minute = int.tryParse(timePart[1]);
    final day = int.tryParse(datePart[0]);
    final month = monthToIndex[datePart[1]];
    final year = int.tryParse(datePart[2]);

    if (hour == null ||
        minute == null ||
        day == null ||
        month == null ||
        year == null) {
      return null;
    }

    return DateTime(year, month, day, hour, minute);
  }

  void _rebuildChartData() {
    final logs = singleton.log;
    final buckets = chosenTime == "Month"
        ? List<double>.filled(12, 0)
        : List<double>.filled(_yearWindow.length, 0);

    if (chosenTime == "Month") {
      for (final entry in logs) {
        if (entry.isEmpty) continue;
        final date = _parseLogTimestamp(entry[0]);
        if (date == null) continue;
        buckets[date.month - 1] += 1;
      }
    } else {
      final years = _yearWindow;
      final startYear = int.parse(years.first);
      final endYear = int.parse(years.last);

      for (final entry in logs) {
        if (entry.isEmpty) continue;
        final date = _parseLogTimestamp(entry[0]);
        if (date == null || date.year < startYear || date.year > endYear) {
          continue;
        }
        buckets[date.year - startYear] += 1;
      }
    }

    pointList = List.generate(
      buckets.length,
      (index) => FlSpot(index.toDouble(), buckets[index]),
    );

    final maxValue = buckets.isEmpty
        ? 0.0
        : buckets.reduce(math.max).toDouble();
    lineBarY = maxValue > 0 ? maxValue : 1;
  }

  void _handleSingletonUpdate() {
    if (!mounted) return;
    final signature = _buildLogSignature();
    if (signature == _lastLogSignature) return;
    _lastLogSignature = signature;
    setState(_rebuildChartData);
  }

  String _buildLogSignature() {
    return singleton.healthDataVersion.toString();
  }

  @override
  void initState() {
    super.initState();
    _lastLogSignature = _buildLogSignature();
    _rebuildChartData();
    singleton.addListener(_handleSingletonUpdate);

    _animationController = AnimationController(
      duration: const Duration(milliseconds: 520),
      vsync: this,
    );
    _animation = CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeOutCubic,
    );
    _animationController.forward();
  }

  @override
  void dispose() {
    singleton.removeListener(_handleSingletonUpdate);
    _animationController.dispose();
    super.dispose();
  }

  LineChartData get sampleData1 => LineChartData(
    lineTouchData: lineTouchData1,
    gridData: gridData,
    titlesData: titlesData1,
    borderData: borderData,
    lineBarsData: lineBarsData1,
    minX: 0,
    maxX: chosenTime == "Month" ? 11 : (_yearWindow.length - 1).toDouble(),
    maxY: lineBarY + 1,
    minY: 0,
  );

  LineTouchData get lineTouchData1 {
    final colors = context.colors;
    return LineTouchData(
      handleBuiltInTouches: true,
      touchSpotThreshold: 24,
      getTouchedSpotIndicator: (barData, spotIndexes) {
        return spotIndexes.map((index) {
          return TouchedSpotIndicatorData(
            FlLine(
              color: barData.color!.withValues(alpha: 0.35),
              strokeWidth: 2,
              dashArray: [4, 4],
            ),
            FlDotData(
              show: true,
              getDotPainter: (spot, percent, bar, i) {
                return FlDotCirclePainter(
                  radius: 5,
                  color: bar.color!,
                  strokeWidth: 2.5,
                  strokeColor: colors.surface,
                );
              },
            ),
          );
        }).toList();
      },
      touchTooltipData: LineTouchTooltipData(
        getTooltipColor: (spot) => colors.surface,
        tooltipRoundedRadius: 12,
        tooltipPadding: const EdgeInsets.all(12),
        getTooltipItems: (touchedSpots) {
          return touchedSpots.map((spot) {
            return LineTooltipItem(
              '${spot.y.toInt()} symptoms',
              TextStyle(color: colors.primary, fontWeight: FontWeight.w600),
            );
          }).toList();
        },
      ),
    );
  }

  FlTitlesData get titlesData1 => FlTitlesData(
    bottomTitles: AxisTitles(sideTitles: bottomTitles),
    rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
    topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
    leftTitles: AxisTitles(sideTitles: leftTitles()),
  );

  List<LineChartBarData> get lineBarsData1 => [lineChartBarData1_3];

  Widget leftTitleWidgets(double value, TitleMeta meta) {
    final colors = context.colors;
    TextStyle style = TextStyle(
      fontWeight: FontWeight.w500,
      fontSize: 12,
      color: colors.textSecondary,
    );
    String text = value.toInt().toString();

    return Text(text, style: style, textAlign: TextAlign.center);
  }

  SideTitles leftTitles() => SideTitles(
    getTitlesWidget: leftTitleWidgets,
    showTitles: true,
    interval: 1,
    reservedSize: 32,
  );

  Widget bottomTitleWidgets(double value, TitleMeta meta) {
    final colors = context.colors;
    TextStyle style = TextStyle(
      fontWeight: FontWeight.w500,
      fontSize: 12,
      color: colors.textSecondary,
    );
    late Widget text;
    if (chosenTime == "Month") {
      switch (value.toInt()) {
        case 0:
          text = Text('Jan', style: style);
          break;
        case 3:
          text = Text('Apr', style: style);
          break;
        case 6:
          text = Text('Jul', style: style);
          break;
        case 9:
          text = Text('Oct', style: style);
          break;
        default:
          text = const Text('');
          break;
      }
    } else {
      switch (value.toInt()) {
        case 0:
          text = Text(_yearWindow[0], style: style);
          break;
        case 1:
          text = Text(_yearWindow[1], style: style);
          break;
        case 2:
          text = Text(_yearWindow[2], style: style);
          break;
        case 3:
          text = Text(_yearWindow[3], style: style);
          break;
        case 4:
          text = Text(_yearWindow[4], style: style);
          break;
        case 5:
          text = Text(_yearWindow[5], style: style);
          break;
        default:
          text = const Text('');
          break;
      }
    }

    return SideTitleWidget(axisSide: meta.axisSide, space: 10, child: text);
  }

  SideTitles get bottomTitles => SideTitles(
    showTitles: true,
    reservedSize: 32,
    interval: 1,
    getTitlesWidget: bottomTitleWidgets,
  );

  FlGridData get gridData {
    final colors = context.colors;
    return FlGridData(
      show: true,
      drawHorizontalLine: true,
      drawVerticalLine: false,
      horizontalInterval: 1,
      getDrawingHorizontalLine: (value) {
        return FlLine(
          color: colors.divider.withValues(alpha: 0.5),
          strokeWidth: 1,
          dashArray: [5, 5],
        );
      },
    );
  }

  FlBorderData get borderData {
    final colors = context.colors;
    return FlBorderData(
      show: true,
      border: Border(
        bottom: BorderSide(color: colors.divider, width: 1),
        left: BorderSide(color: colors.divider, width: 1),
        right: const BorderSide(color: Colors.transparent),
        top: const BorderSide(color: Colors.transparent),
      ),
    );
  }

  LineChartBarData get lineChartBarData1_3 {
    final colors = context.colors;
    return LineChartBarData(
      isCurved: true,
      curveSmoothness: 0.3,
      preventCurveOverShooting: true,
      color: colors.chartLine,
      barWidth: 3,
      isStrokeCapRound: true,
      dotData: const FlDotData(show: false),
      belowBarData: BarAreaData(
        show: true,
        color: colors.chartLine.withValues(alpha: 0.08),
      ),
      spots: pointList,
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final insights = singleton.longitudinalInsights;

    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Quick stats row
          FadeTransition(
            opacity: _animation,
            child: Row(
              children: [
                Expanded(
                  child: _buildQuickStat(
                    colors,
                    Icons.favorite_rounded,
                    '${singleton.log.length}',
                    'Symptoms',
                    colors.primary,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildQuickStat(
                    colors,
                    Icons.medication_rounded,
                    '${singleton.schedule.length}',
                    'Medications',
                    colors.secondary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          if (insights.hasMeaningfulData) ...[
            ModernCard(
              padding: const EdgeInsets.all(18),
              borderRadius: 16,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.insights_outlined,
                        color: colors.info,
                        size: 24,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Health patterns',
                              style: Theme.of(context).textTheme.titleMedium
                                  ?.copyWith(fontWeight: FontWeight.w700),
                            ),
                            Text(
                              '${insights.eventCount} recorded events',
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(color: colors.textTertiary),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Text(
                    insights.summary,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: colors.textSecondary,
                      height: 1.45,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],

          // Symptom chart
          ModernCard(
            padding: const EdgeInsets.all(20),
            borderRadius: 16,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.show_chart_rounded,
                          color: colors.chartLine,
                          size: 24,
                        ),
                        const SizedBox(width: 12),
                        Text(
                          'Symptoms',
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                      ],
                    ),
                    DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: chosenTime,
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        icon: Icon(
                          Icons.keyboard_arrow_down_rounded,
                          color: colors.textSecondary,
                          size: 20,
                        ),
                        style: Theme.of(context).textTheme.labelMedium
                            ?.copyWith(color: colors.textPrimary),
                        dropdownColor: colors.surface,
                        borderRadius: BorderRadius.circular(12),
                        onChanged: (String? newValue) {
                          if (newValue == null) return;
                          HapticUtils.selectionClick();
                          setState(() {
                            chosenTime = newValue;
                            _rebuildChartData();
                          });
                        },
                        items: time.map<DropdownMenuItem<String>>((
                          String item,
                        ) {
                          return DropdownMenuItem<String>(
                            value: item,
                            child: Text(item),
                          );
                        }).toList(),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                _symptomChartHasData
                    ? Semantics(
                        label:
                            'Symptom trend chart. '
                            '${singleton.log.length} symptoms logged, '
                            'shown by ${chosenTime.toLowerCase()}.',
                        child: SizedBox(
                          height: 200,
                          child: AnimatedBuilder(
                            animation: _animation,
                            builder: (context, child) {
                              return LineChart(
                                sampleData1,
                                duration: const Duration(milliseconds: 300),
                              );
                            },
                          ),
                        ),
                      )
                    : Container(
                        height: 200,
                        alignment: Alignment.center,
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.show_chart_rounded,
                              size: 44,
                              color: colors.textTertiary.withValues(alpha: 0.6),
                            ),
                            const SizedBox(height: 14),
                            Text(
                              'Log symptoms to see your trend',
                              style: Theme.of(context).textTheme.bodyMedium
                                  ?.copyWith(color: colors.textTertiary),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Medication chart
          ModernCard(
            padding: const EdgeInsets.all(20),
            borderRadius: 16,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.medication_outlined,
                      color: colors.chartBar,
                      size: 24,
                    ),
                    const SizedBox(width: 12),
                    Text(
                      'Weekly Medications',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                _medicationChartHasData
                    ? const BarChartSample3()
                    : Container(
                        height: 180,
                        alignment: Alignment.center,
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.medication_rounded,
                              size: 44,
                              color: colors.textTertiary.withValues(alpha: 0.6),
                            ),
                            const SizedBox(height: 14),
                            Text(
                              'Add medications to see your weekly schedule',
                              textAlign: TextAlign.center,
                              style: Theme.of(context).textTheme.bodyMedium
                                  ?.copyWith(color: colors.textTertiary),
                            ),
                          ],
                        ),
                      ),
              ],
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildQuickStat(
    AppColors colors,
    IconData icon,
    String value,
    String label,
    Color color,
  ) {
    return ModernCard(
      padding: const EdgeInsets.all(16),
      borderRadius: 14,
      margin: const EdgeInsets.symmetric(vertical: 0),
      child: Row(
        children: [
          Icon(icon, color: color, size: 28),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  value,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: colors.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colors.textSecondary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
