; # x-basic -- BASIC on x-lang
;
; ## lib/basic/parse.x -- tokens to statements
;
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)
;
; A line's tokens to its statements, each a list headed by its name.  Every
; reader here takes the dialect D and the tokens and answers (RESULT .
; TOKENS-LEFT).  A statement that does not parse becomes (bad "SN"), which
; raises when it is reached, as Microsoft's BASICs report syntax when they
; run a line and not when it is typed.
;
; IF is (if EXPR) followed by what came after THEN as statements of the same
; line: a false IF skips the rest of the line, and THEN 100 is GOTO 100.
;
; Expressions, loosest first: IMP, EQV, XOR, OR, AND, NOT, the relations,
; + and -, MOD, \, * and /, a sign, ^.  So NOT A=B is NOT (A=B), -2^2 is
; -4, and 2^-1 is .5.  A level whose word is not one of the dialect's
; reserved words is never met: the 6502's has no \, MOD, XOR, EQV or IMP.
;
;   (num N) (str TEXT) (var NAME) (elem NAME ARGS) (call WORD ARGS)
;   (neg E) (not E) (op WORD A B) (rel MASK A B)
;
; A number is read by the dialect's reader (its numbers' read) from the
; text of the tokens: the 6502's FIN runs on crunched text, where a
; reserved word other than + and - ends it, the 8086's on the text as
; typed.  A name is its first characters, as many as the dialect keeps,
; and its type sign, one of the dialect's; MASK holds 1 for <, 2 for = and
; 4 for >.

(module basic/parse)
(import x/type/list)
(import x/type/str)
(import x/type/dict)
(import x/type/err)
(import x/core/doors int+ int- int* int< int= int| str-byte-ref)
(import basic/lex basic-lex)

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

; Whether TS starts a name: a name token, or a letter
(def %bp-name? (fn (_ ts) (or (and (not (null? ts)) (eq? (first (first ts)) (lit name))) (%bp-letter? (%bp-byte ts)))))

; Whether TS is at the end of a statement: a colon, or a ' remark or an
; ELSE, which CRUNCH stores after one
(def %bp-end?
  (fn (_ ts)
    (or (null? ts) (%bp-c? ts ":") (%bp-kw? ts "ELSE")
        (and (eq? (first (first ts)) (lit rem)) (Str8 starts? "'" (List second (first ts)))))))

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

; A line number: digits only, no more than the dialect's last
(def %bp-line-number
  (fn (_ d ts)
    (let ((got (%bp-digits ts)))
      (if (null? (first got)) (%bp-fail)
        (let ((n (List fold (fn (_ n b) (int+ (int* n 10) (int- b 48))) 0 (first got))))
          (if (int< (d get (lit line-max)) n) (%bp-fail) (pair n (rest got))))))))

; The text a number is read from at TS: every token's, or for crunched
; text those up to a reserved word other than + and -
(def %bp-number-text
  (fn (_ d ts)
    (let ((raw (eq? (d get (lit number-text)) (lit raw))))
      (let ((go (fn (self ts acc)
                  (if (or (null? ts)
                          (and (not raw) (eq? (first (first ts)) (lit kw))
                               (not (List includes? (List second (first ts)) (list "+" "-")))))
                    (Str8 join "" (List reverse acc))
                    (self (rest ts) (pair (List second (first ts)) acc))))))
        (go ts ())))))

; TS with its first N characters gone: a token they end inside is read
; again from the byte after them
(def %bp-drop-chars
  (fn (_ d ts n)
    (if (int= n 0) ts
      (let ((k (Str8 length (List second (first ts)))))
        (if (not (int< n k)) (%bp-drop-chars d (rest ts) (int- n k))
          (let ((text (List second (first ts))))
            (List append (basic-lex d (Str8 sub n (int- k n) text)) (rest ts))))))))

; The number at TS, read by the dialect: (NUMBER . TS-LEFT), or nil
(def %bp-read-number
  (fn (_ d ts)
    (let ((got (((d get (lit numbers)) get (lit read)) (%bp-number-text d ts) 0)))
      (if (null? got) () (pair (first got) (%bp-drop-chars d ts (rest got)))))))

