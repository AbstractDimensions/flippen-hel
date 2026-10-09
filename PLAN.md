# FLIPpen Hel Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rebuild `FlipRunner.ps1` into FLIPpen Hel per `SPEC.md`: fix serial RX, fix autoisp/hex bugs, Flip-faithful face, firmware-reset help window, pop-out terminal, smart device/COM handling.

**Architecture:** Single-file PowerShell + WinForms app (no new files except `PLAN.md`/`SPEC.md` already present); main form + 2 owned windows (terminal, reset-help); UI-thread timer polling replaces all serial events.

**Tech Stack:** Windows PowerShell 5.1, .NET WinForms / System.IO.Ports (built-in only), `batchisp.exe` CLI, SDCC firmware untouched.

**Spec:** `C:\Users\Louis\OneDrive\Documents\CodeBlocks\FlipRunner\SPEC.md`

## Global Constraints

- PowerShell + built-in .NET only — no new dependencies, no installs.
- No git commits anywhere in this tree (no repo) — "done" = file saved + parser-clean.
- Parser gate for every code task: `$errs.Count` must be `0` via `[System.Management.Automation.Language.Parser]::ParseFile`.
- NEVER write `New-Object Drawing.Point(a, b <op> c)` with a spaced expression
  — it throws at runtime (SPEC §3.4). Precompute or parenthesize: `($yy + 3)`.
- Parser gate for every code task: `$errs.Count` must be `0` via `[System.Management.Automation.Language.Parser]::ParseFile`.
- Firmware snippet stays the verified `__asm ljmp 0 __endasm` form — never reintroduce the `(code *)` cast.
- `batchisp -autoisp` takes TWO args (`1 0`); never emit the one-arg form.
- Afrikaans only in title/subtitle/logo — grep-verify in Task 3.
- RS232 8051 scope only; signature/security boxes stay display-only.

## Review Focus

1. COM port unplugged mid-session → status OFF + human message, no red text. (Pinned: Task 1 test.)
2. Remembered hex deleted/renamed → visible fallback notice naming the file picked, never a silent wrong flash. (Pinned: Task 2 test.)
3. `batchisp` nonzero exit → message names device/port/baud/ISP-mode. (Pinned: Task 2 test.)
4. Tally scan over a huge Downloads → completes in seconds, never freezes the UI (bounded globs, filenames-only outside code). (Pinned: Task 7 test.)
5. Modal help dialog open → main-form shortcuts must not fire, dialog's own Ctrl+Shift+C must. (Pinned: Task 5 test.)

---

### Task 1: Serial RX poll (fixes §3.1 no-output bug + event leak)

**Files:**
- Modify: `FlipRunner.ps1` (`Open-Serial`, `Close-Serial`, timers, `Add_FormClosing`)

**Interfaces:**
- Consumes: nothing new.
- Produces: `$script:port` (`SerialPort` or `$null`); `$pollTimer` (`Forms.Timer`, 50 ms, appends `ReadExisting()` output to the terminal log when `BytesToRead -gt 0`); `Open-Serial`/`Close-Serial` register ZERO event subscribers.

- [ ] **Step 1: Delete the event approach.** Remove `Register-ObjectEvent … DataReceived` from `Open-Serial` and the `BeginInvoke([action]…)` line; remove the `Get-EventSubscriber … Unregister-Event` cleanup if nothing else uses it.
- [ ] **Step 2: Add `$pollTimer`.** 50 ms `Forms.Timer`; on tick, if `$script:port` open and `BytesToRead -gt 0`, append `ReadExisting()` to the terminal log control (name it `$termLog` now — Task 6 reuses it). Start/stop with connect/disconnect.
- [ ] **Step 3: Parser gate.** Run: `[void][System.Management.Automation.Language.Parser]::ParseFile('…\FlipRunner.ps1',[ref]$null,[ref]$errs); $errs.Count` — Expected: `0`.
- [ ] **Step 4: Smoke test.** Launch app, screenshot main window, close via window X, kill process. Expected: window renders, no console errors on launch/close; unplug-port case logs a human message (Review Focus 1).

