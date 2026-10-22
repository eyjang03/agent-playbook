---
name: ponytail-pass
description: Review or edit code in one bounded, behavior-preserving simplification pass when there is concrete duplication, unnecessary complexity or an opportunity to reuse existing facilities. Agents choose when the pass would help the current task; explicit simplification requests also apply.
---

# Ponytail simplification pass

Decide whether this pass would help the current task without asking the user to choose the tool. Use it for concrete duplication, unnecessary indirection or flexibility, or code that existing helpers or standard facilities can replace completely. Skip it when the code is already straightforward, the task is unrelated to code, or the likely benefit does not justify the churn or risk. Do not run a pass automatically on every task or repeatedly search for reductions after the useful work is done.

This skill is self-contained: it does not enable the upstream Ponytail plugin, load its persistent persona, install dependencies, run activation hooks or change mode flags.

## Scope

Select a bounded target from the current task's diff, files or behavior. Follow the project's instructions and existing authorization. Do not expand the task into unrelated cleanup. Read the affected code and callers before suggesting a smaller implementation. Resolve routine scope choices yourself; ask only when a missing requirement or authorization prevents correct work, never whether to use this skill.

## Review

Look for duplicated logic, unused flexibility, unnecessary wrappers or dependencies, and existing helpers or standard-library facilities that fully cover the requirements. Preserve observable behavior, public interfaces, project structure and conventions, validation, error handling, security, accessibility and meaningful tests. Include empty or malformed input and failure paths when they are relevant. Fewer lines are useful only when the result stays readable and complete.

For each useful finding, state the location, proposed simplification, why behavior is preserved, and any tradeoff or validation needed. Do not replace a correctness or security review with this pass; report concerns you notice rather than suppressing them. A pass can end with no changes when there is no worthwhile simplification.

## Edits and completion

A review request produces suggestions. Apply changes when the user asked for edits or existing authorization covers them; avoid another confirmation for the same authorized change. Verify the affected behavior with the project's relevant checks, including error paths where appropriate. Report meaningful changes and any unverified limits as part of the task's normal result; no separate tool-choice discussion is needed.

This pass ends when its selected scope is complete. Do not carry a brevity persona into later work or other chats, and do not instruct unrelated subagents to use it. Use a normal correctness review for the resulting change when the risk warrants one.