(def %bp-number
  (fn (_ d ts)
    (let ((got (%bp-read-number d ts)))
      (if (null? got) (%bp-fail) (pair (list (lit num) (first got)) (rest got))))))

; A name at TS: a name token, or a letter then letters and digits; then a
; type sign.  The name kept is as many characters as the dialect keeps,
; and the sign; one longer than the dialect allows is ?SN.
(def %bp-name
  (fn (_ d ts)
    (unless (%bp-name? ts) (%bp-fail))
    (let ((got (if (eq? (first (first ts)) (lit name)) (pair (List second (first ts)) (rest ts))
                 (let ((go (fn (self ts acc)
                             (let ((b (%bp-byte ts)))
                               (if (or (%bp-letter? b) (%bp-digit? b)) (self (rest ts) (pair b acc))
                                 (pair (bytes->str (List reverse acc)) ts))))))
                   (go ts ())))))
      (let ((text (first got)) (keep (d get (lit name-length))) (limit (d get-or () (lit name-limit))))
        (when (and (not (null? limit)) (int< limit (Str8 length text))) (%bp-fail))
        (let ((sign (let ((t (rest got)))
                      (if (and (not (null? t)) (eq? (first (first t)) (lit c))
                               (Str8 includes? (List second (first t)) (d get (lit suffixes))))
                        (List second (first t)) ""))))
          (pair (Str8 append (if (int< keep (Str8 length text)) (Str8 sub 0 keep text) text) sign)
                (if (= (Str8 length sign) 0) (rest got) (rest (rest got)))))))))

; Expressions separated by commas, to a closing parenthesis
(def %bp-args
  (fn (_ d ts)
    (let ((go (fn (self ts acc)
                (let ((got (basic-parse-expr d ts)))
                  (if (%bp-c? (rest got) ",") (self (rest (rest got)) (pair (first got) acc))
                    (pair (List reverse (pair (first got) acc)) (%bp-expect-c (rest got) ")")))))))
      (go ts ()))))

