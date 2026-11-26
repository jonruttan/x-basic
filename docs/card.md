# x-basic card

## Run

```sh
x -l basic                                # the prompt, the KIM-1's 6502 BASIC
X_BASIC_DIALECT=gw x -l basic             # GW-BASIC's
X_BASIC_FOLD_CASE=0 x -l basic            # only capitals are reserved words
X_BASIC_TAPE=FILE x -l basic              # the tape SAVE and LOAD use
sh tests/card-run.sh FILE                 # FILE's lines typed at a new machine
X_BASIC_DIALECT=gw sh tests/card-run.sh tests/card/gw.bas | sed 1q -> THREE 3  1
```

```basic
10 FOR I=1 TO 3
20 PRINT I;
30 NEXT
RUN
```

```output
 1  2  3
OK
```

| At the prompt          | Does                                             |
|------------------------|--------------------------------------------------|
| `MEMORY SIZE?` `WIDTH?` | the KIM's start-up questions; Return takes each |
| a line with a number   | is stored, in its place; the variables are cleared |
| a number alone         | deletes that line                                |
| any other line         | runs at once, then `OK`                          |
| `RUN` `RUN 100`        | run the program; from line 100                   |
| `LIST`                 | show the program                                 |
| `NEW` `CLEAR`          | forget the program; the variables                |
| `CONT`                 | go on after `STOP` or `END`                      |
| `SAVE` `LOAD`          | write the program to the tape; read it back      |
| a program on this page | its lines typed; blank lines and end blanks cut  |

## PRINT

```basic
PRINT 2+3*4, 7/2, 2^10
PRINT "A";"B", "C"
? 1/3; -5; 1E10; .001
PRINT TAB(5);"X";SPC(3);"Y"
print "lower", sqr(16)
```

```output
 14            3.5           1024
OK
AB            C
OK
 .333333333 -5  1E+10  1E-03
OK
     X   Y
OK
lower          4
OK
```

| In PRINT               | Does                                             |
|------------------------|--------------------------------------------------|
| `,`                    | on to the next zone, 14 columns each             |
| `;`                    | nothing between; at the end, the line stays open |
| `TAB(N)` `SPC(N)`      | on to column N; N blanks                         |
| a number               | a blank or `-` before it, a blank after          |
| `?`                    | `PRINT`                                          |
| `POS(0)`               | the column the next character goes in            |

## Numbers

```basic
PRINT INT(-2.5);ABS(-3);SGN(-9);SQR(2)
PRINT 4*ATN(1);EXP(1);LOG(10);SIN(1);COS(0)
PRINT 7 AND 3;7 OR 8;NOT 0;3=3;3<>3
A%=2.7:PRINT A%
```

```output
-3  3 -1  1.41421356
OK
 3.14159266  2.71828183  2.30258509  .841470985  1
OK
 3  15 -1 -1  0
OK
 2
OK
```

| Written                | Is                                               |
|------------------------|--------------------------------------------------|
| `A` `AB` `A1`          | a number: two characters of a name are kept      |
| `A%`                   | an integer, -32768 to 32767                      |
| `A$`                   | a string, to 255 characters                      |
| `1.5` `-3` `1E10` `.5` | a constant: nine digits, to 1.7E+38              |
| `+` `-` `*` `/` `^`    | arithmetic; `^` binds tightest                   |
| `=` `<>` `<` `>` `<=` `>=` | a comparison: -1 when true, 0 when not       |
| `AND` `OR` `NOT`       | on the bits of 16-bit integers                   |
| `SGN` `INT` `ABS` `SQR` | the sign; the floor; the size; the square root  |
| `LOG` `EXP`            | the natural logarithm; e to the power            |
| `SIN` `COS` `TAN` `ATN` | in radians                                      |
| `RND(1)`               | the next random number, 0 to 1                   |
| `LET A=1` `A=1`        | assignment                                       |

## Strings

```basic
A$="HELLO WORLD"
PRINT LEN(A$);LEFT$(A$,5);"/";RIGHT$(A$,5);"/";MID$(A$,7,3)
PRINT ASC("A");CHR$(66);STR$(12);VAL("3.5")+1
PRINT "AB"+"CD", "A"<"B"
```

```output
OK
 11 HELLO/WORLD/WOR
OK
 65 B 12 4.5
OK
ABCD          -1
OK
```

| Function               | Is                                               |
|------------------------|--------------------------------------------------|
| `LEN(A$)`              | how many characters                              |
| `LEFT$(A$,N)` `RIGHT$(A$,N)` | the first N; the last N                    |
| `MID$(A$,I)` `MID$(A$,I,N)` | from the Ith on; N of them                  |
| `ASC(A$)` `CHR$(N)`    | the first character's code; a code's character   |
| `STR$(N)` `VAL(A$)`    | a number as it prints; the number a string reads |
| `A$+B$`                | the two joined                                   |

## Flow and data

```basic
10 DIM A(5)
20 FOR I=0 TO 5:READ A(I):NEXT
30 DATA 3,1,4,1,5,9
40 S=0:FOR I=5 TO 0 STEP -1:S=S+A(I):NEXT
50 PRINT S
60 ON 2 GOSUB 100,200:PRINT "BACK"
70 IF S>20 THEN PRINT "BIG":GOTO 90
80 PRINT "SMALL"
90 END
100 PRINT "ONE":RETURN
200 PRINT "TWO":RETURN
RUN
```

