# Agent Instructions

This project uses **bd** (beads) for issue tracking. Run `bd prime` for full workflow context.

> **Architecture in one line:** Issues live in a local Dolt database
> (`.beads/dolt/`); cross-machine sync uses `bd dolt push/pull` (a
> git-compatible protocol), stored under `refs/dolt/data` on your git
> remote — separate from `refs/heads/*` where your code lives.
> `.beads/issues.jsonl` is a passive export, not the wire protocol.
>
> See [sync-concepts](https://github.com/gastownhall/beads/blob/main/docs/core-concepts/sync-concepts.md)
> for the one-screen overview and anti-patterns (don't treat JSONL as the
> source of truth; don't `bd import` during normal operation; don't
> reach for third-party Dolt hosting before trying the default).

## Quick Reference

```bash
bd ready              # Find available work
bd show <id>          # View issue details
bd update <id> --claim  # Claim work atomically
bd close <id>         # Complete work
bd dolt push          # Push beads data to remote
```

## Git Policy

**This section is authoritative and overrides the git guidance in the managed Beads
blocks below, in this file and in `CLAUDE.md`.** Those blocks are template-generated and
carry a content hash, so a future `bd setup claude` / `bd setup codex` may regenerate them
and reintroduce a "do not commit" rule. If that happens, this section still wins — and the
regenerated text should be corrected again.

### Commit as you go

Make an **atomic commit after each completed changeset**. A changeset is one coherent,
separately-verifiable unit of work — typically one beads issue, or one logical change
within it. Do not batch unrelated work into a single commit, and do not leave finished work
uncommitted for a later "session close" step.

Follow the **`ship` skill** for the mechanics. In short:

1. Inspect the tree (`git status`, `git diff`, `git diff --staged`) and read the change
   well enough to explain *why* it was made.
2. **Run the quality gates first** — `make build`, `make lint`, and `make test` once it
   exists. Never commit over a red build or new lint violations; fix or report them.
3. Stage explicit paths, not `git add -A`. If the diff spans unrelated concerns, split it
   into several commits.
4. Write a Conventional Commit: `type(scope): imperative subject` (≤72 chars), a body
   explaining the why, and the `Co-Authored-By` trailer.

### Repo-specific conventions

- **Commit directly on `main`.** This repo's history is linear on `main`; the `ship`
  skill's default of branching first does *not* apply here unless asked.
- Types in use: `feat`, `fix`, `chore`, `docs`, `build`, `style`, `refactor`. Scopes are
  optional and match the touched area (e.g. `placer`).
- Include the `Co-Authored-By: Claude <noreply@anthropic.com>` trailer. The existing
  history has none — that is stale, not a preference.
- When a commit completes a bead: `bd note <id> "<what was done, commit hash>"` then
  `bd close <id>`, and reference the id in the commit body.

### Pushing stays explicit

Committing is now automatic; **publishing is not.** Do not run `git push` or
`bd dolt push` unless asked for that specific push. Report what is ready to push at
handoff instead. Rationale: commits are local and cheap to amend or reorder, whereas a
push is outward-facing and hard to walk back.

## Versioning

The project uses **semantic versioning**, `MAJOR.MINOR.PATCH`, tagged `vX.Y.Z` to match
the existing `v0.1.0` … `v0.3.0`.

**One version bump per changeset.** Every completed changeset — i.e. every atomic commit
that finishes a beads issue — bumps the version and gets its own tag. Do not batch several
changesets into one release.

Which component moves:

- **PATCH** for a bug fix, or for an internal-only change with no user-visible surface
  (tests, refactors, dead-code removal, docs). One patch per *distinct bug fixed* — two
  unrelated fixes are two bumps, not one.
- **MINOR** for anything that changes user-facing behaviour: a new subcommand or flag, a
  changed default, a new or removed binary, a changed config or output format. While the
  version is `0.x`, MINOR is also the breaking-change slot.
- **MAJOR** — `1.0.0` is reserved for the point where spikot-wm needs no third-party
  window manager, hotkey daemon or launcher script.

### Single source of truth

The version lives in **one** constant, `spikotVersion` in `Sources/StateCore/Version.swift`,
which both executables pass to `CommandConfiguration(version:)`. Everything else derives
from it or is checked against it.

This matters because three sources currently disagree: `Sources/State/main.swift:11` says
`0.0.1`, `README.md:5` claims `0.3.0`, and the newest tag is `v0.3.0`. Reconciling them is
`spikot-win-1iz.2`, and it is a prerequisite for the tagging below meaning anything — do it
first.

`make version-check` must assert that `spikotVersion` equals the newest `git tag` with the
`v` stripped, so the two cannot drift again.

### Release commits and tags

Because every changeset *is* a release, the version bump goes **in the changeset's own
commit** — do not add a separate `chore(release):` commit, which would double the history
for no gain. So the commit that finishes a bead also edits `Version.swift`, and its subject
stays the Conventional Commit for the actual work:

```
fix(state): Make the cache round-trip across runs
```

Then tag that commit, annotated:

```bash
git tag -a v0.3.3 -m "v0.3.3 — cache round-trips across runs"
```

Order matters: run the quality gates, bump the constant, commit, `make version-check`, then
tag. Tagging before the commit exists, or bumping without tagging, is what lets the constant
and the tags drift apart again.

Tags are **not** pushed automatically; `git push --tags` follows the same
explicit-request rule as any other push. Never move or delete a tag that has been pushed.

### Beads track the target version

Each **leaf** issue carries exactly one `release:X.Y.Z` label, naming the version it ships
as. Epics carry none, because they span a range of versions.

```bash
bd list --label release:0.4.0        # what ships in that version
bd list --label-pattern 'release:*'  # the whole roadmap
```

When work is discovered mid-stream, give it the next free version rather than folding it
into an existing one. Renumbering later is just a relabel, so do not agonise over the exact
number at creation time — but keep the sequence monotonic in dependency order, so the
version numbers and the dependency graph agree.

The current roadmap:

| Version | Changeset | Bump |
|---|---|---|
| `0.3.1` | Single-source the version constant (`1iz.2`) | fix |
| `0.3.2` | Turn logging on, delete dead code (`yeh.1`) | fix |
| `0.3.3` | Make the cache round-trip (`yeh.2`) | fix |
| `0.4.0` | Config file; gap default 5 → 10 (`yeh.3`) | minor |
| `0.4.1` | Test target; make `State`'s dependencies injectable (`yeh.4`) | internal |
| `0.4.2` | Stop trapping; fix the clamp (`yeh.5`) | fix |
| `0.4.3` | Fix closed-window removal (`yeh.6`) | fix |
| `0.4.4` | Move the toolchain note to `bd remember` (`1iz.4`) | internal |
| `0.5.0` | `doctor` subcommand (`yeh.7`) | minor |
| `0.5.1` | `CSpikotAX` C target (`6sd.1`) | internal |
| `0.6.0` | AX↔window-id bridge, `debug ax` (`6sd.2`) | minor |
| `0.7.0` | Real per-window focus, `--pid` (`6sd.3`) | minor |
| `0.8.0` | Window titles, `list --format` (`6sd.4`) | minor |
| `0.9.0` | `.app` bundle, signing, install prefix (`m7t.1`) | minor |
| `0.9.1` | IPC protocol and socket transport (`m7t.2`) | internal |
| `0.10.0` | `spikot-agent` (`m7t.3`) | minor |
| `0.11.0` | Thin client + LaunchAgent (`m7t.4`) | minor |
| `0.12.0` | **Menu bar status item** (`nho.1`) | minor |
| `0.13.0` | Config editing UI (`nho.2`) | minor |
| `0.14.0` | Display/geometry core (`80o.1`) | minor |
| `0.15.0` | `place` for stacks (`80o.2`) | minor |
| `0.16.0` | Parity: halves + maximize (`80o.3`) | minor |
| `0.17.0` | Parity: thirds (`80o.4`) | minor |
| `0.18.0` | Parity: display transfer (`80o.5`) | minor |
| `0.19.0` | Parity: frame history + restore (`80o.6`) | minor |
| `0.20.0` | Retire `spikot-placer` (`80o.7`) | minor |
| `0.21.0` | Hotkey backend (`1k4.1`) | minor |
| `0.22.0` | Keybinding config (`1k4.2`) | minor |
| `0.23.0` | **skhd retired** (`1k4.3`) | minor |
| `0.24.0` | `launch` subcommand (`9ic.1`) | minor |
| `0.25.0` | Window picker panel (`9ic.2`) | minor |
| `0.26.0` | **`mylauncher` retired**; `list` default flips (`9ic.3`) | minor |
| `1.0.0` | **Rectangle uninstalled, shims removed — self-sufficient** (`1iz.1`) | major |
| `1.0.1` | Documentation rewrite (`1iz.3`) | docs |

## Non-Interactive Shell Commands

**ALWAYS use non-interactive flags** with file operations to avoid hanging on confirmation prompts.

Shell commands like `cp`, `mv`, and `rm` may be aliased to include `-i` (interactive) mode on some systems, causing the agent to hang indefinitely waiting for y/n input.

**Use these forms instead:**
```bash
# Force overwrite without prompting
cp -f source dest           # NOT: cp source dest
mv -f source dest           # NOT: mv source dest
rm -f file                  # NOT: rm file

# For recursive operations
rm -rf directory            # NOT: rm -r directory
cp -rf source dest          # NOT: cp -r source dest
```

**Other commands that may prompt:**
- `scp` - use `-o BatchMode=yes` for non-interactive
- `ssh` - use `-o BatchMode=yes` to fail instead of prompting
- `apt-get` - use `-y` flag
- `brew` - use `HOMEBREW_NO_AUTO_UPDATE=1` env var

<!-- BEGIN BEADS INTEGRATION v:1 profile:minimal hash:46cd31e7 -->
## Beads Issue Tracker

This project uses **bd (beads)** for issue tracking. Run `bd prime` to see full workflow context and commands.

### Quick Reference

```bash
bd ready              # Find available work
bd show <id>          # View issue details
bd update <id> --claim  # Claim work
bd close <id>         # Complete work
```

### Rules

- Use `bd` for ALL task tracking — do NOT use TodoWrite, TaskCreate, or markdown TODO lists
- Run `bd prime` for detailed command reference and session close protocol
- Use `bd remember` for persistent knowledge — do NOT use MEMORY.md files

**Architecture in one line:** issues live in a local Dolt DB; sync uses `refs/dolt/data` on your git remote; `.beads/issues.jsonl` is a passive export. See https://github.com/gastownhall/beads/blob/main/docs/core-concepts/sync-concepts.md for details and anti-patterns.

## Agent Context Profiles

The managed Beads block is task-tracking guidance, not permission to override repository, user, or orchestrator instructions.

**This repository explicitly opts in to team-maintainer for commits.** See the Git Policy
section of `AGENTS.md`, which is authoritative: commit atomically after each completed
changeset, per the `ship` skill. `git push` and `bd dolt push` still require an explicit
request.

## Session Completion

This protocol applies when ending a Beads implementation workflow. It is subordinate to explicit user, repository, and orchestrator instructions.

1. **File issues for remaining work** - Create beads for anything that needs follow-up
2. **Run quality gates** (if code changed) - Tests, linters, builds
3. **Update issue status** - Close finished work, update in-progress items
4. **Confirm nothing is left uncommitted**. Work should already be committed changeset by
   changeset, so this is a check, not a batch commit:
   ```bash
   git status            # expect a clean tree
   git log --oneline -5  # the changesets from this session

   # Only when the user asks for the push:
   git pull --rebase && bd dolt push && git push
   ```
5. **Hand off** - Summarize changes, validation, issue status, and any blocked sync/commit/push step

**Critical rules:**
- Explicit user or orchestrator instructions override this Beads block.
- Commit atomically after each completed changeset (see the Git Policy in `AGENTS.md`).
  Do not push (`git push`, `bd dolt push`) without an explicit request.
- If a required sync or push is blocked, stop and report the exact command and error.
<!-- END BEADS INTEGRATION -->

<!-- BEGIN BEADS CODEX SETUP: generated by bd setup codex -->
## Beads Issue Tracker

Use Beads (`bd`) for durable task tracking in repositories that include it. Use the `beads` skill at `.agents/skills/beads/SKILL.md` (project install) or `~/.agents/skills/beads/SKILL.md` (global install) for Beads workflow guidance, then use the `bd` CLI for issue operations.

### Quick Reference

```bash
bd ready                # Find available work
bd show <id>            # View issue details
bd update <id> --claim  # Claim work
bd close <id>           # Complete work
bd prime                # Refresh Beads context
```

### Rules

- Use `bd` for all task tracking; do not create markdown TODO lists.
- Run `bd prime` when Beads context is missing or stale. Codex 0.129.0+ can load Beads context automatically through native hooks; use `/hooks` to inspect or toggle them.
- Keep persistent project memory in Beads via `bd remember`; do not create ad hoc memory files.

**Architecture in one line:** issues live in a local Dolt DB; sync uses `refs/dolt/data` on your git remote; `.beads/issues.jsonl` is a passive export. See https://github.com/gastownhall/beads/blob/main/docs/core-concepts/sync-concepts.md for details and anti-patterns.
<!-- END BEADS CODEX SETUP -->
