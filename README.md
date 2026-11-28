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

Pre-release: no release has been cut. Paired with x-lang v0.62.0
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
  `LIST`, `NEW`, `CLEAR`, `NULL`, `POKE`, `WAIT`, `GET`, `SAVE`, `LOAD`,
  and `DEF FN` with `FN` calls. `GET` waits for a key, which the terminal shows, as a
  KIM's does. A `WAIT` that does not hold at once waits for ever: only
  the program writes the memory it watches.
- **Functions.** `SGN INT ABS LEN STR$ VAL ASC CHR$ LEFT$ RIGHT$ MID$
  POS FRE PEEK USR`, and `SQR RND LOG EXP SIN COS TAN ATN` with `^` as
  `EXP(Y*LOG(X))`, step for step from the source's tables
  (`lib/basic/mbf-math.x`). A string's bytes are kept as a list, so a
  zero byte (`CHR$(0)`) is counted, compared and stored like any other;
  `VAL` reads to it, and the terminal is not sent it.
- **Start-up.** `MEMORY SIZE?` and `WIDTH?`, as the KIM build's INIT
  asks them: a blank size takes RAM to $C000, a blank width keeps 72
  columns, and an answer that does not read is asked again. Then the
  bytes free and the banner.
- **Memory.** A 64K byte image laid out as the 6502 lays it out
  (`lib/basic/mem.x`): the crunched program from $4001, simple variables of
  seven bytes, arrays, and strings given space down from the top and
  collected as GARBA2 collects them. `FRE` is exact; `?OM` when the
  space runs out. `PEEK` and `POKE` read and write the image, and a
  variable's value is kept only there. The program runs from its parsed
  lines, so a `POKE` into its text is not seen by `RUN` or `LIST`, and
  the interpreter's pointers and the ROM are not in the image.
- **Tape.** `SAVE` and `LOAD` use a file holding what the KIM-1 monitor
  writes to cassette (`lib/basic/tape.x`): 100 SYN, `*`, the ID, the start
  address and the data as hex digit pairs, `/`, the checksum, two EOT.
  The file is `X_BASIC_TAPE`, or `basic.tape` in the current directory.
  `LOAD` takes the first record whatever its ID, puts it at $4001, says
  `LOADED` and reads the next line with no `OK`, as the KIM build does. A
  tape that cannot be read or written shows `FFFF`, the monitor's error
  display, and the program is kept.
- **USR.** A 6502 runs machine code in the image (`lib/basic/cpu.x`):
  the NMOS part's documented instructions, decimal mode included.
  `USR(X)` puts X in the floating accumulator in page zero ($B1-$B6,
  FACOV $C0) and calls through USRPOK, the JMP at $0A, its address at
  $0B and $0C; INIT points it at FCERR, so `USR` is `?FC` until a program
  `POKE`s an address there. AYINT ($2FC2) and GIVAYF ($3195), at $06 and
  $08, run as BASIC's own routines; their addresses are those of the
  KIM BASIC that shipped. Page zero holds only these and the FAC; BRK
  or an undocumented opcode stops the routine.
- **Errors.** Two-letter, as the KIM build prints them:
  `?SN ERROR IN  20`.

