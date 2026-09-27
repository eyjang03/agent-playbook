# Handoff

Updated 2026-09-27.

- Version 1.2.0 adds guided app setup, optional working tips, and project Git/GitHub setup with local, ask-before-upload, and automatic upload choices.
- Version 1.2.1 asks before deploying only for big releases or important changes; small urgent or low-risk fixes ship without asking.
- Upload/download choices are local to each checkout and computer. Existing `.project-sync` projects are not migrated automatically.
- Both apps share local preferences and project choices; their installations and hook activation still need separate verification.
- Validation uses the playbook self-test and isolated Git tests in `tests/`. Run the commands in `README.md` after code changes.
- Codex's native plugin reader recognizes the custom hook declaration; the bundled standalone validator currently rejects that pre-existing field.
- Publication of version 1.2.0 is approved. Fresh sessions in each installed app are still needed to verify live hook activation after installation or update. Independent model review has not been performed.
