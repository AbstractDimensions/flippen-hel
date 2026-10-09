---
title: Features
nav_order: 2
---

# Features

## One-click flash and run

Press **Run** (`F5`). A progress popup opens and runs the exact sequence real
FLIP runs, as **separate** `batchisp` calls so a failure can be blamed on the
stage that caused it:

| Stage | What it does |
| :-- | :-- |
| Erase | Full chip erase. Resets the SSB, Hardware Byte, BSB and SBV |
| Blank Check | Confirms the flash is blank, reports the first non-blank address |
| Program | Writes the loaded hex buffer into flash |
| Verify | Reads the flash back and compares it with the buffer |
| Start | Launches the app and pulses RESET, so your firmware runs immediately |

Popups are **modeless** - Settings, help, the serial terminal and the progress
popup never trap your cursor. You can click past all of them and keep working.

{: .note }
A full chip erase **resets the special bytes**. If you set a custom Security
Level or BLJB it will be wiped. Set them after flashing with
**Device > Write/Read Special Bits...**.

## Serial monitor, built in

* The **Terminal** button (`Ctrl+T`) opens a Termite-style serial monitor.
* **Serial: Auto** is the default: the moment your firmware prints something,
  the terminal pops open by itself. No button press.
* Turn that off in **Settings** if you prefer to be asked.
* The monitor has its own Disconnect button so you can drop the port without
  losing the log.

## Firmware reset over UART

**Firmware Reset** (`Ctrl+R`) sends `!!!RESET!!!` on the open port. Your firmware
sees three bangs and reboots to address 0, so you can test again without
reflashing.

{: .warning }
This restarts your **application**. It cannot enter the bootloader. Over TX/RX
that is a physical impossibility on the 8051 - only the ISP hardware condition
or the BLJB / AutoISP wiring can do that. See [Firmware reset](firmware-reset).

## COM port choices made for you

On launch FLIPpen Hel silently ignores the Bluetooth ports and picks the best
candidate. When the guess is a guess, the port is labelled **(auto)** everywhere
it appears. The moment you pick a port yourself, the label disappears.

If a flash fails, FLIPpen Hel **automatically retries every remaining
non-Bluetooth port** before giving up, and logs each try. Real boards get
plugged into real hubs, so this matters.

## Remembered things

FLIPpen Hel keeps, in `FlipRunner.json` next to the script:

* the last hex file and the last six hex files
* the last device and the last five devices
* the COM port and both baud rates
* whether the signature block is collapsed
* whether Serial: Auto is on

## A FLIP that never leaves you guessing

Every control has a tooltip explaining what it does, what it changes and its
keyboard shortcut. The tooltips are written from the Atmel documentation, not
from guesswork.
