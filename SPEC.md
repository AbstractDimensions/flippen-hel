# FLIPpen Hel — Design Spec

> Method: superpowers `brainstorming` (architectural path) → this spec →
> superpowers `writing-plans` (after user approves this spec) → implement.
> Classification: **architectural** — new app identity, new windows, restructured UI.
> Review trail: technical review by subagent 2026-10-08 (batchisp `-h`,
> live SDCC compile of both reboot forms, WMI property check, full-file reads);
> user answered architectural/visual questions 2026-10-08 (§7). No git repo
> anywhere in this tree, so spec + plan live beside the code in `FlipRunner\`.

## 1. Intent

Replace Atmel Flip 3.4.7's pain points for AT89LP51RD2 development (SDCC +
CodeBlocks, 11.0592 MHz, 9600 8N1) with a zero-install Windows GUI that:

- flashes as fast as pressing "run" locally (one button: erase → program →
  verify → start, remembering the last hex),
- shows chip output in a built-in serial monitor (Termite replacement),
- reboots the app over UART without touching the board or reflashing,
- looks like Atmel Flip so classmates/faculty feel at home,
- runs from a double-click with nothing to install (PowerShell + .NET
  WinForms only — no Python on these machines, only a Store stub).

Success = edit code in CodeBlocks → build → one click → see new output in
seconds, and share the folder with a friend who gets the same in seconds.

## 2. Context / current state (verified in repo)

| Item | Value |
|---|---|
| App (current name) | `Documents\CodeBlocks\FlipRunner\FlipRunner.ps1` (422 lines) + `FlipRunner.bat` launcher + Desktop `FlipRunner.lnk` |
| Config | `FlipRunner\FlipRunner.json` — currently `Device AT89C51RD2`, `Port COM3`, `IspBaud 115200`, `MonBaud 9600`, `AutoIsp true`, hex = `FlipRunnerTest\bin\Debug\FlipRunnerTest.hex` |
| Flasher backend | `C:\Program Files (x86)\Atmel\Flip 3.4.7\bin\batchisp.exe` (Atmel's own CLI — no decompile needed) |
| Device wrinkle | Flip 3.4.7 ships `AT89C51RD2.xml` but **no `AT89LP51RD2` part file** (verified: 123 part files listed, none match LP51; `batchisp -device AT89LP51RD2` → `Device does not exist`). App defaults to `AT89C51RD2` |
| Firmware test proj | `Documents\CodeBlocks\FlipRunnerTest\` — single-`main.c` SDCC project (`-mmcs51 --model-small`, `packihx` post-step), local copy of `AT89LP51RD2.H`, `bin\Release\FlipRunnerTest.hex` (verified compiling 2026-10-08) |
| Firmware behavior | UART 9600 8N1, prints `Hello from FlipRunnerTest!` + incrementing `count = N`; `UartResetPoll()` in loop reboots app on `!!!` |
| SDCC constraint | Installed SDCC 4.5.0 rejects `(void (code *)(void))0()` (`syntax error: token -> 'code'`); reboot MUST use `__asm ljmp 0 __endasm` (verified compiling). The `ljmp` form needs the SFR header (`EA`) — the snippet always ships with its `#include` note |
| Toolchain present | `C:\Program Files\SDCC\bin\{sdcc,packihx}.exe`, Node v22.23.2, NO Python, NO pnpm |

## 3. Diagnosed bugs (current app)

1. **No UART text output + console errors.** Root cause: RX uses
   `Register-ObjectEvent … DataReceived`, whose action runs as a PSEventJob in
   a separate runspace where `$form`/`$txtLog` resolve to `$null` — so every
   received byte throws into the console and nothing displays. (Note:
   `[action]` IS `[System.Action]` — the type was never the problem.)
   Secondary leak: every connect registers a new subscriber; `Close-Serial`
   never unregisters (only form-close does).
   **Fix direction:** delete the event approach AND the leak; poll
   `BytesToRead`/`ReadExisting()` on a UI-thread `Forms.Timer` (~50 ms) and
   append inline. No cross-thread marshaling, no console spam.