### Task 2: Flash-flow corrections (§3.2, autoisp, §4.2)

**Files:**
- Modify: `FlipRunner.ps1` (`Run-BatchIsp`, `btnRun` click, `Update-HexInfo`, startup hex validation)

**Interfaces:**
- Consumes: `$pollTimer`/`$script:port` from Task 1 (port released before flash, reopened after only if it was open).
- Produces: `Run-BatchIsp($extraOp)` builds `-autoisp 1 0` (two args, omitted when unchecked); startup logs which hex file + variant (Debug/Release) is selected or fell back to.

- [ ] **Step 1: Two-arg autoisp.** Change `$auto = '-autoisp 1'` → `'-autoisp 1 0'`; keep flag omitted when the checkbox is off.
- [ ] **Step 2: Visible hex validation.** At startup: if remembered hex missing → newest-hex fallback + log `remembered hex not found, using <file>`; `Update-HexInfo` labels Debug vs Release from the path.
- [ ] **Step 3: Parser gate** (same command as Task 1). Expected: `0`.
- [ ] **Step 4: Dry-run verify.** With no board attached, press Run. Expected: human message naming device/port/baud/ISP-mode (Review Focus 2+3), no red exception text, nothing thrown to console.

### Task 3: Rebrand to FLIPpen Hel (§4.1)

**Files:**
- Modify: `FlipRunner.ps1` (title, subtitle label, logo text); rename Desktop `FlipRunner.lnk` → `FLIPpen Hel.lnk` (retarget, same target).

**Interfaces:**
- Consumes: none. Produces: title `FLIPpen Hel`, subtitle `maar .hex loading vat lank`, logo block same geometry.

- [ ] **Step 1: Title + subtitle + logo.** Set `form.Text`, add/adjust subtitle label directly under the title area, swap logo text. Touch nothing else.
- [ ] **Step 2: Shortcut rename.** Recreate the `.lnk` as `FLIPpen Hel.lnk`, delete the old one.
- [ ] **Step 3: Afrikaans quarantine grep.** Run: `Select-String -Path FlipRunner.ps1 -Pattern '(?i)vat lank|FLIPpen Hel' | Measure-Object` plus manual scan for any other non-English string. Expected: hits only in title/subtitle/logo lines (acceptance test 7).
- [ ] **Step 4: Parser gate + screenshot.** Expected: `0` errors; screenshot shows new title.

### Task 4: Flip-faithful face + Settings relocation (§4.2)

**Files:**
- Modify: `FlipRunner.ps1` (menu, toolbar, 3 panels, connection row removal)

**Interfaces:**
- Consumes: control names from Tasks 1–2. Produces: `Settings` menu owning COM selector, ISP/monitor baud, device entry (§4.8 submenu in Task 7), DTR/RTS, pulse, Browse/Newest-hex; main face = menu + toolbar + 3 panels + status bar only.

- [ ] **Step 1: Move extras to Settings.** Relocate COM/baud/device/DTR/RTS/pulse/hex-picking into `Settings` menu items reusing existing handlers; delete the connection row from the main face.
- [ ] **Step 2: Match Flip geometry.** Align Operations-Flow radios/checkboxes, Run bottom-left, AutoISP beneath; buffer panel fields; right-panel rows incl. `Start Application` + `Reset`-checkbox row. Compare against the reference screenshot in chat.
- [ ] **Step 3: Parser gate + screenshot.** Expected: `0`; screenshot side-compared with Flip reference.

### Task 5: `firmware reset` + (?) help dialog (§4.3)

**Files:**
- Modify: `FlipRunner.ps1` (right panel buttons, `$ResetMagic`, `$FirmwareSnippet`, new modal `$helpForm`)

**Interfaces:**
- Consumes: `$script:port` (send `!!!RESET!!!`+CRLF only when open). Produces: dialog-local Ctrl+Shift+C; main face has NO copy button.

