// Deterministic output guards for the motion summary.
//
// The model is instructed to only restate provided numbers; these checks
// make that rule enforceable instead of aspirational. Pure functions so
// they can be unit tested with `deno test`.

const MAX_SUMMARY_CHARS = 600;
const MAX_SUMMARY_WORDS = 90;

/// Every numeric token a summary is allowed to contain, harvested from the
/// exact input the model saw. Rounded forms are included because prose
/// naturally rounds ("81.5" may be spoken as "82" or "81").
export function extractAllowedNumbers(input: unknown): Set<string> {
  const allowed = new Set<string>();
  const visit = (value: unknown): void => {
    if (typeof value === "number" && Number.isFinite(value)) {
      allowed.add(String(value));
      allowed.add(String(Math.round(value)));
      allowed.add(String(Math.floor(value)));
      allowed.add(String(Math.ceil(value)));
      allowed.add(value.toFixed(1));
    } else if (typeof value === "string") {
      for (const match of value.matchAll(/\d+(?:\.\d+)?/g)) {
        allowed.add(match[0]);
      }
    } else if (Array.isArray(value)) {
      // Counting list entries is fair game ("all 4 movements").
      allowed.add(String(value.length));
      value.forEach(visit);
    } else if (value && typeof value === "object") {
      Object.values(value).forEach(visit);
    }
  };
  visit(input);
  // Small counts read naturally in prose regardless of the metrics.
  for (let i = 0; i <= 10; i += 1) allowed.add(String(i));
  return allowed;
}

/// True only when the summary is within bounds and every number in it also
/// appears in the allowed set.
export function validateSummary(
  summary: string,
  allowedNumbers: Set<string>,
): boolean {
  if (summary.length === 0 || summary.length > MAX_SUMMARY_CHARS) {
    return false;
  }
  if (summary.split(/\s+/).length > MAX_SUMMARY_WORDS) {
    return false;
  }
  for (const match of summary.matchAll(/\d+(?:\.\d+)?/g)) {
    if (!allowedNumbers.has(match[0])) {
      return false;
    }
  }
  return true;
}