2. **Debug-vs-Release confusion.** Config points at `bin\Debug\…hex`, which
   EXISTS and is newer than the verified Release hex — so the risk is picking
   the wrong variant, not a missing file. The newest-hex fallback exists but
   is silent. **Fix:** validate the remembered hex at startup, fall back
   visibly (log which file + which variant), and label the variant in the UI.
3. **Port may be wrong machine-to-machine.** Config pins `COM3`. Keep the
   stored port as a preference only; always rescan at startup.
4. **Controls mispositioned + console spam (runtime, parser-invisible).**
   Any `New-Object Drawing.Point(a, <expr with spaces>)` — e.g. `$yy + 3`,
   `$cy - 1`, `$i * 40` — is parsed as THREE `New-Object` args and throws
   `Cannot find an overload for "Point"`, leaving the control unpositioned
   (device rows, connection row, log box all affected). The PS parser reports
   0 errors, so this only shows at runtime / in the console.
   **Fix direction:** never put a spaced expression inside `New-Object`
   args — precompute into a variable or parenthesize (`($yy + 3)`).

## 4. Requirements

### 4.1 Identity (only Afrikaans in the project — nowhere else)

- Window title: `FLIPpen Hel`, subtitle line under it: `maar .hex loading vat lank`.
- Desktop shortcut renamed to `FLIPpen Hel`. Middle-panel logo block keeps
  Flip's position/size but shows `FLIPpen Hel` instead of `ATMEL`.
- Internal file/variable names stay English. No other Afrikaans strings
  anywhere (code, comments, messages).

### 4.2 Main window mirrors Atmel Flip (reference: user's screenshot)

- Menu row: `File Buffer Device Settings Help` (same order).
- Icon toolbar row beneath it (text buttons acceptable, same left-to-right
  ideas: connect, load hex, run, start app, reset).
- Three panels, same positions/sizes as Flip:
  - Left `Operations Flow`: radio + checkbox rows `Erase`, `Blank Check`,
    `Program`, `Verify`; bold `Run` bottom-left; `AutoISP` checkbox beneath.
  - Middle `FLASH Buffer Information`: `Size`, `Range`, `Checksum`,
    `HEX File`, file actions, logo block (§4.1).
  - Right device panel: `Signature Bytes` (3), `Device Boot Ids` (2),
    `Hardware Byte` + `BLJB`/`X2`, `Bootloader Ver.`, `BSB / SBV`,
    `Security Level` (Level 0/1/2), `Start Application` button with `Reset`
    checkbox to its right (same row as Flip), status bar `Communication OFF/ON`.
- `Run` executes the full flow honoring the checkboxes:
  `MEMORY FLASH [ERASE F] [BLANKCHECK] LOADBUFFER "<hex>" [PROGRAM] [VERIFY]
  START RESET 0` via `batchisp.exe -device … -hardware RS232 -port …
  -baudrate <isp> [-autoisp 1 0]`. **The autoisp flag takes TWO args**
  (`-autoisp 1` alone → `Parameter is missing`); omit the flag entirely when
  unchecked. (Second-arg semantics unverified without hardware — pass `1 0`.)
  Operation order follows Atmel's left-to-right convention; note that
  batchisp parses even bogus keywords through to the port stage, so
  acceptance test 2 is the first real hardware proof of the order.
- `Start Application` (F6) runs `START RESET 0` only — no flash.
- All connection extras (COM selector, ISP/monitor baud, device name, DTR/RTS
  state, DTR pulse, Refresh, Browse/Newest-hex) move OUT of the main face
  into the `Settings` menu (and toolbar where Flip-like). Main face keeps only
  what Flip shows.

### 4.3 `firmware reset` button + (?) help window

- Right panel gets a full-name `firmware reset` button (below `Start
  Application`, same width family) with a circled-`?` button immediately to
  its right.
