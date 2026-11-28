GW-BASIC's MKI$, MKS$ and MKD$, CVI, CVS and CVD (DSKCOM.ASM): a number
as the bytes a variable of its type holds, low byte first, and back.

## MKI$, MKS$ and MKD$

### an integer's two bytes

```x
(%gw-typed "A$=MKI$(258):B$=MKI$(-1):PRINT LEN(A$);ASC(A$);ASC(RIGHT$(A$,1));ASC(B$);ASC(RIGHT$(B$,1))")
```
---
```output
A$=MKI$(258):B$=MKI$(-1):PRINT LEN(A$);ASC(A$);ASC(RIGHT$(A$,1));ASC(B$);ASC(RIGHT$(B$,1))
 2  2  1  255  255 
Ok
```

### a single's four, the exponent last and the sign in the byte before it

```x
(%gw-typed "A$=MKS$(1.5):B$=MKS$(-1):PRINT LEN(A$);ASC(A$);ASC(MID$(A$,3));ASC(MID$(A$,4));ASC(MID$(B$,3))")
```
---
```output
A$=MKS$(1.5):B$=MKS$(-1):PRINT LEN(A$);ASC(A$);ASC(MID$(A$,3));ASC(MID$(A$,4));ASC(MID$(B$,3))
 4  0  64  129  128 
Ok
```

### a double's eight, and a zero's all zero

```x
(%gw-typed "PRINT LEN(MKD$(1));ASC(RIGHT$(MKD$(1),1));ASC(MKS$(0));ASC(RIGHT$(MKS$(0),1))")
```
---
```output
PRINT LEN(MKD$(1));ASC(RIGHT$(MKD$(1),1));ASC(MKS$(0));ASC(RIGHT$(MKS$(0),1))
 8  129  0  0 
Ok
```

### the number forced to the type first

```x
(%gw-typed "PRINT CVI(MKI$(2.6))\nPRINT MKI$(40000)\nPRINT MKS$(\"A\")")
```
---
```output
PRINT CVI(MKI$(2.6))
 3 
Ok
PRINT MKI$(40000)
Overflow
Ok
PRINT MKS$("A")
Type mismatch
Ok
```

## CVI, CVS and CVD

### back again

```x
(%gw-typed "PRINT CVI(MKI$(-12345));CVS(MKS$(1.5));CVD(MKD$(.125#))")
```
---
```output
PRINT CVI(MKI$(-12345));CVS(MKS$(1.5));CVD(MKD$(.125#))
-12345  1.5  .125 
Ok
```

### the first bytes read, a shorter string refused

```x
(%gw-typed "PRINT CVI(CHR$(1)+CHR$(2)+CHR$(3))\nPRINT CVI(\"A\")\nPRINT CVS(MKI$(1))")
```
---
```output
PRINT CVI(CHR$(1)+CHR$(2)+CHR$(3))
 513 
Ok
PRINT CVI("A")
Illegal function call
Ok
PRINT CVS(MKI$(1))
Illegal function call
Ok
```
