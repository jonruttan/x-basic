; # x-basic -- BASIC on x-lang
;
; ## basic/m6502.x -- Microsoft 6502 BASIC 1.1, the KIM-1 build
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

(module basic/m6502)
(import x/type/dict)

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
      (lit ready) "OK"
      (lit zone) 14
      (lit width) 72
      (lit array-size) 11
      (lit name-length) 2)))

(provide basic/m6502 m6502-dialect)
