; # x-basic -- BASIC on x-lang
;
; ## basic/parse.x -- tokens to statements
;
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)
;
; A line's tokens to its statements, each a list headed by its name.  Every
; reader here takes the tokens and answers (RESULT . TOKENS-LEFT).  A
; statement that does not parse becomes (bad "SN"), which raises when it is
; reached, as Microsoft's BASICs report syntax when they run a line and not
; when it is typed.
;
; IF is (if EXPR) followed by what came after THEN as statements of the same
; line: a false IF skips the rest of the line, and THEN 100 is GOTO 100.
;
; Expressions, loosest first: OR, AND, NOT, the relations, + and -, * and /,
; a sign, ^.  So NOT A=B is NOT (A=B), -2^2 is -4, and 2^-1 is .5.
;
;   (num N) (str TEXT) (var NAME) (elem NAME ARGS) (call WORD ARGS)
;   (neg E) (not E) (op WORD A B) (rel MASK A B)
;
; A name is its first two characters and its $ or %; MASK holds 1 for <,
; 2 for = and 4 for >.

(module basic/parse)
(import x/type/list)
(import x/type/str)
(import x/type/err)
(import x/core/doors int+ int- int* int< int= int| char->int str-byte-ref)
(import basic/mbf mbf-from-digits)

(def %bp-fail (fn (_) (Err raise (lit basic) "SN")))

; --- tokens ---------------------------------------------------------------

(def %bp-kw?
  (fn (_ ts word)
    (and (not (null? ts)) (eq? (first (first ts)) (lit kw))
         (str=? (List second (first ts)) word))))

(def %bp-c?
  (fn (_ ts ch)
    (and (not (null? ts)) (eq? (first (first ts)) (lit c))
         (str=? (List second (first ts)) ch))))

; The byte of a one-byte token, or nil
(def %bp-byte
  (fn (_ ts)
    (if (or (null? ts) (not (eq? (first (first ts)) (lit c)))) ()
      (str-byte-ref (List second (first ts)) 0))))

(def %bp-letter? (fn (_ b) (and (not (null? b)) (not (int< b 65)) (not (int< 90 b)))))
(def %bp-digit? (fn (_ b) (and (not (null? b)) (not (int< b 48)) (not (int< 57 b)))))

; Whether TS is at the end of a statement
(def %bp-end? (fn (_ ts) (or (null? ts) (%bp-c? ts ":"))))

(def %bp-expect-c
  (fn (_ ts ch) (if (%bp-c? ts ch) (rest ts) (%bp-fail))))

(def %bp-expect-kw
  (fn (_ ts word) (if (%bp-kw? ts word) (rest ts) (%bp-fail))))

; --- numbers and names ----------------------------------------------------

; Digits at TS: (BYTES . TS-LEFT)
(def %bp-digits
  (fn (_ ts)
    (let ((go (fn (self ts acc)
                (let ((b (%bp-byte ts)))
                  (if (%bp-digit? b) (self (rest ts) (pair b acc))
                    (pair (List reverse acc) ts))))))
      (go ts ()))))

; A line number: digits only, under 64000
(def %bp-line-number
  (fn (_ ts)
    (let ((got (%bp-digits ts)))
      (if (null? (first got)) (%bp-fail)
        (let ((n (List fold (fn (_ n b) (int+ (int* n 10) (int- b 48))) 0 (first got))))
          (if (int< n 64000) (pair n (rest got)) (%bp-fail)))))))

