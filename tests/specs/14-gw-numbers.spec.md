GW-BASIC's numbers (`lib/basic/mbf86.x`): integers, singles and doubles as
the 8086 source reads, works and prints them.

## reading and printing

### integers, singles and doubles by their digits

An integer to 32767, a single past it or with a point, a double from the
eighth digit.

```x
(%gw-numbers (list "0" "7" "-32768" "32767" "32768" "1234567" "12345678" "9999999999999999"))
```
---
```output
(" 0" " 7" "-32768" " 32767" " 32768" " 1234567" " 12345678" " 9999999999999999")
```

### a point, and seven digits

```x
(%gw-numbers (list ".5" "-1.5" "1.1" "3.14159265" "100.25" "0.001234"))
```
---
```output
(" .5" "-1.5" " 1.1" " 3.14159265" " 100.25" " .001234")
```

### E and D notation outside the places

1E38 reads as the single just under it, which prints so.

```x
(%gw-numbers (list "1E7" "1E-8" "1E-7" "1.5E+20" "1E38" "1D16" "123456789012345678" "1D-20"))
```
---
```output
(" 1E+07" " 1E-08" " .0000001" " 1.5E+20" " 9.999999E+37" " 1D+16" " 1.234567890123457D+17" " 1D-20")
```

### # makes a double and ! a single

```x
(%gw-numbers (list "1.5#" "12345678!" "2D0" "1E2%"))
```
---
```output
(" 1.5" " 1.234568E+07" " 2" " 100")
```

### &H and &O

```x
(%gw-numbers (list "&H7F" "&HFFFF" "&O777" "&17"))
```
---
```output
(" 127" "-1" " 511" " 15")
```

## arithmetic

### a single's division, printed to seven digits

$FOTNV scales 1/3 to 3333333.43 and makes it a single, 3333333.5, before
the half is added, so it prints .3333334.

```x
(list (%gw-op m86-div "1" "3") (%gw-op m86-div "2" "3") (%gw-op m86-div "10" "3")
      (%gw-op m86-add ".1" ".2") (%gw-op m86-mul "100000" "100000"))
```
---
```output
(" .3333334" " .6666667" " 3.333333" " .3" " 1E+10")
```

### a double's to sixteen

```x
(list (%gw-op m86-div "1#" "3") (%gw-op m86-div "2#" "3") (%gw-op m86-mul "1.1#" "1.1#"))
```
---
```output
(" .3333333333333333" " .6666666666666667" " 1.21")
```

### integers go to singles when they will not fit

```x
(list (%gw-op m86-add "32767" "1") (%gw-op m86-mul "300" "300") (%gw-op m86-sub "-32768" "1")
      (%gw-op m86-add "100" "-200"))
```
---
```output
(" 32768" " 90000" "-32769" "-100")
```

### \ and MOD truncate

```x
(list (%gw-op m86-idiv "7" "2") (%gw-op m86-idiv "-7" "2") (%gw-op m86-mod "-7" "2")
      (%gw-op m86-idiv "7.6" "2") (%gw-op m86-idiv "-32768" "-1"))
```
---
```output
(" 3" "-3" "-1" " 4" " 32768")
```

### overflow and division by zero name the kind and sign

```x
(list (%basic-raised (fn (_) (%gw-op m86-div "1" "0")))
      (%basic-raised (fn (_) (%gw-op m86-mul "-1E30" "1E30")))
      (%basic-raised (fn (_) (%gw-read "1E39")))
      (%basic-raised (fn (_) (m86-cint (%gw-read "32767.5")))))
```
---
```output
(('basic-div0 "4+") ('basic-overflow "4-") ('basic-overflow "4+") ('basic "OV"))
```

## conversions

### to an integer rounds half away from zero; INT floors

```x
(List map m86->str
  (list (m86-cint (%gw-read "2.5")) (m86-cint (%gw-read "-2.5")) (m86-cint (%gw-read ".4"))
        (m86-floor (%gw-read "-2.5")) (m86-floor (%gw-read "2.9")) (m86-floor (%gw-read "-3"))))
```
---
```output
(" 3" "-3" " 0" "-3" " 2" "-3")
```

### a double goes to a single on the byte below

```x
(List map m86->str (list (m86->single (%gw-read "1.23456789#")) (m86->double (%gw-read "1.1"))))
```
---
```output
(" 1.234568" " 1.100000023841858")
```

### packed as memory holds them, low byte first

```x
(List map m86->bytes (list (%gw-read "1") (%gw-read "1.0") (m86->single (%gw-read "-32768")) (%gw-read ".5#")))
```
---
```output
((1 0) (0 0 0 129) (0 0 128 144) (0 0 0 0 0 0 0 128))
```
