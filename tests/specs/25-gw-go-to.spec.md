GW-BASIC's GO TO and GO SUB with blanks (`lib/basic/lex.x`), as CRUNCH's
GOSTEX check in GWMAIN.ASM reads them: "GO " matched, CHRGTR one byte on
and past blanks, then TO, else UB from where TO's match stopped.

## GO SUB

### one blank

```x
(%gw-typed "10 GO SUB 100\n20 END\n100 PRINT \"SUB\"\n110 RETURN\nRUN")
```
---
```output
10 GO SUB 100
20 END
100 PRINT "SUB"
110 RETURN
RUN
SUB
Ok
```

### two blanks are not GO SUB

```x
(%gw-typed "GO  SUB 100")
```
---
```output
GO  SUB 100
Syntax error
Ok
```

## GO TO

### two blanks or more

```x
(%gw-typed "10 GO  TO 30\n20 PRINT \"A\"\n30 PRINT \"B\";\n40 GO   TO 60\n50 PRINT \"C\"\n60 PRINT \"D\"\nRUN")
```
---
```output
10 GO  TO 30
20 PRINT "A"
30 PRINT "B";
40 GO   TO 60
50 PRINT "C"
60 PRINT "D"
RUN
BD
Ok
```

### one blank is not GO TO: CHRGTR steps past the T

```x
(%gw-typed "GO TO 30")
```
---
```output
GO TO 30
Syntax error
Ok
```
