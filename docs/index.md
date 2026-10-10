---
title: Home
nav_order: 0
---

# How this project was made

**Read this first.**

FLIPpen Hel was built by an AI in conversation with one developer — no design
document, no tests, and no code review by a second person. That is not a
disclaimer for its own sake. It explains most of the quirks you are about to
run into, and it tells you how much weight to put on any given claim.

What to actually expect:

* **Nothing here was confirmed against a real AT89LP51RD2 board.** Everything
  about flashing, serial and programming mode was reasoned from Atmel's own
  documentation. It works on the machine it was written on. That is a single
  data point, not a test matrix.
* **The documentation was written by the same AI**, so where this site and the
  tool disagree, the tool is probably right. Which is exactly the kind of bug
  worth reporting.
* **The UI is deliberately modelled on FLIP**, including parts that are
  redundant — the checkboxes that turn green on pass and red on fail, the
  status LEDs, the three-panel layout. If FLIP has a habit you rely on, it is
  probably still there, and if it is missing that is a real bug.
* **Automation is real and switchable.** Everything it does without asking —
  auto device detection, auto COM port, auto port retry, auto hex reload, auto
  terminal — has a checkbox. Turn them off and it behaves like FLIP, because
  FLIP was the brief.

If something behaves oddly, it is far more likely to be an honest gap in an
unreviewed tool than a deliberate choice. Reports are genuinely useful and read.


---

# FLIPpen Hel

**[FLIPping hell]** *— the name is a pun: FLIP in hell.*

*Want Atmel FLIP was 'n groot FLOP.*
**[Because Atmel FLIP is a big FLOP.]**

A zero-install replacement for Atmel FLIP, built for **AT89LP51RD2** and
**AT89C51RD2** 8051 development with SDCC.

No Python. No Node. No drivers to hunt for. PowerShell and .NET WinForms, and
both of those are already on your Windows machine.

## Why

Because flashing one file in Atmel FLIP takes six clicks, because it never tells
you what any button is for, and because there is no way to point something else
at it and let go.

FLIPpen Hel fixes that. It flashes in one keypress, tells you what every control
does on hover, remembers your hex and your port, watches your serial output, and
can be driven from a terminal by a script or an agent with no window at all.

## Get it

Download the zip from the
[Releases tab](https://github.com/AbstractDimensions/flippen-hel/releases/latest),
unzip it anywhere, and double-click `FLIPpen Hel.bat`.

Nothing to install. The release carries its own copy of `batchisp.exe` and the
Atmel device part files, so **Atmel FLIP is not required**. If you do have Flip
installed, that copy gets used instead.

Then:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -STA -File FlipRunner.ps1
```

## Then

**[Getting started](getting-started)** — what to install and how to flash.

## What you get

**One-click flash and run** — press `F5`. A progress popup walks Erase, Blank
Check, Program, Verify and Start as separate calls, and each checkbox turns
green on pass and red on fail.

**A serial monitor** — where your firmware output pops open the moment anything
arrives, so you see the first print without hunting for a window.

**Firmware reset** — `Ctrl+R` sends `!!!RESET!!!`, your firmware reboots, and
you are testing again in a fraction of a second.

**Something that picks for you** — it silently ignores the Bluetooth ports,
picks the best COM candidate, marks its choice as a guess, and if a flash fails
it tries the next port on its own.

**A terminal agent** — `-Cli -Action Flash` sets an exit code and prints plain
lines, so a Makefile or an AI agent can load and test code without ever showing
a window.

## The name

FLIPpen Hel is Afrikaans-flavoured for "FLIP in Excel", or if you prefer,
"a giant cheat sheet instead of FLIP". **Fillip** is the flip-flop.
