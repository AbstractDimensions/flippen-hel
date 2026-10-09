# FLIPpen Hel

**Want Atmel FLIP was 'n groot FLOP.**

A zero-install replacement for Atmel FLIP, built for AT89LP51RD2 / AT89C51RD2
8051 development with SDCC.

No Python. No Node. No drivers to hunt for. PowerShell and .NET WinForms, and
both are already on your Windows machine.

## Why

Because Atmel FLIP is a Java dinosaur, because it traps your cursor, because it
makes you click six things to flash one file, and because it never tells you
what a button is for.

FLIPpen Hel fixes that. It flashes in one keypress, tells you what every control
does on hover, remembers your hex and your port, watches your serial output, and
can be driven from a terminal with no window at all.

## What you need

* Windows 10 or 11
* [Atmel FLIP 3.4.7](https://www.microchip.com/en-us/development-tool/flip) installed
  (FLIPpen Hel reuses its `batchisp.exe`; it does not replace it)
* Your hex, compiled with SDCC and converted with `packihx`

## Running it

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -STA -File FlipRunner.ps1
```

Then press **Run** (`F5`).

## Without the GUI

```powershell
.\FlipRunner.ps1 -Cli -Action Flash -Hex firmware.hex -Port COM3
.\FlipRunner.ps1 -Cli -Action Monitor -Port COM3 -Seconds 5
.\FlipRunner.ps1 -Cli -Action Reset -Port COM3
```

`Flash`, `Reset` and `Monitor`. Zero windows, plain output, exit code `0` or `1`
— so a Makefile or an AI agent can load and test code on its own.

## Documentation

Full docs are published at
**<https://abstractdimensions.github.io/flippen-hel/>** — and the sources live in
[`docs/`](docs/).

## Licence

MIT.
