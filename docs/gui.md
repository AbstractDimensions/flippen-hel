---
title: The GUI
nav_order: 3
has_children: true
---

# The GUI

FLIPpen Hel is laid out like the FLIP you already know: a menu bar on top, an
icon toolbar under it, and three panels below.

## The menu bar

**File**

* **Load HEX...** (`Ctrl+O`) - pick a hex file. Remembers the last six.
* **Use newest hex in CodeBlocks** - grabs the most recently built hex.
* **Save Buffer Contents...** (`Ctrl+S`) - write the current hex out to a new file.
* **Refresh port list** - rescan the COM ports.

**Buffer**

Shows live hex size and range, and the Debug or Release variant, parsed from the
path.

**Device**

* The most recent devices you used, as a quick-pick list.
* **Select Device...** - the full list of devices harvested from your Flip part
  description files.
* **Erase** - full chip erase.
* **Erase Blocks...** - erase a start/end range only.
* **Blank Check** (`Ctrl+B`) - check the range is blank.
* **Read** - read the target memory into the buffer.
* **Verify** - compare memory against the buffer.
* **Check Communications** - does the device answer at all?
* **Write/Read Special Bits...** - BLJB, X2, BSB/SBV and Security Level.

**Settings**

* **Connection settings...** - port, device, both baud rates, batchisp path.
* **Terminal window...** - open the serial monitor.
* **Device** - the recent-device quick list.

**Help**

* **Copy firmware reset snippet** - the C code for the reset poller.
* **Help topics...** - the firmware reset explanation window.

## The toolbar

Left to right: **Device**, **Serial: Auto**, **Load HEX**, **Run**, **Start
App**, **Firmware Reset**, **Terminal**. Separators group them the way real FLIP
groups its buttons.

## The three panels

**Operations Flow** - the Erase / Blank Check / Program / Verify checkboxes, a
**Run** button, a **Clear** button, the target memory picker (FLASH or EEPROM)
and the **AutoISP** checkbox.

A checked stage runs as part of Run. A checkbox turns **green** when that stage
passed and **red** when it failed. **Clear** puts everything back to defaults.

**FLASH Buffer Information** - the size and address range of your hex, the
checksum equivalent (data bytes and byte count), the hex filename and how long
ago it was built. If a newer build shows up in CodeBlocks, a blue "
NEWER BUILD" line appears and you can click it to switch. It never switches on
its own.

**The device frame** - signature bytes, device boot ids, hardware byte, BLJB,
X2, BSB/SBV and security level, then the run buttons. The +/- toggle collapses
it. Collapsing only ever moves the bottom edge, so the buttons below never shift
under your mouse.

## Keyboard

| Key | Action |
| :-- | :-- |
| `F5` | Run |
| `F6` | Start Application |
| `Ctrl+O` | Load HEX |
| `Ctrl+S` | Save Buffer Contents |
| `Ctrl+B` | Blank Check |
| `Ctrl+T` | Serial: Auto (connect and show terminal) |
| `Ctrl+L` | Clear monitor |
| `Ctrl+R` | Firmware Reset |
| `Ctrl+Shift+C` | Copy the firmware reset snippet |
