; # x-basic -- BASIC on x-lang
;
; ## lib/basic/repl.x -- the prompt
;
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)
;
; The line editor reads the lines and each is typed into the session's
; machine.  The prompt is empty, as on the machines these BASICs ran on: the
; dialect's ready text is what the session prints.

(module basic/repl)
(import x/type/list)
(import x/type/str)
(import x/type/dict)
(import x/core/doors int= int<)
(import x/repl/line)
(import x/repl/lang)
(import x/repl/term)
(import basic/m6502 m6502-dialect)
(import basic/gwbasic gwbasic-dialect)
(import basic/exec basic-machine basic-boot-begin! basic-boot-prompt basic-boot-answer! basic-type)
(import basic/term basic-term-out basic-term-zeros)

; The session's machine, made when the first line is typed
(def %basic-session (Dict make))

; A line read for INPUT, nil when the reader gives up
(def %basic-reply
  (fn (_)
    (let ((line (Line read "")))
      (if (or (eq? line (lit eof)) (eq? line (lit cancel))) () line))))

; A key read for GET: the terminal raw so the key comes without Enter, its
; signal keys still signalling, then put back; the key shown, as a KIM's
; terminal shows it; nil at the end of input
(def %basic-key
  (fn (_)
    (let ((saved (Term raw-with-signals! 0)))
      (let ((b (Sys fd-read 0 1)))
        (Term restore! 0 saved)
        (if (null? b) ()
          (do (basic-term-out (bytes->str (list (first b)))) (first b)))))))

; Whether a session folds case, given X_BASIC_FOLD_CASE's VALUE: DEFAULT
; when it is unset or empty, no for 0, no, off or false in any case, and
; yes for anything else
(def basic-fold-case-setting
  (fn (_ value default)
    (if (or (not (str? value)) (int= (Str8 length value) 0)) default
      (not (List includes? (Str8 downcase value) (list "0" "no" "off" "false"))))))

; The dialects by the names X_BASIC_DIALECT takes
(def %basic-dialects (list (pair "m6502" m6502-dialect) (pair "gw" gwbasic-dialect)))

; The session's dialect: X_BASIC_DIALECT's, the KIM's when it is unset or
; names none of them
(def %basic-dialect
  (fn (_)
    (let ((name (Sys getenv "X_BASIC_DIALECT")))
      (let ((hit (if (str? name) (List find (fn (_ p) (str=? (first p) (Str8 downcase name))) %basic-dialects) ())))
        (if (null? hit) m6502-dialect (rest hit))))))

(def %basic-machine
  (fn (_)
    (unless (%basic-session has? (lit m))
      (let ((m (basic-machine (%basic-dialect) basic-term-out basic-term-zeros %basic-reply %basic-key)))
        (m set! (lit fold-case)
          (basic-fold-case-setting (Sys getenv "X_BASIC_FOLD_CASE") (m get (lit fold-case))))
        ; the tape file SAVE and LOAD use, X_BASIC_TAPE when it is set
        (let ((tape (Sys getenv "X_BASIC_TAPE")))
          (when (and (str? tape) (int< 0 (Str8 length tape))) (m set! (lit tape) tape)))
        (basic-boot-begin! m)
        (%basic-session set! (lit m) m)))
    (%basic-session get (lit m))))

; The seam the editor calls with a finished line: an answer to the start-up
; question the prompt shows, or a line typed into the started machine
(def basic-eval-line
  (fn (_ line)
    (let ((m (%basic-machine)))
      (m set! (lit col) 0)
      (if (null? (basic-boot-prompt m)) (basic-type m line)
        (do (basic-boot-answer! m line)
            (%basic-register! (basic-boot-prompt m))
            (Lang use! "basic")))
      ())))

; The lang registered with PROMPT, nil for none: the editor shows the
; start-up questions as the prompt, and nothing once the machine is ready
(def %basic-register!
  (fn (_ prompt)
    (Lang register! "basic"
      (list (pair (lit %repl-prompt) (if (null? prompt) "" prompt))
            (pair (lit %repl-prompt-more) "")
            (pair (lit %repl-paint) ())
            (pair (lit %repl-complete) ())
            (pair (lit %repl-eval-line) basic-eval-line)))))

; The first prompt is the dialect's first start-up question, none for a
; dialect that asks nothing
(def basic-repl-register!
  (fn (_)
    (let ((d (%basic-dialect)))
      (%basic-register!
        (if (d has? (lit memory-prompt)) (Str8 append (d get (lit memory-prompt)) "? ") ())))))

; The machine made at once when its dialect asks nothing at start-up, so its
; banner is the first thing the session prints
(def basic-repl-start!
  (fn (_) (unless ((%basic-dialect) has? (lit memory-prompt)) (%basic-machine))))

; Whether this lang owns the session: the wrapper names the first -l in
; %lang-lead, and a bundle named by a later one is loaded beside it.  A
; wrapper older than the seam binds nothing, and the answer then is yes.
; The wrapper binds %lang-lead before the entry is imported; nothing in
; the bundle defines it, and the linter is told so.
; lint-known: %lang-lead
(def basic-leads?
  (fn (_) (guard (_ #t) (str=? %lang-lead "basic"))))

(provide basic/repl basic-eval-line basic-repl-register! basic-repl-start! basic-leads? basic-fold-case-setting)
