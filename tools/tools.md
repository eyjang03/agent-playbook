# Recommended tools

Install per app, only what the user wants. Check first; skip anything already present. `npx skills add ... -g` installs into `~/.agents/skills`, which both Claude Code (through `~/.claude/skills` links) and Codex read; add `-a codex` when a tool should also land in `~/.codex/skills`.

| Tool | What it's for | Claude Code | Codex | Check |
|---|---|---|---|---|
| **humanizer** | Makes English writing sound natural (the core rules say when) | `claude plugin marketplace add blader/humanizer` then `claude plugin install humanizer@humanizer` | `npx skills add blader/humanizer -g -a codex` | `claude plugin list`; `~/.codex/skills/humanizer` |
| **humanize-korean** | The same for Korean writing | `claude plugin marketplace add epoko77-ai/im-not-ai` then `claude plugin install humanize-korean@im-not-ai` (and `claude plugin enable` it if it was installed but off) | clone `https://github.com/epoko77-ai/im-not-ai`, then run `./install.sh --codex-only` inside it | `claude plugin list`; `~/.codex/skills/humanize-korean` |
| **ponytail** | "Simplest thing that works" coding style | `claude plugin marketplace add DietrichGebert/ponytail` then `claude plugin install ponytail@ponytail` | `codex plugin marketplace add DietrichGebert/ponytail` then `codex plugin add ponytail@ponytail`, then approve its hooks | `claude plugin list`; `codex plugin list` |
| **hyperframes** (about 18 video skills) | Making videos, captions, and motion graphics from HTML | `npx skills add heygen-com/hyperframes -g` | same install (Codex reads `~/.agents/skills`) | `~/.agents/skills/hyperframes` |
| **frontend-design** | Distinctive visual design for web UI | `npx skills add anthropics/skills --skill frontend-design -g` | add `-a codex` to the same command | `~/.agents/skills/frontend-design` |
| **web-design-guidelines** | Reviewing UI against web interface guidelines | `npx skills add vercel-labs/agent-skills --skill web-design-guidelines -g` | add `-a codex` to the same command | `~/.agents/skills/web-design-guidelines` |

Notes:
- `npx` needs Node.js. Ask before installing it.
- Signing in to GitHub is done by the user.
- Plugins installed from GitHub update through each app's plugin manager; `npx skills` installs update with `npx skills update`.