```output
 23
TWO
BACK
BIG
OK
```

| Statement              | Does                                             |
|------------------------|--------------------------------------------------|
| `A:B`                  | two statements on a line                         |
| `GOTO N`               | go to line N                                     |
| `GOSUB N` `RETURN`     | go to line N; come back                          |
| `IF X THEN ...` `IF X GOTO N` | the rest of the line when X is not 0      |
| `ON X GOTO N,...` `ON X GOSUB N,...` | the Xth line of the list           |
| `FOR I=A TO B STEP C` `NEXT I` | a loop; `STEP 1` and the name may go     |
| `DIM A(N)` `DIM A(N,M)` | an array, 0 to N; 0 to 10 when not said         |
| `DATA 1,"A"` `READ A,B$` | items in the program; the next ones read       |
| `RESTORE`              | read the items from the first again              |
| `DEF FNA(X)=X*X` `FNA(7)` | a function of one line; a call                |
| `REM TEXT`             | a remark                                         |
| `END` `STOP`           | stop; stop and say where                         |

## INPUT

```input
ADA
3,4
```

```basic
10 INPUT "NAME";N$
20 INPUT A,B
30 PRINT "HELLO, ";N$;A+B
RUN
```

```output
NAME? ADA
? 3,4
HELLO, ADA 7
OK
```

| Statement              | Does                                             |
|------------------------|--------------------------------------------------|
| `INPUT A` `INPUT A,B$` | ask `?` and read a line into the variables       |
| `INPUT "TEXT";A`       | ask with TEXT first                              |
| `GET A$`               | wait for one key                                 |

## Machine

```basic
10 PRINT "A"
20 STOP
30 PRINT "B"
RUN
CONT
PRINT FRE(0)
POKE 20000,65:PRINT PEEK(20000)
```

```output
A
BREAK IN  20
OK
B
OK
 32739
OK
 65
OK
```

| Word                   | Does                                             |
|------------------------|--------------------------------------------------|
| `FRE(0)`               | the bytes free, of a 64K image laid out as a 6502's |
| `PEEK(A)` `POKE A,B`   | read a byte of the image; write one              |
| `USR(X)`               | call 6502 code through the address at 11 and 12  |
| `WAIT A,M` `WAIT A,M,X` | wait until the byte at A, masked, is not 0      |
| `NULL N`               | N zero bytes after each new line                 |

## Errors

```basic
10 DEF FNS(X)=X*X
20 PRINT FNS(7)
30 SCORE=5
RUN
PRINT 1/0
PRINT "A"+1
NEXT
RETURN
DIM A(2):PRINT A(3)
```

```output
 49
?SN ERROR IN  30
OK
?/0 ERROR
OK
?TM ERROR
OK
?NF ERROR
OK
?RG ERROR
OK
?BS ERROR
OK
```

| Error                  | Is                                               |
|------------------------|--------------------------------------------------|
| `?SN`                  | syntax; `SCORE` holds `OR`, a word found in a name |
| `?NF` `?RG`            | `NEXT` without `FOR`; `RETURN` without `GOSUB`   |
| `?OD`                  | out of `DATA`                                    |
| `?FC`                  | a function called with a number it cannot take   |
| `?OV` `?/0`            | overflow; division by zero                       |
| `?OM`                  | out of memory                                    |
| `?US` `?UF`            | a line that is not there; a function not defined |
| `?BS` `?DD`            | a subscript out of range; an array made twice    |
| `?ID` `?CN`            | not at the prompt; cannot continue               |
| `?TM`                  | a string where a number goes, or the other way   |
| `?LS` `?ST`            | a string too long; a string formula too complex  |
| `IN  30`               | the line it happened in                          |

## GW-BASIC

| With `X_BASIC_DIALECT=gw` | Is                                            |
|------------------------|--------------------------------------------------|
| `A%` `A!` `A#` `A$`    | an integer; a single; a double; a string         |
| a name                 | 40 characters kept; `FORI` is a name             |
| `\` `MOD`              | integer division; its remainder                  |
| `XOR` `EQV` `IMP`      | on the bits, beside `AND` `OR` `NOT`             |
| `CINT` `CSNG` `CDBL` `FIX` | to an integer; a single; a double; cut whole |
| `IF X THEN ... ELSE ...` | the other way too                              |
| `WHILE X` `WEND`       | a loop while X is not 0                          |
| `DEFINT A-Z` `DEFSNG` `DEFDBL` `DEFSTR` | a name's type by its first letter |
| `SWAP A,B` `ERASE A`   | swap two variables; forget an array              |
| `OPTION BASE 1`        | arrays from 1                                    |
| `'`                    | a remark                                         |
| `Ok`, `Syntax error in 10` | the ready text; the long messages            |

## Differs

| Here                                        | On the machine                |
|---------------------------------------------|-------------------------------|
| `print` is read as `PRINT`; a string keeps its case | capitals only         |
| a program in a file or a pipe is not run    | a tape, or a file             |
| GW's `SAVE` says `SAVE is not in x-basic yet` | writes a file               |

## More

| Where                          | What                                     |
|--------------------------------|------------------------------------------|
| `README.md`                    | each dialect, and what it does not run yet |
| `lib/basic/m6502.x`            | the KIM's words, in the order it finds them |
| `lib/basic/gwbasic.x`          | GW-BASIC's                               |
| `tests/specs/`                 | each statement, held to the source       |
| `tests/card-run.sh`            | types a program of this page at a machine |
