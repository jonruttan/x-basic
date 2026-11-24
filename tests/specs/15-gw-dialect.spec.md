GW-BASIC (`lib/basic/gwbasic.x`): the 8086 BASIC's words, names, types and
messages, run by the machine the KIM's runs on.

## starting

### the copyright line, the bytes free and Ok

```x
(%gw-started "PRINT 1+1")
```
---
```output

(C) Copyright Microsoft 1982         
60926 Bytes free
Ok
PRINT 1+1
 2 
Ok
```

## names and types

### a name keeps its 40 characters

```x
(%gw-typed "LONGNAME=5:LONGNAMX=6:PRINT LONGNAME;LONGNAMX")
```
---
```output
LONGNAME=5:LONGNAMX=6:PRINT LONGNAME;LONGNAMX
 5  6 
Ok
```

### an integer, a single and a double

An integer rounds what it is given; a single prints as $FOTNV makes it (14-gw-numbers).

```x
(%gw-typed "A%=7.6:A!=1/3:A#=1#/3:PRINT A%;A!;A#")
```
---
```output
A%=7.6:A!=1/3:A#=1#/3:PRINT A%;A!;A#
 8  .3333334  .3333333333333333 
Ok
```

### a word is taken where a name could not go on

```x
(%gw-typed "FOR I=1 TO 3:PRINT I;:NEXT\nFORI=4:PRINT FORI")
```
---
```output
FOR I=1 TO 3:PRINT I;:NEXT
 1  2  3 
Ok
FORI=4:PRINT FORI
 4 
Ok
```

### integer division, MOD and XOR

```x
(%gw-typed "PRINT 7\\2;7 MOD 3;5 XOR 3;-1 IMP 0")
```
---
```output
PRINT 7\2;7 MOD 3;5 XOR 3;-1 IMP 0
 3  1  6  0 
Ok
```

### a remark after '

```x
(%gw-typed "PRINT 1 ' A NOTE")
```
---
```output
PRINT 1 ' A NOTE
 1 
Ok
```

## messages

### an error by its message, and the line it is in

```x
(%gw-typed "PRINT X(11)\n10 GOTO 50\nRUN")
```
---
```output
PRINT X(11)
Subscript out of range
Ok
10 GOTO 50
RUN
Undefined line number in 10
Ok
```

### an integer that will not fit

```x
(%gw-typed "A%=40000")
```
---
```output
A%=40000
Overflow
Ok
```

### a division by zero is printed, and the run goes on

```x
(%gw-typed "PRINT 1/0;\"X\"")
```
---
```output
PRINT 1/0;"X"
Division by zero
 1.701412E+38 X
Ok
```

### STOP, and a statement this bundle does not run yet

```x
(%gw-typed "10 STOP\nRUN\nSAVE \"X\"")
```
---
```output
10 STOP
RUN
Break in 10
Ok
SAVE "X"
SAVE is not in x-basic yet
Ok
```

### LIST

```x
(%gw-typed "20 END\n10 PRINT \"HI\"\nLIST")
```
---
```output
20 END
10 PRINT "HI"
LIST
10 PRINT "HI"
20 END
Ok
```
