FRE and the memory behind it (`basic/mem.x`): the program crunched from
$4001, simple variables of 7 bytes after it, then arrays, and strings given
space down from the top.  FRE collects the strings and answers FRETOP -
STREND as a signed word.  The machine starts by asking MEMORY SIZE? and
WIDTH?, as the KIM build's INIT does.

Commodore's BASIC 2 lays memory out the same way from $0801 to $A000, so
the drops in FRE below are what VICE prints; the totals are its totals
moved to the KIM's $4001 to $C000.

## starting

### blank answers take all the RAM and a 72-column line

```x
(%basic-started (list "" "") "PRINT FRE(0)")
```
---
```output

MEMORY SIZE? 
WIDTH? 

 32767 BYTES FREE

KIM BASIC V1.1
COPYRIGHT 1978 MICROSOFT

OK
PRINT FRE(0)
 32765 

OK
```

### a size and a width; an answer that does not read is asked again

A typed width W puts the last comma column at W less W's remainder in 14,
so 40 stops the zones at 28.

```x
(%basic-started (list "LOTS" "20000" "8" "40") "PRINT FRE(0)\nPRINT 1,2,3,4")
```
---
```output

MEMORY SIZE? LOTS
MEMORY SIZE? 20000
WIDTH? 8
WIDTH? 40

 3615 BYTES FREE

KIM BASIC V1.1
COPYRIGHT 1978 MICROSOFT

OK
PRINT FRE(0)
 3613 

OK
PRINT 1,2,3,4
 1             2             3 
 4 

OK
```

## what takes memory

### variables, a copied string, arrays, a function and a READ

Seven bytes a simple variable, a function's included; D$ is three bytes of
string space; H$=D$ copies them, I$=C$ points at C$'s constant in the
program; E(5) is 37 bytes, F$(2) 16 and G%(3,1) 25.

```x
(%basic-typed "10 A=FRE(0)\n20 B=1:C$=\"AB\":D$=C$+\"C\":DIM E(5),F$(2),G%(3,1)\n30 PRINT A-FRE(0)\n40 H$=D$:I$=C$\n50 PRINT A-FRE(0)\n60 DEF FNA(X)=X+1\n70 PRINT A-FRE(0)\n80 READ J$:DATA HELLO\n90 PRINT A-FRE(0)\n100 PRINT FRE(0)+65536\nRUN")
```
---
```output
10 A=FRE(0)
20 B=1:C$="AB":D$=C$+"C":DIM E(5),F$(2),G%(3,1)
30 PRINT A-FRE(0)
40 H$=D$:I$=C$
50 PRINT A-FRE(0)
60 DEF FNA(X)=X+1
70 PRINT A-FRE(0)
80 READ J$:DATA HELLO
90 PRINT A-FRE(0)
100 PRINT FRE(0)+65536
RUN
 102 
 119 
 133 
 140 
 97978 

OK
```

## out of memory

### an array past the strings is ?OM

```x
(%basic-started (list "16500" "") "DIM A(100)\nPRINT FRE(0)")
```
---
```output

MEMORY SIZE? 16500
WIDTH? 

 115 BYTES FREE

KIM BASIC V1.1
COPYRIGHT 1978 MICROSOFT

OK
DIM A(100)

?OM ERROR
OK
PRINT FRE(0)
 113 

OK
```
