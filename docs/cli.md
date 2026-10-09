---
title: Headless CLI
nav_order: 4
---

# Headless CLI

The whole point of FLIPpen Hel is that the boring part is automated. If you can
run one line, you never have to look at the GUI at all.

```powershell
powershell -NoProfile -NonInteractive -STA -File FlipRunner.ps1 -Cli -Action <action> [options]
```

The `-Cli` switch makes the script **open zero windows**. It prints lines and
sets an exit code, so it can be driven by a script, a Makefile, or an AI agent
sitting in a terminal.

## Actions

| Action | What it does |
| :-- | :-- |
| `Flash` | The full flow: erase, blank check, load buffer, program, verify, start, reset |
| `Reset` | Sends `!!!RESET!!!` on the port |
| `Monitor` | Streams the UART to stdout for N seconds |

## Options

| Option | Default | Meaning |
| :-- | :-- | :-- |
| `-Hex <path>` | from `FlipRunner.json` | Intel hex to flash |
| `-Device <name>` | from config | e.g. `AT89C51RD2` |
| `-Port <COMx>` | from config | COM port |
| `-IspBaud <n>` | `115200` | ISP baud rate |
| `-MonBaud <n>` | `9600` | monitor baud rate |
| `-Seconds <n>` | `10` | how long `Monitor` listens |

Anything you omit falls back to `FlipRunner.json`, then to a hardcoded default,
so an empty command line still works if you have run the GUI once.

## Output

Every run prints machine-readable lines and exits clean.

```
FLIPHEL TRY COM3: batchisp.exe -device AT89C51RD2 ...
FLIPHEL OK flashed C:\firmware.hex on COM3 as AT89C51RD2
```

```
FLIPHEL FAIL batchisp exit -1 (device AT89C51RD2 port COM3 isp 115200)
```

Exit codes: `0` for success, `1` for failure. A failed flash prints `FLIPHEL
FAIL` with the device, port and baud rate so you can tell exactly which knob is
wrong.

## Examples

Flash and watch the boot message:

```powershell
.\FlipRunner.ps1 -Cli -Action Flash -Hex firmware.hex -Port COM3
.\FlipRunner.ps1 -Cli -Action Monitor -Port COM3 -Seconds 5
```

Just reboot the app without reflashing:

```powershell
.\FlipRunner.ps1 -Cli -Action Reset -Port COM3
```

{: .tip }
Because it writes plain lines and returns 0 or 1, you can chain it:
`.\FlipRunner.ps1 -Cli -Action Flash && .\FlipRunner.ps1 -Cli -Action Monitor -Seconds 20`

## What the CLI will not do

The CLI cannot make your board enter its bootloader. That is the same hardware
limit described under [Firmware reset](firmware-reset). It will happily report
`FAIL` if the board is not in ISP mode, with the exact reason.
