import {
  assert,
  assertFalse,
} from "jsr:@std/assert@1";
import {
  extractAllowedNumbers,
  validateSummary,
} from "../validate.ts";

const input = {
  session: {
    overall_score: 81.5,
    steps: [
      { exercise_id: "sit_to_stand", completed_repetitions: 3 },
    ],
  },
  recent_sessions: [{ overall_score: 76.2, day: "2026-08-18" }],
};

Deno.test("accepts a summary that only restates provided numbers", () => {
  const allowed = extractAllowedNumbers(input);
  assert(
    validateSummary(
      "Nice work today. You scored 82, up from 76 in your last session, " +
        "and completed 3 sit-to-stands.",
      allowed,
    ),
  );
});

Deno.test("rejects a summary that invents a number", () => {
  const allowed = extractAllowedNumbers(input);
  assertFalse(
    validateSummary("Your grip strength improved by 47 percent.", allowed),
  );
});

Deno.test("rejects an overlong summary", () => {
  const allowed = extractAllowedNumbers(input);
  assertFalse(validateSummary("well done ".repeat(120), allowed));
});

Deno.test("rejects an empty summary", () => {
  assertFalse(validateSummary("", extractAllowedNumbers(input)));
});

Deno.test("allows rounded forms of provided decimals", () => {
  const allowed = extractAllowedNumbers({ score: 81.5 });
  assert(validateSummary("You reached 82 today.", allowed));
  assert(validateSummary("You reached 81.5 today.", allowed));
});
