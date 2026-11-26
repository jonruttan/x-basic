; # x-basic -- BASIC on x-lang
;
; ## lib/basic/gwbasic.x -- Microsoft GW-BASIC, the 8086 BASIC
;
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)
;
; Facts read from Microsoft's MIT-licensed 8086 source: the reserved words
; and their tokens (IBMRES), CRUNCH taking a word only where a name could not
; go on, names of up to 40 characters with a type sign, the long messages
; (ERRTAB), "Ok" (READY), the copyright line HEDING prints and the bytes
; free INITSA counts.  Where the program starts depends on the build; here
; it is $1000, and the top of memory 512 bytes under 64K.
;
; Its numbers are basic/mbf86's: integers, singles and doubles.

(module basic/gwbasic)
(import x/type/list)
(import x/type/dict)
(import x/core/doors int+ int- int* int< int= int>> int& int| str-byte-ref)
(import x/type/str)
(import basic/mbf86
  m86-int m86-integer m86-zero? m86->single m86->double m86-cint m86-floor
  m86-neg m86-abs m86-sgn m86-add m86-sub m86-mul m86-div m86-idiv m86-mod m86-cmp
  m86->bytes m86-from-bytes m86->str m86-read)
(import basic/mbf86-math
  m86-sqr m86-log m86-exp m86-sin m86-cos m86-tan m86-atn m86-power
  m86-rnd m86-rnd-seed m86-randomize)