GW-BASIC, from Microsoft's MIT-licensed 8086 source
([microsoft/GW-BASIC](https://github.com/microsoft/GW-BASIC)), is under
way (`lib/basic/gwbasic.x`), run by the same machine with
`X_BASIC_DIALECT=gw`:

- **Numbers.** `lib/basic/mbf86.x`: 16-bit integers that become singles
  when they will not fit, four-byte singles and eight-byte doubles,
  added, multiplied and divided as MATH1.ASM and MATH2.ASM do it, read as
  FIN reads a constant and printed as FOUT prints one. `\`, `MOD`, `XOR`,
  `EQV` and `IMP`; `CINT`, `CSNG`, `CDBL` and `FIX`. An overflow or a
  division by zero in arithmetic prints its message and goes on with the
  largest number, as the 8086 does.
- **Maths.** `lib/basic/mbf86-math.x`: `^`, `SQR`, `LOG`, `EXP`, `SIN`,
  `COS`, `TAN`, `ATN` and `RND` as MATH1.ASM and MATH2.ASM compute them,
  each in single precision, with Hart's coefficients; inside one of them
  or a `^`, an overflow goes on and only the first is printed. `RND` with
  no argument, and `RANDOMIZE`, which asks for the seed when it is given
  none and keeps the old seed's lowest byte, so the same seed twice need
  not give the same numbers; `CLEAR` and `RUN` put the seed back.
- **Lines.** The 8086's tokens. A reserved word is taken only where a
  name could not go on, so `FORI` is a name and `FOR I` a loop; `'`
  starts a remark. Names keep 40 characters and a `$`, `%`, `!` or `#`;
  one without a sign is a single.
- **Memory.** Variables laid out as the 8086 lays them out: VALTYP, the
  name, then two, three, four or eight bytes of value. The program from
  $1000 and memory to 512 bytes under 64K (the build decides both), so
  60926 bytes free.
- **Messages.** The copyright line and the bytes free at start-up, `Ok`,
  and the long messages: `Undefined line number in 10`.
- **Statements.** The 6502's, and `IF ... THEN ... ELSE` (each IF
  between needing an ELSE of its own), `WHILE` and `WEND`, `DEFINT`,
  `DEFSNG`, `DEFDBL` and `DEFSTR` (set back by `CLEAR` and `RUN`),
  `SWAP`, `ERASE` and `OPTION BASE`.
- **Strings.** `HEX$` and `OCT$` of a word from -32768 to 65535 (FRQINT),
  `INSTR` with or without its start, `SPACE$` and `STRING$`, as
  BISTRS.ASM makes them. The `MID$` statement replaces a string's bytes
  where they are, its length kept, a string in the program's text copied
  to string space first. `MKI$`, `MKS$` and `MKD$` make a number the
  bytes a variable of its type holds, and `CVI`, `CVS` and `CVD` read
  them back (DSKCOM.ASM).
- **Output and input.** `WRITE`, strings in quotes and numbers without
  the blank for their sign, commas between (FIVEO.ASM); `LINE INPUT`,
  the whole line typed into a string, with no question mark. `PRINT
  USING` as BIPRTU.ASM scans its format: `#`, `.`, `,`, `+` and a
  trailing `-`, `**`, `$$`, `**$` and `^^^^`; `!`, `\ \` and `&`; `_`;
  the format again while values are left. Each number is built as PUFOUT
  builds it in FBUFF, a `%` ahead of one too wide for its field.
- **Errors.** `ON ERROR GOTO`, `RESUME` (the erring statement, `NEXT` or
  a line), `ERROR` and the numbers `ERR` and `ERL` give, as GWMAIN.ASM
  traps them: the line typed is trapped too (`ERL` 65535), an error in
  the handler is printed, `ON ERROR GOTO 0` there prints the one being
  handled, and running off the program's end in it is `No RESUME`. While
  the trap is set an overflow or a division by zero is an error it takes.

Those it does not run, and the words the KIM runs that mean another thing
here (`SAVE`, `LOAD`, `GET`, `WAIT`), print `SAVE is not in x-basic yet`.
Not yet: `GO TO` with a blank, DEF FN's memory entries, LIST of the
crunched text, and the line editor after a syntax error.

A
program run from a file (`x -l basic -f FILE`) or piped in waits on a
line reader in x-lang.

## Install

    make install        # into <share>/bundles/basic
    make check          # the suite, against tests/contract/known-failures.txt
    make card           # docs/card.md: its format, its row and its programs

[docs/card.md](docs/card.md) is the card: the prompt and BASIC as the KIM
takes it, in tables and programs that `make card` runs, with a table of
what GW-BASIC adds.

## Licence

MIT No Attribution (MIT-0). Microsoft and BASIC-M6502 are named only to
say which BASIC a dialect follows.