- [ ] **Step 1: Rename + (?) button.** `FW Reset` → full `firmware reset` (same width family as Start Application); circled-`?` button immediately right opens the modal.
- [ ] **Step 2: Help dialog.** Modal, scrollable text (what reset does / does NOT do — no bootloader over TX/RX — wiring notes, snippet), `Copy code` button → clipboard; Ctrl+Shift+C wired on the dialog; delete old main-face copy button + its global shortcut entry.
- [ ] **Step 3: Review-Focus-5 check.** With dialog open, press F5 → main must NOT run; Ctrl+Shift+C → clipboard gets the `ljmp` snippet. Expected: both hold.
- [ ] **Step 4: Parser gate.** Expected: `0`.

### Task 6: Pop-out terminal (§4.4)

**Files:**
- Modify: `FlipRunner.ps1` (new owned `$termForm` with `$termLog`, send box, Clear, Disconnect, DTR/RTS indicators)

**Interfaces:**
- Consumes: `$pollTimer` output target becomes `$termLog` (Task 1 named it); `$script:port`. Produces: `Show-Terminal`/`Hide-Terminal`; auto-show on first RX bytes while hidden; close = hide, stay connected.

- [ ] **Step 1: Extract terminal.** Move log/send/clear/DTR/RTS into `$termForm` (owned by main, title shows port+baud); main keeps no embedded log. Ctrl+T toggles connect AND shows terminal.
- [ ] **Step 2: Auto-pop.** In poll tick: first `ReadExisting()` bytes while hidden → `Show-Terminal`. Closing (X) hides only; Disconnect button drops the port.
- [ ] **Step 3: Parser gate + smoke.** Expected: `0`; launch → connect with no device → no pop; close window → status still ON.

### Task 7: COM steadiness + device guess (§4.5, §4.8)

**Files:**
- Modify: `FlipRunner.ps1` (`Get-ComPortsFiltered`, `Settings → Device` submenu, `FlipRunner.json` gains `RecentDevices[]`); keep existing rescan triggers.

**Interfaces:**
- Consumes: Settings menu from Task 4. Produces: `Invoke-DeviceGuess` → token or `$null`; MRU list persisted, most-recent-first.

- [ ] **Step 1: Keep + verify filter.** Keep WMI Bluetooth exclusion + raw-list fallback; verify against live `Win32_SerialPort` output on this machine.
- [ ] **Step 2: MRU.** Append chosen device to `RecentDevices[]` on successful flash (dedupe, cap 5); submenu lists them first.
- [ ] **Step 3: Device-wide tally.** Harvest tokens from `PartDescriptionFiles\*.xml` NAMEs; score code contents (weight 2, `*.c;*.h;*.cbp` under CodeBlocks root) + doc filenames (weight 1, Documents/Downloads, filenames only, skip hidden); preselect winner on empty preference only; fallback `AT89C51RD2`.
- [ ] **Step 4: Bound check.** Run tally timed on this machine. Expected: completes in seconds (Review Focus 4); then parser gate `0`.

### Task 8: Acceptance pass (§6)

**Files:** none (verification only).

- [ ] **Step 1: Run acceptance tests 1–7** against the finished app with FlipRunnerTest (flash real hardware for test 2).
- [ ] **Step 2: Log any failure** back against its SPEC section; fix forward in the owning task's style, re-run parser gate.

## Round 2 (SPEC §8 — user review feedback, 2026-10-08)

Global Constraints still apply (parser gate, ASCII-only, no spaced-expression
`Point/Size`, no new deps, no Afrikaans additions, no commits). New risks:
picker dialog must be modal to main (`ShowDialog($form)`) or it hides;
json gains `RecentHex[]` + `CollapsedSig` — old files must default cleanly;
collapse toggle must reflow, not leave dead space.

### Task 9: Header + grey toolbar icons

