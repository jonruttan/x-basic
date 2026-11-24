; # x-basic -- BASIC on x-lang
;
; ## lib/basic/m6502.x -- Microsoft 6502 BASIC 1.1, the KIM-1 build
;
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)
;
; Facts read from Microsoft's MIT-licensed source, m6502.asm, assembled with
; REALIO=1 (MOS Technology KIM-1): the reserved words in the order CRUNCH
; searches them (RESLST), two-letter errors (LNGERR=0), "OK" after a command,
; print zones of 14 columns (CLMWID) on a 72-column line (LINLEN), nine-digit
; numbers (ADDPRC=1) and arrays of 11 elements when undimensioned.
;
; A dialect is a Dict the machine reads everything it does not share from:
; its words, its numbers (a kit of the operations the machine uses, here
; the five-byte format of basic/mbf), how its variables lie in memory, and
; the texts it prints.

(module basic/m6502)
(import x/type/list)
(import x/type/dict)
(import x/type/err)
(import x/core/doors int+ int- int< int<< int>> int& int| str-byte-ref)
(import x/type/str)
(import basic/mbf
  mbf-zero mbf-zero? mbf-bytes mbf->bytes mbf-int mbf-neg mbf-abs mbf-sgn mbf-cmp mbf-round mbf-add mbf-sub
  mbf-mul mbf-div mbf-floor mbf->int mbf->str mbf-read)
(import basic/mbf-math
  mbf-log mbf-exp mbf-power mbf-sqr mbf-sin mbf-cos mbf-tan mbf-atn mbf-rnd-seed mbf-rnd)

; A number as an integer by INT, wrapped to 16 bits as the source's AYINT
; path takes it; ?FC past 65536 either way
(def %m65-integer (fn (_ v) (mbf->int (mbf-floor v) 65536)))

; A number as a signed word: ?FC outside -32768..32767
(def %m65-word
  (fn (_ v)
    (let ((n (%m65-integer v)))
      (if (or (int< n -32768) (int< 32767 n)) (Err raise (lit basic) "FC") n))))

(def %m65-signed (fn (_ w) (if (int< w 32768) w (int- w 65536))))

(def %m65-numbers
  (Dict from-plist
    (list
      (lit zero) mbf-zero
      (lit int) mbf-int
      (lit zero?) mbf-zero?
      (lit neg) mbf-neg
      (lit abs) mbf-abs
      (lit sign) mbf-sgn
      (lit cmp) mbf-cmp
      ; FADD and FSUB round the accumulator first; FMULT takes its operands
      ; the other way about
      (lit add) (fn (_ a b) (mbf-add (mbf-round a) b))
      (lit sub) (fn (_ a b) (mbf-sub (mbf-round a) b))
      (lit mul) (fn (_ a b) (mbf-mul b a))
      (lit div) mbf-div
      (lit power) (fn (_ a b) (mbf-power (mbf-round a) b))
      (lit floor) mbf-floor
      (lit integer) %m65-integer
      (lit ->str) mbf->str
      (lit read) mbf-read
      ; FRE's FRETOP - STREND made a signed word (GIVAYF)
      (lit fre) (fn (_ n) (mbf-int (%m65-signed (int& n 65535))))
      ; a value as a variable of TYPE holds it: an integer's word, ?FC
      ; outside it; a real rounded to its four mantissa bytes
      (lit fit) (fn (_ type v) (if (int= type 2) (mbf-int (%m65-word v)) (mbf-round v)))
      ; an integer's bytes high first, a real's five as MOVMF stores them
      (lit ->bytes)
        (fn (_ type v)
          (if (int= type 2)
            (let ((w (int& (mbf->int v 65536) 65535))) (list (int>> w 8) (int& w 255)))
            (mbf->bytes v)))
      (lit from-bytes)
        (fn (_ type bs)
          (if (int= type 2) (mbf-int (%m65-signed (int+ (int<< (first bs) 8) (List second bs))))
            (mbf-bytes (first bs) (List second bs) (List third bs) (List ref 3 bs) (List ref 4 bs))))
      (lit math)
        (Dict from-plist
          (list "SQR" mbf-sqr "LOG" mbf-log "EXP" mbf-exp "SIN" mbf-sin "COS" mbf-cos
                "TAN" mbf-tan "ATN" mbf-atn))
      (lit rnd) mbf-rnd
      (lit rnd-seed) mbf-rnd-seed)))

; NAME1 NAME2 of a name (PTRGET): the letters, the second 0 when there is
; none; a string's second with its top bit on, an integer's both
(def %m65-name-bytes
  (fn (_ base)
    (pair (str-byte-ref base 0) (if (int< 1 (Str8 length base)) (str-byte-ref base 1) 0))))

