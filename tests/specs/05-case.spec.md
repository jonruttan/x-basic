Case folding (`basic/lex.x`, `basic-fold`): a typed line is upper-cased
before it is stored or run, all but its strings, the remark after REM and
the items after DATA.  Reserved words and names then read in either case,
and LIST shows them in capitals.  A machine's `fold-case` turns it off; the
dialect sets it on.

## folded

### a program typed in lower case runs, and lists in capitals

```x
(%basic-typed "10 for i=1 to 2:print \"Hi\";i:next\nlist\nrun")
```
---
```output
10 for i=1 to 2:print "Hi";i:next
list

 10 FOR I=1 TO 2:PRINT "Hi";I:NEXT
OK
run
Hi 1 
Hi 2 

OK
```

### a name is the same name in either case

```x
(%basic-typed "a=5:print A;len(\"MiXed\")")
```
---
```output
a=5:print A;len("MiXed")
 5  5 

OK
```

### REM's remark and DATA's items keep their case

```x
(%basic-typed "10 data abc,\"x Y\":rem Keep This\n20 read a$,b$:print a$;b$\nlist\nrun")
```
---
```output
10 data abc,"x Y":rem Keep This
20 read a$,b$:print a$;b$
list

 10 DATA abc,"x Y":REM Keep This
 20 READ A$,B$:PRINT A$;B$
OK
run
abcx Y

OK
```

## kept

### with fold-case off, lower case is not a reserved word

```x
(%basic-typed-cased "PRINT 1\nprint 1")
```
---
```output
PRINT 1
 1 

OK
print 1

?SN ERROR
OK
```

## the switch

### X_BASIC_FOLD_CASE: unset or empty keeps the default; 0, no, off or false turn folding off

```x
(List map (fn (_ v) (basic-fold-case-setting v #t))
          (list () "" "0" "no" "OFF" "False" "1" "yes"))
```
---
```output
(#t #t #f #f #f #f #t #t)
```