- `firmware reset` (Ctrl+R) sends `!!!RESET!!!` + CRLF on the open serial port;
  if closed, log `open serial first` instead of failing silently.
- The `?` opens a modal, scrollable explanation window containing: what the
  reset does (app reboot, NOT bootloader entry — TX/RX cannot enter the
  bootloader; that still needs the ISP hardware condition / BLJB / AutoISP
  wiring), wiring notes (DTR→RST Arduino-style for true hands-free), and the
  exact `UartResetPoll()` C snippet with a `Copy code` button inside the
  window. No standalone copy button on the main face anymore.
- The snippet's shortcut (Ctrl+Shift+C) is wired ON THE MODAL DIALOG itself
  (Copy button + dialog-level key handler) — the main form's KeyDown does not
  fire while a modal has focus, so a global-only shortcut would be dead. It is
  dialog-local, not global.
- Snippet MUST be the `__asm ljmp 0 __endasm` form (§2), with comment telling
  the user to call `UartResetPoll()` in `while(1)` and `#include` the SFR header.

### 4.4 Serial terminal = separate pop-out window

- UART log/send lives in its OWN window (Termite replacement), not embedded.
- It pops open automatically the moment incoming UART data is detected
  (first `ReadExisting()` returns bytes while the window is hidden).
- Manual control too: `Settings`/toolbar `Terminal` toggle + Ctrl+T connect
  implies showing it. Closing the window HIDES it and stays connected
  (decided); disconnect is explicit via the Terminal's Disconnect button.
- Terminal contents: monospace scrolling log, send box (Enter sends + CRLF),
  Clear (Ctrl+L), DTR/RTS indicators, port+baud in its title bar.

### 4.5 COM auto-detect, Bluetooth ignored

- Rescan at startup, on Settings→Port submenu open, on `Refresh`, and every
  ~3 s while disconnected and no dropdown is open.
- Exclude any port whose WMI (`Win32_SerialPort`) description/PNP ID matches
  `Bluetooth|BTH|RFCOMM|btport|BlueSoleil|BTENUM`; if WMI yields nothing,
  fall back to the raw list rather than an empty box. Never auto-switch away
  from the user's selected port while connected.

### 4.6 Shortcuts, all revealed on hover

| Action | Key | Scope | Tooltip shows |
|---|---|---|---|
| Run full flow | F5 | main | yes |
| Start Application | F6 | main | yes |
| Load HEX / Newest hex | Ctrl+O | main | yes |
| Terminal connect/disconnect | Ctrl+T | main | yes |
| firmware reset | Ctrl+R | main | yes |
| Copy snippet | Ctrl+Shift+C | help dialog only | yes (on dialog) |
| Clear terminal | Ctrl+L | terminal | yes |

Every major button AND toolbar item carries a tooltip naming its shortcut.
Main form keeps `KeyPreview = $true` with a single KeyDown handler; the help
dialog and terminal wire their own local keys.

### 4.7 Portability (friend/faculty)

- BatchISP path auto-detected (`Program Files (x86)` → `Program Files` →
  `PATH`), CodeBlocks root auto-detected (`%USERPROFILE%\OneDrive\Documents\
  CodeBlocks` → `%USERPROFILE%\Documents\CodeBlocks`).
- Share = copy the `FlipRunner` folder (+ optional `FlipRunnerTest`); first
  run works with zero edits. Friend's COM port is never inherited blindly (§3.3).
- Keep zero-dependency rule: PowerShell + built-in .NET only.

### 4.8 Device selection (educated guess + memory)

- Manual device entry is always retained (textbox, Flip 3.4.7 part names).
- `Settings → Device` submenu shows most-recently-used picks at the top
  (persisted `RecentDevices[]` in `FlipRunner.json`, most recent first).
