GW-BASIC's MID$ statement (LHSMID in BISTRS.ASM): a string's bytes
replaced where they are, its length kept.

## replacing

### from a position, as far as the new text or the string goes

```x
(%gw-typed "A$=\"ABCDEF\":MID$(A$,2)=\"XY\":PRINT A$\nMID$(A$,5)=\"1234\":PRINT A$\nMID$(A$,1,1)=\"QQ\":PRINT A$")
```
---
```output
A$="ABCDEF":MID$(A$,2)="XY":PRINT A$
AXYDEF
Ok
MID$(A$,5)="1234":PRINT A$
AXYD12
Ok
MID$(A$,1,1)="QQ":PRINT A$
QXYD12
Ok
```

### none at all when the count is 0

```x
(%gw-typed "A$=\"ABC\":MID$(A$,2,0)=\"Z\":PRINT A$")
```
---
```output
A$="ABC":MID$(A$,2,0)="Z":PRINT A$
ABC
Ok
```

### an element of an array

```x
(%gw-typed "DIM S$(2):S$(1)=\"ABC\":MID$(S$(1),2)=\"Z\":PRINT S$(1)")
```
---
```output
DIM S$(2):S$(1)="ABC":MID$(S$(1),2)="Z":PRINT S$(1)
AZC
Ok
```

### a string in the program's text is copied first

```x
(%gw-typed "10 A$=\"HELLO\":B$=A$\n20 MID$(A$,1)=\"J\"\n30 PRINT A$;\" \";B$\nRUN")
```
---
```output
10 A$="HELLO":B$=A$
20 MID$(A$,1)="J"
30 PRINT A$;" ";B$
RUN
JELLO HELLO
Ok
```

## errors

### a position of 0 or past the end, and a number's variable

```x
(%gw-typed "A$=\"ABCDEF\":MID$(A$,7)=\"Z\"\nMID$(A$,0)=\"Z\"\nMID$(A,1)=\"Z\"")
```
---
```output
A$="ABCDEF":MID$(A$,7)="Z"
Illegal function call
Ok
MID$(A$,0)="Z"
Illegal function call
Ok
MID$(A,1)="Z"
Type mismatch
Ok
```
