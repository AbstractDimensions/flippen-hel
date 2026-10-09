---
title: Wiring
nav_order: 6
has_children: true
---

# Wiring

## Minimum for flashing

For ISP over RS232 you need the standard three wires plus the ISP condition.

```
Board                USB-serial adapter

VCC         <-------> VCC        (optional, do not power from it)
GND         <-------> GND        (required)
TX          <-------> RXD
RX          <-------> TXD
```

`batchisp -device AT89C51RD2 -hardware RS232 -port COMx -baudrate 115200`
speaks to the 8051 bootloader on those pins. If the board is in ISP mode, that
is enough to flash.

### Getting into ISP mode

The AT89LP51RD2 bootloader is entered when the device sees a reset with specific
levels on the pins. In practice, one of these:

* Power-cycle the board **while holding the ISP button** if it has one
* Power-cycle with a **BLJB** jumper set, so the bootloader runs on reset
* Let `-autoisp` do it, which needs the next section's wiring

## For hands-free flashing, add two wires

AutoISP needs `batchisp` to move the reset and boot-select pins. Over a
USB-serial adapter those are DTR and RTS.

```
Adapter DTR    ---->  Board RST
Adapter RTS    ---->  Board PSEN
```

Then check **AutoISP** in the Operations Flow panel. FLIPpen Hel sends
`-autoisp 1 0`: **the first argument is the RESET active level, the second is
the PSEN active level**, per the Atmel documentation.

| Argument | Value sent | Meaning |
| :-- | :-- | :-- |
| 1 | `1` | RESET is active high |
| 2 | `0` | PSEN is active low |

Your board may need `-autoisp 1 1` or `-autoisp 0 0` instead if you added
inverting transistors. Change it in the config if so.

{: .tip }
A plain resistor-capacitor diode from DTR into RST is the common Arduino trick
and it works for most AT89LP boards.

## For reset-over-UART, no extra wire

Firmware Reset, the `!!!RESET!!!` magic, only needs the TX/RX pair you already
have. No additional wiring for that. See [Firmware reset](firmware-reset).

## For serial monitoring, nothing new

Same TX/RX lines. Your firmware just needs `printf` or `putchar` on the UART at
9600 8N1, and the monitor shows it. **Serial: Auto** pops the terminal open on
the first byte so you do not have to think about it.

## Checklist

| Symptom | Likely cause |
| :-- | :-- |
| Device selection passes, opening port fails | Wrong COM port, or the adapter is unplugged |
| Opening port passes, everything else fails | Board is not in ISP mode |
| Works only when you hold a button | No BLJB and no AutoISP wiring |
| Works on port A, not port B | Cheap clone adapter; FLIPpen Hel auto-retries for this |
| Terminal shows nothing | Baud rate mismatch, or firmware never prints |
| Flash succeeds but nothing runs after | `START` failed; try Start App (`F6`) |