; A simple variable is NAME1 NAME2 and five value bytes; an array NAME1
; NAME2, its whole length, the count of its dimensions and each one's size
; high byte first.  A function is NAME1 with its top bit on.
(def %m65-layout
  (Dict from-plist
    (list
      (lit var-header)
        (fn (_ base type)
          (let ((nb (%m65-name-bytes base)))
            (match
              ((int= type 3) (list (first nb) (int| (rest nb) 128)))
              ((int= type 2) (list (int| (first nb) 128) (int| (rest nb) 128)))
              (#t (list (first nb) (rest nb))))))
      (lit fn-header)
        (fn (_ base type) (let ((nb (%m65-name-bytes base))) (list (int| (first nb) 128) (rest nb))))
      (lit value-size) (fn (_ type) 5)
      (lit element-size) (fn (_ type) (match ((int= type 3) 3) ((int= type 2) 2) (#t 5)))
      (lit header-length) (fn (_ peek a) 2)
      (lit entry-type)
        (fn (_ peek a)
          (let ((n1 (peek a)) (n2 (peek (int+ a 1))))
            (match
              ((and (int< n1 128) (not (int< n2 128))) 3)
              ((and (not (int< n1 128)) (not (int< n2 128))) 2)
              (#t 4))))
      (lit array-field) (fn (_ total hl) total)
      (lit array-total) (fn (_ field hl) field)
      (lit dim-bytes) (fn (_ w) (list (int>> w 8) (int& w 255))))))

(def m6502-dialect
  (Dict from-plist
    (list
      (lit name) "m6502"
      (lit words)
        (list "END" "FOR" "NEXT" "DATA" "INPUT" "DIM" "READ" "LET" "GOTO" "RUN"
              "IF" "RESTORE" "GOSUB" "RETURN" "REM" "STOP" "ON" "NULL" "WAIT"
              "LOAD" "SAVE" "DEF" "POKE" "PRINT" "CONT" "LIST" "CLEAR" "GET" "NEW"
              "TAB(" "TO" "FN" "SPC(" "THEN" "NOT" "STEP"
              "+" "-" "*" "/" "^" "AND" "OR" ">" "=" "<"
              "SGN" "INT" "ABS" "USR" "FRE" "POS" "SQR" "RND" "LOG" "EXP" "COS"
              "SIN" "TAN" "ATN" "PEEK" "LEN" "STR$" "VAL" "ASC" "CHR$" "LEFT$"
              "RIGHT$" "MID$" "GO")
      ; CRUNCH makes ? into PRINT
      (lit aliases) (list (pair "?" "PRINT"))
      (lit crunch) (lit anywhere)
      ; FIN reads a constant from the crunched text
      (lit number-text) (lit crunched)
      (lit numbers) %m65-numbers
      (lit layout) %m65-layout
      ; two characters of a name are kept, and $ or % after it
      (lit name-length) 2
      (lit suffixes) "$%"
      (lit default-type) 4
      (lit line-max) 63999
      (lit ready) "OK"
      (lit zone) 14
      (lit width) 72
      (lit array-size) 11
      ; names and reserved words read in either case, as later BASICs do
      (lit fold-case) #t
      ; the texts it prints: a two-letter error, a line number with the
      ; blank its sign leaves (LINPRT), and a new line before an error and
      ; before OK whatever the column
      (lit error-text) (fn (_ code) (Str8 append "?" code " ERROR"))
      (lit todo-text) (fn (_ word) (Str8 append "?" word " IS NOT IN X-BASIC YET"))
      (lit in-text) " IN "
      (lit break-text) "BREAK"
      (lit redo-text) "?REDO FROM START"
      (lit extra-text) "?EXTRA IGNORED"
      (lit free-text) " BYTES FREE"
      (lit linprt) (lit sign)
      (lit fresh-line) (lit always)
      ; the program from RAMLOC + 1 ($4001), a zero before it; a blank
      ; MEMORY SIZE? finds RAM to $C000 here, 32K past RAMLOC
      (lit txttab) 16385
      (lit ram-top) 49152
      ; INIT's questions and what it prints after the bytes free (KIMROM:
      ; WIDTH, not TERMINAL WIDTH, and no WANT SIN-COS-TAN-ATN)
      (lit memory-prompt) "MEMORY SIZE"
      (lit width-prompt) "WIDTH"
      (lit banner) (list "KIM BASIC V1.1" "COPYRIGHT 1978 MICROSOFT")
      ; USR: page zero as the ROMSW build lays it out (START, RDYJSR,
      ; ADRAYI, ADRGAY, then USRPOK's JMP, which INIT points at FCERR;
      ; VALTYP; the FAC's FACEXP FACHO FACMOH FACMO FACLO FACSGN, and
      ; FACOV), and the ROM routines' addresses in the KIM BASIC that
      ; shipped (FCERR, AYINT, GIVAYF), where a program reaches them
      (lit adrayi) 6
      (lit adrgay) 8
      (lit usrpok) 10
      (lit valtyp) 17
      (lit fac) 177
      (lit facov) 192
      (lit fcerr) 12363
      (lit ayint) 12226
      (lit givayf) 12693)))

(provide basic/m6502 m6502-dialect)