- First-run guess (educated, device-wide): a coder targeting a chip usually has
  its docs downloaded, so scan two cheap sources and tally case-insensitive
  hits for known device tokens (part `NAME` values harvested from Flip's
  `PartDescriptionFiles\*.xml`): (a) CONTENTS of `*.c;*.h;*.cbp` under the
  CodeBlocks root (weight 2 — code mentions mean active use), (b) FILENAMES
  under Documents/Downloads (weight 1 — e.g. `at89lp51rd2.pdf`,
  `AT89C51RD2-datasheet.pdf`). Bounded and fast: filenames only outside code
  dirs (no PDF content parsing), skip hidden/system paths, cap at a few
  seconds. Preselect the winner; fall back to `AT89C51RD2` on ties/zero hits.
  Guess never overrides a stored preference — it only fills an empty one.

## 5. Non-goals

- No decompiling or patching of Flip/batchisp binaries.
- Signature/security boxes stay display-only (Flip remains the reader for those).
- No Python/Node rewrite (target machines lack both toolchains).
- No CAN/USB-DFU flows in this iteration (RS232 8051 only).

## 6. Acceptance tests

1. Fresh copy on a second machine: double-click → window titled `FLIPpen Hel`,
   hex auto-found or clearly requested, COM list has no Bluetooth entries.
2. `Run (F5)` with FlipRunnerTest: batchisp exit 0, log shows OK, app starts.
   (First hardware proof of operation order, §4.2.)
3. Terminal pops open on first `count =` line without any click.
4. `firmware reset` restarts the counter at 0; `?` window opens, scrolls,
   `Copy code` puts the `ljmp` snippet on the clipboard (also via Ctrl+Shift+C
   with the dialog focused).
5. With serial cable unplugged: flash fails with a human message naming
   device/port/ISP-mode — no red exception text, nothing thrown to console.
6. Hovering Run/Start/firmware-reset shows its shortcut; F5/F6/Ctrl+R work.
7. No Afrikaans string exists outside title/subtitle/logo (grep check).

## 7. Decided questions (was: open questions)

1. Terminal-close → hide-only, stay connected. Rationale: cheapest mental
   model; matches "pop-out viewer" framing.
2. Logo block → `FLIPpen Hel` branding, same position/size.
3. `BLANKCHECK` stays ON in the default Run flow.
4. Device default → `AT89C51RD2` fallback + codebase-tally guess + MRU (§4.8),
   per user's "educated guess" proposal.

## 8. Round 2 amendments (2026-10-08, from user review of the running app)

- **Header:** one in-window header block — title text exactly `FLIPpen Hel`
  but italic (keep face/size, add Italic), subtitle `maar .hex loading vat
  lank` directly beneath it. Remove the old standalone toolbar subtitle so it
  appears exactly once.
