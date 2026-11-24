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
(import x/sys/file)
(import x/core/doors int+ int< int= int& str-byte-ref str-byte-len str-make)
(import x/type/vector)
(import x/type/err)
(import basic/cpu cpu-make cpu-call!)
(import basic/m6502 m6502-dialect)
(import basic/gwbasic gwbasic-dialect)
(import basic/lex basic-lex)
(import basic/mbf mbf-int mbf-div mbf-mul mbf-add mbf->str mbf-bytes)
(import basic/mbf86
  m86-read m86->str m86-add m86-sub m86-mul m86-div m86-idiv m86-mod m86->bytes m86->single m86->double
  m86-cint m86-floor m86-neg)
(import basic/exec basic-machine basic-boot basic-type)
(import basic/repl basic-fold-case-setting)
(import basic/term basic-term-out basic-term-zeros)

; The tape the machines SAVE to and LOAD from: a file in the temporary
; directory named for this process, so suites running at once keep apart
(def %basic-tape
  (Str8 append (let ((t (Sys getenv "TMPDIR"))) (if (str? t) t "/tmp")) "/x-basic-"
    (Str8 trim (mbf->str (mbf-int (Sys getpid)))) ".tape"))

; The tape removed, when it is there
(def %basic-tape-remove!
  (fn (_) (when (File exists? %basic-tape) (File unlink %basic-tape))))

; TEXT written as the tape
(def %basic-tape-write!
  (fn (_ text)
    (let ((fd (File open %basic-tape (list 'wronly 'creat 'trunc))))
      (File write fd text (str-byte-len text))
      (File close fd))))

(def %basic-tape-size 4096)

; The tape's text, its first bytes read, the SYN run before the * counted
; as "N SYN " and each EOT shown as <EOT>
(def %basic-tape-shown
  (fn (_)
    (let ((fd (File open %basic-tape 'rdonly)) (buf (str-make %basic-tape-size)))
      (let ((n (File read fd buf %basic-tape-size)))
        (File close fd)
        (let ((syn (let ((go (fn (self i) (if (and (int< i n) (int= (str-byte-ref buf i) 22)) (self (int+ i 1)) i))))
                     (go 0))))
          (Str8 append (Str8 trim (mbf->str (mbf-int syn))) " SYN "
            (Str8 join ""
              (List map
                (fn (_ i) (let ((b (str-byte-ref buf i))) (if (int= b 4) "<EOT>" (bytes->str (list b)))))
                (List range syn n)))))))))

; TEXT's lines typed into a new DIALECT machine, shown as a terminal shows
; them: each typed line, then what it printed.  REPLIES are the lines typed
; in answer to INPUT, shown as they are read.  FOLD is the machine's
; fold-case; BOOT, whether the machine is started first, REPLIES then
; answering its questions.  KEYS are the keys GET reads, each shown as it
; is read.
(def %basic-typed-boot
  (fn (_ dialect boot fold text replies keys)
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
        (let ((m (basic-machine dialect basic-term-out basic-term-zeros in key)))
          (m set! (lit fold-case) fold)
          (m set! (lit tape) %basic-tape)
          (when boot (basic-boot m))
          (List for-each
            (fn (_ line) (basic-term-out line) (basic-term-out "\n") (basic-type m line))
            (Str8 split "\n" text)))))))

(def %basic-typed-on (fn (_ fold text replies) (%basic-typed-boot m6502-dialect #f fold text replies "")))

; TEXT typed into a new machine, KEYS pressed for its GETs
(def %basic-typed-keys (fn (_ text keys) (%basic-typed-boot m6502-dialect #f #t text () keys)))

; A machine started with ANSWERS to its start-up questions, then TEXT typed
(def %basic-started (fn (_ answers text) (%basic-typed-boot m6502-dialect #t #t text answers "")))

(def %basic-typed-input (fn (_ text replies) (%basic-typed-on #t text replies)))

(def %basic-typed (fn (_ text) (%basic-typed-on #t text ())))

; TEXT typed into a new GW-BASIC machine, REPLIES its INPUT's; started
; first, its banner printed, with %gw-started
(def %gw-typed-input (fn (_ text replies) (%basic-typed-boot gwbasic-dialect #f #t text replies "")))
(def %gw-typed (fn (_ text) (%gw-typed-input text ())))
(def %gw-started (fn (_ text) (%basic-typed-boot gwbasic-dialect #t #t text () "")))

; TEXT's tokens in GW-BASIC
(def %gw-tokens (fn (_ text) (basic-lex gwbasic-dialect text)))

; TEXT typed into a machine that reads it as typed, its case kept
(def %basic-typed-cased (fn (_ text) (%basic-typed-on #f text ())))

; CODE, a list of bytes, put at $0300 in a fresh 64K and called, HOOKS a
; list of (ADDRESS . FN); answers (A X Y P) after its RTS, P in binary
; NV-BDIZC order as a string
(def %basic-cpu
  (fn (_ code hooks)
    (let ((bytes (Vector make 65536 0)) (h (Dict make)))
      (List for-each (fn (_ i) (Vector set! (int+ 768 i) (List ref i code) bytes))
        (List range 0 (List length code)))
      (List for-each (fn (_ e) (h set! (first e) (rest e))) hooks)
      (let ((c (cpu-make bytes)))
        (cpu-call! c 768 h)
        (list (c get (lit a)) (c get (lit x)) (c get (lit y))
              (Str8 join ""
                (List map (fn (_ bit) (if (int= (int& (c get (lit p)) bit) 0) "0" "1"))
                  (list 128 64 32 16 8 4 2 1))))))))

; The label and payload of the error THUNK raises
(def %basic-raised
  (fn (_ thunk) (guard (e (list (Err label e) (Err text e))) (thunk))))

; TEXT's tokens in the 6502 dialect
(def %basic-tokens (fn (_ text) (basic-lex m6502-dialect text)))

; --- the 8086 BASIC's numbers --------------------------------------------

; Each of TEXTS read as GW-BASIC reads a number, then printed as it prints
; one
(def %gw-numbers
  (fn (_ texts) (List map (fn (_ t) (m86->str (first (m86-read t 0)))) texts)))

; The number TEXT reads as
(def %gw-read (fn (_ text) (first (m86-read text 0))))

; The number OP makes of the numbers A and B read, printed
(def %gw-op (fn (_ op a b) (m86->str (op (%gw-read a) (%gw-read b)))))