; Each reserved word and the bytes CRUNCH stores it as: one byte, or $FD,
; $FE or $FF and one more
(def %gw-words
  (list
    (pair "AUTO" (list 170)) (pair "AND" (list 238)) (pair "ABS" (list 255 134))
    (pair "ATN" (list 255 142)) (pair "ASC" (list 255 149)) (pair "BSAVE" (list 194))
    (pair "BLOAD" (list 195)) (pair "BEEP" (list 197)) (pair "COLOR" (list 191))
    (pair "CLOSE" (list 187)) (pair "CONT" (list 153)) (pair "CLEAR" (list 146))
    (pair "CSRLIN" (list 219)) (pair "CINT" (list 255 156)) (pair "CSNG" (list 255 157))
    (pair "CDBL" (list 255 158)) (pair "COS" (list 255 140)) (pair "CHR$" (list 255 150))
    (pair "CALL" (list 179)) (pair "CLS" (list 192)) (pair "DELETE" (list 169))
    (pair "DATA" (list 132)) (pair "DIM" (list 134)) (pair "DEFSTR" (list 172))
    (pair "DEFINT" (list 173)) (pair "DEFSNG" (list 174)) (pair "DEFDBL" (list 175))
    (pair "DEF" (list 151)) (pair "ELSE" (list 161)) (pair "END" (list 129))
    (pair "ERASE" (list 165)) (pair "EDIT" (list 166)) (pair "ERROR" (list 167))
    (pair "ERL" (list 212)) (pair "ERR" (list 213)) (pair "EXP" (list 255 139))
    (pair "EOF" (list 255 163)) (pair "EQV" (list 241)) (pair "FOR" (list 130))
    (pair "FN" (list 209)) (pair "FRE" (list 255 143)) (pair "FIX" (list 255 159))
    (pair "GOTO" (list 137)) (pair "GOSUB" (list 141)) (pair "HEX$" (list 255 154))
    (pair "INPUT" (list 133)) (pair "IF" (list 139)) (pair "INSTR" (list 216))
    (pair "INT" (list 255 133)) (pair "INP" (list 255 144)) (pair "IMP" (list 242))
    (pair "INKEY$" (list 222)) (pair "KEY" (list 201)) (pair "LOCATE" (list 202))
    (pair "LPRINT" (list 157)) (pair "LLIST" (list 158)) (pair "LPOS" (list 255 155))
    (pair "LET" (list 136)) (pair "LINE" (list 176)) (pair "LOAD" (list 188))
    (pair "LIST" (list 147)) (pair "LOG" (list 255 138)) (pair "LOC" (list 255 164))
    (pair "LEN" (list 255 146)) (pair "LEFT$" (list 255 129)) (pair "LOF" (list 255 165))
    (pair "MOTOR" (list 193)) (pair "MERGE" (list 189)) (pair "MOD" (list 243))
    (pair "MID$" (list 255 131)) (pair "NEXT" (list 131)) (pair "NEW" (list 148))
    (pair "NOT" (list 211)) (pair "OPEN" (list 186)) (pair "OUT" (list 156))
    (pair "ON" (list 149)) (pair "OR" (list 239)) (pair "OCT$" (list 255 153))
    (pair "OPTION" (list 184)) (pair "OFF" (list 221)) (pair "PRINT" (list 145))
    (pair "POKE" (list 152)) (pair "POS" (list 255 145)) (pair "PEEK" (list 255 151))
    (pair "PSET" (list 198)) (pair "PRESET" (list 199)) (pair "POINT" (list 220))
    (pair "PEN" (list 255 160)) (pair "RUN" (list 138)) (pair "RETURN" (list 142))
    (pair "READ" (list 135)) (pair "RESTORE" (list 140)) (pair "REM" (list 143))
    (pair "RESUME" (list 168)) (pair "RIGHT$" (list 255 130)) (pair "RND" (list 255 136))
    (pair "RENUM" (list 171)) (pair "RANDOMIZE" (list 185)) (pair "SCREEN" (list 200))
    (pair "STOP" (list 144)) (pair "SWAP" (list 164)) (pair "SAVE" (list 190))
    (pair "SPC(" (list 210)) (pair "STEP" (list 207)) (pair "SGN" (list 255 132))
    (pair "SQR" (list 255 135)) (pair "SIN" (list 255 137)) (pair "STR$" (list 255 147))
    (pair "STRING$" (list 214)) (pair "SPACE$" (list 255 152)) (pair "SOUND" (list 196))
    (pair "STICK" (list 255 161)) (pair "STRIG" (list 255 162)) (pair "THEN" (list 205))
    (pair "TRON" (list 162)) (pair "TROFF" (list 163)) (pair "TAB(" (list 206))
    (pair "TO" (list 204)) (pair "TAN" (list 255 141)) (pair "USING" (list 215))
    (pair "USR" (list 208)) (pair "VAL" (list 255 148)) (pair "VARPTR" (list 218))
    (pair "WIDTH" (list 160)) (pair "WAIT" (list 150)) (pair "WHILE" (list 177))
    (pair "WEND" (list 178)) (pair "WRITE" (list 183)) (pair "XOR" (list 240))
    (pair "+" (list 233)) (pair "-" (list 234)) (pair "*" (list 235))
    (pair "/" (list 236)) (pair "^" (list 237)) (pair "\\" (list 244))
    (pair "'" (list 217)) (pair ">" (list 230)) (pair "=" (list 231))
    (pair "<" (list 232)) (pair "CHAIN" (list 254 140)) (pair "CVI" (list 253 129))
    (pair "CVS" (list 253 130)) (pair "CVD" (list 253 131)) (pair "COMMON" (list 254 139))
    (pair "COM" (list 254 144)) (pair "CIRCLE" (list 254 145)) (pair "CALLS" (list 254 161))
    (pair "DATE$" (list 254 141)) (pair "DRAW" (list 254 146)) (pair "FIELD" (list 254 130))
    (pair "FILES" (list 254 129)) (pair "GET" (list 254 137)) (pair "IOCTL" (list 254 150))
    (pair "KILL" (list 254 135)) (pair "LSET" (list 254 133)) (pair "LCOPY" (list 254 160))
    (pair "MKI$" (list 253 132)) (pair "MKS$" (list 253 133)) (pair "MKD$" (list 253 134))
    (pair "NAME" (list 254 132)) (pair "PUT" (list 254 136)) (pair "PAINT" (list 254 143))
    (pair "PLAY" (list 254 147)) (pair "RSET" (list 254 134)) (pair "RESET" (list 254 138))
    (pair "SYSTEM" (list 254 131)) (pair "TIME$" (list 254 142))
    ))

