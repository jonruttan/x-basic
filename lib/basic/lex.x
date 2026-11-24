; # x-basic -- BASIC on x-lang
;
; ## lib/basic/lex.x -- a line's text to tokens
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
          ; A newline end text on a Lexer that appends one to each read; x-lang
          ; past v0.61.0 appends nothing and has no end field, and the end of
          ; the text ends the last token
          (guard (_ ()) (l end "\n"))
          (%basic-lexers set! name l)))
      (%basic-lexers get name))))

; TEXT's tokens, each alias spelled as the word it stands for, and each
; string constant (str TEXT ORD), ORD its place among the line's strings
(def basic-lex
  (fn (_ dialect text)
    (let ((aliases (dialect get (lit aliases))))
      (let ((go (fn (self toks k acc)
                  (if (null? toks) (List reverse acc)
                    (let ((tok (first toks)))
                      (match
                        ((eq? (first tok) (lit kw))
                          (let ((hit (List find (fn (_ a) (str=? (first a) (List second tok))) aliases)))
                            (self (rest toks) k (pair (if (null? hit) tok (list (lit kw) (rest hit))) acc))))
                        ((eq? (first tok) (lit str))
                          (self (rest toks) (int+ k 1) (pair (list (lit str) (List second tok) k) acc)))
                        (#t (self (rest toks) k (pair tok acc)))))))))
        (go ((%basic-lexer dialect) read-str text) 0 ())))))

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

; --- CRUNCH ---------------------------------------------------------------

; The token of the reserved word at I in TEXT, and its length, or nil: the
; first of the dialect's words, in their order, spelled there
(def %crunch-word
  (fn (_ words text i n)
    (let ((at? (fn (_ w)
                 (let ((k (Str8 length w)))
                   (and (not (int< n (int+ i k))) (str=? (Str8 sub i k text) w))))))
      (let ((go (fn (self ws t)
                  (match
                    ((null? ws) ())
                    ((at? (first ws)) (pair t (Str8 length (first ws))))
                    (#t (self (rest ws) (int+ t 1)))))))
        (go words 128)))))

; TEXT, a stored line after its number, as CRUNCH stores it: (BYTES STRS
; DATAS), BYTES the line's bytes, STRS the offset of each string constant's
; first byte (past its quote) in order, and DATAS each DATA item's.  A
; reserved word is its token; ? is PRINT's; blanks, digits, : and ; are
; kept; a string, a REM's remark and DATA's items to the colon are copied.
(def basic-crunch
  (fn (_ dialect text)
    (let ((words (dialect get (lit words))) (n (Str8 length text)))
      (let ((token (fn (_ w) (int+ 128 (List index-of w words)))))
        (let ((print (token "PRINT")) (data (token "DATA")) (rem (token "REM")))
          (let ((b (fn (_ i) (str-byte-ref text i)))
                ; the bytes, STRS and DATAS reversed, and the next offset
                (out (Dict make)))
            (out set! (lit bytes) ())
            (out set! (lit strs) ())
            (out set! (lit datas) ())
            (out set! (lit at) 0)
            (let ((put (fn (_ byte)
                         (out set! (lit bytes) (pair byte (out get (lit bytes))))
                         (out set! (lit at) (int+ (out get (lit at)) 1))))
                  (mark (fn (_ key) (out set! key (pair (out get (lit at)) (out get key))))))
              (let ((copy-to (fn (self i stop)
                               ; bytes copied to STOP (taken) or the end
                               (match
                                 ((not (int< i n)) i)
                                 ((int= (b i) stop) (do (put stop) (int+ i 1)))
                                 (#t (do (put (b i)) (self (int+ i 1) stop)))))))
                (let ((items (fn (self i fresh)
                               ; DATA's items from I; FRESH when an item starts
                               ; an empty item starts where it ends
                               (match
                                 ((not (int< i n)) (do (when fresh (mark (lit datas))) i))
                                 ((int= (b i) 32) (do (put 32) (self (int+ i 1) fresh)))
                                 ((int= (b i) 58) (do (when fresh (mark (lit datas))) i))
                                 ((int= (b i) 44)
                                   (do (when fresh (mark (lit datas))) (put 44) (self (int+ i 1) #t)))
                                 ((int= (b i) 34)
                                   (do (put 34)
                                       (when fresh (mark (lit datas)))
                                       (self (copy-to (int+ i 1) 34) #f)))
                                 (#t (do (when fresh (mark (lit datas)))
                                         (put (b i)) (self (int+ i 1) #f)))))))
                  (let ((go (fn (self i)
                              (when (int< i n)
                                (let ((c (b i)))
                                  (match
                                    ((int= c 32) (do (put 32) (self (int+ i 1))))
                                    ((int= c 34)
                                      (do (put 34) (mark (lit strs)) (self (copy-to (int+ i 1) 34))))
                                    ((int= c 63) (do (put print) (self (int+ i 1))))
                                    ((and (not (int< c 48)) (int< c 60)) (do (put c) (self (int+ i 1))))
                                    (#t
                                      (let ((w (%crunch-word words text i n)))
                                        (if (null? w) (do (put c) (self (int+ i 1)))
                                          (do (put (first w))
                                              (match
                                                ((int= (first w) rem)
                                                  (self (copy-to (int+ i (rest w)) -1)))
                                                ((int= (first w) data)
                                                  (self (items (int+ i (rest w)) #t)))
                                                (#t (self (int+ i (rest w)))))))))))))))
                    (go 0)
                    (list (List reverse (out get (lit bytes)))
                          (List reverse (out get (lit strs)))
                          (List reverse (out get (lit datas))))))))))))))

; The text of crunched BYTES, each token its reserved word, as LIST prints
; it; a byte past the dialect's tokens is kept
(def basic-detokenize
  (fn (_ dialect bytes)
    (let ((words (dialect get (lit words))))
      (let ((count (List length words)))
        (Str8 join ""
          (List map
            (fn (_ b)
              (if (or (int< b 128) (not (int< (int- b 128) count))) (bytes->str (list b))
                (List ref (int- b 128) words)))
            bytes))))))

(provide basic/lex basic-lex basic-fold basic-crunch basic-detokenize)
