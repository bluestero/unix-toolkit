# work-toolkit: notes for Claude

Shell toolkit (okcli, kx, ctx, twin, ws, tk, k-bg, k-theme, kitty config). Shared
look and helpers live in `lib/ui.sh`; every tool uses them.

## UI rules

- **Every choice is a picker.** Never a typed `[y/N]` or `read -p` line: ask yes/no
  with `confirm "question" [y|n]`, ask for text with `ui_ask "question" [prefill]`
  (both in `lib/ui.sh`). Asked from inside a list, the list must stay visible:
  the question goes in that list's header (amber frame, the row still
  highlighted; kx lists do it in `kube/lib/list.sh`), never in a box that replaces it.
  kx lists stay open throughout: actions run as fzf callbacks, slow work in the
  background with progress in the footer; results (✓ ✗) fade after 5 s. Logs
  stay full screen; a shell or port-forward opens in its own kitty tab (needs fzf 0.63+).
  Outside a list they open a small box.
- **Never leave the picker to ask.** This holds for every list, not only kx: yes/no
  questions *and* typed ones (a folder, a port, a name) open in the picker itself,
  in its header and prompt, the way `kube/lib/list.sh` does (`list_confirm`,
  `list_ask`); the list stays open before, during and after. A wrong answer never
  closes anything: the same question comes back with why it failed on top, in red,
  and the typed text kept so it can be fixed (`list_ask` retry). Only a screen that
  must be full (logs) or its own process (a shell, a port-forward: its own kitty tab) leaves.
  Any other picker that reports a result does it the same way, in the footer:
  `ui_fzf --toast` and its key prints `ui_toast "✓ …"` (fzf 0.63+); never in the header.
- Pick from a list with `ui_fzf`. Pickers fill the window (fzf's own screen, clean on
  resize); don't pass a smaller `--height` (only `confirm` and `ui_ask` do). Its `--header='key: what · key: what'` is styled
  by `ui_keys` (keys coloured, words grey, divider under the hints).
- A table in a picker: title row first with `--header-lines=1` (raw `\x1f` cells are laid
  out by `ui_fzf`). Layout (`print_table`): gap 3 minimum, grows to 8 with spare width;
  when too narrow only the widest columns are cut with …, and the footer shows the full value of the cut cell under the cursor (sortable \x1f tables
  also re-lay out when the window is resized). Add `--sortable` to sort it by column (alt-s, alt-←→, click a title; alt-shift-←→ moves the column);
  `grep -rn -- --sortable` lists every sortable picker. Its title row is the last line of
  fzf's header: a sortable picker that changes its header passes the new one through
  `ui_sort_keys` (plain key hints, wrapped again on resize) or `ui_sort_header`, or the
  titles vanish.
- Spelled-out words, few options. Risky actions default to No; on prod, typing the
  name confirms.
- Never use faint (SGR 2): greys are 248 for text, 244 for lines. Rounded boxes.
- Don't bind keys kitty uses: ctrl+n, ctrl+w, ctrl+[ / ctrl+], ctrl+c, ctrl+v.
  Ctrl+Shift+drag is kitty's rectangle select.

## Working here

- Commit or push only when asked. Several sessions may edit at once: commit only
  your own changes.

## Coding guidelines

Behavioral guidelines to reduce common LLM coding mistakes. Merge with project-specific instructions as needed.

**Tradeoff:** These guidelines bias toward caution over speed. For trivial tasks, use judgment.

### 1. Think Before Coding

**Don't assume. Don't hide confusion. Surface tradeoffs.**

Before implementing:
- State your assumptions explicitly. If uncertain, ask.
- If multiple interpretations exist, present them - don't pick silently.
- If a simpler approach exists, say so. Push back when warranted.
- If something is unclear, stop. Name what's confusing. Ask.

### 2. Simplicity First

**Minimum code that solves the problem. Nothing speculative.**

- No features beyond what was asked.
- No abstractions for single-use code.
- No "flexibility" or "configurability" that wasn't requested.
- No error handling for impossible scenarios.
- If you write 200 lines and it could be 50, rewrite it.

Ask yourself: "Would a senior engineer say this is overcomplicated?" If yes, simplify.

### 3. Surgical Changes

**Touch only what you must. Clean up only your own mess.**

When editing existing code:
- Don't "improve" adjacent code, comments, or formatting.
- Don't refactor things that aren't broken.
- Match existing style, even if you'd do it differently.
- If you notice unrelated dead code, mention it - don't delete it.

When your changes create orphans:
- Remove imports/variables/functions that YOUR changes made unused.
- Don't remove pre-existing dead code unless asked.

The test: Every changed line should trace directly to the user's request.

### 4. Goal-Driven Execution

**Define success criteria. Loop until verified.**

Transform tasks into verifiable goals:
- "Add validation" → "Write tests for invalid inputs, then make them pass"
- "Fix the bug" → "Write a test that reproduces it, then make it pass"
- "Refactor X" → "Ensure tests pass before and after"

For multi-step tasks, state a brief plan:
```
1. [Step] → verify: [check]
2. [Step] → verify: [check]
3. [Step] → verify: [check]
```

Strong success criteria let you loop independently. Weak criteria ("make it work") require constant clarification.
