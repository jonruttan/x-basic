GW-BASIC's PRINT USING: BIPRTU.ASM scans the format, and PUFOUT
(MATH1.ASM, MATH2.ASM) builds each number in FBUFF, zero suppression and
the fit to the field last ($FOTZS, $PUFXE).

## numeric fields

### digits, the point and rounding

```x
(%gw-typed "PRINT USING \"##.##\";3.14159;2.5#\nPRINT USING \"#.#\";.25")
```
---
```output
PRINT USING "##.##";3.14159;2.5#
 3.14 2.50
Ok
PRINT USING "#.#";.25
0.3
Ok
```

### the sign takes a place, and a leading zero gives one up

```x
(%gw-typed "PRINT USING \"###\";-12\nPRINT USING \"###.##\";-.5\nPRINT USING \"#.##\";-.5")
```
---
```output
PRINT USING "###";-12
-12
Ok
PRINT USING "###.##";-.5
 -0.50
Ok
PRINT USING "#.##";-.5
-.50
Ok
```

### a number too wide for its field, after a %

```x
(%gw-typed "PRINT USING \"##\";123\nPRINT USING \"##\";1E+20")
```
---
```output
PRINT USING "##";123
%123
Ok
PRINT USING "##";1E+20
% 1E+20
Ok
```

### + before the field, - or + after it

```x
(%gw-typed "PRINT USING \"+##\";5;-5\nPRINT USING \"##.##-\";-1.5;1.5")
```
---
```output
PRINT USING "+##";5;-5
 +5 -5
Ok
PRINT USING "##.##-";-1.5;1.5
 1.50- 1.50 
Ok
```

### commas, asterisks and the floating $

```x
(%gw-typed "PRINT USING \"##,###\";12345\nPRINT USING \"**#.##\";1.5\nPRINT USING \"$$###.##\";1234.5\nPRINT USING \"**$##.##\";12.5")
```
---
```output
PRINT USING "##,###";12345
12,345
Ok
PRINT USING "**#.##";1.5
**1.50
Ok
PRINT USING "$$###.##";1234.5
$1234.50
Ok
PRINT USING "**$##.##";12.5
**$12.50
Ok
```

### ^^^^: E notation

```x
(%gw-typed "PRINT USING \"##.##^^^^\";234.56\nPRINT USING \".####^^^^-\";-888888\nPRINT USING \"+.##^^^^\";123")
```
---
```output
PRINT USING "##.##^^^^";234.56
 2.35E+02
Ok
PRINT USING ".####^^^^-";-888888
.8889E+06-
Ok
PRINT USING "+.##^^^^";123
+.12E+03
Ok
```

## string fields and the rest

### !, \ \ and &

```x
(%gw-typed "PRINT USING \"!-&-\\  \\|\";\"XY\";\"Z\";\"ABCDEF\"\nPRINT USING \"\\  \\|\";\"AB\"")
```
---
```output
PRINT USING "!-&-\  \|";"XY";"Z";"ABCDEF"
X-Z-ABCD|
Ok
PRINT USING "\  \|";"AB"
AB  |
Ok
```

### _ prints the next byte, and other bytes print as they are

```x
(%gw-typed "PRINT USING \"_##=#\";5")
```
---
```output
PRINT USING "_##=#";5
#5=
Ok
```

### the format again while values are left, and a last ; keeps the line

```x
(%gw-typed "PRINT USING \"##\";1;2;3\nPRINT USING \"##\";5;:PRINT \"X\"\nPRINT \"A\";USING \"##\";5")
```
---
```output
PRINT USING "##";1;2;3
 1 2 3
Ok
PRINT USING "##";5;:PRINT "X"
 5X
Ok
PRINT "A";USING "##";5
A 5
Ok
```

## errors

### a string where a number goes, or a number where a string does

```x
(%gw-typed "PRINT USING \"##\";\"A\"\nPRINT USING \"!\";1\nPRINT USING 5;1")
```
---
```output
PRINT USING "##";"A"
Type mismatch
Ok
PRINT USING "!";1
Type mismatch
Ok
PRINT USING 5;1
Type mismatch
Ok
```

### an empty format, one with no field, and more than 24 digits

```x
(%gw-typed "PRINT USING \"\";1\nPRINT USING \"AB\";1\nPRINT USING \"#####################.####\";1")
```
---
```output
PRINT USING "";1
Illegal function call
Ok
PRINT USING "AB";1
AB
Illegal function call
Ok
PRINT USING "#####################.####";1
Illegal function call
Ok
```
