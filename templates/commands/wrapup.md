---
# Managed by opencode-router. Edit the template in the repo, then re-run install.sh.
description: Save this session to my notes and propose lessons (does not edit skills)
---

Summarise this session into my personal notes in `{{NOTES_DIR}}`. Topic (may be empty): $ARGUMENTS

1. Pick a short topic name in kebab-case (use the topic above if given). Check `{{NOTES_DIR}}/index.md` for an existing note on the same task and reuse it.
2. Create or update `{{NOTES_DIR}}/<topic>.md` with these sections:
   - **Goal**
   - **Done**
   - **Left to do**
   - **Decisions** (and why)
   - **Useful references** — repo names, file paths, URLs, ticket IDs. No secrets, no tokens, no customer or account data.
   - **Lessons** — problems we hit and what worked
3. Add or update one line for this note in `{{NOTES_DIR}}/index.md`: `- <topic>.md — <one-line description> (updated YYYY-MM-DD)`
4. For each lesson that would help next time, append to `{{NOTES_DIR}}/lessons-inbox.md`:
   - the lesson
   - which skill it belongs in (or "AGENTS.md" or "none")
   - the exact text to add
5. If I had to redo work done by a subagent in this session, append one line to `{{NOTES_DIR}}/redo-log.md`: `YYYY-MM-DD | task | agent | what was wrong`
6. Do **not** edit any skill or agent file. Show me the list of proposed lessons at the end.
