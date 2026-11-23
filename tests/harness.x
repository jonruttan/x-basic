; # x-basic -- BASIC on x-lang
;
; ## tests/harness.x -- what the spec harness adds to the dialect
;
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)
;
; The bundle kit's generator writes tests/lib/harness.gen.x: the dialect
; bundle.xon declares, the bundle's lib/ on the import path, then this file.
(import x/type/list)
(import x/type/str)
(import x/type/dict)
(import x/core/doors str-byte-ref)
(import basic/m6502 m6502-dialect)
(import basic/lex basic-lex)
(import basic/mbf mbf-int mbf-div mbf-mul mbf-add mbf->str mbf-bytes)
(import basic/exec basic-machine basic-boot basic-type)
(import basic/repl basic-fold-case-setting)
(import basic/term basic-term-out basic-term-zeros)

; TEXT's lines typed into a new 6502 machine, shown as a terminal shows
; them: each typed line, then what it printed.  REPLIES are the lines typed
; in answer to INPUT, shown as they are read.  FOLD is the machine's
; fold-case; BOOT, whether the machine is started first, REPLIES then
; answering its questions.  KEYS are the keys GET reads, each shown as it
; is read.
(def %basic-typed-boot
  (fn (_ boot fold text replies keys)
    (let ((left (Dict make)))
      (left set! (lit replies) replies)
      (left set! (lit keys) (List map (fn (_ i) (str-byte-ref keys i)) (List range 0 (Str8 length keys))))
      (let ((in (fn (_)
                  (let ((r (left get (lit replies))))
                    (if (null? r) ()
                      (do (left set! (lit replies) (rest r))
                          (basic-term-out (first r)) (basic-term-out "\n")
                          (first r))))))
            (key (fn (_)
                   (let ((k (left get (lit keys))))
                     (if (null? k) ()
                       (do (left set! (lit keys) (rest k))
                           (basic-term-out (bytes->str (list (first k))))
                           (first k)))))))
        (let ((m (basic-machine m6502-dialect basic-term-out basic-term-zeros in key)))
          (m set! (lit fold-case) fold)
          (when boot (basic-boot m))
          (List for-each
            (fn (_ line) (basic-term-out line) (basic-term-out "\n") (basic-type m line))
            (Str8 split "\n" text)))))))

(def %basic-typed-on (fn (_ fold text replies) (%basic-typed-boot #f fold text replies "")))

; TEXT typed into a new machine, KEYS pressed for its GETs
(def %basic-typed-keys (fn (_ text keys) (%basic-typed-boot #f #t text () keys)))

; A machine started with ANSWERS to its start-up questions, then TEXT typed
(def %basic-started (fn (_ answers text) (%basic-typed-boot #t #t text answers "")))

(def %basic-typed-input (fn (_ text replies) (%basic-typed-on #t text replies)))

(def %basic-typed (fn (_ text) (%basic-typed-on #t text ())))

; TEXT typed into a machine that reads it as typed, its case kept
(def %basic-typed-cased (fn (_ text) (%basic-typed-on #f text ())))

; TEXT's tokens in the 6502 dialect
(def %basic-tokens (fn (_ text) (basic-lex m6502-dialect text)))