(def %gw-numbers
  (Dict from-plist
    (list
      (lit zero) (m86-int 0)
      (lit int) m86-int
      (lit zero?) m86-zero?
      (lit neg) m86-neg
      (lit abs) m86-abs
      (lit sign) (fn (_ v) (m86-integer (m86-sgn v)))
      (lit cmp) m86-cmp
      (lit add) m86-add
      (lit sub) m86-sub
      (lit mul) m86-mul
      (lit div) m86-div
      (lit idiv) m86-idiv
      (lit mod) m86-mod
      (lit floor) m86-floor
      ; an integer by CINT, ?OV outside a word
      (lit integer) (fn (_ v) (m86-integer (m86-cint v)))
      (lit power) m86-power
      (lit ->str) m86->str
      (lit read) m86-read
      ; FRE's count, a single (m86->single floats an integer of any size)
      (lit fre) (fn (_ n) (m86->single (m86-int n)))
      ; a value as a variable of TYPE holds it: CINT, CSNG or CDBL
      (lit fit)
        (fn (_ type v)
          (match ((int= type 2) (m86-cint v)) ((int= type 8) (m86->double v)) (#t (m86->single v))))
      (lit ->bytes) (fn (_ type v) (m86->bytes v))
      (lit from-bytes) m86-from-bytes
      (lit math)
        (Dict from-plist
          (list "SQR" m86-sqr "LOG" m86-log "EXP" m86-exp "SIN" m86-sin "COS" m86-cos
                "TAN" m86-tan "ATN" m86-atn))
      (lit rnd) m86-rnd
      (lit rnd-seed) m86-rnd-seed
      ; CLEAR and RUN put RNDCOP back in RNDX
      (lit rnd-clear) #t
      (lit randomize) m86-randomize
      ; ERL, a line number as an unsigned single (INEG2)
      (lit line-value) (fn (_ n) (m86->single (m86-int n))))))

; A variable is VALTYP, the name's first two characters (the second 0 when
; there is none), the count of those past them and each of those with its
; top bit set, then VALTYP bytes of value.  An array's header is the same,
; then the length of what follows it, the count of its dimensions and each
; one's size, low byte first.
(def %gw-layout
  (Dict from-plist
    (list
      (lit var-header)
        (fn (_ base type)
          (let ((n (Str8 length base)))
            (pair type
              (pair (str-byte-ref base 0)
                (pair (if (int< 1 n) (str-byte-ref base 1) 0)
                  (pair (if (int< 2 n) (int- n 2) 0)
                    (List map (fn (_ i) (int| (str-byte-ref base i) 128)) (List range 2 n))))))))
      ; DEF FN's entries are not kept here yet
      (lit fn-header) ()
      (lit value-size) (fn (_ type) type)
      (lit element-size) (fn (_ type) type)
      (lit header-length) (fn (_ peek a) (int+ 4 (peek (int+ a 3))))
      (lit entry-type) (fn (_ peek a) (peek a))
      (lit array-field) (fn (_ total hl) (int- total (int+ hl 2)))
      (lit array-total) (fn (_ field hl) (int+ field (int+ hl 2)))
      (lit dim-bytes) (fn (_ w) (list (int& w 255) (int>> w 8))))))

; ERRTAB: each error's number, the code the machine raises it by (nil for
; one it does not raise) and its message; a "?" entry prints as an
; unprintable error.  The disk errors start at 50.
(def %gw-errors
  (list
    (list 1 "NF" "NEXT without FOR") (list 2 "SN" "Syntax error") (list 3 "RG" "RETURN without GOSUB")
    (list 4 "OD" "Out of DATA") (list 5 "FC" "Illegal function call") (list 6 "OV" "Overflow")
    (list 7 "OM" "Out of memory") (list 8 "US" "Undefined line number")
    (list 9 "BS" "Subscript out of range") (list 10 "DD" "Duplicate Definition")
    (list 11 "/0" "Division by zero") (list 12 "ID" "Illegal direct") (list 13 "TM" "Type mismatch")
    (list 14 "OS" "Out of string space") (list 15 "LS" "String too long")
    (list 16 "ST" "String formula too complex") (list 17 "CN" "Can't continue")
    (list 18 "UF" "Undefined user function") (list 19 "NR" "No RESUME")
    (list 20 "RW" "RESUME without error") (list 21 "UE" "Unprintable error")
    (list 22 "MO" "Missing operand") (list 23 "BO" "Line buffer overflow")
    (list 24 "DT" "Device Timeout") (list 25 "DF" "Device Fault") (list 26 "FN" "FOR Without NEXT")
    (list 27 "OP" "Out of Paper") (list 29 "WH" "WHILE without WEND") (list 30 "WE" "WEND without WHILE")
    (list 50 () "FIELD overflow") (list 51 () "Internal error") (list 52 () "Bad file number")
    (list 53 () "File not found") (list 54 () "Bad file mode") (list 55 () "File already open")
    (list 57 () "Device I/O Error") (list 58 () "File already exists") (list 61 () "Disk full")
    (list 62 () "Input past end") (list 63 () "Bad record number") (list 64 () "Bad file name")
    (list 66 () "Direct statement in file") (list 67 () "Too many files")
    (list 68 () "Device Unavailable") (list 69 () "Communication buffer overflow")
    (list 70 () "Disk write protected") (list 71 () "Disk not Ready") (list 72 () "Disk media error")
    (list 73 () "Advanced Feature") (list 74 () "Rename across disks")))

(def %gw-error-texts
  (let ((d (Dict make)))
    (List for-each (fn (_ e) (d set! (first e) (List third e))) %gw-errors)
    d))

(def %gw-error-numbers
  (let ((d (Dict make)))
    (List for-each (fn (_ e) (unless (null? (List second e)) (d set! (List second e) (first e)))) %gw-errors)
    d))

(def %gw-error-codes
  (let ((d (Dict make)))
    (List for-each (fn (_ e) (unless (null? (List second e)) (d set! (first e) (List second e)))) %gw-errors)
    d))

; The number of the error raised as CODE: its entry's, or, for ERROR of a
; number with no code, the number CODE spells
(def %gw-error-number
  (fn (_ code)
    (let ((n (%gw-error-numbers get-or () code)))
      (if (not (null? n)) n
        (List fold (fn (_ k b) (int+ (int* k 10) (int- b 48))) 0
          (List map (fn (_ i) (str-byte-ref code i)) (List range 0 (Str8 length code))))))))

(def gwbasic-dialect
  (Dict from-plist
    (list
      (lit name) "gw"
      (lit words) (List map first %gw-words)
      (lit tokens) (List map rest %gw-words)
      (lit aliases) (list (pair "?" "PRINT"))
      ; a word is taken where a name could not go on; FN and USR need
      ; nothing after them, and a word ending "(" ends there
      (lit crunch) (lit name-start)
      (lit prefix-words) (list "FN" "USR")
      ; RND with no argument is RND(1); ERR and ERL take none
      (lit bare-calls) (list "RND" "ERR" "ERL")
      ; CRUNCH puts a colon before ELSE
      (lit colon-before) (list "ELSE")
      ; FIN reads a constant from the text as typed
      (lit number-text) (lit raw)
      (lit numbers) %gw-numbers
      (lit layout) %gw-layout
      (lit name-length) 40
      (lit name-limit) 40
      (lit suffixes) "$%!#"
      (lit default-type) 4
      (lit line-max) 65529
      (lit for-integer) #t
      ; words this machine runs for the KIM, which mean another thing here
      (lit todo-words) (list "SAVE" "LOAD" "GET" "WAIT")
      (lit ready) "Ok"
      (lit zone) 14
      (lit width) 80
      (lit array-size) 11
      (lit fold-case) #t
      (lit error-text) (fn (_ code) (%gw-error-texts get-or "Unprintable error" (%gw-error-number code)))
      ; ERR's number for a code, and ERROR's code for a number
      (lit error-number) %gw-error-number
      (lit error-code) (fn (_ n) (%gw-error-codes get-or (Str8 str n) n))
      (lit todo-text) (fn (_ word) (Str8 append word " is not in x-basic yet"))
      (lit in-text) " in "
      (lit break-text) "Break"
      (lit redo-text) "?Redo from start"
      ; RANDOMIZE with no formula asks for the seed (RANMES)
      (lit seed-text) "Random number seed (-32768 to 32767)"
      ; items past the variables are a reason to ask again
      (lit extra-text) ()
      (lit free-text) " Bytes free"
      ; LINPRT starts past the sign's blank; CRDONZ begins a line only when
      ; the column is not 0
      (lit linprt) (lit bare)
      (lit fresh-line) (lit crdonz)
      ; HEDING's line, $DATE nine blanks, then INITSA's bytes free:
      ; MEMSIZ - TXTTAB - 2
      (lit banner-first) #t
      (lit banner) (list "" "(C) Copyright Microsoft 1982         ")
      (lit free-less) 2
      (lit txttab) 4096
      (lit ram-top) 65024)))

(provide basic/gwbasic gwbasic-dialect)
