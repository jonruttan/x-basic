; # x-basic -- BASIC on x-lang
;
; ## run.x -- the entry
;
; @description Microsoft's BASICs and the others: `x -l basic` is a prompt
;   where a numbered line is stored and any other line runs at once.
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)
;
; This file contains no path literals.  x.sh boots the dialect lang.xon
; declares, arms this bundle's root with import-path!, reads this file, and
; appends the launcher when no -f was given.
(import basic/version basic-version)
(import basic/repl basic-leads? basic-repl-register!)

(basic-repl-register!)

; The prompt is this lang's when it leads the session.
(when (basic-leads?)
  (set! %lang-name "BASIC")
  (set! %lang-version basic-version)
  (Lang use! "basic"))
