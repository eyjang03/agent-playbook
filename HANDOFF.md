# Handoff

Updated 2026-09-28.

- Version 1.2.2 is prepared locally to prevent missing-cache hook failures in active sessions. Both apps' hook commands carry their exact runtime; they do not select a newer installation or skip sync after a cache deletion.
- Run `python3 scripts/build_hooks.py` after changing runtime sources, rules, or versions; `--check` verifies the committed bundles. Design, upgrade steps, and limits are in `docs/hook-runtime.md`.
- Upload/download choices are local to each checkout and computer. Existing `.project-sync` projects are not migrated automatically.
- Both apps share local preferences and project choices; their installations and hook activation still need separate verification.
- Validation uses the playbook self-test and isolated Git tests in `tests/`. Run the commands in `README.md` after code changes.
- Validation passed: 38 isolated tests, playbook self-test, generated-bundle and whitespace checks. Earlier hook checks passed on Python 3.9 and Claude manifest validation passed. The optional standalone Codex validator could not start because PyYAML is unavailable.
- Rules audit: clarified small low-risk deployments, reused approval, integration/cleanup scope, and personal overrides. Removed residual model-per-step advice. Fixed filtering of unrelated older memory topics and added regressions. Expanded the behavioral check to ten scenarios; these have not been run against an agent.
- Publication of this release and fresh in-app execution remain pending. Pre-1.2.2 sessions need a one-time reload. Do not overwrite hook approval records. Independent model review has not been performed.
