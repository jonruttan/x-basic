DEF FN and FN (`basic/parse.x`, `basic/exec.x`) as the 6502's DEF and
FNDOER run them: a function of one numeric argument, its formula read at
each call with the argument's variable set to the argument and then put
back.  DEF skips its formula as DATA is skipped, so a formula's error is
the call's.  The values are what Commodore's BASIC 2, built from the same
routines, prints in VICE; its errors there are the long forms of these.

## calls

### the argument's variable is set for the call and put back after it

```x
(%basic-typed "10 DEF FNA(X)=X*X+1\n20 X=5:PRINT FNA(3);X;FNA(FNA(2))\nRUN")
```
---
```output
10 DEF FNA(X)=X*X+1
20 X=5:PRINT FNA(3);X;FNA(FNA(2))
RUN
 10  5  26 

OK
```

### a formula reads the other variables as they are at the call

```x
(%basic-typed "10 DEF FNB(Y)=Y+Z:Z=10:PRINT FNB(1)\nRUN")
```
---
```output
10 DEF FNB(Y)=Y+Z:Z=10:PRINT FNB(1)
RUN
 11 

OK
```

### a formula that does not parse is ?SN where it is called, not at its DEF

```x
(%basic-typed "30 DEF FNC(X)=X+:PRINT \"OK\"\n40 PRINT FNC(1)\nRUN")
```
---
```output
30 DEF FNC(X)=X+:PRINT "OK"
40 PRINT FNC(1)
RUN
OK

?SN ERROR IN  40
OK
```

## errors

### FN with no DEF is ?UF

```x
(%basic-typed "PRINT FNB(1)")
```
---
```output
PRINT FNB(1)

?UF ERROR
OK
```

### DEF typed at the prompt is ?ID

```x
(%basic-typed "DEF FNA(X)=X")
```
---
```output
DEF FNA(X)=X

?ID ERROR
OK
```

### a string function is ?TM

```x
(%basic-typed "10 DEF FNA$(X)=X\nRUN")
```
---
```output
10 DEF FNA$(X)=X
RUN

?TM ERROR IN  10
OK
```

### a line typed clears the functions with the variables

```x
(%basic-typed "10 DEF FNA(X)=2*X\nRUN\nPRINT FNA(4)\n20 REM\nPRINT FNA(4)")
```
---
```output
10 DEF FNA(X)=2*X
RUN

OK
PRINT FNA(4)
 8 

OK
20 REM
PRINT FNA(4)

?UF ERROR
OK
```
