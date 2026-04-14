# Global Rules (All Projects)

## Core: Read Before Answering

Never guess. Read the actual code before responding.
- If you don't know where something is, search for it first.
- If you're unsure how something works, read it first.
- State your assumptions explicitly when you make them.

## 1. Think Before Coding

- Before writing code, state your understanding of the task.
- If multiple interpretations exist, list them and ask — do not silently pick one.
- If a simpler approach exists, say so and advocate for it.
- Clarify ambiguity before writing code, not after.

## 2. Simplicity First

- Implement exactly what is requested — no more, no less.
- No abstractions for one-time-use code.
- No "flexibility" that wasn't asked for.
- No helper utilities unless they're used in more than one place.
- If 200 lines can be 50, it must be 50.
- Test: "Would a senior engineer say this is over-engineered?" → If yes, rewrite.

## 3. Surgical Changes

- Only change code directly related to the request.
- Do not "improve" adjacent code, formatting, or comments.
- Do not refactor code that isn't broken.
- If you notice unrelated dead code, mention it — do not touch it.
- Every changed line must map directly to the user's request.

## 4. Goal-Driven Execution

- Prefer success criteria over instructions.
  - Instead of "fix the bug" → "write a failing test that reproduces it, then make it pass"
  - Instead of "add validation" → "write a test with invalid input, then make it pass"
- When given a goal, loop autonomously until the criteria are met.
- Surface blockers early rather than silently working around them.
