; # x-basic -- BASIC on x-lang
;
; ## basic/lex.x -- a line's text to tokens
;
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)
;
; Microsoft's CRUNCH, as rules: a reserved word is found wherever its bytes
; are, inside a name or not, so FORI=1TO9 is FOR I = 1 TO 9 and SCORE is
; SC OR E.  Every other byte is a token of its own, and the parser joins
; letters into names and digits into numbers, as CHRGET reads them with the
; blanks skipped.  REM takes the rest of the line, DATA the text up to a
; colon outside quotes, and a string runs to its closing quote or the end
; of the line.
;
; A token is (TAG TEXT): kw a reserved word, as the dialect names it after
; its aliases; rem, data and str the spans; c any other byte.

(module basic/lex)
(import x/type/list)
(import x/type/str)
(import x/type/dict)
(import x/reader/lexer)
(import x/core/doors int+ int- int< int= str-byte-ref)

; A dialect's lexer, made when a line of it is first read
(def %basic-lexers (Dict make))

(def %basic-lexer
  (fn (_ dialect)
    (let ((name (dialect get (lit name))))
      (unless (%basic-lexers has? name)
        (let ((l (Lexer make
                   (list
                     (Lexer until (lit rem) "REM" "\n" (lit to-end))
                     (Lexer nested (lit data) "DATA" (lit d)
                       (list (list (lit d) 58 () (list (pair "\"" (lit q))))
                             (list (lit q) 34 () ()))
                       (lit to-end))
                     (Lexer until (lit str) "\"" "\"" (lit take) (lit to-end))
                     (Lexer table (lit kw)
                       (List append (dialect get (lit words))
                                    (List map first (dialect get (lit aliases)))))
                     (Lexer skip " \n")
                     (Lexer any (lit c))))))
          (l end "\n")
          (%basic-lexers set! name l)))
      (%basic-lexers get name))))

; TEXT's tokens, each alias spelled as the word it stands for
(def basic-lex
  (fn (_ dialect text)
    (let ((aliases (dialect get (lit aliases))))
      (List map
        (fn (_ tok)
          (if (eq? (first tok) (lit kw))
            (let ((hit (List find (fn (_ a) (str=? (first a) (List second tok))) aliases)))
              (if (null? hit) tok (list (lit kw) (rest hit))))
            tok))
        ((%basic-lexer dialect) read-str text)))))

; Where a span token's own text starts: past REM's and DATA's word, which
; is folded with the rest
(def %basic-span-skip
  (fn (_ tok)
    (match
      ((eq? (first tok) (lit rem)) 3)
      ((eq? (first tok) (lit data)) 4)
      (#t 0))))

; TEXT with every byte outside a string, a REM's remark and DATA's items
; upper-cased, so `print a` is PRINT A.  The spans are found by lexing the
; upper-cased text, whose bytes stand where TEXT's do.
(def basic-fold
  (fn (_ dialect text)
    (let ((up (Str8 upcase text)))
      (if (str=? up text) text
        (let ((n (Str8 length text)))
          (let ((blank? (fn (_ i) (let ((b (str-byte-ref up i))) (or (int= b 32) (int= b 10))))))
            (let ((go (fn (self toks pos from acc)
                        ; POS the byte the next token is looked for at; FROM
                        ; the first byte not yet in ACC, the pieces reversed
                        (if (null? toks)
                          (List fold (fn (_ s p) (Str8 append p s)) (Str8 sub from (int- n from) up) acc)
                          (let ((start (let ((skip (fn (self i) (if (and (int< i n) (blank? i)) (self (int+ i 1)) i))))
                                         (skip pos)))
                                (tok (first toks)))
                            (let ((len (Str8 length (List second tok))) (k (%basic-span-skip tok)))
                              (if (and (int= k 0) (not (eq? (first tok) (lit str))))
                                (self (rest toks) (int+ start len) from acc)
                                (let ((at (int+ start k)) (end (int+ start len)))
                                  (self (rest toks) end end
                                        (pair (Str8 sub at (int- end at) text)
                                              (pair (Str8 sub from (int- at from) up) acc)))))))))))
              (go ((%basic-lexer dialect) read-str up) 0 0 ()))))))))

(provide basic/lex basic-lex basic-fold)
