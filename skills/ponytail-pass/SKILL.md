---
name: ponytail-pass
description: Perform one behavior-preserving simplification pass only when the user explicitly requests it or invokes ponytail-pass. Review selected code for unnecessary complexity and reuse existing code or standard facilities. Never activate for ordinary coding, debugging, planning or review tasks.
disable-model-invocation: true
---

# Ponytail simplification pass

Use only for an explicit request for this pass. A natural-language request for a simplification pass counts; a generic coding or review request does not. This skill is self-contained: it does not enable the upstream Ponytail plugin, load its persistent persona, install dependencies, run activation hooks or change mode flags.

## Scope

Work on the diff, files or behavior the user selected. If the target is clear from the conversation, proceed. If it is unclear, ask what to review. Follow the project's instructions and existing authorization. Read the affected code and callers before suggesting a smaller implementation.

## Review

Look for duplicated logic, unused flexibility, unnecessary wrappers or dependencies, and existing helpers or standard-library facilities that fully cover the requirements. Preserve observable behavior, public interfaces, project structure and conventions, validation, error handling, security, accessibility and meaningful tests. Include empty or malformed input and failure paths when they are relevant. Fewer lines are useful only when the result stays readable and complete.

For each useful finding, state the location, proposed simplification, why behavior is preserved, and any tradeoff or validation needed. Do not replace a correctness or security review with this pass; report concerns you notice rather than suppressing them. If there is no worthwhile simplification, say so.

## Edits and completion

A review request produces suggestions. Apply changes when the user asked for edits or existing authorization covers them; avoid another confirmation for the same authorized change. Verify the affected behavior with the project's relevant checks, including error paths where appropriate. Report what changed and any unverified limits.

This pass ends when its requested scope is complete. Do not carry a brevity persona into later work or other chats, and do not instruct unrelated subagents to use it. Use a normal correctness review for the resulting change when the risk warrants one.
