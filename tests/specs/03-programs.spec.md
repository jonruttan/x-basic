Lines typed at the prompt (`lib/basic/exec.x`): a numbered line is stored and
prints nothing; any other runs at once and is followed by OK.

## program lines

### a FOR loop and a semicolon that keeps the line open

```x
(%basic-typed "10 FOR I=1 TO 3\n20 PRINT I;\n30 NEXT\n40 PRINT \"DONE\"\nRUN")
```
---
```output
10 FOR I=1 TO 3
20 PRINT I;
30 NEXT
40 PRINT "DONE"
RUN
 1  2  3 DONE

OK
```

### LIST shows each line after its number and a blank

```x
(%basic-typed "20 END\n10 PRINT \"HI\"\nLIST")
```
---
```output
20 END
10 PRINT "HI"
LIST

 10 PRINT "HI"
 20 END
OK
```

### a line number alone deletes the line

```x
(%basic-typed "10 PRINT 1\n20 PRINT 2\n10\nRUN")
```
---
```output
10 PRINT 1
20 PRINT 2
10
RUN
 2 

OK
```

## errors

### a syntax error is found when the line runs, and names it

```x
(%basic-typed "10 PRINT \"A\"\n20 PRINT (\nRUN")
```
---
```output
10 PRINT "A"
20 PRINT (
RUN
A

?SN ERROR IN  20
OK
```

### GOTO a missing line is ?US

```x
(%basic-typed "GOTO 50")
```
---
```output
GOTO 50

?US ERROR
OK
```

### RETURN with no GOSUB is ?RG

```x
(%basic-typed "10 RETURN\nRUN")
```
---
```output
10 RETURN
RUN

?RG ERROR IN  10
OK
```

### STOP prints BREAK and the line

```x
(%basic-typed "10 PRINT 1\n20 STOP\n30 PRINT 3\nRUN\nCONT")
```
---
```output
10 PRINT 1
20 STOP
30 PRINT 3
RUN
 1 

BREAK IN  20
OK
CONT
 3 

OK
```

## control

### GOSUB and RETURN, and IF THEN a line number

```x
(%basic-typed "10 GOSUB 100\n20 IF 1 THEN 40\n30 PRINT \"NO\"\n40 END\n100 PRINT \"SUB\"\n110 RETURN\nRUN")
```
---
```output
10 GOSUB 100
20 IF 1 THEN 40
30 PRINT "NO"
40 END
100 PRINT "SUB"
110 RETURN
RUN
SUB

OK
```

### a false IF skips the rest of its line

```x
(%basic-typed "IF 0 THEN PRINT 1:PRINT 2\nIF 1 THEN PRINT 1:PRINT 2")
```
---
```output
IF 0 THEN PRINT 1:PRINT 2

OK
IF 1 THEN PRINT 1:PRINT 2
 1 
 2 

OK
```

### ON GOTO picks a line by number, and falls through past the list

```x
(%basic-typed "10 FOR K=1 TO 3\n20 ON K GOTO 40,50\n30 PRINT \"C\":NEXT:END\n40 PRINT \"A\":NEXT\n50 PRINT \"B\":NEXT\nRUN")
```
---
```output
10 FOR K=1 TO 3
20 ON K GOTO 40,50
30 PRINT "C":NEXT:END
40 PRINT "A":NEXT
50 PRINT "B":NEXT
RUN
A
B
C

OK
```

### a FOR loop runs its body once even when past its limit

```x
(%basic-typed "FOR I=5 TO 1:PRINT I:NEXT")
```
---
```output
FOR I=5 TO 1:PRINT I:NEXT
 5 

OK
```

### FOR with a STEP down

```x
(%basic-typed "FOR I=3 TO 1 STEP -1:PRINT I;:NEXT I")
```
---
```output
FOR I=3 TO 1 STEP -1:PRINT I;:NEXT I
 3  2  1 
OK
```

## data

### READ takes DATA in order, strings with their blanks kept

```x
(%basic-typed "10 DATA 1, 2.5,HELLO ,\"A,B\"\n20 READ A,B,C$,D$\n30 PRINT A;B;C$;\"|\";D$\nRUN")
```
---
```output
10 DATA 1, 2.5,HELLO ,"A,B"
20 READ A,B,C$,D$
30 PRINT A;B;C$;"|";D$
RUN
 1  2.5 HELLO |A,B

OK
```

### reading past the last item is ?OD

```x
(%basic-typed "10 DATA 1\n20 READ A,B\nRUN")
```
---
```output
10 DATA 1
20 READ A,B
RUN

?OD ERROR IN  20
OK
```

### the colon that ends DATA starts the next statement

```x
(%basic-typed "10 DATA 1:PRINT 2\nRUN")
```
---
```output
10 DATA 1:PRINT 2
RUN
 2 

OK
```

## strings

### the string functions

```x
(%basic-typed "A$=\"HELLO\":PRINT LEN(A$);LEFT$(A$,2);RIGHT$(A$,3);MID$(A$,2,3);ASC(A$);CHR$(66)")
```
---
```output
A$="HELLO":PRINT LEN(A$);LEFT$(A$,2);RIGHT$(A$,3);MID$(A$,2,3);ASC(A$);CHR$(66)
 5 HELLOELL 72 B

OK
```

### STR$ keeps the sign's blank and VAL reads a number's start

```x
(%basic-typed "PRINT STR$(12);\"|\";VAL(\" 12AB\")+1")
```
---
```output
PRINT STR$(12);"|";VAL(" 12AB")+1
 12| 13 

OK
```

### a number where a string belongs is ?TM

```x
(%basic-typed "A$=1")
```
---
```output
A$=1

?TM ERROR
OK
```

## arrays

### an array is 0 to 10 until dimensioned, and 11 is ?BS

```x
(%basic-typed "A(10)=5:PRINT A(10):A(11)=1")
```
---
```output
A(10)=5:PRINT A(10):A(11)=1
 5 

?BS ERROR
OK
```

### DIM twice is ?DD

```x
(%basic-typed "DIM B(3,4):B(3,4)=7:PRINT B(3,4):DIM B(2)")
```
---
```output
DIM B(3,4):B(3,4)=7:PRINT B(3,4):DIM B(2)
 7 

?DD ERROR
OK
```

## input

### INPUT prompts with its text and a question mark

```x
(%basic-typed-input "10 INPUT \"NAME\";N$\n20 INPUT A,B\n30 PRINT \"HI \";N$;A+B\nRUN" (list "BOB" "1" "2"))
```
---
```output
10 INPUT "NAME";N$
20 INPUT A,B
30 PRINT "HI ";N$;A+B
RUN
NAME? BOB
? 1
?? 2
HI BOB 3 

OK
```

### a reply that is no number asks again

```x
(%basic-typed-input "10 INPUT A\n20 PRINT A\nRUN" (list "X" "4"))
```
---
```output
10 INPUT A
20 PRINT A
RUN
? X
?REDO FROM START
? 4
 4 

OK
```

### PRINT's comma moves to the next zone of 14

```x
(%basic-typed "PRINT 1,2;\"X\"")
```
---
```output
PRINT 1,2;"X"
 1             2 X

OK
```

### TAB moves to a column, SPC prints blanks, and POS is the column

```x
(%basic-typed "PRINT \"A\";TAB(10);\"B\";SPC(3);\"C\";POS(0)")
```
---
```output
PRINT "A";TAB(10);"B";SPC(3);"C";POS(0)
A         B   C 15 

OK
```
