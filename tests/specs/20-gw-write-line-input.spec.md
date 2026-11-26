GW-BASIC's WRITE (FIVEO.ASM) and LINE INPUT (GWMAIN.ASM).

## WRITE

### strings in quotes, numbers without the blank for their sign, commas between

```x
(%gw-typed "A$=\"X\":WRITE 1,-2.5;\"A,B\";.5,A$\nWRITE")
```
---
```output
A$="X":WRITE 1,-2.5;"A,B";.5,A$
1,-2.5,"A,B",.5,"X"
Ok
WRITE

Ok
```

### a mark with nothing after it

```x
(%gw-typed "WRITE 1,")
```
---
```output
WRITE 1,
Syntax error
Ok
```

## LINE INPUT

### the whole line, blanks, commas and quotes kept, and no question mark

```x
(%gw-typed-input "10 LINE INPUT \"NAME? \";A$\n20 LINE INPUT B$\n30 PRINT \"[\";A$;\"][\";B$;\"]\"\nRUN" (list "  A, \"B\"" "HI"))
```
---
```output
10 LINE INPUT "NAME? ";A$
20 LINE INPUT B$
30 PRINT "[";A$;"][";B$;"]"
RUN
NAME?   A, "B"
HI
[  A, "B"][HI]
Ok
```

### an empty line is a null string

```x
(%gw-typed-input "10 LINE INPUT A$\n20 PRINT LEN(A$)\nRUN" (list ""))
```
---
```output
10 LINE INPUT A$
20 PRINT LEN(A$)
RUN

 0 
Ok
```

### a number's variable

```x
(%gw-typed "10 LINE INPUT A\nRUN")
```
---
```output
10 LINE INPUT A
RUN
Type mismatch in 10
Ok
```
