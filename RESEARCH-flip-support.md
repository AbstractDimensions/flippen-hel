# FLIPpen Hel research notes

Verified 2026-10-12, against the local Flip 3.4.7 install and its own help docs.
Every claim here was tested, not inferred. Labelled **[VERIFIED]** (ran it, saw
the output) or **[DOC]** (Atmel's own help pages).

## The headline correction

**`batchisp -device AT89LP51RD2` returns "Device does not exist."** **[VERIFIED]**

This matters because the app is named after that chip. Flip 3.4.7 ships
`AT89C51RD2.xml` and **no** `AT89LP51RD2.xml` **[VERIFIED]**. The LP part is the
newer silicon with the same bootloader, so in practice you select
**`AT89C51RD2`** and flash the LP with it - which is why the app defaults to
that. But the docs must not claim AT89LP51RD2 is a device name batchisp accepts.

## Device coverage: 122 part files, 81 usable over RS232

Batchisp reports two stages that matter: `Device selection` (it knows the name)
and `Hardware selection` (it can load the transport for that part). A part can
pass the first and fail the second.

Testing all 122 part files with `-hardware RS232` **[VERIFIED]**:

| | Count | Notes |
|---|---|---|
| Part files shipped | 122 | `PartDescriptionFiles\*.xml` |
| Pass `Hardware selection` over RS232 | **81** | genuinely flashable by FLIPpen Hel |
| Fail at `Hardware selection` | 41 | need USB DFU, CAN or another transport |

**The 81 that work over RS232** **[VERIFIED]**:

- `AT89C5115`, `AT89C5130`, `AT89C5131`, `AT89C5132`
- `AT89C51AC2`, `AT89C51AC3`, `AT89C51CC01`, `AT89C51CC02`, `AT89C51CC03`
- `AT89C51ED2`, `AT89C51IC2`, `AT89C51ID2`, `AT89C51IE2`
- `AT89C51RB2`, `AT89C51RC2`, `AT89C51RD2`, `AT89C51RE2`
- `AT89C51SND1`, `AT89C51SND2`, `AT89S54`, `AT89S58`, `AT89S64`
- `T89C51CC01`, `T89C51CC02`, `T89C51IC2`, `T89C51RB2`, `T89C51RC2`, `T89C51RD2`
- `AT32UC3A*` (20), `AT32UC3B*` (15), `AT32UC3C*` (9), `AT32UC3L*` (6) - 50 AVR32 parts
- `ATUC128D3`, `ATUC128D4`, `ATUCL3128U`, `ATUCL3256U`, `ATUCL364U`, `ATUCL4128U`, `ATUCL4256U`, `ATUCL464U`
- `ATOCDTARGET`

**The 41 that do not** (all fail `Hardware selection` with
`Could not load dynamic library`) **[VERIFIED]**:

- `AT90USB*` - USB DFU
- `AT90CAN*` - CAN
- `ATmega8U2/16U2/32U2`, `ATmega16U4/32U4/32U6` - USB DFU
- `ATmega16M1/32M1/64M1`, `ATmega32C1/64C1` - CAN
- all `ATxmega*` - PDI/USB, not RS232 bootloader

FLIPpen Hel is `-hardware RS232` only, so those 41 are out of reach regardless of
what the Device picker lists. **The picker over-promises.**

## Programming mode on the AT89 8051 parts **[DOC]**

`help/setting_the_autoisp_mode.htm`: "The first argument is the RESET signal
active level. The second argument is the PSEN signal level." The app sends
`-autoisp 1 0`: RESET active high, PSEN active low.

`help/using_the_operations_flow.htm`: checkboxes, "the checkbox color turns to
green" on pass and "red" on fail, plus a **Clear** button. All three behaviours
are implemented.

`help/launching_the_embedded_application_batch.htm`: `start <reset|noreset>
<address>`, and "after execution of this directive, there is no more possible
communication between batchisp and the target device bootloader, unless you reset
the device." That is why the app stages Start last.

`help/erasing_memory.htm`: "Performing a full chip erase usually resets the device
special bytes: the Software Security Byte, the Hardware Byte, the Boot Status Byte
and the Software Boot Vector." The Erase tooltip says this.

## batchisp is not self-contained **[VERIFIED]**

`batchisp.exe` needs `AtJniIsp.dll` beside it. Confirmed by stripping every
`Atmel` path from `PATH` and re-running the app's CLI: it failed with
`Could not find AtJniIsp.dll` until the DLL was shipped in `bin/`.

`AtLibUsbDfu.dll` is the USB DFU backend and must **not** be bundled - adding it
makes RS232 operations hang.

## Not verified

* Nothing has been run against a real AT89LP51RD2 or AT89C51RD2 board.
* Whether `-autoisp 1 0` works on a given board depends on DTR->RST / RTS->PSEN
  wiring that has never been inspected.
* The 81-part RS232 list proves batchisp *accepts* the device+hardware pair. It
  does not prove the flash works on each board.
