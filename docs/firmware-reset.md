---
title: Firmware reset
nav_order: 5
---

# Firmware reset

## Press the button

Open the serial connection and press **Firmware Reset** (`Ctrl+R`). FLIPpen Hel
sends `!!!RESET!!!` followed by a CR LF on the open port.

Nothing happens until your firmware is looking for it.

## Add this to your firmware

The **?** button next to Firmware Reset opens a window with this snippet and a
**Copy Code** button (`Ctrl+Shift+C` inside the window):

```c
// --- FLIPpen Hel firmware reset (AT89LP51RD2, SDCC, 8051) ---
// 1. Call UartResetPoll() inside your main while(1) loop.
// 2. In FLIPpen Hel, open serial then press Reset (Ctrl+R).
//    The PC sends "!!!RESET!!!" and this reboots the APP.
//    (TX/RX alone CANNOT enter the bootloader -- that still needs the
//     hardware ISP condition or BLJB/AutoISP wiring. This is app-restart
//     for fast testing without reflashing.)
void UartResetPoll(void) {
    static unsigned char n = 0;
    if (RI) {
        RI = 0;
        if (SBUF == '!') {
            if (++n >= 3) {
                n = 0;
                EA = 0;              // stop interrupts
                __asm               // reboot app from address 0
                    ljmp 0
                __endasm;
                while (1);           // never reached
            }
        } else n = 0;
    }
}
```

With that in place, **Firmware Reset** restarts your program instantly. No
reflash, no cable swap, no waiting for the GUI to grumble.

## What it can never do

{: .warning }
Entering the **bootloader** over TX/RX is physically impossible. On the 8051 the
bootloader is a piece of flash entered by a specific hardware condition on the
RST and PSEN pins, or by setting BLJB. A serial character cannot move a pin.

So: **Firmware Reset restarts your app. It does not put the chip into ISP
mode.** To flash, the board must be in ISP mode.

## Flashing without touching a button

You have three honest options.

**1. Put the board in ISP mode yourself once.** Power cycle it with the ISP
condition held, or press the ISP button if your board has one. Then run
Firmware Reset only for app restarts.

**2. Wire DTR to RST.** Then use **Pulse DTR** in the Terminal window to reset
the board from the PC, exactly like Arduino auto-reset. Combined with BLJB or
AutoISP this gets you close to hands-free.

**3. Leave AutoISP on.** **AutoISP** in the GUI, `-autoisp 1 0` under the hood,
tells `batchisp` to drive the RESET and PSEN lines itself. It needs DTR to RST
and RTS to PSEN wired on your board. If your board has that wiring, check the
box and flashing becomes one keypress.

## What "app restart" is actually for

Flash, watch a counter run, wait for a bug, hit `Ctrl+R`, watch it again. The
reboot costs a fraction of a second. The whole point is a tight
edit-build-flash-watch loop where "flash" is the only slow part.