; A number: digits, a point and digits, then E, a sign and digits
(def %bp-number
  (fn (_ ts)
    (let ((whole (%bp-digits ts)))
      (let ((frac (if (%bp-c? (rest whole) ".") (%bp-digits (rest (rest whole)))
                    (pair () (rest whole)))))
        (let ((ex (if (%bp-c? (rest frac) "E")
                    (let ((after (rest (rest frac))))
                      (let ((neg (%bp-kw? after "-")))
                        (let ((ds (%bp-digits (if (or neg (%bp-kw? after "+")) (rest after) after))))
                          (pair (List fold (fn (_ n b) (int+ (int* n 10) (int- b 48))) 0
                                           (List take 3 (first ds)))
                                (pair neg (rest ds))))))
                    (pair 0 (pair #f (rest frac))))))
          (let ((e (if (List second ex) (int- 0 (first ex)) (first ex))))
            (pair (list (lit num)
                        (mbf-from-digits (List append (first whole) (first frac))
                                         (List length (first frac)) e))
                  (rest (rest ex)))))))))

; A name at TS: a letter, then letters and digits, then $ or %.  The name
; kept is the first two characters and the sign.
(def %bp-name
  (fn (_ ts)
    (unless (%bp-letter? (%bp-byte ts)) (%bp-fail))
    (let ((go (fn (self ts acc)
                (let ((b (%bp-byte ts)))
                  (if (or (%bp-letter? b) (%bp-digit? b)) (self (rest ts) (pair b acc))
                    (pair (List reverse acc) ts))))))
      (let ((got (go ts ())))
        (let ((sign (match
                      ((%bp-c? (rest got) "$") "$")
                      ((%bp-c? (rest got) "%") "%")
                      (#t ""))))
          (pair (Str8 append (bytes->str (List take 2 (first got))) sign)
                (if (= (Str8 length sign) 0) (rest got) (rest (rest got)))))))))

; Expressions separated by commas, to a closing parenthesis
(def %bp-args
  (fn (_ ts)
    (let ((go (fn (self ts acc)
                (let ((got (basic-parse-expr ts)))
                  (if (%bp-c? (rest got) ",") (self (rest (rest got)) (pair (first got) acc))
                    (pair (List reverse (pair (first got) acc)) (%bp-expect-c (rest got) ")")))))))
      (go ts ()))))

; A variable, or an array element when a parenthesis follows
(def %bp-target
  (fn (_ ts)
    (let ((got (%bp-name ts)))
      (if (%bp-c? (rest got) "(")
        (let ((args (%bp-args (rest (rest got)))))
          (pair (list (lit elem) (first got) (first args)) (rest args)))
        (pair (list (lit var) (first got)) (rest got))))))

; --- expressions ----------------------------------------------------------

; The functions, by reserved word, and how many arguments each takes: a
; list of the counts it accepts
(def %bp-functions
  (list (pair "SGN" (list 1)) (pair "INT" (list 1)) (pair "ABS" (list 1))
        (pair "USR" (list 1)) (pair "FRE" (list 1)) (pair "POS" (list 1))
        (pair "SQR" (list 1)) (pair "RND" (list 1)) (pair "LOG" (list 1))
        (pair "EXP" (list 1)) (pair "COS" (list 1)) (pair "SIN" (list 1))
        (pair "TAN" (list 1)) (pair "ATN" (list 1)) (pair "PEEK" (list 1))
        (pair "LEN" (list 1)) (pair "STR$" (list 1)) (pair "VAL" (list 1))
        (pair "ASC" (list 1)) (pair "CHR$" (list 1)) (pair "LEFT$" (list 2))
        (pair "RIGHT$" (list 2)) (pair "MID$" (list 2 3))))

(def %bp-primary
  (fn (_ ts)
    (let ((t (if (null? ts) (%bp-fail) (first ts))))
      (match
        ((eq? (first t) (lit str))
          (let ((text (List second t)))
            (let ((n (Str8 length text)))
              (pair (list (lit str)
                          (if (and (int< 1 n) (int= (str-byte-ref text (int- n 1)) 34))
                            (Str8 sub 1 (int- n 2) text)
                            (Str8 sub 1 (int- n 1) text)))
                    (rest ts)))))
        ((%bp-c? ts "(")
          (let ((got (basic-parse-expr (rest ts))))
            (pair (first got) (%bp-expect-c (rest got) ")"))))
        ((or (%bp-digit? (%bp-byte ts)) (%bp-c? ts ".")) (%bp-number ts))
        ((%bp-letter? (%bp-byte ts)) (%bp-target ts))
        ; FN, a name, and its argument in parentheses (FNDOER)
        ((%bp-kw? ts "FN")
          (let ((name (%bp-name (rest ts))))
            (let ((got (basic-parse-expr (%bp-expect-c (rest name) "("))))
              (pair (list (lit fn) (first name) (first got)) (%bp-expect-c (rest got) ")")))))
        ((eq? (first t) (lit kw))
          (let ((fun (List find (fn (_ f) (str=? (first f) (List second t))) %bp-functions)))
            (if (null? fun) (%bp-fail)
              (let ((args (%bp-args (%bp-expect-c (rest ts) "("))))
                (if (List includes? (List length (first args)) (rest fun))
                  (pair (list (lit call) (first fun) (first args)) (rest args))
                  (%bp-fail))))))
        (#t (%bp-fail))))))

; The operand of ^: a sign may lead it
(def %bp-power-operand
  (fn (_ ts)
    (match
      ((%bp-kw? ts "-")
        (let ((got (%bp-power-operand (rest ts)))) (pair (list (lit neg) (first got)) (rest got))))
      ((%bp-kw? ts "+") (%bp-power-operand (rest ts)))
      (#t (%bp-primary ts)))))

(def %bp-power
  (fn (_ ts)
    (let ((go (fn (self got)
                (if (%bp-kw? (rest got) "^")
                  (let ((r (%bp-power-operand (rest (rest got)))))
                    (self (pair (list (lit op) "^" (first got) (first r)) (rest r))))
                  got))))
      (go (%bp-primary ts)))))

(def %bp-sign
  (fn (_ ts)
    (match
      ((%bp-kw? ts "-")
        (let ((got (%bp-sign (rest ts)))) (pair (list (lit neg) (first got)) (rest got))))
      ((%bp-kw? ts "+") (%bp-sign (rest ts)))
      (#t (%bp-power ts)))))

; A left-associative level: operands read by NEXT, joined by WORDS
(def %bp-level
  (fn (_ ts next words)
    (let ((go (fn (self got)
                (let ((hit (List find (fn (_ w) (%bp-kw? (rest got) w)) words)))
                  (if (null? hit) got
                    (let ((r (next (rest (rest got)))))
                      (self (pair (list (lit op) hit (first got) (first r)) (rest r)))))))))
      (go (next ts)))))

(def %bp-product (fn (_ ts) (%bp-level ts %bp-sign (list "*" "/"))))
(def %bp-sum (fn (_ ts) (%bp-level ts %bp-product (list "+" "-"))))

; The relation the < = > tokens at TS spell: (MASK . TS-LEFT), MASK 0 when
; there is none
(def %bp-relation
  (fn (_ ts)
    (let ((go (fn (self ts mask)
                (match
                  ((%bp-kw? ts "<") (self (rest ts) (int| mask 1)))
                  ((%bp-kw? ts "=") (self (rest ts) (int| mask 2)))
                  ((%bp-kw? ts ">") (self (rest ts) (int| mask 4)))
                  (#t (pair mask ts))))))
      (go ts 0))))

(def %bp-compare
  (fn (_ ts)
    (let ((go (fn (self got)
                (let ((rel (%bp-relation (rest got))))
                  (if (int= (first rel) 0) got
                    (let ((r (%bp-sum (rest rel))))
                      (self (pair (list (lit rel) (first rel) (first got) (first r)) (rest r)))))))))
      (go (%bp-sum ts)))))

(def %bp-not
  (fn (_ ts)
    (if (%bp-kw? ts "NOT")
      (let ((got (%bp-not (rest ts)))) (pair (list (lit not) (first got)) (rest got)))
      (%bp-compare ts))))

(def %bp-and (fn (_ ts) (%bp-level ts %bp-not (list "AND"))))

(def basic-parse-expr (fn (_ ts) (%bp-level ts %bp-and (list "OR"))))

; A number at TS with its sign, as FIN reads one from DATA, INPUT or VAL:
; (NUMBER . TS-LEFT), or nil when TS holds none
(def basic-parse-value
  (fn (_ ts)
    (let ((neg (%bp-kw? ts "-")))
      (let ((ts (if (or neg (%bp-kw? ts "+")) (rest ts) ts)))
        (if (not (or (%bp-digit? (%bp-byte ts)) (%bp-c? ts "."))) ()
          (let ((got (%bp-number ts)))
            (pair (if neg (list (lit neg) (first got)) (first got)) (rest got))))))))

; --- DATA and INPUT items -------------------------------------------------

; A DATA token's text without the word and the colon that ended it
(def %bp-data-text
  (fn (_ text)
    (let ((n (Str8 length text)))
      (if (and (int< 4 n) (int= (str-byte-ref text (int- n 1)) 58))
        (Str8 sub 4 (int- n 5) text)
        (Str8 sub 4 (int- n 4) text)))))

; TEXT split at its commas outside quotes, each item with its leading
; blanks gone: (quoted TEXT) inside quotes, else (plain TEXT) with its
; trailing blanks kept
(def basic-items
  (fn (_ text)
    (let ((n (Str8 length text)))
      (let ((skip (fn (self i) (if (and (int< i n) (int= (str-byte-ref text i) 32)) (self (int+ i 1)) i)))
            (upto (fn (self i b) (if (or (not (int< i n)) (int= (str-byte-ref text i) b)) i (self (int+ i 1) b)))))
        (let ((go (fn (self i acc)
                    (let ((s (skip i)))
                      (if (and (int< s n) (int= (str-byte-ref text s) 34))
                        (let ((close (upto (int+ s 1) 34)))
                          (let ((item (list (lit quoted) (Str8 sub (int+ s 1) (int- close (int+ s 1)) text)))
                                (comma (upto close 44)))
                            (if (int< comma n) (self (int+ comma 1) (pair item acc))
                              (List reverse (pair item acc)))))
                        (let ((comma (upto s 44)))
                          (let ((item (list (lit plain) (Str8 sub s (int- comma s) text))))
                            (if (int< comma n) (self (int+ comma 1) (pair item acc))
                              (List reverse (pair item acc))))))))))
          (go 0 ()))))))

; --- statements -----------------------------------------------------------

; Targets separated by commas, to the end of the statement
(def %bp-targets
  (fn (_ ts)
    (let ((go (fn (self ts acc)
                (let ((got (%bp-target ts)))
                  (if (%bp-c? (rest got) ",") (self (rest (rest got)) (pair (first got) acc))
                    (pair (List reverse (pair (first got) acc)) (rest got)))))))
      (go ts ()))))

; Line numbers separated by commas
(def %bp-line-numbers
  (fn (_ ts)
    (let ((go (fn (self ts acc)
                (let ((got (%bp-line-number ts)))
                  (if (%bp-c? (rest got) ",") (self (rest (rest got)) (pair (first got) acc))
                    (pair (List reverse (pair (first got) acc)) (rest got)))))))
      (go ts ()))))

(def %bp-print-items
  (fn (_ ts)
    (let ((go (fn (self ts acc)
                (match
                  ((%bp-end? ts) (pair (List reverse acc) ts))
                  ((%bp-c? ts ";") (self (rest ts) (pair (list (lit semi)) acc)))
                  ((%bp-c? ts ",") (self (rest ts) (pair (list (lit comma)) acc)))
                  ((or (%bp-kw? ts "TAB(") (%bp-kw? ts "SPC("))
                    (let ((got (basic-parse-expr (rest ts))))
                      (self (%bp-expect-c (rest got) ")")
                            (pair (list (if (%bp-kw? ts "TAB(") (lit tab) (lit spc)) (first got))
                                  acc))))
                  (#t (let ((got (basic-parse-expr ts)))
                        (self (rest got) (pair (list (lit expr) (first got)) acc))))))))
      (go ts ()))))

(def %bp-assign
  (fn (_ ts)
    (let ((target (%bp-target ts)))
      (let ((value (basic-parse-expr (%bp-expect-kw (rest target) "="))))
        (pair (list (list (lit let) (first target) (first value))) (rest value))))))

; FOR V = A TO B [STEP C]; V a plain number variable
(def %bp-for
  (fn (_ ts)
    (let ((name (%bp-name ts)))
      (when (or (Str8 ends? "$" (first name)) (Str8 ends? "%" (first name))) (%bp-fail))
      (let ((from (basic-parse-expr (%bp-expect-kw (rest name) "="))))
        (let ((to (basic-parse-expr (%bp-expect-kw (rest from) "TO"))))
          (let ((step (if (%bp-kw? (rest to) "STEP") (basic-parse-expr (rest (rest to)))
                        (pair () (rest to)))))
            (pair (list (list (lit for) (first name) (first from) (first to) (first step)))
                  (rest step))))))))

(def %bp-next
  (fn (_ ts)
    (if (%bp-end? ts) (pair (list (list (lit next) ())) ts)
      (let ((go (fn (self ts acc)
                  (let ((got (%bp-name ts)))
                    (if (%bp-c? (rest got) ",") (self (rest (rest got)) (pair (first got) acc))
                      (pair (list (list (lit next) (List reverse (pair (first got) acc))))
                            (rest got)))))))
        (go ts ())))))

(def %bp-dim
  (fn (_ ts)
    (let ((go (fn (self ts acc)
                (let ((name (%bp-name ts)))
                  (let ((args (%bp-args (%bp-expect-c (rest name) "("))))
                    (let ((acc2 (pair (pair (first name) (first args)) acc)))
                      (if (%bp-c? (rest args) ",") (self (rest (rest args)) acc2)
                        (pair (list (list (lit dim) (List reverse acc2))) (rest args)))))))))
      (go ts ()))))

; IF E THEN N, IF E GOTO N, or IF E THEN statements
(def %bp-if
  (fn (_ ts)
    (let ((test (basic-parse-expr ts)))
      (let ((after (rest test)))
        (match
          ((%bp-kw? after "GOTO")
            (let ((n (%bp-line-number (rest after))))
              (pair (list (list (lit if) (first test)) (list (lit goto) (first n))) (rest n))))
          ((%bp-kw? after "THEN")
            (if (%bp-digit? (%bp-byte (rest after)))
              (let ((n (%bp-line-number (rest after))))
                (pair (list (list (lit if) (first test)) (list (lit goto) (first n))) (rest n)))
              (pair (list (list (lit if) (first test))) (pair (list (lit c) ":") (rest after)))))
          (#t (%bp-fail)))))))

(def %bp-on
  (fn (_ ts)
    (let ((which (basic-parse-expr ts)))
      (let ((kind (match
                    ((%bp-kw? (rest which) "GOTO") (lit goto))
                    ((%bp-kw? (rest which) "GOSUB") (lit gosub))
                    (#t (%bp-fail)))))
        (let ((ns (%bp-line-numbers (rest (rest which)))))
          (pair (list (list (lit on) (first which) kind (first ns))) (rest ns)))))))

(def %bp-input
  (fn (_ ts)
    (let ((prompt (if (and (not (null? ts)) (eq? (first (first ts)) (lit str)))
                    (let ((got (%bp-primary ts)))
                      (pair (List second (first got)) (%bp-expect-c (rest got) ";")))
                    (pair () ts))))
      (let ((targets (%bp-targets (rest prompt))))
        (pair (list (list (lit input) (first prompt) (first targets))) (rest targets))))))

; LIST, LIST N, LIST N-, LIST -M, LIST N-M
(def %bp-list
  (fn (_ ts)
    (let ((from (if (%bp-digit? (%bp-byte ts)) (%bp-line-number ts) (pair () ts))))
      (if (%bp-kw? (rest from) "-")
        (let ((to (if (%bp-digit? (%bp-byte (rest (rest from))))
                    (%bp-line-number (rest (rest from)))
                    (pair () (rest (rest from))))))
          (pair (list (list (lit list) (first from) (first to))) (rest to)))
        (pair (list (list (lit list) (first from) (first from))) (rest from))))))

; TS split at its first colon: (BEFORE . FROM-THE-COLON)
(def %bp-to-colon
  (fn (_ ts)
    (let ((go (fn (self ts acc)
                (if (%bp-end? ts) (pair (List reverse acc) ts) (self (rest ts) (pair (first ts) acc))))))
      (go ts ()))))

; A DEF's formula: its expression, or bad when it does not parse whole.
; DEF skips the formula's text as DATA does and FN reads it, so its error
; is the call's.
(def %bp-formula
  (fn (_ ts)
    (guard (e (if (eq? (Err label e) (lit basic)) (lit bad) (error e)))
      (let ((got (basic-parse-expr ts)))
        (if (null? (rest got)) (first got) (lit bad))))))

; DEF FN NAME(ARG)=FORMULA: (def NAME ARG FORMULA)
(def %bp-def
  (fn (_ ts)
    (let ((name (%bp-name (%bp-expect-kw ts "FN"))))
      (let ((arg (%bp-name (%bp-expect-c (rest name) "("))))
        (let ((formula (%bp-to-colon (%bp-expect-kw (%bp-expect-c (rest arg) ")") "="))))
          (pair (list (list (lit def) (first name) (first arg) (%bp-formula (first formula))))
                (rest formula)))))))

; A statement with a line number after it, or none
(def %bp-jump
  (fn (_ ts tag)
    (let ((n (%bp-line-number ts)))
      (pair (list (list tag (first n))) (rest n)))))

; The words a statement may start with that need nothing after them
(def %bp-bare
  (list (pair "END" (lit end)) (pair "STOP" (lit stop)) (pair "RETURN" (lit return))
        (pair "RESTORE" (lit restore)) (pair "NEW" (lit new)) (pair "CLEAR" (lit clear))
        (pair "CONT" (lit cont))))

; One statement at TS: (STATEMENTS . TS-LEFT)
(def %bp-statement
  (fn (_ ts)
    (let ((t (first ts)))
      (match
        ((eq? (first t) (lit rem)) (pair (list (list (lit rem))) (rest ts)))
        ; the colon that ended the DATA token is the separator after it
        ((eq? (first t) (lit data))
          (pair (list (list (lit data) (basic-items (%bp-data-text (List second t)))))
                (if (Str8 ends? ":" (List second t)) (pair (list (lit c) ":") (rest ts)) (rest ts))))
        ((%bp-letter? (%bp-byte ts)) (%bp-assign ts))
        ((not (eq? (first t) (lit kw))) (%bp-fail))
        (#t
          (let ((word (List second t)) (ts (rest ts)))
            (let ((bare (List find (fn (_ b) (str=? (first b) word)) %bp-bare)))
              (match
                ((not (null? bare)) (pair (list (list (rest bare))) ts))
                ((str=? word "PRINT")
                  (let ((got (%bp-print-items ts)))
                    (pair (list (list (lit print) (first got))) (rest got))))
                ((str=? word "LET") (%bp-assign ts))
                ((str=? word "GOTO") (%bp-jump ts (lit goto)))
                ((str=? word "GOSUB") (%bp-jump ts (lit gosub)))
                ((and (str=? word "GO") (%bp-kw? ts "TO")) (%bp-jump (rest ts) (lit goto)))
                ((str=? word "IF") (%bp-if ts))
                ((str=? word "FOR") (%bp-for ts))
                ((str=? word "NEXT") (%bp-next ts))
                ((str=? word "DIM") (%bp-dim ts))
                ((str=? word "ON") (%bp-on ts))
                ((str=? word "READ")
                  (let ((got (%bp-targets ts)))
                    (pair (list (list (lit read) (first got))) (rest got))))
                ((str=? word "INPUT") (%bp-input ts))
                ((str=? word "RUN")
                  (if (%bp-end? ts) (pair (list (list (lit run) ())) ts) (%bp-jump ts (lit run))))
                ((str=? word "LIST") (%bp-list ts))
                ((str=? word "DEF") (%bp-def ts))
                ((str=? word "NULL")
                  (let ((got (basic-parse-expr ts)))
                    (pair (list (list (lit null) (first got))) (rest got))))
                (#t (pair (list (list (lit todo) word)) ()))))))))))

; A line's tokens as its statements.  Parsing stops at the first statement
; that does not parse, which becomes (bad "SN").
(def basic-parse-line
  (fn (_ ts)
    (let ((go (fn (self ts acc)
                (match
                  ((null? ts) (List reverse acc))
                  ((%bp-c? ts ":") (self (rest ts) acc))
                  (#t
                    (let ((got (guard (e (if (eq? (Err label e) (lit basic)) () (error e)))
                                 (let ((r (%bp-statement ts)))
                                   (if (%bp-end? (rest r)) r (%bp-fail))))))
                      (if (null? got) (List reverse (pair (list (lit bad) "SN") acc))
                        (self (rest got) (List append (List reverse (first got)) acc)))))))))
      (go ts ()))))

(provide basic/parse basic-parse-line basic-parse-expr basic-parse-value basic-items)
