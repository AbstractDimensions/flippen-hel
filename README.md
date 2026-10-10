# FLIPpen Hel

**[FLIPping hell]** *— the name is a pun: FLIP in hell.*

*Want Atmel FLIP was 'n groot FLOP.* **[Because Atmel FLIP is a big FLOP.]**

A zero-install replacement for Atmel FLIP, built for AT89LP51RD2 / AT89C51RD2
8051 development with SDCC.

No Flip. No Python. No Node. No drivers to hunt for. PowerShell and .NET
WinForms, and both of those are already on your Windows machine.

## Why

Because flashing one file in Atmel FLIP takes six clicks, because it never tells
you what any button is for, and because there is no way to point something else
at it and let go.

FLIPpen Hel fixes that. It flashes in one keypress, tells you what every control
does on hover, remembers your hex and your port, watches your serial output, and
can be driven from a terminal by a script or an agent with no window at all.

## Install and run

Grab the zip from the [Releases tab](https://github.com/AbstractDimensions/flippen-hel/releases/latest),
unzip it anywhere, and double-click `FLIPpen Hel.bat`.

Or run it by hand:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -STA -File FlipRunner.ps1
```

Then press **Run** (`F5`).

The zip carries its own copy of `batchisp.exe` and the Atmel device part files,
so nothing has to be installed. If Atmel FLIP 3.4.7 *is* installed, FLIPpen Hel
prefers that copy — but it never needs it.

{: .note }
FLIPpen Hel is a from-scratch PowerShell reimplementation, not a fork of Atmel
FLIP. Nothing from the Flip source tree is used; the bundled `batchisp.exe` and
part files are Atmel's own binaries.

## Without the GUI

```powershell
.\FlipRunner.ps1 -Cli -Action Flash   -Hex firmware.hex -Port COM3
.\FlipRunner.ps1 -Cli -Action Monitor -Port COM3 -Seconds 5
.\FlipRunner.ps1 -Cli -Action Reset   -Port COM3
```

`Flash`, `Reset` and `Monitor`. Zero windows, plain output, exit code `0` or `1`
— so a Makefile or an AI agent can load and test code on its own.

## Documentation

Full docs are published at
**<https://abstractdimensions.github.io/flippen-hel/>** — and the sources live in
[`docs/`](docs/).

## Licence

MIT, except the bundled `batchisp.exe` and `PartDescriptionFiles/`, which remain
Atmel/Microchip software covered by their own licence.


---

**FLIPpen Hel** *[FLIPping hell]* — a zero-install Atmel FLIP replacement for
AT89LP51RD2 / AT89C51RD2 development with SDCC. No Flip install, no Python, no
Node. One keypress to flash, a built-in serial monitor, firmware reset over
UART, and a headless CLI that a Makefile or an AI agent can drive.

| | |
|---|---|
| Platform | Windows 10 / 11 |
| Needs | PowerShell 5.1+, .NET WinForms (already on Windows) |
| Licence | MIT (bundled `batchisp.exe` and part files remain Atmel's) |

### How this was made

Built by an AI in conversation with one developer. No tests, no second reviewer.
Nothing here was confirmed against a real AT89LP51RD2 board — the flashing,
serial and programming-mode behaviour was reasoned from Atmel's documentation.
Where the docs and the tool disagree, the tool is probably right, and a report
would be genuinely useful. Hit **Feedback** in the app or open a
[bug report](https://github.com/AbstractDimensions/flippen-hel/issues/new/choose).

> **Translation, since the name needs one:** the Afrikaans pun is *"Want Atmel
> FLIP was 'n groot FLOP"* — roughly *"because Atmel FLIP is a big FLOP."*

## Install and run