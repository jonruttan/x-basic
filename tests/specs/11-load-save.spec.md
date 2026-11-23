SAVE and LOAD (`lib/basic/exec.x`, `lib/basic/tape.x`).  The tape is a
file holding what the KIM-1 monitor writes to cassette: 100 SYN, `*`, the
ID, the start address and the data as hex digit pairs, `/`, the checksum,
two EOT.  SAVE writes TXTTAB up to VARTAB with ID $FE; LOAD takes the first
record, loads it at TXTTAB whatever address it names, says LOADED, and
reads the next line with no ready prompt, as KIM BASIC's LOAD goes on to
MAIN.  A tape the monitor cannot read shows the KIM's FFFF.

## save

### SAVE writes the program as a cassette record

`10 END` is its link $4007, its number 10, END's token $80, the line's
zero, and the program's end 00 00; the checksum $0112 is the start address
and those bytes summed.

```x
(do (%basic-tape-remove!) (%basic-typed "10 END\nSAVE") (basic-term-out (%basic-tape-shown)) ())
```
---
```output
10 END
SAVE
SAVED

OK
100 SYN *FE014007400A0080000000/1201<EOT><EOT>
```

### a running program goes on after SAVE

```x
(%basic-typed "10 SAVE:PRINT \"ON\"\nRUN")
```
---
```output
10 SAVE:PRINT "ON"
RUN
SAVED
ON

OK
```

## load

### LOAD brings the program back, ? spelled PRINT as LIST spells its token

```x
(%basic-typed "10 ? \"HI\";A\n20 A=A+1:IF A<3 GOTO 10\nSAVE\nNEW\nLIST\nLOAD\nLIST\nRUN")
```
---
```output
10 ? "HI";A
20 A=A+1:IF A<3 GOTO 10
SAVE
SAVED

OK
NEW

OK
LIST

OK
LOAD
LOADEDLIST

 10 PRINT "HI";A
 20 A=A+1:IF A<3 GOTO 10
OK
RUN
HI 0 
HI 1 
HI 2 

OK
```

### LOAD in a program ends the run, its variables cleared

```x
(%basic-typed "10 PRINT \"ONE\"\nSAVE\n10 A=5:LOAD\n20 PRINT \"NO\"\nRUN\nPRINT A")
```
---
```output
10 PRINT "ONE"
SAVE
SAVED

OK
10 A=5:LOAD
20 PRINT "NO"
RUN
LOADEDPRINT A
 0 

OK
```

### the record's ID, start address and links are not read, and a short SYN run is passed over

The tape names ID $01 and address $0000, and its link is $FF77: the line
lands at TXTTAB and is relinked.  Three SYN and an X come before the
eleven SYN LOADT needs.

```x
(do (%basic-tape-write!
      (Str8 append "\x16\x16\x16X" (Str8 repeat 11 "\x16") "*010000" "77FF0A0080000000" "/0002\x04\x04"))
    (%basic-typed "LOAD\nLIST"))
```
---
```output
LOAD
LOADEDLIST

 10 END
OK
```

### a bad checksum, a byte not hex, a short tape and no tape each show FFFF and keep the program

```x
(do (%basic-tape-write! (Str8 append (Str8 repeat 11 "\x16") "*010000" "77FF0A0080000000" "/0102\x04\x04"))
    (%basic-typed "10 PRINT\nLOAD\nLIST")
    (%basic-tape-write! (Str8 append (Str8 repeat 11 "\x16") "*010000" "77FG0A0080000000" "/0002\x04\x04"))
    (%basic-typed "LOAD")
    (%basic-tape-write! (Str8 append (Str8 repeat 11 "\x16") "*010000" "77FF0A00"))
    (%basic-typed "LOAD")
    (%basic-tape-remove!)
    (%basic-typed "LOAD"))
```
---
```output
10 PRINT
LOAD
FFFF
OK
LIST

 10 PRINT
OK
LOAD
FFFF
OK
LOAD
FFFF
OK
LOAD
FFFF
OK
```
