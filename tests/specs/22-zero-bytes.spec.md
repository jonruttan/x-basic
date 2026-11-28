A zero byte in a string (`lib/basic/exec.x`): one byte like any other,
counted, compared, cut and stored; VAL's FIN stops at it, and the
terminal is not sent it.

## counted and cut

### LEN counts it

```x
(%gw-typed "PRINT LEN(CHR$(0));LEN(\"A\"+CHR$(0)+\"B\");LEN(STRING$(255,0))")
```
---
```output
PRINT LEN(CHR$(0));LEN("A"+CHR$(0)+"B");LEN(STRING$(255,0))
 1  3  255 
Ok
```

### LEFT$, MID$, RIGHT$ and ASC see the bytes around it

```x
(%gw-typed "A$=\"A\"+CHR$(0)+\"B\":PRINT ASC(MID$(A$,2));ASC(RIGHT$(A$,1));LEN(LEFT$(A$,2))")
```
---
```output
A$="A"+CHR$(0)+"B":PRINT ASC(MID$(A$,2));ASC(RIGHT$(A$,1));LEN(LEFT$(A$,2))
 0  66  2 
Ok
```

### kept in a variable, and in an array

```x
(%gw-typed "A$=STRING$(3,0)+\"X\":DIM B$(1):B$(1)=A$:PRINT LEN(A$);ASC(RIGHT$(B$(1),1));LEN(B$(1))")
```
---
```output
A$=STRING$(3,0)+"X":DIM B$(1):B$(1)=A$:PRINT LEN(A$);ASC(RIGHT$(B$(1),1));LEN(B$(1))
 4  88  4 
Ok
```

### put in place by the MID$ statement

```x
(%gw-typed "A$=\"ABC\":MID$(A$,2)=CHR$(0):PRINT LEN(A$);ASC(MID$(A$,2));ASC(RIGHT$(A$,1))")
```
---
```output
A$="ABC":MID$(A$,2)=CHR$(0):PRINT LEN(A$);ASC(MID$(A$,2));ASC(RIGHT$(A$,1))
 3  0  67 
Ok
```

## compared and searched

### a zero byte sorts below every other, and is not the null string

```x
(%gw-typed "PRINT CHR$(0)=\"\";CHR$(0)>\"\";CHR$(0)+\"A\"<CHR$(0)+\"B\";CHR$(0)<CHR$(1)")
```
---
```output
PRINT CHR$(0)="";CHR$(0)>"";CHR$(0)+"A"<CHR$(0)+"B";CHR$(0)<CHR$(1)
 0 -1 -1 -1 
Ok
```

### INSTR finds past it

```x
(%gw-typed "PRINT INSTR(\"A\"+CHR$(0)+\"B\",CHR$(0)+\"B\");INSTR(\"A\"+CHR$(0)+\"B\",\"B\")")
```
---
```output
PRINT INSTR("A"+CHR$(0)+"B",CHR$(0)+"B");INSTR("A"+CHR$(0)+"B","B")
 2  3 
Ok
```

## where it ends the text

### VAL reads to it

```x
(%gw-typed "PRINT VAL(\"12\"+CHR$(0)+\"3\")")
```
---
```output
PRINT VAL("12"+CHR$(0)+"3")
 12 
Ok
```

### PRINT does not send it

```x
(%gw-typed "PRINT \"A\";CHR$(0);\"B\"")
```
---
```output
PRINT "A";CHR$(0);"B"
AB
Ok
```

## the 6502

### LEN counts it there too

```x
(%basic-typed "PRINT LEN(CHR$(0)+\"A\")")
```
---
```output
PRINT LEN(CHR$(0)+"A")
 2 

OK
```
