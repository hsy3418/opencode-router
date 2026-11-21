# VERIFY.md — checks to run on the work laptop

This setup was written and tested on a personal laptop **without opencode installed**. The install scripts were tested. The opencode-specific parts (file format, permission names, paths, behaviour) were taken from the opencode docs and **not run against a real opencode**. This file lists every assumption so an agent on the work laptop can check them one by one.

---

## Instructions for the agent doing these checks

1. Work through the checks in order. Each one has: **Assumption**, **Why it matters**, **How to check**, **Pass if**, **If it fails**.
2. Use the opencode docs for the version actually installed (`opencode --version`; the current docs are at https://opencode.ai/docs, and V1 docs are under https://opencode.ai/v1/docs).
3. **Do not edit files in `~/.config/opencode/` directly.** Fix the files in `templates/` or `presets/` in this repo, then run `./install.sh <preset>` again.
4. **Ask the user before you:** change which model or pool an agent uses, run `install.sh` with a preset they have not filled in, change anything outside this repo and `~/.config/opencode/`, or change an opencode setting managed by work.
5. Write results to `~/agent-notes/opencode-router-verify.md`, **not into this repo**. Results may hold internal names such as Portkey integration IDs. For each check write: ID, PASS / FAIL / SKIPPED, what you saw, and what you changed.
6. If a check can't be done (no access, no permission), mark it SKIPPED with the reason and go on.

---

## A. Environment and paths

### V01 — opencode is V2
- **Assumption:** opencode V2. The agent files use the V2 `permissions:` list.
- **Why:** V1 uses a different permission format (a `permission:` map, plus `tools:`). In V1 the `permissions:` blocks may be ignored or rejected.
- **How:** `opencode --version`; compare with the V2 agents docs.
- **Pass if:** V2.
- **If it fails:** rewrite only the `permissions:` blocks in `templates/agents/*.md` to the V1 format (V1 agents and permissions docs). Keep `model`, `description`, `mode` and the body text. Re-install.

### V02 — global config paths
- **Assumption:** global agents go in `~/.config/opencode/agents/`, commands in `~/.config/opencode/commands/`, and the global instructions file is `~/.config/opencode/AGENTS.md`.
- **Why:** if opencode reads another folder, nothing installed is used.
- **How:** check the docs (agents, commands, rules/AGENTS.md pages). After install, start opencode and see whether `router`, `explorer` and `deep-thinker` are listed and `/wrapup` and `/continue` show up.
- **Pass if:** all three agents and both commands show up.
- **If it fails:** install with `OPENCODE_CONFIG_DIR=<correct folder> ./install.sh <preset>`. If AGENTS.md lives somewhere else, move the block between `<!-- opencode-router:start -->` and `<!-- opencode-router:end -->` there.

### V03 — model IDs
- **Assumption:** model IDs look like `<provider-id>/<model-id>`, and the user's Portkey and Copilot providers are already connected in opencode.
- **Why:** a wrong ID means the agent fails, or silently uses another model.
- **How:** `opencode models`. Find Sonnet 5.5, Haiku 5.5 and Opus 5.5 for both Portkey and Copilot.
- **Pass if:** all six exist.
- **If it fails:** show the user the list and fill in the presets **with** them. Opus 5 was deliberately left out. Do not add other models without asking.

### V04 — `default_agent`
- **Assumption:** `"default_agent": "router"` in `~/.config/opencode/opencode.json` makes `router` the starting agent.
- **How:** docs (config / agents), then start a new session.
- **Pass if:** a new session starts on `router`.
- **If it fails:** find the right key in the docs. Until then the user presses Tab to pick `router`.

---

## B. Agent and command file format

### V05 — permission rules
- **Assumption:** each rule is `action` / `resource` / `effect` (`allow` / `ask` / `deny`), wildcards work, and **the last matching rule wins**. The action names used are `subagent`, `edit`, `shell` and `external_directory`.
- **Why:** if the order is reversed (first match wins), every "deny all, then allow some" block does the opposite of what was intended.
- **How:** read the V2 agents/permissions docs, then run V06 and V07.
- **Pass if:** the docs match, and V06 and V07 behave as described.
- **If it fails:** reorder the rules or rename the actions in the templates.

### V06 — main agent can only use our subagents
- **Assumption:** in `router.md`, `subagent` `*` → deny, then `explorer` and `deep-thinker` → allow, which blocks the built-in subagents (`general`, `explore`).
- **Why:** the built-in subagents use the main agent's model (Sonnet), so reading work would not get cheaper.
- **How:** in a `router` session, ask "use the general subagent to list files in this folder". Then ask for something that should go to `explorer`.
- **Pass if:** `general` is refused or not offered, and `explorer` works.
- **If it fails:** check the subagent IDs in opencode's agent list or the agents docs, and fix the `resource` values in `templates/agents/router.md`.

### V07 — explorer and deep-thinker cannot edit repo files
- **Assumption:** `edit` `*` → deny blocks edits. In `explorer`, a later rule allows edits only under `<notes>/evidence/**`.
- **How:** ask `explorer` (through the router) to change a line in a repo file. Then run a log dive and check that the evidence files are written.
- **Pass if:** the repo edit is refused, and the evidence is written.
- **If it fails:** fix the rule order or the resource pattern.

### V08 — evidence folder outside the project
- **Assumption:** `external_directory` with an absolute path glob (`/Users/<you>/agent-notes/evidence/**`) lets `explorer` write there. `install.sh` writes the absolute path, because `~` may not be expanded.
- **How:** run a log dive and watch for permission prompts.
- **Pass if:** at most one approval, then evidence is written.
- **If it fails:** check the docs for `external_directory`. It may need the folder without `/**`, or a separate `read` rule. Fix it in `templates/agents/explorer.md`.

### V09 — `steps`
- **Assumption:** `steps` is the maximum number of **model steps** for a subagent run. On the last step opencode removes tools and asks for a summary. It is not exactly a tool-call count.
- **How:** docs; watch one `explorer` run.
- **Pass if:** a long run ends with a summary instead of running on.
- **If it fails:** change `EXPLORER_STEPS` / `HEAVY_STEPS` in the preset, or remove `steps` if V2 rejects it.

### V10 — skills reachable from explorer
- **Assumption:** the user's skills (for example the Observe log dive skill) can be loaded by `explorer`, because no `skill` rule blocks them.
- **How:** ask the router for a log dive and check that `explorer` loads the skill.
- **Pass if:** the skill loads.
- **If it fails:** add to `explorer.md` under `permissions:` (adjust the pattern to the user's skill names):
  ```yaml
    - action: skill
      resource: "*"
      effect: allow
  ```

### V11 — commands
- **Assumption:** command files use frontmatter `description`, the body is the prompt, and `$ARGUMENTS` is replaced by what follows the command. With no `agent` field, the command runs on the current agent.
- **How:** run `/continue test-topic` and `/wrapup test-topic`.
- **Pass if:** the topic appears in what the agent does, and `/wrapup` writes to `~/agent-notes/` and edits no skill.
- **If it fails:** fix the placeholder or frontmatter using the commands docs.

---

## C. Browser (opencode Browse)

### V12 — Browse tool names and permissions
- **Assumption:** Browse is an MCP server whose tools share a name prefix, and permission `action` patterns can match MCP tool names. **The names are unknown.**
- **Why:** browser checks must run in `explorer`, so page data stays out of the main session.
- **How:** list the Browse tools in opencode. Check the docs for how MCP tools are named in permission rules.
- **Pass if:** you can write one pattern that matches all Browse tools.
- **If it passes:** add `allow` for that pattern to `templates/agents/explorer.md` and `deny` to `templates/agents/router.md` (see README step 7), then re-install.

### V13 — text or screenshots
- **Assumption:** none. The Browse page doesn't say how pages are read.
- **How:** do one Observe log dive and look at the Portkey log for that run: number of calls, tokens, cost.
- **Report:** tokens and cost for one log dive. This is the baseline.

### V14 — Haiku can drive Observe
- **Assumption:** Haiku is good enough for the log dive.
- **How:** run the same log dive twice: once through `explorer` (Haiku), once directly in a Sonnet session. Compare cost, and whether the findings match.
- **Report:** both costs and whether the results matched. **Ask the user** before moving `explorer` (or browser work) to Sonnet.

---

## D. Does routing actually happen?

### V15 — the right model runs
- **Assumption:** each subagent really runs on the model in its `model` field. (Users of other tools have reported subagents silently running on the parent's model.)
- **How:** after the README tests, open the Portkey logs and check the model of each call.
- **Pass if:** `explorer` calls show Haiku, `deep-thinker` calls show Opus, and the rest show Sonnet.
- **If it fails:** report it to the user. Do not work around it without asking.

### V16 — the router follows the rules
- **Assumption:** the main agent follows the routing rules most of the time. They are instructions, not enforcement.
- **How:** run the 7 tests in the README, section "Check that it works".
- **Report:** which tests went to the expected agent and which didn't. If one fails often, suggest a wording change to the user. Don't make it on your own.

---

## E. Cost and billing

### V17 — Copilot billing type
- **Assumption:** the work Copilot plan uses **usage-based (token) billing**. GitHub moved to this on 1 June 2026; the older per-request billing remains only for some annual personal plans.
- **Why:** with per-request billing, long agent runs would be cheap on Copilot and many small calls expensive, which would change the pool split.
- **How:** the Copilot usage/billing page the user can see, or ask the user to ask their Copilot admin.
- **Report:** billing type.

### V18 — Portkey cost view
- **Assumption:** the user can filter Portkey logs by model and by cost.
- **How:** open the Portkey logs/analytics page.
- **Report:** whether this works, and the exact filter steps (the user needs them for the weekly check).

### V19 — pool split in `presets/both.env`
- **Assumption (guess):** `explorer` on Copilot, `router` and `deep-thinker` on Portkey.
- **How:** nothing to check now. After one week, compare spend per pool.
- **Report:** a suggestion only. The user decides.

---

## F. Work rules (ask the user; do not decide)

### V20 — allowed to use
- Personal repo and personal opencode config on the work laptop.
- Log lines and screenshots from work systems stored in `~/agent-notes/evidence/` on the laptop.
- Log content being sent to models through Portkey and Copilot, not only code.

Write down what the user says. If any answer is "no" or "not sure", stop and tell the user which parts of the setup are affected.