**Files:** Modify `FlipRunner.ps1` (logo/subtitle labels, toolbar buttons).
**Interfaces:** Consumes: existing toolbar buttons/handlers. Produces: `New-GreyIcon(name)` helper returning a 16×16 grey bitmap; unchanged handler names.
- [ ] **Step 1: Single header.** Middle-panel logo keeps exact text, adds Italic; subtitle moves directly beneath it; delete the old toolbar subtitle label.
- [ ] **Step 2: Icons.** Code-drawn grey GDI icons (chip, folder, play, start, reset-arrow, terminal) on each toolbar button; text labels retained.
- [ ] **Step 3: Parser gate + screenshot.** Expected: `0`; header + icons visible.

### Task 10: Working HEX selector + freshness

**Files:** Modify `FlipRunner.ps1` (middle-panel HEX row, `Invoke-BrowseHex`, json `RecentHex[]`).
**Interfaces:** Produces: `$cmbHex` (ComboBox, MRU cap 8 persisted); `Update-HexFreshness`; `Invoke-BrowseHex` opens modal picker; selection updates info + freshness + `Next` field (Task 11 reads them).
- [ ] **Step 1: Fix picker.** Diagnose why it never opens (owner/visibility/handler reachability); make it modal to main; keep `Invoke-NewestHex` working.
- [ ] **Step 2: MRU ComboBox.** Replace read-only box; add-picked/add-flashed/add-newest to `RecentHex[]` (dedupe, cap 8, persist); full path in tooltip.
- [ ] **Step 3: Freshness + watcher.** Relative-age label (`built Xm ago`, timer + focus refresh); newer-build indicator vs CodeBlocks `bin\*\*.hex` with click-to-switch; never auto-switch.
- [ ] **Step 4: Parser gate + screenshot.** Expected: `0`; age label visible.

### Task 11: State clarity + Device menu fix

**Files:** Modify `FlipRunner.ps1` (status strip, `Update-DeviceMenu`, action handlers).
**Interfaces:** Produces: status `State` + `Next` fields refreshed by every action (flash/connect/reset/hex-pick); working Device submenu.
- [ ] **Step 1: Fix Device submenu.** Diagnose non-working MRU menu; MRU click sets device; manual entry retained.
- [ ] **Step 2: State/Next strip.** `State`: hex filename + age • device • port. `Next`: context suggestion after every action. Full-path tooltips on hex/device fields.
- [ ] **Step 3: Parser gate + screenshot.** Expected: `0`; strip legible.

### Task 12: Collapsible signature block

**Files:** Modify `FlipRunner.ps1` (right device panel).
**Interfaces:** Produces: `▸/▾` toggle; `CollapsedSig` persisted; default collapsed.
- [ ] **Step 1: Toggle.** Hides display-only rows (signature/boot/hw/security/note); action buttons stay; panel reflows without dead space.
- [ ] **Step 2: Parser gate + screenshot (both states).** Expected: `0`.

### Task 13: Button stack + capitalization

**Files:** Modify `FlipRunner.ps1` (right panel, tooltips).
**Interfaces:** Produces: vertical stack Start Application → firmware reset + ? → Serial: Connect/Disconnect (same connect handler as toolbar/Ctrl+T).
- [ ] **Step 1: Restack + relabel** to Title Case list (SPEC §8); update affected tooltips; toolbar labels match.
- [ ] **Step 2: Parser gate + screenshot.** Expected: `0`; caps consistent.

### Task 14: Round-2 acceptance

**Files:** none (verification only).
- [ ] **Step 1: Checklist** — picker opens; MRU persists across restart; age label ticks; collapse persists; caps consistent; no new Afrikaans; stderr empty on launch; hardware flash + terminal pop + reset still pass (needs board).
- [ ] **Step 2: Log failures** against SPEC §8; fix forward.

## Round 3 (SPEC §9 — second user review, 2026-10-08)

Same Global Constraints (parser gate, ASCII-only, parenthesized Point/Size,
no new deps, no Afrikaans additions, no commits). New risks: modeless dialogs
must not allow conflicting edits mid-flash (guard Run while Settings open or
re-read on Run); CLI mode must never create windows (headless parser-safe).

### Task 15: Header spacing + drop debug label

