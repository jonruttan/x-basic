GET and WAIT (`lib/basic/exec.x`).  GET waits for a key, as the KIM's
GETCH does, and the terminal shows it without the machine's column
counting it.  What GET makes of the key is what Commodore's BASIC 2, which
shares that code past the key, shows in VICE.  WAIT goes on once the byte
at its address has a bit of its mask on.

## get

### a string takes the key as it is, a blank, colon or comma too

```x
(%basic-typed-keys "10 FOR I=1 TO 4:GET A$:PRINT \"[\";A$;\"]\";:NEXT:PRINT\nRUN" "A :,")
```
---
```output
10 FOR I=1 TO 4:GET A$:PRINT "[";A$;"]";:NEXT:PRINT
RUN
A[A] [ ]:[:],[,]

OK
```

### a number reads the key as a number does

A digit is its value; a blank, a point, a sign or E is zero; a comma is
zero and leaves ?EXTRA IGNORED.

```x
(%basic-typed-keys "10 FOR I=1 TO 6:GET A:PRINT A;:NEXT:PRINT\nRUN" "E.- ,5")
```
---
```output
10 FOR I=1 TO 6:GET A:PRINT A;:NEXT:PRINT
RUN
E 0 . 0 - 0   0 ,?EXTRA IGNORED
 0 5 5 

OK
```

### a key for each variable

```x
(%basic-typed-keys "10 GET A$,B:PRINT A$;B\nRUN" "Q7")
```
---
```output
10 GET A$,B:PRINT A$;B
RUN
Q7Q 7 

OK
```

### a letter for a number is ?SN, named as at the prompt

```x
(%basic-typed-keys "10 GET A\n20 PRINT \"NO\"\nRUN" "X")
```
---
```output
10 GET A
20 PRINT "NO"
RUN
X
?SN ERROR
OK
```

### GET at the prompt is ?ID

```x
(%basic-typed-keys "GET A$" "X")
```
---
```output
GET A$

?ID ERROR
OK
```

## wait

### WAIT goes on when the byte has a bit of the mask on, the second mask flipping it first

```x
(%basic-typed "POKE 2,6:WAIT 2,4:PRINT \"ON\"\nWAIT 2,1,1:PRINT \"FLIPPED\"\nWAIT 65536,1\nWAIT 2,256")
```
---
```output
POKE 2,6:WAIT 2,4:PRINT "ON"
ON

OK
WAIT 2,1,1:PRINT "FLIPPED"
FLIPPED

OK
WAIT 65536,1

?FC ERROR
OK
WAIT 2,256

?FC ERROR
OK
```
