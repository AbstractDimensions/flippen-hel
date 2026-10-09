---
title: Getting started
nav_order: 1
has_toc: true
---

# Getting started

## What you need

* Windows 10 or 11
* **Atmel FLIP 3.4.7** installed. FLIPpen Hel reuses its `batchisp.exe`; it does not replace it. Download it from [microchip.com](https://www.microchip.com/en-us/development-tool/flip).
* Your hex file, compiled with SDCC and converted with `packihx`

That is the whole dependency list. No Python, no Node, no drivers.

## Running it

The simplest way, just run it:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -STA -File FlipRunner.ps1
```

If you want it on your desktop, make a shortcut with that same command line and give it the title **FLIPpen Hel**.

On first launch FLIPpen Hel:

1. finds `batchisp.exe` inside your Flip install
2. scans the COM ports and silently drops the Bluetooth ones
3. picks the best-looking port for you and marks it **(auto)**
4. picks your newest CodeBlocks hex build

{: .note }
Everything above can be overridden by hand in the **Settings** window. Nothing is forced on you; the auto choices are only defaults.

## Flashing

1. Put the board into ISP mode. If it has no ISP button, use the **Pulse DTR** button in the Terminal window (needs DTR wired to RST).
2. Press **Run** (or `F5`).

A progress popup opens and walks through the stages, **Erase** then **Blank Check** then **Program** then **Verify** then **Start**. Each checkbox in the Operations Flow panel goes **green when the stage passes** and **red when it fails**, exactly like real FLIP.

## First flash failing?

If a stage fails, FLIPpen Hel does not stop there. It retries the whole sequence on the next non-Bluetooth COM port and logs every attempt, so a duplicated CP210x or an FTDI clone still works. Only when every port is exhausted does it report failure.

{: .tip }
If you have more than one USB-serial adapter plugged in, read the log. It names the exact port that worked, and the port box updates to that port so your next flash starts there.

## If the port answers nothing

Open the Terminal window (the **Terminal** button or `Ctrl+T`) and press **Pulse DTR**. If the board has DTR wired to RST this resets it. If nothing resets, your board needs the hardware ISP condition instead, see [Wiring](wiring).
