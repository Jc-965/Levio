/// Allowlisted, deterministic labels for engine codes.
///
/// Every user-visible sentence here corresponds to a machine-readable code
/// the engine emits. Unknown codes return null and render nothing: a new
/// engine code must be given reviewed copy before it can reach a person,
/// so no free-form or generated text can ever appear in feedback.
library;

/// Plain-language explanation of why a step or session was not measured.
String? reasonCodeLabel(String code) => switch (code) {
  'no_complete_reps' =>
    'No complete movements were detected for this exercise.',
  'low_coverage' =>
    'The camera could not see enough of your body to measure this.',
  'low_required_landmark_coverage' =>
    'The camera could not see enough of your body to measure this.',
  'low_sampling_rate' =>
    'The camera could not keep up; closing other apps may help.',
  'pose_discontinuity' =>
    'Tracking jumped mid-session, so these movements were not scored.',
  'bilateral_movement_required' =>
    'This exercise is measured only when both sides move together.',
  'incomplete_session_tracking' =>
    'Part of the session could not be tracked, so treat this as a rough '
        'reading.',
  'symmetry_not_applicable' =>
    'Side-to-side balance is not measured for this exercise.',
  'no_valid_side_features' =>
    'Left and right sides could not be told apart this session.',
  'insufficient_reps_for_sequence' =>
    'At least three movements are needed to read an amplitude trend.',
  'single_rep' => 'Only one movement was measured, so ranges are rough.',
  'partial_side_feature_coverage' =>
    'Some movements were measured on one side only.',
  'no_frames' => 'The camera produced no usable frames.',
  _ => null,
};

/// Short label for a live-cue code, used in "most frequent guidance" lines.
String? cueLabel(String code) => switch (code) {
  'amplitude' => 'make the movement a little larger',
  'tempo' => 'keep a steady, comfortable pace',
  'smoothness' => 'keep the movement smooth and controlled',
  'positive' => 'nice movement',
  _ => null,
};
