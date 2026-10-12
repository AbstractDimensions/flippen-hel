---
title: Atmel FLIP alternative
nav_order: 2
description: FLIPpen Hel is a free, zero-install alternative to Atmel FLIP for flashing AT89C51RD2, AT89S54, AT32UC3 and 78 other parts batchisp reaches over RS232. One keypress to flash, built-in serial monitor, and a headless CLI.
keywords: atmel flip alternative, flip replacement, at89c51rd2 flash, 8051 isp programmer, sdcc hex flashing, batchisp frontend, at32uc3 rs232
---

# Atmel FLIP alternative

{: .note }
**Looking for an Atmel FLIP replacement?** This page is the short version of
what FLIPpen Hel is, what it does the same, and what it does differently.

## The short version

[Atmel FLIP](https://www.microchip.com/en-us/development-tool/flip) is a Java
program that flashes 8051 and AVR parts over RS232, USB or CAN. It works, but it
asks you to click six things to flash one file, it locks its dialogs, and it
never tells you what any button is for.

**FLIPpen Hel is a drop-in alternative for the 81 parts batchisp reaches over RS232** - all 22 AT89 8051s, the 50 AT32UC3 AVR32 parts, the ATUCL low-power parts, and the T89C51 variants. Full tested list on [Supported devices](supported-devices).
It drives the same `batchisp.exe` that FLIP's own command-line tool uses, so the
flashing itself is identical — you are not trusting a reimplementation of the
protocol, you are using the same engine with a saner front end.

## What it keeps from FLIP

The point was to feel familiar, so the layout and vocabulary are the same:

* The **Operations Flow** checkboxes — Erase, Blank Check, Program, Verify —
  and the checkbox turns **green on pass, red on fail**, with a round status LED
  beside it, exactly like a FLIP sequence.
* The three panels: Operations Flow, FLASH Buffer Information, and a device
  frame showing signature bytes, hardware byte, BLJB, X2 and security level.
* The **Start Application** button, which does `START RESET 0` and launches your
  firmware.
* Device selection from the same Atmel part-description files.

If you have FLIP muscle memory, it mostly still applies.

## What it adds

| | |
|---|---|
| **One keypress** | `F5` runs the whole sequence and shows a progress popup with real per-stage results |
| **No install** | The release carries `batchisp.exe` and the part files, so Atmel FLIP is not required |
| **COM port picked for you** | Bluetooth ports ignored silently, best candidate chosen and marked *(auto)* |
| **Auto-retry** | A flash that fails on one port is retried on every other non-Bluetooth port |
| **Serial monitor** | Built-in, pops open on the first byte your firmware prints |
| **Firmware reset** | `Ctrl+R` reboots your app over UART without reflashing |
| **Remembered** | Last hex, last device, both baud rates, and the last six hex files |
| **Headless CLI** | `Flash`, `Reset`, `Monitor` with exit codes, for Makefiles and CI |
| **Tooltips everywhere** | Every control says what it does and its shortcut |

## What it deliberately does not do

* **It does not replace the chip's bootloader.** Entering programming mode is
  still the hardware condition — hold PSEN and press RESET, or wire DTR to RST
  and RTS to PSEN. That is silicon, not software. See [Wiring](wiring).
* **It is Windows only.** PowerShell and WinForms. A Linux build would need the
  batchisp protocol reimplemented from scratch, which is a different project.
* **No CAN, no USB DFU.** RS232 only, because that is what the AT89 bootloader
  speaks. The 41 parts that boot over USB or CAN are listed on
  [Supported devices](supported-devices) and will stop at the hardware stage.

## Is the flashing safe?

The flashing itself is done by `batchisp.exe`, the same Atmel tool FLIP's
command line ships. FLIPpen Hel does not touch flash directly — it builds the
same command line, splits it into per-stage calls so failures can be blamed on a
stage, and reports the result. The risk is a UI bug, not a corrupted flash.

## Install

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -STA -File FlipRunner.ps1
```

Then press **Run**. See [Getting started](getting-started) for the first flash.
