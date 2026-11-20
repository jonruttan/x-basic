; # x-basic -- BASIC on x-lang
;
; ## basic/repl.x -- the prompt
;
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)
;
; The line editor reads the lines and each is typed into the session's
; machine.  The prompt is empty, as on the machines these BASICs ran on: the
; dialect's ready text is what the session prints.

(module basic/repl)
(import x/type/dict)
(import x/repl/line)
(import x/repl/lang)
(import basic/m6502 m6502-dialect)
(import basic/exec basic-machine basic-type)

; The session's machine, made when the first line is typed
(def %basic-session (Dict make))

; A line read for INPUT, nil when the reader gives up
(def %basic-reply
  (fn (_)
    (let ((line (Line read "")))
      (if (or (eq? line (lit eof)) (eq? line (lit cancel))) () line))))

(def %basic-machine
  (fn (_)
    (unless (%basic-session has? (lit m))
      (%basic-session set! (lit m) (basic-machine m6502-dialect display %basic-reply)))
    (%basic-session get (lit m))))

; The seam the editor calls with a finished line
(def basic-eval-line
  (fn (_ line)
    (let ((m (%basic-machine)))
      (m set! (lit col) 0)
      (basic-type m line)
      ())))

(def basic-repl-register!
  (fn (_)
    (Lang register! "basic"
      (list (pair (lit %repl-prompt) "")
            (pair (lit %repl-prompt-more) "")
            (pair (lit %repl-paint) ())
            (pair (lit %repl-complete) ())
            (pair (lit %repl-eval-line) basic-eval-line)))))

; Whether this lang owns the session: the wrapper names the first -l in
; %lang-lead, and a bundle named by a later one is loaded beside it.  A
; wrapper older than the seam binds nothing, and the answer then is yes.
(def basic-leads?
  (fn (_) (guard (_ #t) (str=? %lang-lead "basic"))))

(provide basic/repl basic-eval-line basic-repl-register! basic-leads?)
