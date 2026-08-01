import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'singleton.dart';
import 'theme/app_theme.dart';

class BarChartSample3 extends StatefulWidget {
  const BarChartSample3({super.key});

  @override
  State<StatefulWidget> createState() => BarChartSample3State();
}

class BarChartSample3State extends State<BarChartSample3> {
  final singleton = Singleton();
  String _lastScheduleSignature = '';

  @override
  void initState() {
    super.initState();
    _lastScheduleSignature = _buildScheduleSignature();
    singleton.calcMeds();
    singleton.addListener(_onSingletonUpdate);
  }

  @override
  void dispose() {
    singleton.removeListener(_onSingletonUpdate);
    super.dispose();
  }

  void _onSingletonUpdate() {
    if (!mounted) return;
    final nextSignature = _buildScheduleSignature();
    if (nextSignature == _lastScheduleSignature) return;
    _lastScheduleSignature = nextSignature;
    singleton.calcMeds();
    setState(() {});
  }

  String _buildScheduleSignature() {
    if (singleton.schedule.isEmpty) return 'empty';
    final last = singleton.schedule.last;
    final lastToken = last.isNotEmpty ? last.first : '';
    return '${singleton.schedule.length}|$lastToken';
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final dosesThisWeek = singleton.medsPerDay.values
        .fold<double>(0, (sum, count) => sum + count)
        .round();

    return Semantics(
      label:
          'Weekly medication chart. '
          '$dosesThisWeek doses logged in the last 7 days.',
      child: SizedBox(
        height: 180,
        child: BarChart(
          BarChartData(
            barTouchData: barTouchData(colors),
            titlesData: titlesData(colors),
            borderData: borderData(colors),
            barGroups: barGroups(colors),
            gridData: FlGridData(
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
            ),
            alignment: BarChartAlignment.spaceAround,
            maxY: singleton.barY,
          ),
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOutCubic,
        ),
      ),
    );
  }

  BarTouchData barTouchData(AppColors colors) => BarTouchData(
    enabled: true,
    touchTooltipData: BarTouchTooltipData(
      getTooltipColor: (group) => colors.surface,
      tooltipPadding: const EdgeInsets.all(12),
      getTooltipItem: (group, groupIndex, rod, rodIndex) {
        final days = [
          'Monday',
          'Tuesday',
          'Wednesday',
          'Thursday',
          'Friday',
          'Saturday',
          'Sunday',
        ];
        return BarTooltipItem(
          '${days[group.x]}\n',
          TextStyle(color: colors.textSecondary, fontSize: 12),
          children: [
            TextSpan(
              text: '${rod.toY.toInt()} meds',
              style: TextStyle(
                color: colors.chartBar,
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
            ),
          ],
        );
      },
    ),
  );

  Widget getTitles(double value, TitleMeta meta, AppColors colors) {
    TextStyle style = TextStyle(
      color: colors.textSecondary,
      fontWeight: FontWeight.w500,
      fontSize: 12,
    );
    String text;
    switch (value.toInt()) {
      case 0:
        text = 'Mon';
        break;
      case 1:
        text = 'Tue';
        break;
      case 2:
        text = 'Wed';
        break;
      case 3:
        text = 'Thu';
        break;
      case 4:
        text = 'Fri';
        break;
      case 5:
        text = 'Sat';
        break;
      case 6:
        text = 'Sun';
        break;
      default:
        text = '';
        break;
    }
    return SideTitleWidget(
      meta: meta,
      space: 8,
      child: Text(text, style: style),
    );
  }

  FlTitlesData titlesData(AppColors colors) => FlTitlesData(
    show: true,
    bottomTitles: AxisTitles(
      sideTitles: SideTitles(
        showTitles: true,
        reservedSize: 32,
        getTitlesWidget: (value, meta) => getTitles(value, meta, colors),
      ),
    ),
    leftTitles: AxisTitles(
      sideTitles: SideTitles(
        showTitles: true,
        reservedSize: 32,
        interval: 1,
        getTitlesWidget: (value, meta) {
          return Text(
            value.toInt().toString(),
            style: TextStyle(
              color: colors.textSecondary,
              fontWeight: FontWeight.w500,
              fontSize: 12,
            ),
          );
        },
      ),
    ),
    topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
    rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
  );

  FlBorderData borderData(AppColors colors) => FlBorderData(
    show: true,
    border: Border(
      bottom: BorderSide(color: colors.divider, width: 1),
      left: BorderSide(color: colors.divider, width: 1),
      right: const BorderSide(color: Colors.transparent),
      top: const BorderSide(color: Colors.transparent),
    ),
  );

  List<BarChartGroupData> barGroups(AppColors colors) {
    final values = singleton.medsPerDay.values.toList();
    return List.generate(7, (index) {
      return BarChartGroupData(
        x: index,
        barRods: [
          BarChartRodData(
            toY: values[index],
            gradient: LinearGradient(
              colors: [colors.chartBar, colors.chartBar.withValues(alpha: 0.6)],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
            width: 20,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(6)),
          ),
        ],
      );
    });
  }
}
