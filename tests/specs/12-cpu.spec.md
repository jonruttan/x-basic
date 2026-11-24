The 6502 (`lib/basic/cpu.x`).  Each case puts its bytes at $0300, calls
them as JSR would, and shows A, X and Y after the RTS, then the flags
NV-BDIZC.

## arithmetic

### ADC adds the carry in

LDA #$05, CLC, ADC #$03, RTS.

```x
(%basic-cpu (list 169 5 24 105 3 96) ())
```
---
```output
(8 0 0 "00100100")
```

### ADC sets V when two positives make a negative

LDA #$7F, CLC, ADC #$01.

```x
(%basic-cpu (list 169 127 24 105 1 96) ())
```
---
```output
(128 0 0 "11100100")
```

### SBC borrows when the carry is clear after

SEC, LDA #$05, SBC #$07.

```x
(%basic-cpu (list 56 169 5 233 7 96) ())
```
---
```output
(254 0 0 "10100100")
```

### ROR takes the carry into bit 7

SEC, LDA #$01, ROR A.

```x
(%basic-cpu (list 56 169 1 106 96) ())
```
---
```output
(128 0 0 "10100101")
```

## decimal mode

### ADC adds two-digit decimal numbers

SED, CLC, LDA #$19, ADC #$28: $47.

```x
(%basic-cpu (list 248 24 169 25 105 40 96) ())
```
---
```output
(71 0 0 "00101100")
```

### 99 + 1 carries to 00, Z from the binary sum and N from the high digit, as the NMOS part sets them

SED, CLC, LDA #$99, ADC #$01.

```x
(%basic-cpu (list 248 24 169 153 105 1 96) ())
```
---
```output
(0 0 0 "10101101")
```

### SBC subtracts in decimal, its flags the binary subtraction's

SED, SEC, LDA #$50, SBC #$01: $49.

```x
(%basic-cpu (list 248 56 169 80 233 1 96) ())
```
---
```output
(73 0 0 "00101101")
```

## flow

### a counted loop

LDX #0, LDY #0, then INY, INX, CPX #10, BNE back.

```x
(%basic-cpu (list 162 0 160 0 200 232 224 10 208 250 96) ())
```
---
```output
(0 10 10 "00100111")
```

### JSR and RTS nest

JSR $0310, INY, RTS; at $0310 LDX #5, RTS.

```x
(%basic-cpu (List append (list 32 16 3 200 96) (List map (fn (_ i) 0) (List range 5 16)) (list 162 5 96)) ())
```
---
```output
(0 5 1 "00100100")
```

### PHA and PLA

LDA #$42, PHA, LDA #0, PLA.

```x
(%basic-cpu (list 169 66 72 169 0 104 96) ())
```
---
```output
(66 0 0 "00100100")
```

### JMP indirect takes the high byte from the start of the pointer's page

JMP ($04FF) reads $04FF and $0400, not $0500: $0305, LDA #$77, RTS.

```x
(%basic-cpu
  (List map
    (fn (_ i)
      (match
        ((int= i 0) 108) ((int= i 1) 255) ((int= i 2) 4)
        ((int= i 5) 169) ((int= i 6) 119) ((int= i 7) 96)
        ((int= i 256) 3) ((int= i 511) 5)
        (#t 0)))
    (List range 0 512))
  ())
```
---
```output
(119 0 0 "00100100")
```

## hooks

### a hook runs in place of the code at its address, then returns

JSR $E000, RTS; and JMP $E000, whose RTS ends the call.

```x
(list (%basic-cpu (list 32 0 224 96) (list (pair 57344 (fn (_ c) (c set! (lit a) 9)))))
      (%basic-cpu (list 76 0 224) (list (pair 57344 (fn (_ c) (c set! (lit a) 9))))))
```
---
```output
((9 0 0 "00100100") (9 0 0 "00100100"))
```

### BRK stops the call, naming its byte and address

```x
(%basic-raised (fn (_) (%basic-cpu (list 234 0) ())))
```
---
```output
('cpu "OPCODE 00 AT 0301")
```