- **Toolbar icons:** Flip-style icon row, but code-drawn 16×16 grey bitmaps
  (GDI shapes: chip, folder, play, start, reset-arrow, terminal — no emoji,
  no font dependency). Keep the short text labels beside the icons (clarity
  beats Flip's icons-only here).
- **HEX selector that works:** the picker must open (modal to main form);
  selector becomes a ComboBox with MRU (`RecentHex[]`, cap 8, persisted);
  full path in tooltip (name is cut off otherwise); freshness label beneath
  (`built 2 min ago`, refreshed on timer/focus); newer-build watcher against
  CodeBlocks `bin\*\*.hex` shows `NEWER BUILD available (HH:MM) — click to
  switch`, never silently switching.
- **State clarity:** status strip gains `State` (hex filename + age • device
  • port) and `Next` (suggested next action, updated after every action:
  `Press Run (F5)` / `Connect serial (Ctrl+T)` / `Flashed OK hh:mm`).
  Fix the Settings→Device submenu (reported non-working); MRU click sets the
  device; manual entry retained.
- **Collapsible signature block:** small `▸/▾` toggle on the device panel
  collapsing all display-only rows (signature/boot/hw/security/note);
  action buttons always visible; collapsed state persisted; default collapsed.
- **Right-panel stack + caps:** vertical order `Start Application` →
  `firmware reset` + `?` → `Serial: Connect/Disconnect` (moved inside the
  box; toolbar/Ctrl+T keep working via the same handler). Title Case
  everywhere: Run, Start Application, Firmware Reset, Serial: Connect,
  Serial: Disconnect, Browse…, Newest Hex, Clear, Send, Copy Code, Close,
  Refresh, Pulse DTR, Disconnect.

## 9. Round 3 amendments (2026-10-08, second user review)

- **Header spacing:** subtitle larger, tucked directly under the italic title.
  The `batchisp: ...` debug label is deleted from the middle panel (it was a
  dev leftover; the path auto-detects and stays visible in Settings).
- **Collapse never moves buttons:** Start Application / firmware reset / ?
  / Serial stay at identical screen coordinates in both states. Collapsing
  hides the display-only rows and pulls the panel's BOTTOM edge up under the
  buttons — nothing above the buttons shifts (muscle memory).
- **Toolbar layout:** menu row on top, icon row directly beneath it, labels
  UNDER the icons (`ImageAboveText`), grey code-drawn icons retained.
- **Modeless dialogs:** Settings and firmware-reset help become modeless
  owned windows (click-out allowed); settings persist on change + on close,
  never only on OK. Terminal already modeless — keep.
- **Serial Auto (default):** button reads `Serial: Auto`; with the port open,
  first RX bytes auto-open the terminal. Click always connects (if needed) +
  opens the terminal for typing. New Settings toggle `Serial auto-open on RX
  data` (default ON, persisted); OFF = fully manual (`Serial: Connect`).
- **Headless CLI for AI/automation:** `FlipRunner.ps1 -Cli -Action
  Flash|Reset|Monitor` (params `-Hex -Device -Port -IspBaud -MonBaud
  -Seconds`) runs batchisp/serial with NO GUI, prints `FLIPHEL OK|FAIL …`
  lines, exit code 0/1. `Reset` sends `!!!RESET!!!`; `Monitor` streams UART
  to stdout for N seconds. MCP stdio wrapper documented as follow-up
  (thin wrapper over this CLI).

## 10. Round 4 amendments (2026-10-08, third user review)

- **Menu truly on top:** row order is menu (`File Buffer Device Settings
  Help`) FIRST at the very top, icon toolbar directly beneath it (fix dock
  order — the toolbar currently sits above the menu).
- **Mirror Flip's toolbar:** research the real Flip 3.4.7 UI (launch it,
  screenshot; read its `help\*.htm`) and copy the toolbar order/grouping
  even where items are redundant; same for the three panels. Grey code-drawn
  icons stay; labels stay under icons.
- **Every visible control explains itself:** full tooltip audit — no control
  without an elaborating tooltip (what it does + its shortcut where one
  exists). Tooltips are the primary onboarding; keep them one line + shortcut.
- **COM choice is obvious + resilient:** the auto-selected port is labeled
  as such everywhere it appears (`COM3 (auto)`); on flash failure the app
  retries the full flow on the next non-Bluetooth port automatically before
  reporting failure (with clear logging of each attempt).
- **Run progress popup:** pressing Run opens a small popup with progress
  bar(s) + stage labels (Erase → Blank-check → Program → Verify → Start).
  Implement as genuinely staged `batchisp` calls (one invocation per stage,
  LOADBUFFER wherever a stage needs it) so progress is real and failures
  attribute to a stage; include Cancel (kills the running batchisp).
- **Everything clickable works:** audit every toolbar button and every menu
  item (File/Buffer/Device/Settings/Help) — each must do something real.
  The top-level Device menu gets a working picker (MRU + guess + manual
  entry), not just the Settings submenu. Buffer menu gets real buffer actions
  (info from the parsed hex: size/range/variant).
- **Leave it running:** after the round, launch the GUI for the user and
  keep it up with console output captured so logs can be inspected.