**Files:** Modify `FlipRunner.ps1` (logo/subtitle labels, delete batchisp label).
- [ ] **Step 1: Bigger subtitle tucked under the italic title; delete the
  `batchisp:` debug label** (path stays auto-detected; surface it in
  Settings only). Reflow middle panel, no overlaps.
- [ ] **Step 2: Parser gate + screenshot.** Expected: `0`.

### Task 16: Collapse that never moves buttons

**Files:** Modify `FlipRunner.ps1` (`Set-SigCollapsed`, saved positions).
- [ ] **Step 1: Buttons frozen** — Start Application / firmware reset / ? /
  Serial keep identical coordinates both states; collapse hides rows and
  pulls the panel bottom edge up under the buttons. Update saved-position
  logic accordingly; persist unchanged.
- [ ] **Step 2: Parser gate + screenshot (both states).** Expected: `0`.

### Task 17: Icon-above-label toolbar

**Files:** Modify `FlipRunner.ps1` (toolbar buttons only).
- [ ] **Step 1: `TextImageRelation = ImageAboveText`** on toolbar buttons;
  row stays directly under the menu; grey icons + labels retained.
- [ ] **Step 2: Parser gate + screenshot.** Expected: `0`.

### Task 18: Modeless Settings + help

**Files:** Modify `FlipRunner.ps1` (Settings dialog, help dialog show calls).
- [ ] **Step 1: `Show()` owned modeless instead of `ShowDialog()`** for both;
  settings apply on change and persist on close (save in close handler +
  after each control change, or re-read live at Run time); guard or re-read
  so an open Settings can't desync a flash.
- [ ] **Step 2: Parser gate + screenshot.** Expected: `0`.

### Task 19: Serial Auto mode

**Files:** Modify `FlipRunner.ps1` (connect button, poll tick, Settings toggle, json).
- [ ] **Step 1: Default `Serial: Auto`** — auto-open terminal on first RX
  while open; click = connect (if needed) + open terminal; Settings toggle
  `Serial auto-open on RX data` (default ON, persisted); OFF restores manual
  Connect/Disconnect text and no auto-pop.
- [ ] **Step 2: Parser gate + screenshot.** Expected: `0`.

### Task 20: Headless CLI for AI/automation

**Files:** Modify `FlipRunner.ps1` (param block + CLI branch before any GUI code).
- [ ] **Step 1: `-Cli -Action Flash|Reset|Monitor`** with `-Hex -Device
  -Port -IspBaud -MonBaud -Seconds`; zero windows; `FLIPHEL OK|FAIL …` stdout
  lines; exit 0/1. Flash reuses the exact batchisp construction as Run;
  Reset sends the magic; Monitor streams RX to stdout N seconds.
- [ ] **Step 2: Verify headless** — run `Flash` against missing port,
  expect `FLIPHEL FAIL …` + exit 1, no window. Document MCP-wrapper
  follow-up in SPEC (done in §9).
- [ ] **Step 3: Parser gate.** Expected: `0`.

### Task 21: Round-3 acceptance

**Files:** none (verification only).
- [ ] **Step 1: Checklist** — header spacing; buttons frozen across collapse;
  toolbar layout; click-out works and settings stick; Auto mode pops on RX
  and respects OFF; CLI flash/reset/monitor headless; no new Afrikaans;
  stderr empty; hardware pass (needs board).
- [ ] **Step 2: Log failures** against SPEC §9; fix forward.

## Round 4 (SPEC §10 — third user review, 2026-10-08)

Same Global Constraints plus: staged batchisp calls must preserve the exact
single-flow semantics (same flags, same order, abort-on-first-failure);
auto-port-retry must never flash a port the user didn't select without
logging each attempt loudly; modeless rules from Task 18 still hold.

### Task 22: Research the real Flip UI (read-only)

**Files:** none (research only — do NOT modify the ps1).
- [ ] **Step 1: Launch real Flip** (`Flip 3.4.7\bin\flip.exe`), screenshot
  it via CopyFromScreen, read the shot; kill Flip afterwards. Never touch
  COM ports from Flip.
