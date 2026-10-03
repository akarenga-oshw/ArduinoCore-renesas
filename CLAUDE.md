# Akarenga UNO R4 Minima core

Fork of [arduino/ArduinoCore-renesas](https://github.com/arduino/ArduinoCore-renesas)
for a board that is an UNO R4 Minima with a 12MHz external crystal as the main
clock and a 32.768kHz subclock driving the RTC.

Only the MINIMA variant is supported. `boards.txt` is trimmed to `minima.*`,
and everything else upstream ships is either excluded when packaging or simply
unused.

## Things that are easy to get wrong

**`platform.txt` carries the real version.** Upstream keeps `version=9.9.9` in
git and substitutes the real one at package time with `sed -i`. This fork does
not: `package_akarenga.sh` rewrites no tracked file, so `boards.txt` and
`platform.txt` ship exactly as committed. The cost is that **every upstream
merge conflicts on `platform.txt`**, because upstream edits the `version=` line
and we edit the adjacent `name=` line. Resolve it by keeping our side and
choosing the new version number.

**The USB IDs have to agree in three places** or the IDE stops recognising the
board: `variants/MINIMA/pins_arduino.h` is what the device reports,
`boards.txt` `vid.N`/`pid.N` drive board detection and port matching, and
`upload.vid`/`upload.pid` are what dfu-util is told to look for. State the IDs
freely. How the vendor ID was obtained is a separate matter, with consequences
outside this repository: if it ever needs writing down, work the wording out
first rather than dropping it into a README.

**`USBD_STR_MANUF` lives in the core, not in a variant.** The manufacturer is
one value for the whole vendor, unlike VID/PID which are per board.

**Microsoft OS 2.0 descriptors in `cores/arduino/usb/USB.cpp`.** They are what
lets Windows bind WinUSB to the DFU runtime interface with no driver package,
and so no code signing certificate. That in turn is what lets **uploading a
sketch from the Arduino IDE** work on Windows without first double tapping
reset: the IDE runs dfu-util, which opens that interface to send DFU_DETACH and
put the running board into the bootloader.

This device is **composite**, so the compatible ID is scoped to a function subset
naming interface 2. The bootloader is non-composite and needs the opposite
arrangement; see its own CLAUDE.md. Why not the other way round is in the comment
on `desc_ms_os_20` in `cores/arduino/usb/USB.cpp`.

Changing any descriptor and testing on Windows needs the descriptor cache
cleared first, or Windows will not re-read anything:

    reg delete "HKLM\SYSTEM\CurrentControlSet\Control\usbflags\2886806A0100" /f

That key is VID+PID+bcdDevice, so bumping `bcdDevice` sidesteps the cache
entirely. Do not reach for that while testing, though: `bcdDevice` is the
device's release number, and the rule is to bump it **only when releasing
firmware whose descriptors have changed**, so that a board in hand can be
identified by the number it reports. The cache being keyed on it is a
consequence of that, not a reason to use it. While iterating, delete the key.

**Everything under `variants/MINIMA/` is generated. Do not edit it by hand.**
The clock configuration is the whole point of this fork, and it lives in the
e2studio FSP configurator, not in the header it produces:

| source of truth | generated from it |
|---|---|
| `extras/e2studioProjects/Santiago/configuration.xml` | `variants/MINIMA/includes/ra_gen/bsp_clock_cfg.h` |
| `extras/fsp` (submodule: the FSP sources) | `variants/MINIMA/libs/libfsp.a` |
| the e2studio project's build settings | `defines.txt`, `includes.txt`, `cflags.txt`, `cxxflags.txt`, `elc_defines.h` |

**Do not move the `extras/fsp` submodule off FSP 4.0.0.** It sits at
`9b5a853b` (`v4.0.0-5-g9b5a853b`), and `variants/MINIMA/includes/ra/fsp/inc/fsp_version.h`
agrees: `FSP_VERSION_STRING ("4.0.0")`. FSP 4.3.0 renamed the AGT registers from
`R_AGT0` to `R_AGTX0`, which breaks `cores/arduino/time.cpp:62` where `micros()`
reads the counter directly; renaming it to match was reported not to be enough
to make it work. See upstream issue
[#301](https://github.com/arduino/ArduinoCore-renesas/issues/301), where the
`arduino/fsp` repository holding several FSP versions at once made this easy to
get wrong: its URL suggests 4.4.0, but the recorded commit is 4.0.0 plus
patches. Because `fsp_to_arduino.sh` builds `libfsp.a` from whatever the
submodule is checked out at, and the result is an unreadable binary, **getting
this wrong fails at runtime rather than at merge time.**

`extras/e2studioProjects/Santiago/configuration.xml` and `ra_cfg.txt` are
tracked and carry real changes. The `.secure_xml` and `.settings/` diffs in the
same directory are IDE noise, deliberately left uncommitted.

The clock is set on the **Clocks tab of the FSP Configuration editor** in
e2studio, by editing the clock tree there. `configuration.xml` is that screen's
output, not an input: it is generated, like everything downstream of it.

What the change amounts to, as it reads on that screen and in `ra_cfg.txt`,
which mirrors its labels:

| | stock | here |
|---|---|---|
| XTAL | 0Hz | 12000000Hz |
| PLL Div | /4 | /2 |
| PLL Mul | x12 | x8 |
| Clock Src | HOCO | PLL |
| UCLK Src | HOCO | PLL |

In `configuration.xml` those are the `board.clock.xtal.freq`,
`board.clock.pll.div`, `board.clock.pll.mul`, `board.clock.clock.source` and
`board.clock.uclk.source` nodes. 12MHz / 2 * 8 = 48MHz, which matches
`-DF_CPU=48000000` and gives the 48MHz UCLK that USB requires.

`ra_cfg.txt` is the readable one of the two, so diff that to see what a
regeneration actually changed.

### When regeneration is needed

Only four things call for it:

1. We change the FSP configuration ourselves — the clock, or a peripheral.
2. Upstream moves the `extras/fsp` submodule (see Upstream: that is a decision
   first).
3. Upstream changes `variants/MINIMA/`.
4. Upstream changes `extras/e2studioProjects/Santiago/`.

**Nothing else does.** Edits to `cores/`, `libraries/`, `boards.txt` or
`platform.txt` never need e2studio, and neither does an upstream merge that
leaves those four alone. For calibration: the 17 commits between
`99f8ee40` and upstream's 1.6.0 touched none of them, so that whole release
needed no regeneration.

Check before assuming, against any range:

    BASE=$(git merge-base main upstream/main)
    for p in variants/MINIMA extras/fsp extras/e2studioProjects; do
      printf '%-28s %s\n' "$p" "$(git diff --name-only $BASE..upstream/main -- $p | wc -l)"
    done

### How to regenerate

First, in e2studio, import the project at
`extras/e2studioProjects/Santiago` and **build it once for Debug**. Then:

    cd extras/e2studioProjects/Santiago
    ./fsp_to_arduino.sh MINIMA

**The e2studio build is expected to fail. Ignore it.** Upstream confirms this
([#274](https://github.com/arduino/ArduinoCore-renesas/issues/274)): the RA
interrupt architecture makes it impossible to allocate every interrupt in one
binary, so you get errors like `VECTOR_NUMBER_KEY_INT undeclared` from
`ra_gen/hal_data.c`. The build is only there to produce the makefile and the
defines, and it does that before failing.

For the same reason the Santiago project is **deliberately incomplete** —
upstream says its pinmuxing is wrong and it is shared between Minima and WiFi.
Do not try to "fix" it.

Four ways this goes wrong:

- **Build Debug, not Release.** The script reads `./Debug/makefile`.
- **Pass the target.** It defaults to `UNOWIFIR4` and would overwrite the wrong
  variant.
- **Use e2studio with FSP 4.0.0** (the 2022-7 era). Opening `configuration.xml`
  in a newer e2studio silently upgrades the project to that e2studio's FSP.
  `BSP_CLOCKS_PLL_DIV_12 undefined` means this happened.
- **Never `git submodule update --remote`.** `--remote` moves submodules to
  their remote branch tip, which lands `extras/fsp` on FSP 4.4.0. Plain
  `git submodule update --init --recursive` checks out the recorded commit.

The script symlinks the `extras/fsp` submodule over the project's `ra/` tree,
builds, then **deletes and recreates** `variants/MINIMA/includes/`, so any manual
edit there is lost.

`configuration.xml` says which e2studio to use, so there is no separate version
to remember. It records `version="5.9.0+renesas.0.fsp.4.0.0"` and `version="4.0.0"`
for FSP, and `<raConfiguration version="7">` for the settings schema — the schema
is what a newer e2studio silently upgrades, so check `git diff` on this file after
opening it. It targets `R7FA4M1AB3CNE`; upstream says the project is not meant to
be accurate, since only its makefile and defines are used.

Afterwards, check the generated result rather than assuming it worked:

- `variants/MINIMA/includes/ra_gen/bsp_clock_cfg.h` should have
  `BSP_CFG_XTAL_HZ (12000000)`, `PLL_DIV_2`, `PLL_MUL_8_0`, and PLL as both
  `CLOCK_SOURCE` and `UCK_SOURCE`.
- Flash a sketch and confirm `SystemCoreClock` reads 48000000, and that an RTC
  reading tracks `millis()` to within tens of milliseconds over a few minutes.

That second check is there because the RTC clock source is chosen by one line,
`RTC_CLOCK_SOURCE` in `variants/MINIMA/pins_arduino.h`, and the core defaults to
`RTC_CLOCK_SOURCE_LOCO` when it is absent (`libraries/RTC/src/RTC.cpp`). LOCO is
an on-chip RC oscillator running thousands of ppm off, so losing that line costs
minutes a day — and nothing reports it, since `RTC.begin()` and `isRunning()`
both succeed on LOCO. A few minutes of comparison separates them by an order of
magnitude.

It says nothing about how accurate the crystal is. That needs a host clock as
the reference and hours of running, not two oscillators on the same board.

Because the configuration is shared, our 12MHz settings are in it too. Running
`fsp_to_arduino.sh UNOWIFIR4` from this repository would hand a real UNO R4 WiFi
a 12MHz crystal configuration it does not have. Only ever regenerate `MINIMA`
here.

## Packaging

    ./extras/package_akarenga.sh

Writes the archive plus an index fragment describing just that one version. The
fragment is **not** the file users point their IDE at. The published index
accumulates every release so Boards Manager can offer them all; merge the
fragment in with `merge-index.py` in the `akarenga-oshw/arduino-board-index`
clone.

bzip2 is deterministic but **tar stores each file's mtime**, so rebuilding from
the same commit yields a different archive and a different SHA-256. A `git
checkout` touching files is enough. An index therefore only matches the archive
built alongside it, and cannot be regenerated for an archive already published.
**Upload the archive and merge the fragment from the same run, or neither.**
Never rebuild to fix a checksum mismatch.

Release assets live in `akarenga-oshw/arduino-board-index` under tags prefixed
by architecture, e.g. `renesas-1.5.3-akarenga.1`. Versions must be
relaxed-semver: `X.Y.Z` or `X.Y.Z-prerelease.N`. `1.5.3.1` and `1.5.3a1` are
rejected by arduino-cli 1.5.1 and later.

## Upstream

    git fetch upstream --no-recurse-submodules
    git merge upstream/main

`--no-recurse-submodules` because fetching also brings upstream's tags, and an
old one references a `extras/tinyusb` commit that `arduino/tinyusb` no longer
serves, which makes the whole submodule fetch fail noisily. Nothing on
`upstream/main` needs that commit. Skipping recursion only defers fetching, so
afterwards pull in whatever a merge actually moved, one path at a time — and
never with `--remote`, which would move it off the recorded commit:

    git submodule update --init <path>

None of this affects compiling: nothing in the build refers to `extras/` —
`variants/MINIMA/includes.txt` names no path under it — and packaging excludes it
anyway. Submodules matter only for regenerating `variants/MINIMA/`, where
`libfsp.a` is built from `extras/fsp`.

Before merging, check what upstream touched that we also touched. Submodule
pointers show up as paths here too:

    BASE=$(git merge-base main upstream/main)
    comm -12 <(git diff --name-only $BASE..main | sort) \
             <(git diff --name-only $BASE..upstream/main | sort)

**`extras/fsp` in that list is a decision, not a step.** A merge moves the
recorded pointer, so simply running `git submodule update` afterwards lands us on
whatever FSP upstream chose — which is what "do not move off 4.0.0" above warns
against. Either keep 4.0.0 by restoring our gitlink as part of resolving the
merge, or take upstream's FSP and accept the work that follows: the `R_AGT0` to
`R_AGTX0` rename in `cores/arduino/time.cpp`, an e2studio matching that FSP
version, and regenerating `variants/MINIMA/` from it. Upstream has kept
`extras/fsp` at `9b5a853b` so far, so this has not come up yet.

`variants/MINIMA/` in that list means regenerating rather than merging, since
`libfsp.a` is a binary and the headers get wiped by `fsp_to_arduino.sh` anyway.
Regenerate with the FSP version the submodule is actually on afterwards, which
follows from the decision above.

`extras/package.sh` and `extras/package_index.json.template` are kept
byte-identical to upstream on purpose, so upstream's changes to them merge
cleanly. Our equivalents are `package_akarenga.sh` and
`package_akarenga_index.json.template`.

`.github/workflows/` is upstream's and unused. **Do not enable Actions on this
fork:** `release.yaml` would run upstream's `package.sh`, and
`compile-examples.yml` builds boards that `boards.txt` no longer defines.
Leaving the files untouched keeps them out of merge conflicts.

## Related repositories

| | |
|---|---|
| Bootloader | [akarenga-oshw/arduino-renesas-bootloader](https://github.com/akarenga-oshw/arduino-renesas-bootloader) |
| Index and release assets | [akarenga-oshw/arduino-board-index](https://github.com/akarenga-oshw/arduino-board-index) |

Which core version pairs with which bootloader is recorded in the release notes
on both sides.
