GW-BASIC's error trapping: ON ERROR GOTO, RESUME, ERROR, ERR and ERL, as
the 8086 source runs them.

## the trap

### an error goes to the ON ERROR line, ERR and ERL saying which and where

```x
(%gw-typed "10 ON ERROR GOTO 100\n20 PRINT 1/0\n30 PRINT \"BACK\"\n40 END\n100 PRINT ERR;ERL\n110 RESUME NEXT\nRUN")
```
---
```output
10 ON ERROR GOTO 100
20 PRINT 1/0
30 PRINT "BACK"
40 END
100 PRINT ERR;ERL
110 RESUME NEXT
RUN
 11  20 
BACK
Ok
```

### nothing trapped yet

```x
(%gw-typed "PRINT ERR;ERL")
```
---
```output
PRINT ERR;ERL
 0  0 
Ok
```

### RESUME runs the erring statement again

```x
(%gw-typed "10 ON ERROR GOTO 100\n20 PRINT 10/D\n30 END\n100 PRINT ERR;ERL:D=4:RESUME\nRUN")
```
---
```output
10 ON ERROR GOTO 100
20 PRINT 10/D
30 END
100 PRINT ERR;ERL:D=4:RESUME
RUN
 11  20 
 2.5 
Ok
```

### RESUME with a line number goes there

```x
(%gw-typed "10 ON ERROR GOTO 100\n20 ERROR 5\n30 PRINT \"NO\"\n40 PRINT \"YES\":END\n100 RESUME 40\nRUN")
```
---
```output
10 ON ERROR GOTO 100
20 ERROR 5
30 PRINT "NO"
40 PRINT "YES":END
100 RESUME 40
RUN
YES
Ok
```

### an overflow is trapped, not gone on from

```x
(%gw-typed "10 ON ERROR GOTO 100\n20 X=EXP(100)\n30 END\n100 PRINT ERR:RESUME NEXT\nRUN")
```
---
```output
10 ON ERROR GOTO 100
20 X=EXP(100)
30 END
100 PRINT ERR:RESUME NEXT
RUN
 6 
Ok
```

### the line typed is trapped too, ERL 65535

```x
(%gw-typed "10 PRINT ERR;ERL:RESUME NEXT\nON ERROR GOTO 10:ERROR 7:PRINT \"AFTER\"")
```
---
```output
10 PRINT ERR;ERL:RESUME NEXT
ON ERROR GOTO 10:ERROR 7:PRINT "AFTER"
 7  65535 
AFTER
Ok
```

## errors the trap does not take

### an error inside the handler is printed

```x
(%gw-typed "10 ON ERROR GOTO 100\n20 X=1/0\n100 PRINT \"IN\";ERL:Y=1/0\nRUN")
```
---
```output
10 ON ERROR GOTO 100
20 X=1/0
100 PRINT "IN";ERL:Y=1/0
RUN
IN 20 
Division by zero in 100
Ok
```

### ON ERROR GOTO 0 inside the handler prints the error being handled

```x
(%gw-typed "10 ON ERROR GOTO 100\n20 ERROR 13\n100 ON ERROR GOTO 0\nRUN")
```
---
```output
10 ON ERROR GOTO 100
20 ERROR 13
100 ON ERROR GOTO 0
RUN
Type mismatch in 20
Ok
```

### the handler running off the program's end

```x
(%gw-typed "10 ON ERROR GOTO 100\n20 ERROR 5\n100 PRINT \"TRAPPED\"\nRUN")
```
---
```output
10 ON ERROR GOTO 100
20 ERROR 5
100 PRINT "TRAPPED"
RUN
TRAPPED
No RESUME in 100
Ok
```

### RESUME with no error

```x
(%gw-typed "RESUME\n10 RESUME\nRUN")
```
---
```output
RESUME
RESUME without error
Ok
10 RESUME
RUN
RESUME without error in 10
Ok
```

### ON ERROR GOTO a line not in the program

```x
(%gw-typed "10 ON ERROR GOTO 50\nRUN")
```
---
```output
10 ON ERROR GOTO 50
RUN
Undefined line number in 10
Ok
```

## ERROR

### a number's message, unprintable where it has none

```x
(%gw-typed "ERROR 13\nERROR 53\nERROR 28\nERROR 200")
```
---
```output
ERROR 13
Type mismatch
Ok
ERROR 53
File not found
Ok
ERROR 28
Unprintable error
Ok
ERROR 200
Unprintable error
Ok
```

### 0 and past 255 are not errors

```x
(%gw-typed "ERROR 0\nERROR 256")
```
---
```output
ERROR 0
Illegal function call
Ok
ERROR 256
Illegal function call
Ok
```