- [ ] **Step 2: Read its help docs** (`help\operations_summary.htm`,
  `selecting_a_device.htm`, `selecting_a_communication_medium.htm`,
  `operations_directives_summary.htm`, `setup_directives_summary.htm`) for
  what each toolbar button/menu does.
- [ ] **Step 3: Deliver a toolbar map** — exact left-to-right order,
  grouping, and one-line purpose of every Flip toolbar button + menu
  (File/Buffer/Device/Settings/Help), plus which are redundant with each
  other. Report as file-agnostic list; implementation is Task 23.

### Task 23: Menu-on-top + mirrored toolbar, all wired

**Files:** Modify `FlipRunner.ps1` (menu strip dock order, toolbar construction).
- [ ] **Step 1: Fix order** — menu row truly first, icon row beneath
  (IconAboveText retained). Mirror the Task-22 map order/grouping, redundant
  items included; every button keeps grey icon + label + tooltip.
- [ ] **Step 2: Wire everything** — no dead buttons/menus (details in
  Task 27's audit; Device menu gets its picker here if trivially close,
  else there).
- [ ] **Step 3: Parser gate + screenshot.** Expected: `0`.

### Task 24: Tooltip audit (everything elaborates)

**Files:** Modify `FlipRunner.ps1` (tooltips only).
- [ ] **Step 1: Every visible control** (buttons, checkboxes, radios,
  combos, text fields, toggle, panels' key rows, status fields) gets an
  elaborating tooltip: what it does + consequence + shortcut if any.
- [ ] **Step 2: Parser gate.** Expected: `0`. (Visual proof is hover-only;
  reviewer spot-checks count of `SetToolTip`/`ToolTipText` calls.)

### Task 25: Obvious COM + auto-retry

**Files:** Modify `FlipRunner.ps1` (port display, `Run-BatchIsp`, CLI Flash).
- [ ] **Step 1: `(auto)` tagging** wherever the port appears (combo,
  State strip, terminal title) when it came from auto-select vs explicit pick.
- [ ] **Step 2: Retry** — on flash failure, automatically retry the FULL
  staged flow on the next non-Bluetooth port (skip the failed one), logging
  each attempt; only fail after all ports exhausted. CLI gains the same retry
  (log attempts to stdout).
- [ ] **Step 3: Parser gate.** Expected: `0`.

### Task 26: Run progress popup (staged flash)

**Files:** Modify `FlipRunner.ps1` (Run path, new popup form).
- [ ] **Step 1: Split Run into staged batchisp calls** (Erase / Blank-check /
  Program / Verify / Start — LOADBUFFER wherever needed, same flags/order,
  abort on first failure so semantics match the old single call).
- [ ] **Step 2: Popup** with overall + per-stage progress bars and stage
  labels, log tail, and Cancel (kills the running batchisp). Modeless-safe:
  works with Settings open (snapshot-at-click rule stands).
- [ ] **Step 3: Parser gate.** Expected: `0`.

### Task 27: Device menu + full clickability audit, then launch

**Files:** Modify `FlipRunner.ps1` (menus); then launch.
- [ ] **Step 1: Working top-level Device menu** (picker: MRU + guess +
  manual entry — reuse Task 7/11 pieces); Buffer menu gets real hex-buffer
  info actions; audit EVERY toolbar button and menu item — each does
  something real or is removed.
- [ ] **Step 2: Parser gate.** Expected: `0`.
- [ ] **Step 3: Launch for the user** — start the GUI with stderr/stdout
  captured to `Temp\opencode\live_*.txt`, LEAVE IT RUNNING, report PID +
  screenshot. (Reviewer handles the visual check + log read.)

### Task 28: Round-4 acceptance

**Files:** none (verification only).
- [ ] **Step 1: Checklist** — menu truly on top; toolbar mirrors Flip map;
  all tooltips elaborate; `(auto)` port tags; retry logged; progress popup
  with real stages + cancel; every menu/toolbar item functional; app left
  running with readable logs; hardware pass (needs board).
- [ ] **Step 2: Log failures** against SPEC §10; fix forward.
