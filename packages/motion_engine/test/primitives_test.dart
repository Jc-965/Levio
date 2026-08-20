import 'package:motion_engine/motion_engine.dart';
import 'package:test/test.dart';

void main() {
  test('jointAngle returns a right angle', () {
    expect(
      jointAngle(
        const Vector3(1, 0, 0),
        const Vector3(0, 0, 0),
        const Vector3(0, 1, 0),
      ),
      closeTo(90, 1e-12),
    );
  });

  test('jointAngle abstains on missing and degenerate points', () {
    expect(
      jointAngle(null, const Vector3(0, 0, 0), const Vector3(1, 0, 0)),
      isNaN,
    );
    expect(
      jointAngle(
        const Vector3(0, 0, 0),
        const Vector3(0, 0, 0),
        const Vector3(1, 0, 0),
      ),
      isNaN,
    );
  });

  test('interpolates only bounded short gaps', () {
    expect(
      interpolateShortGaps(<double>[0, double.nan, 2]),
      <double>[0, 1, 2],
    );
    final List<double> longGap = interpolateShortGaps(
      <double>[0, double.nan, double.nan, 3],
      maxGapFrames: 1,
    );
    expect(longGap[1], isNaN);
    expect(longGap[2], isNaN);
  });

  test('sampling rate uses the median timestamp interval', () {
    expect(
        estimateSamplingHz(<int>[0, 60, 121, 181]), closeTo(1000 / 60, 1e-12));
  });

  test('timestamp filtering does not cross a dropped-frame pause', () {
    final List<double> values = <double>[
      ...List<double>.filled(40, 0),
      ...List<double>.filled(40, 100),
    ];
    final List<int> timestamps = <int>[
      for (int index = 0; index < 40; index += 1) index * 60,
      for (int index = 0; index < 40; index += 1) 3000 + index * 60,
    ];
    final List<double> filtered = lowpassTimestamped(values, timestamps);
    expect(
      filtered.sublist(0, 40).every((double value) => value.abs() < 1e-9),
      isTrue,
    );
    expect(
      filtered.sublist(40).every((double value) => (value - 100).abs() < 1e-9),
      isTrue,
    );
  });

  test('segmentation ignores incomplete first and last repetitions', () {
    final List<double> values = <double>[
      90,
      70,
      50,
      30,
      10,
      30,
      50,
      70,
      90,
      70,
      50,
      30,
      10,
      30,
      50,
    ];
    final List<int> timestamps = <int>[
      for (int index = 0; index < values.length; index += 1) index * 100,
    ];
    final List<RepBoundary> repetitions = segmentReps(
      values,
      timestamps,
      SegmentationConfig(
        referenceRomDeg: 80,
        referenceTempoS: 0.8,
      ),
    );
    expect(repetitions, hasLength(1));
    // The boundary start is the activation-crossing sample after the valley.
    expect(repetitions.single.startIndex, 5);
    expect(repetitions.single.peakIndex, 8);
    expect(repetitions.single.endIndex, 12);
  });
}
