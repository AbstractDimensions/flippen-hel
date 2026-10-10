---
title: Home
nav_order: 0
---

# How this project was made

**Read this first.**

FLIPpen Hel was **entirely vibe coded** — written by an AI in conversation with one
developer, with no traditional design document, no tests, and no code review by
anybody who knew what they were doing. The documentation on this site was
**also written by that same AI**.

That has consequences you should know about:

* **The docs may be wrong.** They are best-effort prose generated from the same
  imperfect understanding that produced the code. Where the docs and the code
  disagree, the code is probably right and this page is probably wrong.
* **Take the confident tone with a grain of salt.** A lot of it reads like
  someone knew what they were talking about. They did not.
* **It was never reviewed by an experienced Windows developer.** It works on one
  developer's machine. That is not the same as working on yours.
* **The hardware is unverified.** Everything about flashing, serial and
  programming mode was reasoned from Atmel's documentation, not confirmed
  against a real AT89LP51RD2 board. Treat every claim about the chip as
  untested.

**If you find a discrepancy in the documentation, please report it as a bug.** A
doc that says the opposite of what the tool does is a defect, and it is exactly
the kind of thing this project needs to hear about. Use the **Feedback** button
in the app, or the
[bug report form](https://github.com/AbstractDimensions/flippen-hel/issues/new/choose).

---

# FLIPpen Hel

*Want Atmel FLIP was 'n groot FLOP.*

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
