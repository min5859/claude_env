# Global Rules

## Ambiguity
- Multiple interpretations → list all, then ask before writing code.
- State understanding of the task before starting.

## Simplicity
- If 200 lines can be 50, it must be 50.
- Unrelated dead code: mention it, don't touch it.

## Goal-Driven Execution
- Prefer test-based success criteria:
  - "fix bug" → write a failing test first, then make it pass
  - "add validation" → write test with invalid input, then make it pass
- Surface blockers early, don't silently work around them.
