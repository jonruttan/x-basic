The maths functions as the 6502 computes them (`lib/basic/mbf-math.x`): its
polynomial tables and constants, step for step.  The expected values are
what Commodore's BASIC 2, built from the same routines and tables, prints.

## logs and powers

### SQR, LOG and EXP

```x
(%basic-typed "PRINT SQR(2);SQR(16);LOG(10);EXP(1);EXP(0)")
```
---
```output
PRINT SQR(2);SQR(16);LOG(10);EXP(1);EXP(0)
 1.41421356  4  2.30258509  2.71828183  1 

OK
```

### ^ is EXP(Y*LOG(X)), a negative base only to a whole power

```x
(%basic-typed "PRINT 2^3;3^2;(-2)^3;2^.5;0^0;0^2:PRINT (-8)^(1/3)")
```
---
```output
PRINT 2^3;3^2;(-2)^3;2^.5;0^0;0^2:PRINT (-8)^(1/3)
 8  9 -8  1.41421356  1  0 

?FC ERROR
OK
```

### LOG of zero or less is ?FC

```x
(%basic-typed "PRINT LOG(0)")
```
---
```output
PRINT LOG(0)

?FC ERROR
OK
```

### EXP past the exponent is ?OV, and far below it is 0

```x
(%basic-typed "PRINT EXP(-100):PRINT EXP(100)")
```
---
```output
PRINT EXP(-100):PRINT EXP(100)
 0 

?OV ERROR
OK
```

## trigonometry

### SIN, COS, TAN and ATN

```x
(%basic-typed "PRINT SIN(1);COS(0);TAN(1);ATN(1)")
```
---
```output
PRINT SIN(1);COS(0);TAN(1);ATN(1)
 .841470985  1  1.55740772  .785398163 

OK
```

### four times ATN(1) is pi, a digit high as on the 6502

```x
(%basic-typed "PRINT 4*ATN(1)")
```
---
```output
PRINT 4*ATN(1)
 3.14159266 

OK
```

## RND

### a negative argument seeds, zero repeats, and a value is from 0 to 1

```x
(%basic-typed "X=RND(-5):A=RND(1):X=RND(-5):B=RND(1):PRINT A=B;RND(0)=B;A>=0;A<1")
```
---
```output
X=RND(-5):A=RND(1):X=RND(-5):B=RND(1):PRINT A=B;RND(0)=B;A>=0;A<1
-1 -1 -1 -1 

OK
```
