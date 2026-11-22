NULL (`lib/basic/exec.x`) as the 6502's NULL and CRDO run it: NULL N sets how
many zero bytes follow each new line the machine prints, for a teletype's
carriage to come back.  The new line after a typed line is the machine's
too (INLIN ends with CRDO), so its zero bytes come before what the line
prints.  Commodore's BASIC has no NULL, so these come from the source.

## the zero bytes

### NULL 2 puts two zero bytes after every new line, and NULL 0 none

```x
(%basic-typed "NULL 2\nPRINT 1\nNULL 0\nPRINT 2")
```
---
```output
NULL 2

<<NUL>><<NUL>>OK
<<NUL>><<NUL>>PRINT 1
<<NUL>><<NUL>> 1 
<<NUL>><<NUL>>
<<NUL>><<NUL>>OK
<<NUL>><<NUL>>NULL 0
<<NUL>><<NUL>>
OK
PRINT 2
 2 

OK
```

### NEW and CLEAR leave the count

```x
(%basic-typed "NULL 1\nNEW\nCLEAR\nNULL 0")
```
---
```output
NULL 1

<<NUL>>OK
<<NUL>>NEW
<<NUL>>
<<NUL>>OK
<<NUL>>CLEAR
<<NUL>>
<<NUL>>OK
<<NUL>>NULL 0
<<NUL>>
OK
```

## errors

### 239 and above are ?FC, 238 is not

```x
(%basic-typed "NULL 239\nNULL 256\nNULL 238:NULL 0")
```
---
```output
NULL 239

?FC ERROR
OK
NULL 256

?FC ERROR
OK
NULL 238:NULL 0

OK
```
