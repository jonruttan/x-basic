# x-basic — BASIC on x-lang

BASIC on [x-lang](https://github.com/jonruttan/x-lang), loaded as a lang,
with one module a dialect. The first is Microsoft's 6502 BASIC 1.1 as
built for the KIM-1, read from the source Microsoft released under the
MIT licence ([microsoft/BASIC-M6502](https://github.com/microsoft/BASIC-M6502)).
Dartmouth, BASIC-80 (MBASIC), GW-BASIC, Watcom BASIC and BBC BASIC are to
follow, each a module beside it.

    x -l basic                                # a prompt

    10 FOR I=1 TO 3
    20 PRINT I;
    30 NEXT
    RUN
     1  2  3
    OK

## Status

Pre-release: no release has been cut. Paired with x-lang v0.60.0
(`bundle.xon` is the checkable row).

The 6502 dialect (`lib/basic/m6502.x`):

- **Lines.** A numbered line is stored and any other runs at once, then
  `OK`. Entering or deleting a line clears the variables. Reserved words
  are found inside names, as CRUNCH finds them: `FORI=1TO9`, and `SCORE`
  is `SC OR E`. `?` is `PRINT`. Names are two characters and a `$` or
  `%`.
- **Case.** Reserved words and names read in either case: a typed line
  is upper-cased, all but its strings, REM's remark and DATA's items, so
  LIST shows capitals. `X_BASIC_FOLD_CASE=0` (or `no`, `off`, `false`)
  reads lines as typed, where only capitals are reserved words, as on
  the 6502.
- **Numbers.** The five-byte format, built of integers (`lib/basic/mbf.x`):
  a value is the floating accumulator, four mantissa bytes and the
  guard byte, rounded only where the 6502 rounds, its multiply's lost
  bit included. `?OV` past 2^127, nine digits printed, fixed notation
  from .01 to 999999999.
- **Statements.** `PRINT` (with `,` zones of 14, `;`, `TAB(`, `SPC(`),
  `LET`, `GOTO`, `GOSUB`, `RETURN`, `IF ... THEN`, `IF ... GOTO`,
  `ON ... GOTO|GOSUB`, `FOR ... TO ... STEP`, `NEXT`, `DIM`, `DATA`,
  `READ`, `RESTORE`, `INPUT`, `END`, `STOP`, `CONT`, `REM`, `RUN`,
  `LIST`, `NEW`, `CLEAR`, `NULL`, and `DEF FN` with `FN` calls.
- **Functions.** `SGN INT ABS LEN STR$ VAL ASC CHR$ LEFT$ RIGHT$ MID$
  POS FRE`, and `SQR RND LOG EXP SIN COS TAN ATN` with `^` as
  `EXP(Y*LOG(X))`, step for step from the source's tables
  (`lib/basic/mbf-math.x`).
- **Start-up.** `MEMORY SIZE?` and `WIDTH?`, as the KIM build's INIT
  asks them: a blank size takes RAM to $C000, a blank width keeps 72
  columns, and an answer that does not read is asked again. Then the
  bytes free and the banner.
- **Memory.** A 64K byte image laid out as the 6502 lays it out
  (`lib/basic/mem.x`): the crunched program from $4001, simple variables of
  seven bytes, arrays, and strings given space down from the top and
  collected as GARBA2 collects them. `FRE` is exact; `?OM` when the
  space runs out.
- **Errors.** Two-letter, as the KIM build prints them:
  `?SN ERROR IN  20`.

Not yet: `PEEK POKE USR WAIT GET LOAD SAVE`. A
program run from a file (`x -l basic -f FILE`) or piped in waits on a
line reader in x-lang.

## Install

    make install        # into <share>/bundles/basic
    make check          # the suite, against tests/contract/known-failures.txt

## Licence

MIT No Attribution (MIT-0). Microsoft and BASIC-M6502 are named only to
say which BASIC a dialect follows.
