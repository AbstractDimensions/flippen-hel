---
title: Supported devices
nav_order: 3
description: The 81 Atmel parts FLIPpen Hel can reach over RS232, tested against batchisp 1.2.5. Includes AT89C51RD2, AT89C51CC01, AT89S54, AT32UC3 and ATUCL families.
keywords: at89c51rd2 supported, batchisp device list, atmel 8051 rs232 flashing, at32uc3 rs232, at89s54 flash
---

# Supported devices

**Every list on this page was produced by running `batchisp` against the device
name** — not by reading a datasheet and guessing. The method is in
[RESEARCH-flip-support.md](https://github.com/AbstractDimensions/flippen-hel/blob/main/RESEARCH-flip-support.md).

## The short version

Flip 3.4.7 ships **122 part files**. FLIPpen Hel runs `batchisp -hardware RS232`,
and **81 of those 122 parts accept RS232** — the other 41 need USB DFU, CAN or
PDI and fail at the hardware stage with `Could not load dynamic library`.

So the Device picker in FLIPpen Hel **lists all 122, but only 81 will actually
flash.** That over-promise is Flip's, not ours — we show the list the part files
define.

## The 81 that work over RS232

### AT89 — the 8051 family (22 parts)

The reason this tool exists. These share the AT89 bootloader over serial.

`AT89C5115` · `AT89C5130` · `AT89C5131` · `AT89C5132` · `AT89C51AC2` ·
`AT89C51AC3` · `AT89C51CC01` · `AT89C51CC02` · `AT89C51CC03` · `AT89C51ED2` ·
`AT89C51IC2` · `AT89C51ID2` · `AT89C51IE2` · `AT89C51RB2` · `AT89C51RC2` ·
`AT89C51RD2` · `AT89C51RE2` · `AT89C51SND1` · `AT89C51SND2` · `AT89S54` ·
`AT89S58` · `AT89S64`

### T89C51 — the 8051 variants (6 parts)

`T89C51CC01` · `T89C51CC02` · `T89C51IC2` · `T89C51RB2` · `T89C51RC2` ·
`T89C51RD2`

### AT32UC3 — AVR32 (50 parts)

`AT32UC3A0128` · `AT32UC3A0256` · `AT32UC3A0512` · `AT32UC3A0512ES` ·
`AT32UC3A1128` · `AT32UC3A1256` · `AT32UC3A1512` · `AT32UC3A1512ES` ·
`AT32UC3A3128` · `AT32UC3A3128S` · `AT32UC3A3256` · `AT32UC3A3256S` ·
`AT32UC3A364` · `AT32UC3A364S` · `AT32UC3A4128` · `AT32UC3A4128S` ·
`AT32UC3A4256` · `AT32UC3A4256S` · `AT32UC3A464` · `AT32UC3A464S` ·
`AT32UC3B0128` · `AT32UC3B0256` · `AT32UC3B0256ES` · `AT32UC3B0512` ·
`AT32UC3B064` · `AT32UC3B1128` · `AT32UC3B1128ES` · `AT32UC3B1256` ·
`AT32UC3B1256ES` · `AT32UC3B1512` · `AT32UC3B164` · `AT32UC3C0128C` ·
`AT32UC3C0256C` · `AT32UC3C0512C` · `AT32UC3C1128C` · `AT32UC3C1256C` ·
`AT32UC3C1512C` · `AT32UC3C2128C` · `AT32UC3C2256C` · `AT32UC3C2512C` ·
`AT32UC3L0128` · `AT32UC3L016` · `AT32UC3L0256` · `AT32UC3L032` ·
`AT32UC3L064`

### ATUCL / ATUC — AVR32 low-power (8 parts)

`ATUC128D3` · `ATUC128D4` · `ATUCL3128U` · `ATUCL3256U` · `ATUCL364U` ·
`ATUCL4128U` · `ATUCL4256U` · `ATUCL464U`

### Other

`ATOCDTARGET`

## The 41 that do not work

These fail at `Hardware selection` because they bootload over something other
than RS232.

| Family | Parts | Why |
|---|---|---|
| `AT90USB*` | 9 | USB DFU |
| `AT90CAN*` | 3 | CAN |
| `ATmega*U2/U4/U6` | 7 | USB DFU |
| `ATmega*M1/C1` | 4 | CAN |
| `ATxmega*` | 21 | PDI / USB, no RS232 bootloader |

Listing them for completeness: `AT90CAN128`, `AT90CAN32`, `AT90CAN64`,
`AT90USB1286`, `AT90USB1287`, `AT90USB162`, `AT90USB646`, `AT90USB647`,
`AT90USB82`, `ATmega8U2`, `ATmega16U2`, `ATmega16U4`, `ATmega32U2`,
`ATmega32U4`, `ATmega32U6`, `ATmega16M1`, `ATmega32M1`, `ATmega64M1`,
`ATmega32C1`, `ATmega64C1`, and the 21 `ATxmega` parts.

{: .note }
**FLIPpen Hel is `-hardware RS232` only.** For the USB and CAN parts you need
real FLIP. The Device picker still lists them because Flip's own part files
define them, but the flash will stop at the hardware stage.

## The chip this tool is named after

**`batchisp -device AT89LP51RD2` returns "Device does not exist."** Verified.
Flip 3.4.7 ships `AT89C51RD2.xml` and no `AT89LP51RD2.xml`.

The LP part boots through the same bootloader over the same serial protocol, so
select **`AT89C51RD2`** and flash the LP with it. That is the app's default, and
it is why the name is a pun on the family rather than a claim about the device
string.

{: .warning }
**Nothing on this page has been confirmed against real hardware.** The list
proves `batchisp` accepts the device and hardware pair — it does not prove a
given board flashes. See [How this project was made](index#how-this-project-was-made).

## Picking a device

`Device > Select Device` opens the full list Flip provides. Your last five
choices are remembered, and with **Auto-detect device** on (the default) the app
guesses from your own code before you ever open the picker.
