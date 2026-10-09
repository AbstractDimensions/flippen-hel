---
title: FAQ
nav_order: 7
---

# FAQ

### Do I still need FLIP installed?

Yes. FLIPpen Hel reuses `batchisp.exe` from your Flip 3.4.7 install. It does not
replace it, and it does not ship a second copy. Install Flip from Microchip once
and FLIPpen Hel will find the binary.

### Why is my device AT89C51RD2 and not AT89LP51RD2?

Flip 3.4.7 ships a part file for `AT89C51RD2` and does not ship one for
`AT89LP51RD2`. Since FLIPpen Hel passes your device straight to `batchisp`, it
defaults to the one Flip actually knows. If your build expects the LP, type it
into Settings anyway; the log will tell you quickly whether the part file exists.

### My COM port list is empty

FLIPpen Hel hides Bluetooth ports. If your adapter is genuinely serial but is
hiding inside a Bluetooth stack, it gets dropped along with them. Use
**Refresh** after plugging in the adapter.

### Why do I sometimes see "(auto)" next to the port?

It means FLIPpen Hel chose that port for you. As soon as you choose one
yourself, the label disappears. That is how you tell a guess from your decision.

### What if one port fails?

FLIPpen Hel retries the entire sequence on the next non-Bluetooth port before
reporting failure, and logs each try. Cheap clone adapters and duplicate hub
ports are the usual reason.

### Can Firmware Reset put my chip in ISP mode?

No. Over TX/RX that is impossible on the 8051. See [Firmware reset](firmware-reset).

### What is AutoISP actually sending?

`-autoisp 1 0`. The first number is the RESET active level, the second is the
PSEN active level. It needs DTR wired to RST and RTS wired to PSEN, described
under [Wiring](wiring).

### Settings keeps closing behind the main window

Settings, help, terminal and the progress popup are all **modeless**. You can
click past them and keep using the main window. Settings save as you type, and
once more when you close the window, so nothing is lost if you click away
mid-edit.

### Where are my settings stored?

`FlipRunner.json` next to `FlipRunner.ps1`. It is plain JSON. Deleting it just
resets you to defaults; the app walks the COM ports and picks new guesses.

### Can I use this without the GUI?

Yes, that is the whole point. See [Headless CLI](cli).

### Why is the icon a flip-flop?

Because Atmel made FLIP and the best response to that was to answer with a
joke about a flip-flop that can also flash your chip. His name is Fillip.
