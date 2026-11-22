Numbers as the 6502's five-byte format holds and prints them
(`lib/basic/mbf.x`): nine digits, fixed notation from .01 to 999999999.

## print numbers

### a fraction has nine digits and no leading zero

```x
(%basic-typed "PRINT 1/3;2/3;10/4")
```
---
```output
PRINT 1/3;2/3;10/4
 .333333333  .666666667  2.5 

OK
```

### E notation below .01 and from 1E9

```x
(%basic-typed "PRINT .01;.001;123456789;1E9;1234567890")
```
---
```output
PRINT .01;.001;123456789;1E9;1234567890
 .01  1E-03  123456789  1E+09  1.23456789E+09 

OK
```

### a negative number has its sign where a positive one has a blank

```x
(%basic-typed "PRINT -5;0;-.5")
```
---
```output
PRINT -5;0;-.5
-5  0 -.5 

OK
```

### blanks inside a number are skipped

```x
(%basic-typed "PRINT 1 0 0")
```
---
```output
PRINT 1 0 0
 100 

OK
```

## arithmetic

### unary minus binds looser than ^

```x
(%basic-typed "PRINT -2^2;2^-1;2^3^2")
```
---
```output
PRINT -2^2;2^-1;2^3^2
-4  .5  64 

OK
```

### a relation is -1 when true and 0 when false

```x
(%basic-typed "PRINT 1<2;1=2;\"A\"<\"B\";NOT 0;5 AND 3;5 OR 3")
```
---
```output
PRINT 1<2;1=2;"A"<"B";NOT 0;5 AND 3;5 OR 3
-1  0 -1 -1  1  7 

OK
```

### dividing by zero is ?/0

```x
(%basic-typed "PRINT 1/0")
```
---
```output
PRINT 1/0

?/0 ERROR
OK
```

### INT is the floor

```x
(%basic-typed "PRINT INT(2.5);INT(-2.5);ABS(-3);SGN(-3)")
```
---
```output
PRINT INT(2.5);INT(-2.5);ABS(-3);SGN(-3)
 2 -3  3 -1 

OK
```
