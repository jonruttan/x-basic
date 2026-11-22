PEEK and POKE on the machine's 64K bytes (`basic/mem.x`).  A variable's
value is kept only in those bytes, so a POKE into it is what reads back.
The bytes below are what Commodore's BASIC 2 shows in VICE for the same
lines, its variables from 2051 where the KIM's are from 16387.

## bytes

### a variable is its two name bytes and five value bytes

A real's name is its letters; an integer's has both top bits on and its
value hi then lo.

```x
(%basic-typed "A=1:B%=-2:FOR I=16387 TO 16400:PRINT PEEK(I);:NEXT")
```
---
```output
A=1:B%=-2:FOR I=16387 TO 16400:PRINT PEEK(I);:NEXT
 65  0  129  0  0  0  0  194  128  255  254  0  0  0 
OK
```

### a real is stored rounded, its sign in the first mantissa byte's top bit

```x
(%basic-typed "X=1/3:FOR I=16389 TO 16393:PRINT PEEK(I);:NEXT")
```
---
```output
X=1/3:FOR I=16389 TO 16393:PRINT PEEK(I);:NEXT
 127  42  170  170  171 
OK
```

### a stored line is its link, its number and its crunched bytes

```x
(%basic-typed "10 PRINT\nFOR I=16385 TO 16392:PRINT PEEK(I);:NEXT")
```
---
```output
10 PRINT
FOR I=16385 TO 16392:PRINT PEEK(I);:NEXT
 7  64  10  0  151  0  0  0 
OK
```

## poke

### a POKE into a variable's bytes is its value

```x
(%basic-typed "A=1:POKE 16389,130:PRINT A")
```
---
```output
A=1:POKE 16389,130:PRINT A
 2 

OK
```

### arrays keep their elements when a new variable moves them up

```x
(%basic-typed "DIM X(2),S$(1):X(1)=7:S$(1)=\"AB\":Y=5:X(2)=8:PRINT X(1);X(2);Y;S$(1)")
```
---
```output
DIM X(2),S$(1):X(1)=7:S$(1)="AB":Y=5:X(2)=8:PRINT X(1);X(2);Y;S$(1)
 7  8  5 AB

OK
```

## errors

### an address is 0 to 65535 and a byte 0 to 255, each truncated

```x
(%basic-typed "POKE 2,255.9:PRINT PEEK(2.9)\nPRINT PEEK(65535.9)\nPRINT PEEK(-1)\nPRINT PEEK(65536)\nPOKE 2,256\nPOKE -1,0")
```
---
```output
POKE 2,255.9:PRINT PEEK(2.9)
 255 

OK
PRINT PEEK(65535.9)
 0 

OK
PRINT PEEK(-1)

?FC ERROR
OK
PRINT PEEK(65536)

?FC ERROR
OK
POKE 2,256

?FC ERROR
OK
POKE -1,0

?FC ERROR
OK
```
