; # x-basic -- BASIC on x-lang
;
; ## tests/harness.x -- what the spec harness adds to the dialect
;
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)
;
; The lang kit's generator writes tests/lib/harness.gen.x: the dialect
; lang.xon declares, the bundle's root on the import path, then this file.
(import x/type/list)
(import x/type/str)
(import x/type/dict)
(import basic/m6502 m6502-dialect)
(import basic/lex basic-lex)
(import basic/mbf mbf-int mbf-div mbf-mul mbf-add mbf->str mbf-bytes)
(import basic/exec basic-machine basic-type)

; TEXT's lines typed into a new 6502 machine, shown as a terminal shows
; them: each typed line, then what it printed.  REPLIES are the lines typed
; in answer to INPUT, shown as they are read.  FOLD is the machine's
; fold-case.
(def %basic-typed-on
  (fn (_ fold text replies)
    (let ((left (Dict make)))
      (left set! (lit replies) replies)
      (let ((in (fn (_)
                  (let ((r (left get (lit replies))))
                    (if (null? r) ()
                      (do (left set! (lit replies) (rest r))
                          (display (first r)) (newline)
                          (first r)))))))
        (let ((m (basic-machine m6502-dialect display in)))
          (m set! (lit fold-case) fold)
          (List for-each
            (fn (_ line) (display line) (newline) (m set! (lit col) 0) (basic-type m line))
            (Str8 split "\n" text)))))))

(def %basic-typed-input (fn (_ text replies) (%basic-typed-on #t text replies)))

(def %basic-typed (fn (_ text) (%basic-typed-on #t text ())))

; TEXT typed into a machine that reads it as typed, its case kept
(def %basic-typed-cased (fn (_ text) (%basic-typed-on #f text ())))

; TEXT's tokens in the 6502 dialect
(def %basic-tokens (fn (_ text) (basic-lex m6502-dialect text)))
