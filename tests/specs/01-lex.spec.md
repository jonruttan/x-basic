A line's text to tokens (`basic/lex.x`), as Microsoft's CRUNCH finds the
reserved words: wherever their bytes are, inside a name or not.

## lex words

### a reserved word is found with no blank around it

```x
(%seq (write (%basic-tokens "FORI=1TO9")) (newline))
```
---
    (('kw "FOR") ('c "I") ('kw "=") ('c "1") ('kw "TO") ('c "9"))

### a reserved word inside a name splits it

```x
(%seq (write (%basic-tokens "SCORE")) (newline))
```
---
    (('c "S") ('c "C") ('kw "OR") ('c "E"))

### a blank breaks a reserved word, and blanks are dropped

```x
(%seq (write (%basic-tokens "GO TO 10")) (newline))
```
---
    (('kw "GO") ('kw "TO") ('c "1") ('c "0"))

### a question mark is PRINT

```x
(%seq (write (%basic-tokens "?A")) (newline))
```
---
    (('kw "PRINT") ('c "A"))

## lex spans

### REM takes the rest of the line, colons and quotes too

```x
(%seq (write (%basic-tokens "REM A:\"B")) (newline))
```
---
    (('rem "REM A:\"B"))

### DATA runs to a colon outside quotes

```x
(%seq (write (%basic-tokens "DATA 1,\"A:B\",3:PRINT")) (newline))
```
---
    (('data "DATA 1,\"A:B\",3:") ('kw "PRINT"))

### a string may run to the end of the line unclosed

```x
(%seq (write (%basic-tokens "PRINT \"HI")) (newline))
```
---
    (('kw "PRINT") ('str "\"HI" 0))
