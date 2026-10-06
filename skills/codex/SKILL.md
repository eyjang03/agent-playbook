---
name: codex
description: Run an OpenAI model through the official Codex CLI as a read-only second-model reviewer or helper. Use from Claude Code or another non-Codex agent when the user asks to "run", "ask", or "have Codex/GPT/<model nickname> audit" something, or wants the "review by a different AI model" the core rules offer for risky work. Not for work that needs the calling agent's own connectors, browser, SSH, or accounts, or that would send patient or client records, other people's personal data, or credentials to OpenAI.
---

# Codex as a second model

## Find the CLI

Use `codex` if it is on `PATH`; otherwise the ChatGPT desktop app bundles it at `/Applications/ChatGPT.app/Contents/Resources/codex-cli/bin/codex`. If neither exists, ask the user to install Codex rather than installing it yourself. Run `codex --version` and `codex exec --help` before the first call in a session: flags change between versions. If a call fails with an authentication error, the user must sign in to Codex once themselves.

## Model and effort

`~/.codex/models_cache.json` lists each model's `slug` and `supported_reasoning_levels`. Match the model the user names (a nickname such as "Astra" maps to a slug such as `gpt-6-astra`) and confirm the effort they ask for is in that model's list. With no model named, use the `model` in `~/.codex/config.toml`. Tell the user the model id and effort the run actually used; the first lines of the run log print both, together with the sandbox.

## Audit with an evidence pack, not access

Codex's read-only sandbox blocks writes and network access, so it can't SSH, sign in, or reach services. Collect what it needs first, in a folder in your scratchpad or temp directory:

- `PROMPT.md`: the setup, the task, the verdict scale (for example Correct, Wrong, Overstated, Unsupported, Outdated), and a request to cite `file:line` or a URL and to mark inference.
- `claims/`: the statements under review, verbatim.
- `evidence/`: raw command output collected fresh, each block headed by the exact command. Note any block that failed.
- `context/`: only the note excerpts that matter.

Leave out credentials, tokens, account emails, and other people's personal data. Anything the reviewer needs to judge a claim belongs in the pack: whatever you leave out comes back as "unsupported". Leave your own suspicions out of the prompt when the user wants an independent check, then compare afterwards.

## Call

```bash
codex --search exec -m <slug> -c model_reasoning_effort='"<effort>"' -s read-only --skip-git-repo-check -C "$PACK" -o "$PACK/report.md" - < "$PACK/PROMPT.md" > "$PACK/run.log" 2>&1
```

- `--search` goes before `exec` and enables web search for checking outside claims.
- Never pass `--dangerously-bypass-approvals-and-sandbox`. For code changes, ask for a patch and apply it yourself.
- High efforts take several minutes or more: run the call in the background and wait for it to finish rather than polling.
- Codex loads the user's own config, `AGENTS.md`, hooks, and memories, and may update its own memory files during the run. That is normal Codex behavior; leave those files alone and mention it if the user asks what changed.

## After

The report is another model's opinion. Check its high-impact claims against the sources it cites before relaying them, set aside verdicts that are only "unsupported" because the pack lacked the evidence, and tell the user which findings came from which model and effort.
