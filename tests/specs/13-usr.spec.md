USR (`lib/basic/exec.x`, `lib/basic/cpu.x`).  USR(X) puts X in the
floating accumulator and calls the 6502 routine USRPOK jumps to: USRPOK is
a JMP at $0A, its address at $0B and $0C, and INIT points it at FCERR.  The
value is the FAC after the routine's RTS.  AYINT ($2FC2) and GIVAYF
($3195), whose addresses INIT leaves at $06 and $08, are BASIC's own
routines.

## the vector

### INIT leaves USRPOK a JMP to FCERR, so USR is ?FC

```x
(%basic-typed "PRINT PEEK(10);PEEK(11);PEEK(12);PEEK(6);PEEK(7);PEEK(8);PEEK(9)\nPRINT USR(1)")
```
---
```output
PRINT PEEK(10);PEEK(11);PEEK(12);PEEK(6);PEEK(7);PEEK(8);PEEK(9)
 76  75  48  194  47  149  49 

OK
PRINT USR(1)

?FC ERROR
OK
```

## a routine

### a routine that only returns leaves its argument

RTS at $0300.

```x
(%basic-typed "POKE 768,96:POKE 11,0:POKE 12,3:PRINT USR(5);USR(-1.5)")
```
---
```output
POKE 768,96:POKE 11,0:POKE 12,3:PRINT USR(5);USR(-1.5)
 5 -1.5 

OK
```

### a routine works on the FAC in page zero

INC FACEXP ($B1), RTS: twice the argument.

```x
(%basic-typed "POKE 768,230:POKE 769,177:POKE 770,96:POKE 11,0:POKE 12,3:PRINT USR(5);USR(-1.5)")
```
---
```output
POKE 768,230:POKE 769,177:POKE 770,96:POKE 11,0:POKE 12,3:PRINT USR(5);USR(-1.5)
 10 -3 

OK
```

### AYINT and GIVAYF turn the FAC to an integer and back

JSR AYINT, LDY FACLO, INY, LDA FACMO, JMP GIVAYF: the integer part plus
one.  AYINT floors, and a number past 32767 is ?FC.

```x
(%basic-typed "10 FOR I=0 TO 10:READ B:POKE 768+I,B:NEXT\n20 DATA 32,194,47,164,181,200,165,180,76,149,49\n30 POKE 11,0:POKE 12,3\n40 PRINT USR(41);USR(-1.5);USR(2.9)\n50 PRINT USR(40000)\nRUN")
```
---
```output
10 FOR I=0 TO 10:READ B:POKE 768+I,B:NEXT
20 DATA 32,194,47,164,181,200,165,180,76,149,49
30 POKE 11,0:POKE 12,3
40 PRINT USR(41);USR(-1.5);USR(2.9)
50 PRINT USR(40000)
RUN
 42 -1  3 

?FC ERROR IN  50
OK
```

### a string argument leaves VALTYP a string's, and the value is ?TM

```x
(%basic-typed "POKE 768,96:POKE 11,0:POKE 12,3:PRINT USR(\"A\")")
```
---
```output
POKE 768,96:POKE 11,0:POKE 12,3:PRINT USR("A")

?TM ERROR
OK
```

### BRK stops the routine

```x
(%basic-typed "POKE 768,0:POKE 11,0:POKE 12,3:PRINT USR(1)")
```
---
```output
POKE 768,0:POKE 11,0:POKE 12,3:PRINT USR(1)

?OPCODE 00 AT 0300 IS NOT IN X-BASIC YET
OK
```
