GW-BASIC's maths functions, ^ and RND (`lib/basic/mbf86-math.x`), as the
8086 source computes them: each a single, its argument forced to one.

## the functions

### SQR, LOG and EXP

```x
(%gw-typed "PRINT SQR(2);SQR(16);LOG(2);LOG(10);EXP(1)")
```
---
```output
PRINT SQR(2);SQR(16);LOG(2);LOG(10);EXP(1)
 1.414214  4  .6931471  2.302585  2.718282 
Ok
```

### SIN, COS, TAN and ATN

```x
(%gw-typed "PRINT SIN(1);COS(1);TAN(1);ATN(1)\nPRINT SIN(-1);ATN(-1);ATN(10);COS(0)")
```
---
```output
PRINT SIN(1);COS(1);TAN(1);ATN(1)
 .841471  .5403023  1.557408  .7853983 
Ok
PRINT SIN(-1);ATN(-1);ATN(10);COS(0)
-.841471 -.7853983  1.471128  1 
Ok
```

### a double argument made a single

```x
(%gw-typed "X#=2:PRINT SQR(X#)")
```
---
```output
X#=2:PRINT SQR(X#)
 1.414214 
Ok
```

### what has no answer

```x
(%gw-typed "PRINT LOG(0)\nPRINT SQR(-1)")
```
---
```output
PRINT LOG(0)
Illegal function call
Ok
PRINT SQR(-1)
Illegal function call
Ok
```

### an EXP too large goes on with the largest single

```x
(%gw-typed "PRINT EXP(100):PRINT \"ON\"\nPRINT EXP(-100)")
```
---
```output
PRINT EXP(100):PRINT "ON"
Overflow
 1.701412E+38 
ON
Ok
PRINT EXP(-100)
 0 
Ok
```

## ^

### whole powers, roots and negative powers

```x
(%gw-typed "PRINT 2^10;2^.5;(-2)^3;2^-1;3^0;0^2")
```
---
```output
PRINT 2^10;2^.5;(-2)^3;2^-1;3^0;0^2
 1024  1.414213 -8  .5  1  0 
Ok
```

### a negative number to a fraction, and zero to a negative power

```x
(%gw-typed "PRINT (-2)^.5\nPRINT 0^-1")
```
---
```output
PRINT (-2)^.5
Illegal function call
Ok
PRINT 0^-1
Division by zero
 1.701412E+38 
Ok
```

### an overflow inside ^ printed once

```x
(%gw-typed "PRINT 10^39\nPRINT (-10)^39")
```
---
```output
PRINT 10^39
Overflow
 1.701412E+38 
Ok
PRINT (-10)^39
Overflow
-1.701412E+38 
Ok
```

## RND

### the numbers from the start, and RND(0) the last again

```x
(%gw-typed "PRINT RND;RND(1);RND;RND(0)")
```
---
```output
PRINT RND;RND(1);RND;RND(0)
 .1213501  .651861  .8688611  .8688611 
Ok
```

### RUN starts them again

```x
(%gw-typed "10 PRINT RND\nRUN\nRUN")
```
---
```output
10 PRINT RND
RUN
 .1213501 
Ok
RUN
 .1213501 
Ok
```

### a negative argument makes its bytes the seed

```x
(%gw-typed "PRINT RND(-1);RND;RND(-1);RND")
```
---
```output
PRINT RND(-1);RND;RND(-1);RND
 .65086  .6545178  .65086  .6545178 
Ok
```

### RANDOMIZE sets the seed's upper two bytes, the lowest kept

```x
(%gw-typed "RANDOMIZE 1:PRINT RND;RND\nRANDOMIZE 1:PRINT RND")
```
---
```output
RANDOMIZE 1:PRINT RND;RND
 .4098261  .2512159 
Ok
RANDOMIZE 1:PRINT RND
 .1043339 
Ok
```

### RANDOMIZE asking for its seed until a number is typed

```x
(%gw-typed-input "10 RANDOMIZE\n20 PRINT RND\nRUN" (list "X" "3"))
```
---
```output
10 RANDOMIZE
20 PRINT RND
RUN
Random number seed (-32768 to 32767)? X
Random number seed (-32768 to 32767)? 3
 .2226007 
Ok
```
