# Recommended tools

Install per app, only what the user wants. Check first; skip anything already present. `npx skills add ... -g` installs into `~/.agents/skills`, which both Claude Code (through `~/.claude/skills` links) and Codex read; add `-a codex` when a tool should also land in `~/.codex/skills`.

| Tool | What it's for | Claude Code | Codex | Check |
|---|---|---|---|---|
| **humanizer** | Makes English writing sound natural (the core rules say when) | `claude plugin marketplace add blader/humanizer` then `claude plugin install humanizer@humanizer` | `npx skills add blader/humanizer -g -a codex` | `claude plugin list`; `~/.codex/skills/humanizer` |
| **humanize-korean** | The same for Korean writing | `claude plugin marketplace add epoko77-ai/im-not-ai` then `claude plugin install humanize-korean@im-not-ai` (and `claude plugin enable` it if it was installed but off) | clone `https://github.com/epoko77-ai/im-not-ai`, then run `./install.sh --codex-only` inside it | `claude plugin list`; `~/.codex/skills/humanize-korean` |
| **ponytail-pass** (bundled) | A bounded, behavior-preserving simplification pass selected by the agent when useful | Agent-selected; also available as `/agent-playbook:ponytail-pass` | Agent-selected; also available as `$ponytail-pass` | Automatic skill selection allowed; upstream Ponytail disabled |
| **hyperframes** (about 18 video skills) | Making videos, captions, and motion graphics from HTML | `npx skills add heygen-com/hyperframes -g` | same install (Codex reads `~/.agents/skills`) | `~/.agents/skills/hyperframes` |
| **frontend-design** | Distinctive visual design for web UI | `npx skills add anthropics/skills --skill frontend-design -g` | add `-a codex` to the same command | `~/.agents/skills/frontend-design` |
| **web-design-guidelines** | Reviewing UI against web interface guidelines | `npx skills add vercel-labs/agent-skills --skill web-design-guidelines -g` | add `-a codex` to the same command | `~/.agents/skills/web-design-guidelines` |

## Existing Ponytail installations

The upstream plugin is no longer a recommended always-on tool. Keep it disabled; the bundled `ponytail-pass` skill lets agents select a bounded simplification pass when useful, without asking the user to choose or installing the upstream plugin. During a user-authorized tools setup or migration, disable an enabled Claude installation with `claude plugin disable ponytail@ponytail --scope user`. Inspect project/local overrides too. In Codex, turn off the installed Ponytail plugin through its plugin settings, preserving unrelated settings. A configured default mode of `off` alone is insufficient because versions can share mode flags across chats.

Preserve the installed files and unrelated statusline components. If removing a Ponytail-only statusline, back up the settings first. Start fresh chats after changing plugin activation; old chats can retain injected instructions or loaded hooks. Do not silently change another user's installed-plugin settings merely because their Playbook updated: explain the new default and apply migration when setup or migration is authorized.

Notes:
- `npx` needs Node.js. Ask before installing it.
- Signing in to GitHub is done by the user.
- Plugins installed from GitHub update through each app's plugin manager; `npx skills` installs update with `npx skills update`.
