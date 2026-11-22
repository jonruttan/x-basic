; # x-basic -- BASIC on x-lang
;
; ## lib/basic/run.x -- the entry
;
; @description Microsoft's BASICs and the others: `x -l basic` is a prompt
;   where a numbered line is stored and any other line runs at once.
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)
;
; This file contains no path literals.  x.sh boots the dialect bundle.xon
; declares, arms this bundle's lib/ with import-path!, imports this module
; and calls its main, and appends the launcher when no -f was given.
;
; Importing this module sets BASIC up and starts nothing: the lang is
; registered, and the prompt is made its own when it leads the session.

(module basic/run)
(import basic/version basic-version)
(import basic/repl basic-leads? basic-repl-register!)

(basic-repl-register!)

; The prompt is this lang's when it leads the session.
(when (basic-leads?)
  (set! %lang-name "BASIC")
  (set! %lang-version basic-version)
  (Lang use! "basic"))

; The prompt is all there is: a program from -f or piped in waits on a line
; reader in x-lang, so main has nothing to start.
(def main (fn (_) ()))

(provide basic/run main)
