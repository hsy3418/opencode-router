# opencode-router

A small setup for [opencode](https://opencode.ai) that sends each piece of work to a model that fits it, to stay under the monthly Portkey and Copilot caps:

- **Main agent (Sonnet)** — talks to you, does normal changes, decides who does what.
- **`explorer` (Haiku)** — cheap reader: searching code, reading other teams' repos, docs, browser checks (Observe, certificate portal). Saves evidence to files.
- **`deep-thinker` (Opus)** — only for hard planning: cross-team plans, auth / mTLS / certificate design, security review of a design, or a problem that failed twice.

It also adds a personal notes folder and two commands, `/wrapup` and `/continue`, so one session can pick up where another stopped.

This is version 1: small on purpose. Change it after you have a week of real numbers.

> **Not yet tested against a real opencode.** It was written on a personal laptop without opencode. The scripts are tested; the opencode file format, permission names and paths come from the docs. On the work laptop, after installing, have your agent go through **[VERIFY.md](VERIFY.md)** — it lists each assumption, how to check it, and what to change if it's wrong. A prompt you can paste:
>
> *"Read VERIFY.md in ~/opencode-router and go through every check in order. Follow its instructions for agents. Write the results to ~/agent-notes/opencode-router-verify.md. Ask me before changing models, pools, or anything outside the repo and ~/.config/opencode."*

---

## What gets installed

Everything goes into your **global** opencode config, not into any work repo.

| File on your laptop | What it is |
|---|---|
| `~/.config/opencode/agents/router.md` | Main agent with the routing rules |
| `~/.config/opencode/agents/explorer.md` | Cheap reading / browser subagent |
| `~/.config/opencode/agents/deep-thinker.md` | Strong planning subagent |
| `~/.config/opencode/commands/wrapup.md` | `/wrapup` — save the session to your notes |
| `~/.config/opencode/commands/continue.md` | `/continue <topic>` — pick up earlier work |
| `~/.config/opencode/AGENTS.md` | One short block telling every session where your notes are. Anything else already in this file is kept. |
| `~/agent-notes/` | Your notes folder (local git history, no remote) |

---

## How the routing works

Your prompt always goes to the main agent. The main agent splits the job and hands pieces to subagents. A **subagent** is a helper agent with its own model and its own empty context (working memory). It does one piece of work and returns a short result.

| Rule | Goes to | Why |
|---|---|---|
| Reading: search, read repos/docs, find owners, summarise, **all browser checks** | `explorer` | Reading is safe on a cheap model. Page data and long files stay in the subagent's context, so you don't pay for them again on every later turn. |
| Changes: code, config, k8s, infra, tests, Bruno, Jira/Confluence text | main agent | Sonnet is good enough for most changes, and the context is already there. |
| Hard thinking: cross-team plans, auth/mTLS/cert design, security review, cross-repo test approach, failed twice | `deep-thinker` | Mistakes here are expensive and may not show until the test environment or later. |
| Same thing failed twice | stop and report to you | Retry loops are expensive: every retry sends the whole, growing conversation again. |

Two limits:
- These are **instructions**, not enforcement. The main agent will usually follow them, not always. Check with the tests below.
- The built-in subagents (`general`, `explore`) are turned off for the main agent, so it uses `explorer` instead of a subagent on its own (Sonnet) model.

---

## Before you start (on the work laptop)

1. **Work rules.** Check that you are allowed to bring this repo onto the work laptop and to install personal opencode config. It holds no work data and no keys, only instructions and scripts.
2. **opencode version.** These files use the **V2** agent format (`permissions` as a list, `steps`). Run `opencode --version`. If you are on V1, see [If you are on opencode V1](#if-you-are-on-opencode-v1).
3. **Portkey and Copilot are already connected in opencode.** This repo does not set up providers or keys. It only picks which of your existing models each agent uses.
4. **Optional:** opencode Browse (the browser extension) for the Observe and certificate checks.

---

## Install

### 1. Get the repo

```bash
git clone https://github.com/hsy3418/opencode-router.git ~/opencode-router
cd ~/opencode-router
```

If personal GitHub is blocked on the work laptop, use whatever way of moving files work allows. Don't work around a block.

### 2. Find your model IDs

```bash
opencode models
```

Each ID looks like `<provider-id>/<model-id>`. Write down the IDs for Sonnet 5.5, Haiku 5.5 and Opus 5.5, for both Portkey and Copilot.

### 3. Fill in the presets

A **preset** is a file that says which model each agent uses. There are three, one for each budget situation:

| Preset | Use when |
|---|---|
| `presets/both.env` | Both pools have budget (normal) |
| `presets/portkey-only.env` | The Copilot cap is reached |
| `presets/copilot-only.env` | The Portkey cap is reached |

Open each file and replace every `TODO` with a real model ID. The install script refuses to run while any `TODO` is left.

In `both.env`, `explorer` is on Copilot and the other two are on Portkey. That split is a **guess**: `explorer` should make the most calls, so it goes on the other pool. Change it once you see real spend.

### 4. Dry run (changes nothing)

```bash
./install.sh both --dry-run
```

This checks the preset and lists what would be written.

### 5. Install

```bash
./install.sh both
```

- If a file with the same name already exists and was **not** written by this script, it is backed up first (`router.md.bak.<date-time>`).
- Running it again is safe. It only rewrites its own files.

### 6. Make `router` the default agent

Add this line to `~/.config/opencode/opencode.json`:

```json
"default_agent": "router"
```

Or press **Tab** in opencode to choose `router` each time. Then restart opencode.

### 7. Give `explorer` the browser tools (if you use Browse)

Browse is an MCP server (a tool server that opencode connects to), and its tools have their own names. I don't know the exact names, so this step is manual:

1. In opencode, find the Browse tool names (they share a prefix).
2. In `templates/agents/explorer.md`, add under `permissions:`
   ```yaml
     - action: "<browse-prefix>*"
       resource: "*"
       effect: allow
   ```
3. In `templates/agents/router.md`, add the same rule with `effect: deny`. Then the main agent can't drive the browser itself, and browser checks have to go to `explorer`.
4. Run `./install.sh both` again.

Also use Browse's **Allowed sites** setting to limit the agent's tab to Observe and the certificate portal.

---

## Check that it works

Do these once after installing. For each one, check which agent did the work. The main agent should tell you at the end, and Portkey logs show the model of every call.

| # | Try this | What should happen |
|---|---|---|
| 1 | Start opencode | `router` is the active agent; `explorer` and `deep-thinker` are listed as subagents |
| 2 | "Summarise how `<another team's repo>` handles retries" | Main agent hands it to `explorer`; the Portkey log shows Haiku calls |
| 3 | An Observe log dive with your skill | `explorer` does it; evidence lands in `~/agent-notes/evidence/<date>-<topic>/`; you get a Finding / Evidence / Confidence / Next step report |
| 4 | "Plan the mTLS change for `<our service>` calling `<another team's service>`" | `explorer` gathers context first, then `deep-thinker` plans |
| 5 | A small config change | Main agent does it itself, with no handoff |
| 6 | `/wrapup` at the end | A note in `~/agent-notes/`, a line in `index.md`, proposed lessons in `lessons-inbox.md`, and **no** skill edited |
| 7 | New session: `/continue <topic>` | Reads `index.md`, opens one note, gives you 5 lines, waits for "go" |

**The most useful single test:** do the same log dive twice, once through `explorer` (Haiku) and once directly on Sonnet. Compare the cost in Portkey and whether the findings match. That tells you whether Haiku can drive Observe well enough.

---

## When a cap runs out

```bash
cd ~/opencode-router
./install.sh portkey-only     # or copilot-only
```

Restart opencode. On the 1st of the month, switch back with `./install.sh both`.

---

## Measure it (once a week, 10 minutes)

1. **Portkey:** filter this week's logs by model and look at total cost. Sort by cost and look at the 10 most expensive requests. What were they doing?
2. **Copilot:** check the usage page for your account.
3. **`~/agent-notes/redo-log.md`:** every time you had to redo a subagent's work, there's a line here (`/wrapup` adds them). If the same task appears again and again, send it to a stronger agent by changing the rules in `templates/agents/router.md`.

---

## Your notes folder

```
~/agent-notes/
├── index.md          one line per note; the agent reads this first
├── <topic>.md        one file per task (not per day)
├── lessons-inbox.md  lessons /wrapup proposed; you decide what to keep
├── redo-log.md       work you had to redo
└── evidence/         screenshots and exported logs (kept out of git)
```

- It has its own local git history with no remote. To undo a bad change: `cd ~/agent-notes && git log`, then `git checkout <commit> -- <file>`. Commit when you like: `git add -A && git commit -m "notes"`.
- **Once a month:** move the good lessons from `lessons-inbox.md` into the right skill by hand, delete them from the inbox, and delete notes for finished work.
- Lessons are **never** written into skills automatically. A wrong lesson saved automatically would be repeated in every later session, and nothing would warn you.
- Evidence can contain log lines from work systems. It stays on this laptop. Check what work allows before pasting it anywhere else.

To use another folder, install with `NOTES_DIR=/path/to/folder ./install.sh both`.

---

## Changing things

Edit the files in `templates/` and `presets/`, then run `./install.sh <preset>` again. Don't edit the installed files in `~/.config/opencode/` directly: the next install overwrites them.

---

## Uninstall

```bash
./uninstall.sh
```

This removes only the files the install script wrote, and its block in `AGENTS.md`. Your notes folder and your own files are left alone. Remove `"default_agent": "router"` from `opencode.json` yourself.

---

## Not yet confirmed

Everything not yet checked against a real opencode is listed in **[VERIFY.md](VERIFY.md)**, with how to check each item and what to change. In short:

| Group | Checks | Main risk if wrong |
|---|---|---|
| A. Environment | V01–V04: opencode is V2, config paths, model IDs, `default_agent` | Agents or commands not loaded at all |
| B. File format | V05–V11: permission rule format and order, subagent block, edit block, evidence folder, `steps`, skills, commands | Permissions do the opposite of what's intended, or silently do nothing |
| C. Browser | V12–V14: Browse tool names, text vs screenshots, Haiku on Observe | Browser work stays in the main session (expensive) |
| D. Routing | V15–V16: the right model really runs, rules are followed | No savings, without you noticing |
| E. Cost | V17–V19: Copilot billing type, Portkey cost view, pool split | Wrong pool for the heavy users |
| F. Work rules | V20: personal config, local evidence, log content to models | Policy breach. Ask before using. |

### If you are on opencode V1

V1 uses a different permission format in agent files: a `permission:` map instead of the `permissions:` list, and `tools:` to turn tools off. The model lines, descriptions and instructions still work. Rewrite only the `permissions:` blocks in `templates/agents/*.md` using the V1 agents docs, or upgrade opencode.

---

## Files in this repo

```
VERIFY.md             checklist of unconfirmed assumptions, for an agent on the work laptop
install.sh            install or switch preset (safe to re-run)
uninstall.sh          remove what install.sh wrote
presets/*.env         which model each agent uses, per budget situation
templates/agents/     router, explorer, deep-thinker
templates/commands/   /wrapup, /continue
templates/notes/      starting files for ~/agent-notes
templates/AGENTS.snippet.md   the block added to your global AGENTS.md
```
