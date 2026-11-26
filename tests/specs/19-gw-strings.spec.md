GW-BASIC's string functions HEX$, OCT$, INSTR, SPACE$ and STRING$, as
BISTRS.ASM and MATH1.ASM make them.

## HEX$ and OCT$

### a word's digits, the zeros before them dropped

```x
(%gw-typed "PRINT HEX$(255);\" \";HEX$(0);\" \";HEX$(10.4);\" \";HEX$(32767)\nPRINT OCT$(8);\" \";OCT$(0);\" \";OCT$(511)")
```
---
```output
PRINT HEX$(255);" ";HEX$(0);" ";HEX$(10.4);" ";HEX$(32767)
FF 0 A 7FFF
Ok
PRINT OCT$(8);" ";OCT$(0);" ";OCT$(511)
10 0 777
Ok
```

### from -32768 to 65535, a negative number its 16 bits

```x
(%gw-typed "PRINT HEX$(-1);\" \";HEX$(65535);\" \";HEX$(32768);\" \";HEX$(-32768)\nPRINT OCT$(-1);\" \";OCT$(65535)")
```
---
```output
PRINT HEX$(-1);" ";HEX$(65535);" ";HEX$(32768);" ";HEX$(-32768)
FFFF FFFF 8000 8000
Ok
PRINT OCT$(-1);" ";OCT$(65535)
177777 177777
Ok
```

### past the range, and a string

```x
(%gw-typed "PRINT HEX$(65536)\nPRINT OCT$(-32769)\nPRINT HEX$(\"A\")")
```
---
```output
PRINT HEX$(65536)
Overflow
Ok
PRINT OCT$(-32769)
Overflow
Ok
PRINT HEX$("A")
Type mismatch
Ok
```

## INSTR

### where one string is first found in another

```x
(%gw-typed "A$=\"ABCABC\":PRINT INSTR(A$,\"BC\");INSTR(3,A$,\"BC\");INSTR(A$,\"X\");INSTR(A$,\"ABCABCA\")")
```
---
```output
A$="ABCABC":PRINT INSTR(A$,"BC");INSTR(3,A$,"BC");INSTR(A$,"X");INSTR(A$,"ABCABCA")
 2  5  0  0 
Ok
```

### a null string found where the search starts, unless that is past the end

```x
(%gw-typed "A$=\"ABCABC\":PRINT INSTR(A$,\"\");INSTR(4,A$,\"\");INSTR(7,A$,\"\");INSTR(\"\",\"\")")
```
---
```output
A$="ABCABC":PRINT INSTR(A$,"");INSTR(4,A$,"");INSTR(7,A$,"");INSTR("","")
 1  4  0  0 
Ok
```

### a start of 0, and a number to search

```x
(%gw-typed "PRINT INSTR(0,\"AB\",\"B\")\nPRINT INSTR(1,2,\"B\")")
```
---
```output
PRINT INSTR(0,"AB","B")
Illegal function call
Ok
PRINT INSTR(1,2,"B")
Type mismatch
Ok
```

## SPACE$ and STRING$

### N blanks, or N of a character

```x
(%gw-typed "PRINT \"[\";SPACE$(3);\"]\";LEN(SPACE$(0))\nPRINT STRING$(3,\"XY\");STRING$(2,65);LEN(STRING$(255,48))")
```
---
```output
PRINT "[";SPACE$(3);"]";LEN(SPACE$(0))
[   ] 0 
Ok
PRINT STRING$(3,"XY");STRING$(2,65);LEN(STRING$(255,48))
XXXAA 255 
Ok
```

### past 255, and a null string's character

```x
(%gw-typed "PRINT STRING$(256,65)\nPRINT STRING$(2,\"\")\nPRINT SPACE$(-1)")
```
---
```output
PRINT STRING$(256,65)
Illegal function call
Ok
PRINT STRING$(2,"")
Illegal function call
Ok
PRINT SPACE$(-1)
Illegal function call
Ok
```