; A variable, or an array element when a parenthesis follows
(def %bp-target
  (fn (_ d ts)
    (let ((got (%bp-name d ts)))
      (if (%bp-c? (rest got) "(")
        (let ((args (%bp-args d (rest (rest got)))))
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
        (pair "RIGHT$" (list 2)) (pair "MID$" (list 2 3))
        (pair "CINT" (list 1)) (pair "CSNG" (list 1)) (pair "CDBL" (list 1)) (pair "FIX" (list 1))
        (pair "HEX$" (list 1)) (pair "OCT$" (list 1)) (pair "SPACE$" (list 1))
        (pair "STRING$" (list 2)) (pair "INSTR" (list 2 3))
        (pair "MKI$" (list 1)) (pair "MKS$" (list 1)) (pair "MKD$" (list 1))
        (pair "CVI" (list 1)) (pair "CVS" (list 1)) (pair "CVD" (list 1))))

(def %bp-primary
  (fn (_ d ts)
    (let ((t (if (null? ts) (%bp-fail) (first ts))))
      (match
        ((eq? (first t) (lit str))
          (let ((text (List second t)))
            (let ((n (Str8 length text)))
              (pair (list (lit str)
                          (if (and (int< 1 n) (int= (str-byte-ref text (int- n 1)) 34))
                            (Str8 sub 1 (int- n 2) text)
                            (Str8 sub 1 (int- n 1) text))
                          (List ref 2 t))
                    (rest ts)))))
        ((%bp-c? ts "(")
          (let ((got (basic-parse-expr d (rest ts))))
            (pair (first got) (%bp-expect-c (rest got) ")"))))
        ((or (%bp-digit? (%bp-byte ts)) (%bp-c? ts ".") (%bp-c? ts "&")) (%bp-number d ts))
        ((%bp-name? ts) (%bp-target d ts))
        ; FN, a name, and its argument in parentheses (FNDOER)
        ((%bp-kw? ts "FN")
          (let ((name (%bp-name d (rest ts))))
            (let ((got (basic-parse-expr d (%bp-expect-c (rest name) "("))))
              (pair (list (lit fn) (first name) (first got)) (%bp-expect-c (rest got) ")")))))
        ; a function the dialect lets go without its argument, as RND is
        ((and (eq? (first t) (lit kw)) (not (%bp-c? (rest ts) "("))
              (List find (fn (_ w) (str=? w (List second t))) (d get-or () (lit bare-calls))))
          (pair (list (lit call) (List second t) ()) (rest ts)))
        ((eq? (first t) (lit kw))
          (let ((fun (List find (fn (_ f) (str=? (first f) (List second t))) %bp-functions)))
            (if (null? fun) (%bp-fail)
              (let ((args (%bp-args d (%bp-expect-c (rest ts) "("))))
                (if (List includes? (List length (first args)) (rest fun))
                  (pair (list (lit call) (first fun) (first args)) (rest args))
                  (%bp-fail))))))
        (#t (%bp-fail))))))

; The operand of ^: a sign may lead it
(def %bp-power-operand
  (fn (_ d ts)
    (match
      ((%bp-kw? ts "-")
        (let ((got (%bp-power-operand d (rest ts)))) (pair (list (lit neg) (first got)) (rest got))))
      ((%bp-kw? ts "+") (%bp-power-operand d (rest ts)))
      (#t (%bp-primary d ts)))))

(def %bp-power
  (fn (_ d ts)
    (let ((go (fn (self got)
                (if (%bp-kw? (rest got) "^")
                  (let ((r (%bp-power-operand d (rest (rest got)))))
                    (self (pair (list (lit op) "^" (first got) (first r)) (rest r))))
                  got))))
      (go (%bp-primary d ts)))))

(def %bp-sign
  (fn (_ d ts)
    (match
      ((%bp-kw? ts "-")
        (let ((got (%bp-sign d (rest ts)))) (pair (list (lit neg) (first got)) (rest got))))
      ((%bp-kw? ts "+") (%bp-sign d (rest ts)))
      (#t (%bp-power d ts)))))

; A left-associative level: operands read by NEXT, joined by WORDS
(def %bp-level
  (fn (_ d ts next words)
    (let ((go (fn (self got)
                (let ((hit (List find (fn (_ w) (%bp-kw? (rest got) w)) words)))
                  (if (null? hit) got
                    (let ((r (next d (rest (rest got)))))
                      (self (pair (list (lit op) hit (first got) (first r)) (rest r)))))))))
      (go (next d ts)))))

(def %bp-product (fn (_ d ts) (%bp-level d ts %bp-sign (list "*" "/"))))
(def %bp-quotient (fn (_ d ts) (%bp-level d ts %bp-product (list "\\"))))
(def %bp-modulus (fn (_ d ts) (%bp-level d ts %bp-quotient (list "MOD"))))
(def %bp-sum (fn (_ d ts) (%bp-level d ts %bp-modulus (list "+" "-"))))

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
  (fn (_ d ts)
    (let ((go (fn (self got)
                (let ((rel (%bp-relation (rest got))))
                  (if (int= (first rel) 0) got
                    (let ((r (%bp-sum d (rest rel))))
                      (self (pair (list (lit rel) (first rel) (first got) (first r)) (rest r)))))))))
      (go (%bp-sum d ts)))))

(def %bp-not
  (fn (_ d ts)
    (if (%bp-kw? ts "NOT")
      (let ((got (%bp-not d (rest ts)))) (pair (list (lit not) (first got)) (rest got)))
      (%bp-compare d ts))))

(def %bp-and (fn (_ d ts) (%bp-level d ts %bp-not (list "AND"))))
(def %bp-or (fn (_ d ts) (%bp-level d ts %bp-and (list "OR"))))
(def %bp-xor (fn (_ d ts) (%bp-level d ts %bp-or (list "XOR"))))
(def %bp-eqv (fn (_ d ts) (%bp-level d ts %bp-xor (list "EQV"))))

(def basic-parse-expr (fn (_ d ts) (%bp-level d ts %bp-eqv (list "IMP"))))

; A number at TS with its sign, as FIN reads one from DATA, INPUT or VAL:
; (NUMBER . TS-LEFT), or nil when TS holds none
(def basic-parse-value
  (fn (_ d ts)
    (let ((neg (%bp-kw? ts "-")))
      (let ((ts (if (or neg (%bp-kw? ts "+")) (rest ts) ts)))
        (if (not (or (%bp-digit? (%bp-byte ts)) (%bp-c? ts ".") (%bp-c? ts "&"))) ()
          (let ((got (%bp-read-number d ts)))
            (if (null? got) ()
              (pair (if neg (list (lit neg) (list (lit num) (first got))) (list (lit num) (first got)))
                    (rest got)))))))))

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
  (fn (_ d ts)
    (let ((go (fn (self ts acc)
                (let ((got (%bp-target d ts)))
                  (if (%bp-c? (rest got) ",") (self (rest (rest got)) (pair (first got) acc))
                    (pair (List reverse (pair (first got) acc)) (rest got)))))))
      (go ts ()))))

; Line numbers separated by commas
(def %bp-line-numbers
  (fn (_ d ts)
    (let ((go (fn (self ts acc)
                (let ((got (%bp-line-number d ts)))
                  (if (%bp-c? (rest got) ",") (self (rest (rest got)) (pair (first got) acc))
                    (pair (List reverse (pair (first got) acc)) (rest got)))))))
      (go ts ()))))

; USING F; V [;|, V]... to the end of the statement (PRINUS): the item
; (using F VALUES END), END 'crlf when the list ends the statement, 'none
; after a last ; or , and 'sn when something else follows a value, which
; FNSTRF finds only once that value is printed
(def %bp-using
  (fn (_ d ts)
    (let ((f (basic-parse-expr d ts)))
      (let ((ts (%bp-expect-c (rest f) ";"))
            (skip (fn (self ts) (if (%bp-end? ts) ts (self (rest ts))))))
        (if (%bp-end? ts) (pair (list (lit using) (first f) () (lit none)) ts)
          (let ((go (fn (self ts acc)
                      (let ((got (basic-parse-expr d ts)))
                        (let ((acc (pair (first got) acc)) (ts (rest got)))
                          (match
                            ((%bp-end? ts) (pair (list (lit using) (first f) (List reverse acc) (lit crlf)) ts))
                            ((or (%bp-c? ts ";") (%bp-c? ts ","))
                              (if (%bp-end? (rest ts))
                                (pair (list (lit using) (first f) (List reverse acc) (lit none)) (rest ts))
                                (self (rest ts) acc)))
                            (#t (pair (list (lit using) (first f) (List reverse acc) (lit sn)) (skip ts)))))))))
            (go ts ())))))))

(def %bp-print-items
  (fn (_ d ts)
    (let ((go (fn (self ts acc)
                (match
                  ((%bp-end? ts) (pair (List reverse acc) ts))
                  ((%bp-c? ts ";") (self (rest ts) (pair (list (lit semi)) acc)))
                  ((%bp-c? ts ",") (self (rest ts) (pair (list (lit comma)) acc)))
                  ((%bp-kw? ts "USING")
                    (let ((got (%bp-using d (rest ts))))
                      (pair (List reverse (pair (first got) acc)) (rest got))))
                  ((or (%bp-kw? ts "TAB(") (%bp-kw? ts "SPC("))
                    (let ((got (basic-parse-expr d (rest ts))))
                      (self (%bp-expect-c (rest got) ")")
                            (pair (list (if (%bp-kw? ts "TAB(") (lit tab) (lit spc)) (first got))
                                  acc))))
                  (#t (let ((got (basic-parse-expr d ts)))
                        (self (rest got) (pair (list (lit expr) (first got)) acc))))))))
      (go ts ()))))

(def %bp-assign
  (fn (_ d ts)
    (let ((target (%bp-target d ts)))
      (let ((value (basic-parse-expr d (%bp-expect-kw (rest target) "="))))
        (pair (list (list (lit let) (first target) (first value))) (rest value))))))

; MID$(V$, N [, M]) = E, where the dialect has the statement (LHSMID)
(def %bp-mid
  (fn (_ d ts)
    (let ((target (%bp-target d (%bp-expect-c ts "("))))
      (let ((n (basic-parse-expr d (%bp-expect-c (rest target) ","))))
        (let ((m (if (%bp-c? (rest n) ",") (basic-parse-expr d (rest (rest n))) (pair () (rest n)))))
          (let ((value (basic-parse-expr d (%bp-expect-kw (%bp-expect-c (rest m) ")") "="))))
            (pair (list (list (lit mid) (first target) (first n) (first m) (first value))) (rest value))))))))

; FOR V = A TO B [STEP C]; V a number variable, an integer only where the
; dialect allows one
(def %bp-for
  (fn (_ d ts)
    (let ((name (%bp-name d ts)))
      (when (or (Str8 ends? "$" (first name))
                (and (Str8 ends? "%" (first name)) (not (d get-or #f (lit for-integer)))))
        (%bp-fail))
      (let ((from (basic-parse-expr d (%bp-expect-kw (rest name) "="))))
        (let ((to (basic-parse-expr d (%bp-expect-kw (rest from) "TO"))))
          (let ((step (if (%bp-kw? (rest to) "STEP") (basic-parse-expr d (rest (rest to)))
                        (pair () (rest to)))))
            (pair (list (list (lit for) (first name) (first from) (first to) (first step)))
                  (rest step))))))))

(def %bp-next
  (fn (_ d ts)
    (if (%bp-end? ts) (pair (list (list (lit next) ())) ts)
      (let ((go (fn (self ts acc)
                  (let ((got (%bp-name d ts)))
                    (if (%bp-c? (rest got) ",") (self (rest (rest got)) (pair (first got) acc))
                      (pair (list (list (lit next) (List reverse (pair (first got) acc))))
                            (rest got)))))))
        (go ts ())))))

(def %bp-dim
  (fn (_ d ts)
    (let ((go (fn (self ts acc)
                (let ((name (%bp-name d ts)))
                  (let ((args (%bp-args d (%bp-expect-c (rest name) "("))))
                    (let ((acc2 (pair (pair (first name) (first args)) acc)))
                      (if (%bp-c? (rest args) ",") (self (rest (rest args)) acc2)
                        (pair (list (list (lit dim) (List reverse acc2))) (rest args)))))))))
      (go ts ()))))

; IF E THEN N, IF E GOTO N, or IF E THEN statements
(def %bp-if
  (fn (_ d ts)
    (let ((test (basic-parse-expr d ts)))
      (let ((after (rest test)))
        (match
          ((%bp-kw? after "GOTO")
            (let ((n (%bp-line-number d (rest after))))
              (pair (list (list (lit if) (first test)) (list (lit goto) (first n))) (rest n))))
          ((%bp-kw? after "THEN")
            (if (%bp-digit? (%bp-byte (rest after)))
              (let ((n (%bp-line-number d (rest after))))
                (pair (list (list (lit if) (first test)) (list (lit goto) (first n))) (rest n)))
              (pair (list (list (lit if) (first test))) (pair (list (lit c) ":") (rest after)))))
          (#t (%bp-fail)))))))

(def %bp-on
  (fn (_ d ts)
    (if (%bp-kw? ts "ERROR")
      ; ON ERROR GOTO N
      (if (%bp-kw? (rest ts) "GOTO") (%bp-jump d (rest (rest ts)) (lit on-error)) (%bp-fail))
      (%bp-on-formula d ts))))

(def %bp-on-formula
  (fn (_ d ts)
    (let ((which (basic-parse-expr d ts)))
      (let ((kind (match
                    ((%bp-kw? (rest which) "GOTO") (lit goto))
                    ((%bp-kw? (rest which) "GOSUB") (lit gosub))
                    (#t (%bp-fail)))))
        (let ((ns (%bp-line-numbers d (rest (rest which)))))
          (pair (list (list (lit on) (first which) kind (first ns))) (rest ns)))))))

; An input statement's quoted prompt and the semicolon after it, or nil
(def %bp-prompt
  (fn (_ d ts)
    (if (and (not (null? ts)) (eq? (first (first ts)) (lit str)))
      (let ((got (%bp-primary d ts)))
        (pair (List second (first got)) (%bp-expect-c (rest got) ";")))
      (pair () ts))))

(def %bp-input
  (fn (_ d ts)
    (let ((prompt (%bp-prompt d ts)))
      (let ((targets (%bp-targets d (rest prompt))))
        (pair (list (list (lit input) (first prompt) (first targets))) (rest targets))))))

; LINE INPUT ["PROMPT";] V$
(def %bp-line-input
  (fn (_ d ts)
    (let ((prompt (%bp-prompt d ts)))
      (let ((target (%bp-target d (rest prompt))))
        (pair (list (list (lit line-input) (first prompt) (first target))) (rest target))))))

; WRITE [E [{,|;} E]...]: the formulas, either mark between two
(def %bp-write
  (fn (_ d ts)
    (if (%bp-end? ts) (pair (list (list (lit write) ())) ts)
      (let ((go (fn (self ts acc)
                  (let ((got (basic-parse-expr d ts)))
                    (if (or (%bp-c? (rest got) ",") (%bp-c? (rest got) ";"))
                      (self (rest (rest got)) (pair (first got) acc))
                      (pair (list (list (lit write) (List reverse (pair (first got) acc)))) (rest got)))))))
        (go ts ())))))

; LIST, LIST N, LIST N-, LIST -M, LIST N-M
(def %bp-list
  (fn (_ d ts)
    (let ((from (if (%bp-digit? (%bp-byte ts)) (%bp-line-number d ts) (pair () ts))))
      (if (%bp-kw? (rest from) "-")
        (let ((to (if (%bp-digit? (%bp-byte (rest (rest from))))
                    (%bp-line-number d (rest (rest from)))
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
  (fn (_ d ts)
    (guard (e (if (eq? (Err label e) (lit basic)) (lit bad) (error e)))
      (let ((got (basic-parse-expr d ts)))
        (if (null? (rest got)) (first got) (lit bad))))))

; DEF FN NAME(ARG)=FORMULA: (def NAME ARG FORMULA)
(def %bp-def
  (fn (_ d ts)
    (let ((name (%bp-name d (%bp-expect-kw ts "FN"))))
      (let ((arg (%bp-name d (%bp-expect-c (rest name) "("))))
        (let ((formula (%bp-to-colon (%bp-expect-kw (%bp-expect-c (rest arg) ")") "="))))
          (pair (list (list (lit def) (first name) (first arg) (%bp-formula d (first formula))))
                (rest formula)))))))

; A statement with a line number after it, or none
(def %bp-jump
  (fn (_ d ts tag)
    (let ((n (%bp-line-number d ts)))
      (pair (list (list tag (first n))) (rest n)))))

; The words a statement may start with that need nothing after them
(def %bp-bare
  (list (pair "END" (lit end)) (pair "STOP" (lit stop)) (pair "RETURN" (lit return))
        (pair "RESTORE" (lit restore)) (pair "NEW" (lit new)) (pair "CLEAR" (lit clear))
        (pair "CONT" (lit cont)) (pair "SAVE" (lit save)) (pair "LOAD" (lit load))
        (pair "WEND" (lit wend))))

; ELSE N or ELSE statements: (else), the statements after it its clause
(def %bp-else
  (fn (_ d ts)
    (if (%bp-digit? (%bp-byte ts))
      (let ((n (%bp-line-number d ts)))
        (pair (list (list (lit else)) (list (lit goto) (first n))) (rest n)))
      (pair (list (list (lit else))) (pair (list (lit c) ":") ts)))))

; The letter at TS, a one-letter name: (OFFSET . TS-LEFT), OFFSET from A
(def %bp-letter
  (fn (_ ts)
    (if (and (not (null? ts)) (eq? (first (first ts)) (lit name)) (int= (Str8 length (List second (first ts))) 1))
      (pair (int- (str-byte-ref (List second (first ts)) 0) 65) (rest ts))
      (%bp-fail))))

; DEFINT, DEFSNG, DEFDBL or DEFSTR's letters and ranges of letters, each
; (FROM . TO), TO not before FROM (DEFCON): (deftype TYPE RANGES)
(def %bp-deftype
  (fn (_ type ts)
    (let ((go (fn (self ts acc)
                (let ((from (%bp-letter ts)))
                  (let ((to (if (%bp-kw? (rest from) "-") (%bp-letter (rest (rest from))) from)))
                    (when (int< (first to) (first from)) (%bp-fail))
                    (let ((acc (pair (pair (first from) (first to)) acc)))
                      (if (%bp-c? (rest to) ",") (self (rest (rest to)) acc)
                        (pair (list (list (lit deftype) type (List reverse acc))) (rest to)))))))))
      (go ts ()))))

; SWAP A, B
(def %bp-swap
  (fn (_ d ts)
    (let ((a (%bp-target d ts)))
      (let ((b (%bp-target d (%bp-expect-c (rest a) ","))))
        (pair (list (list (lit swap) (first a) (first b))) (rest b))))))

; ERASE A, B ...: the arrays' names
(def %bp-erase
  (fn (_ d ts)
    (let ((go (fn (self ts acc)
                (let ((got (%bp-name d ts)))
                  (if (%bp-c? (rest got) ",") (self (rest (rest got)) (pair (first got) acc))
                    (pair (list (list (lit erase) (List reverse (pair (first got) acc)))) (rest got)))))))
      (go ts ()))))

; OPTION BASE 0 or 1, the digit read as the next character (the Lexer
; keeps BASE1 one name)
(def %bp-option
  (fn (_ ts)
    (unless (and (not (null? ts)) (eq? (first (first ts)) (lit name)) (Str8 starts? "BASE" (List second (first ts))))
      (%bp-fail))
    (let ((text (List second (first ts))))
      (let ((digit (if (int< 4 (Str8 length text))
                     (pair (Str8 sub 4 (int- (Str8 length text) 4) text) (rest ts))
                     (if (and (not (null? (rest ts))) (eq? (first (first (rest ts))) (lit c)))
                       (pair (List second (first (rest ts))) (rest (rest ts)))
                       (%bp-fail)))))
        (match
          ((str=? (first digit) "0") (pair (list (list (lit option) 0)) (rest digit)))
          ((str=? (first digit) "1") (pair (list (list (lit option) 1)) (rest digit)))
          (#t (%bp-fail)))))))

; One statement at TS: (STATEMENTS . TS-LEFT)
(def %bp-statement
  (fn (_ d ts)
    (let ((t (first ts)))
      (match
        ((eq? (first t) (lit rem)) (pair (list (list (lit rem))) (rest ts)))
        ; the colon that ended the DATA token is the separator after it
        ((eq? (first t) (lit data))
          (pair (list (list (lit data) (basic-items (%bp-data-text (List second t)))))
                (if (Str8 ends? ":" (List second t)) (pair (list (lit c) ":") (rest ts)) (rest ts))))
        ((%bp-name? ts) (%bp-assign d ts))
        ((not (eq? (first t) (lit kw))) (%bp-fail))
        (#t
          (let ((word (List second t)) (ts (rest ts)))
            (let ((bare (List find (fn (_ b) (str=? (first b) word)) %bp-bare)))
              (match
                ; a word the dialect reserves but whose statement is not
                ; this one's yet
                ((List includes? word (d get-or () (lit todo-words))) (pair (list (list (lit todo) word)) ()))
                ((not (null? bare)) (pair (list (list (rest bare))) ts))
                ((str=? word "PRINT")
                  (let ((got (%bp-print-items d ts)))
                    (pair (list (list (lit print) (first got))) (rest got))))
                ((str=? word "LET") (%bp-assign d ts))
                ((str=? word "GOTO") (%bp-jump d ts (lit goto)))
                ((str=? word "GOSUB") (%bp-jump d ts (lit gosub)))
                ((and (str=? word "GO") (%bp-kw? ts "TO")) (%bp-jump d (rest ts) (lit goto)))
                ((str=? word "IF") (%bp-if d ts))
                ((str=? word "FOR") (%bp-for d ts))
                ((str=? word "NEXT") (%bp-next d ts))
                ((str=? word "DIM") (%bp-dim d ts))
                ((str=? word "ON") (%bp-on d ts))
                ((str=? word "READ")
                  (let ((got (%bp-targets d ts)))
                    (pair (list (list (lit read) (first got))) (rest got))))
                ((str=? word "INPUT") (%bp-input d ts))
                ((and (str=? word "LINE") (%bp-kw? ts "INPUT")) (%bp-line-input d (rest ts)))
                ((str=? word "WRITE") (%bp-write d ts))
                ((and (str=? word "MID$") (d get-or #f (lit mid-statement))) (%bp-mid d ts))
                ((str=? word "RUN")
                  (if (%bp-end? ts) (pair (list (list (lit run) ())) ts) (%bp-jump d ts (lit run))))
                ((str=? word "LIST") (%bp-list d ts))
                ((str=? word "DEF") (%bp-def d ts))
                ((str=? word "NULL")
                  (let ((got (basic-parse-expr d ts)))
                    (pair (list (list (lit null) (first got))) (rest got))))
                ((str=? word "GET")
                  (let ((got (%bp-targets d ts)))
                    (pair (list (list (lit get) (first got))) (rest got))))
                ((str=? word "WAIT")
                  (let ((a (basic-parse-expr d ts)))
                    (let ((m1 (basic-parse-expr d (%bp-expect-c (rest a) ","))))
                      (if (%bp-c? (rest m1) ",")
                        (let ((m2 (basic-parse-expr d (rest (rest m1)))))
                          (pair (list (list (lit wait) (first a) (first m1) (first m2))) (rest m2)))
                        (pair (list (list (lit wait) (first a) (first m1) ())) (rest m1))))))
                ((str=? word "ELSE") (%bp-else d ts))
                ((str=? word "WHILE")
                  (let ((got (basic-parse-expr d ts)))
                    (pair (list (list (lit while) (first got))) (rest got))))
                ((str=? word "DEFINT") (%bp-deftype 2 ts))
                ((str=? word "DEFSNG") (%bp-deftype 4 ts))
                ((str=? word "DEFDBL") (%bp-deftype 8 ts))
                ((str=? word "DEFSTR") (%bp-deftype 3 ts))
                ((str=? word "SWAP") (%bp-swap d ts))
                ((str=? word "ERASE") (%bp-erase d ts))
                ((str=? word "OPTION") (%bp-option ts))
                ; RESUME, RESUME NEXT or RESUME N, 0 the same as none
                ((str=? word "RESUME")
                  (match
                    ((%bp-end? ts) (pair (list (list (lit resume) 0)) ts))
                    ((%bp-kw? ts "NEXT") (pair (list (list (lit resume) (lit next))) (rest ts)))
                    (#t (%bp-jump d ts (lit resume)))))
                ((str=? word "ERROR")
                  (let ((got (basic-parse-expr d ts)))
                    (pair (list (list (lit error) (first got))) (rest got))))
                ; RANDOMIZE, the seed asked for when no formula follows
                ((str=? word "RANDOMIZE")
                  (if (%bp-end? ts) (pair (list (list (lit randomize) ())) ts)
                    (let ((got (basic-parse-expr d ts)))
                      (pair (list (list (lit randomize) (first got))) (rest got)))))
                ((str=? word "POKE")
                  (let ((a (basic-parse-expr d ts)))
                    (let ((b (basic-parse-expr d (%bp-expect-c (rest a) ","))))
                      (pair (list (list (lit poke) (first a) (first b))) (rest b)))))
                (#t (pair (list (list (lit todo) word)) ()))))))))))

; A line's tokens as its statements.  Parsing stops at the first statement
; that does not parse, which becomes (bad "SN").
(def basic-parse-line
  (fn (_ d ts)
    (let ((go (fn (self ts acc)
                (match
                  ((null? ts) (List reverse acc))
                  ((%bp-c? ts ":") (self (rest ts) acc))
                  (#t
                    (let ((got (guard (e (if (eq? (Err label e) (lit basic)) () (error e)))
                                 (let ((r (%bp-statement d ts)))
                                   (if (%bp-end? (rest r)) r (%bp-fail))))))
                      (if (null? got) (List reverse (pair (list (lit bad) "SN") acc))
                        (self (rest got) (List append (List reverse (first got)) acc)))))))))
      (go ts ()))))

(provide basic/parse basic-parse-line basic-parse-expr basic-parse-value basic-items)
