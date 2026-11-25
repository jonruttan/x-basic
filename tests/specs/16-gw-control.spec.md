GW-BASIC's ELSE, WHILE and WEND, the DEF types, SWAP, ERASE and OPTION
BASE (`lib/basic/exec.x`), as the 8086 source runs them.

## ELSE

### the clause a false IF runs

```x
(%gw-typed "10 FOR I=1 TO 3\n20 IF I=2 THEN PRINT \"TWO\" ELSE PRINT I\n30 NEXT\nRUN")
```
---
```output
10 FOR I=1 TO 3
20 IF I=2 THEN PRINT "TWO" ELSE PRINT I
30 NEXT
RUN
 1 
TWO
 3 
Ok
```

### each IF between needs an ELSE of its own

```x
(%gw-typed "IF 1 THEN IF 0 THEN PRINT \"A\" ELSE PRINT \"B\" ELSE PRINT \"C\"\nIF 0 THEN IF 1 THEN PRINT \"A\" ELSE PRINT \"B\" ELSE PRINT \"C\"")
```
---
```output
IF 1 THEN IF 0 THEN PRINT "A" ELSE PRINT "B" ELSE PRINT "C"
B
Ok
IF 0 THEN IF 1 THEN PRINT "A" ELSE PRINT "B" ELSE PRINT "C"
C
Ok
```

### ELSE and a line number

```x
(%gw-typed "10 IF 0 THEN 30 ELSE 40\n30 PRINT \"THIRTY\"\n40 PRINT \"FORTY\"\nRUN")
```
---
```output
10 IF 0 THEN 30 ELSE 40
30 PRINT "THIRTY"
40 PRINT "FORTY"
RUN
FORTY
Ok
```

## WHILE and WEND

### a loop while its formula holds

```x
(%gw-typed "10 I=1\n20 WHILE I<4\n30 PRINT I;\n40 I=I+1\n50 WEND\n60 PRINT \"DONE\"\nRUN")
```
---
```output
10 I=1
20 WHILE I<4
30 PRINT I;
40 I=I+1
50 WEND
60 PRINT "DONE"
RUN
 1  2  3 DONE
Ok
```

### a formula false at once goes on past the WEND

```x
(%gw-typed "10 WHILE 0\n20 PRINT \"NO\"\n30 WEND\n40 PRINT \"YES\"\nRUN")
```
---
```output
10 WHILE 0
20 PRINT "NO"
30 WEND
40 PRINT "YES"
RUN
YES
Ok
```

### loops inside loops

```x
(%gw-typed "I=0:WHILE I<2:J=0:WHILE J<2:PRINT I;J;:J=J+1:WEND:I=I+1:WEND")
```
---
```output
I=0:WHILE I<2:J=0:WHILE J<2:PRINT I;J;:J=J+1:WEND:I=I+1:WEND
 0  0  0  1  1  0  1  1 
Ok
```

### a WHILE with no WEND, and a WEND with no WHILE

```x
(%gw-typed "10 WHILE 1\nRUN\nWEND")
```
---
```output
10 WHILE 1
RUN
WHILE without WEND in 10
Ok
WEND
WEND without WHILE
Ok
```

## types by letter

### DEFINT, DEFSTR, and CLEAR putting them back

```x
(%gw-typed "DEFINT A-C:A=7.6:B=2.4:D=2.4:PRINT A;B;D\nDEFSTR S:S=\"HI\":PRINT S\nCLEAR:A=1.5:PRINT A")
```
---
```output
DEFINT A-C:A=7.6:B=2.4:D=2.4:PRINT A;B;D
 8  2  2.4 
Ok
DEFSTR S:S="HI":PRINT S
HI
Ok
CLEAR:A=1.5:PRINT A
 1.5 
Ok
```

## SWAP

### numbers and strings traded

```x
(%gw-typed "A=1:B=2:SWAP A,B:PRINT A;B\nA$=\"X\":B$=\"Y\":SWAP A$,B$:PRINT A$;B$")
```
---
```output
A=1:B=2:SWAP A,B:PRINT A;B
 2  1 
Ok
A$="X":B$="Y":SWAP A$,B$:PRINT A$;B$
YX
Ok
```

### two types, and a second variable SWAP had to make

```x
(%gw-typed "A=1:B$=\"Y\":SWAP A,B$\nX=1:SWAP X,Y")
```
---
```output
A=1:B$="Y":SWAP A,B$
Type mismatch
Ok
X=1:SWAP X,Y
Illegal function call
Ok
```

## ERASE

### an array taken out, then made again; the arrays past it kept

```x
(%gw-typed "DIM A(5),B(3):A(1)=3:B(2)=9:ERASE A:DIM A(2):PRINT A(1);B(2)\nERASE Q")
```
---
```output
DIM A(5),B(3):A(1)=3:B(2)=9:ERASE A:DIM A(2):PRINT A(1);B(2)
 0  9 
Ok
ERASE Q
Illegal function call
Ok
```

## OPTION BASE

### subscripts from 1, and the base set only once

```x
(%gw-typed "OPTION BASE 1\nDIM A(3):A(3)=5:PRINT A(3)\nPRINT A(0)\nOPTION BASE 0")
```
---
```output
OPTION BASE 1
Ok
DIM A(3):A(3)=5:PRINT A(3)
 5 
Ok
PRINT A(0)
Subscript out of range
Ok
OPTION BASE 0
Duplicate Definition
Ok
```
