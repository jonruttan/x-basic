; # x-basic -- BASIC on x-lang
;
; ## lib/basic/lex.x -- a line's text to tokens
;
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)
;
; Microsoft's CRUNCH, as rules, in one of two ways the dialect names.
;
; anywhere (the 6502): a reserved word is found wherever its bytes are,
; inside a name or not, so FORI=1TO9 is FOR I = 1 TO 9 and SCORE is SC OR
; E.  Every other byte is a token of its own, and the parser joins letters
; into names and digits into numbers, as CHRGET reads them.
;
; name-start (the 8086): a name is a letter and then letters, digits and
; dots, and a reserved word is one only where a name starts and when no
; letter, digit or dot follows it, so FORI is a name.  The Lexer's longest
; match is that rule: the name FORI is longer than the word FOR.  A word
; ending in ( needs nothing after it, and so do the dialect's prefix words
; (FN, USR), which a name that starts with them is split at.  ' is a
; remark anywhere.
;
; The tokens of a text partition it: blanks are tokens too, so a token's
; place is the length of those before it.  REM takes the rest of the line,
; DATA the text up to a colon outside quotes, and a string runs to its
; closing quote or the end of the line; where the Lexer reads REM and DATA
; as words (name-start) the tokens after them are joined into the span.
;
; A token is (TAG TEXT): kw a reserved word, as the dialect names it after
; its aliases; rem, data and str the spans; name a name (name-start); c any
; other byte.  basic-lex drops the blanks.

(module basic/lex)
(import x/type/list)
(import x/type/str)
(import x/type/dict)
(import x/reader/lexer)
(import x/core/doors int+ int- int< int= str-byte-ref)

; A dialect's lexer, made when a line of it is first read
(def %basic-lexers (Dict make))

(def %basic-name-start? (fn (_ dialect) (eq? (dialect get-or (lit anywhere) (lit crunch)) (lit name-start))))

(def %basic-rules
  (fn (_ dialect)
    (let ((words (Lexer table (lit kw)
                   (List append (dialect get (lit words)) (List map first (dialect get (lit aliases))))))
          (str (Lexer until (lit str) "\"" "\"" (lit take) (lit to-end)))
          (blank (Lexer run (lit blank) " \n" " \n")))
      (if (%basic-name-start? dialect)
        (list str
              (Lexer until (lit rem) "'" "\n" (lit to-end))
              words
              (Lexer run (lit name) (list (pair 65 90)) (list (pair 65 90) (pair 48 57) 46))
              blank
              (Lexer any (lit c)))
        (list (Lexer until (lit rem) "REM" "\n" (lit to-end))
              (Lexer nested (lit data) "DATA" (lit d)
                (list (list (lit d) 58 () (list (pair "\"" (lit q))))
                      (list (lit q) 34 () ()))
                (lit to-end))
              str
              words
              blank
              (Lexer any (lit c)))))))

(def %basic-lexer
  (fn (_ dialect)
    (let ((name (dialect get (lit name))))
      (unless (%basic-lexers has? name)
        (%basic-lexers set! name (Lexer make (%basic-rules dialect))))
      (%basic-lexers get name))))

(def %basic-kw? (fn (_ tok word) (and (eq? (first tok) (lit kw)) (str=? (List second tok) word))))

(def %basic-joined (fn (_ toks) (Str8 join "" (List map (fn (_ t) (List second t)) toks))))

; TOKS, the Lexer's, with REM and DATA read as words made the spans they
; open, and a name that starts with one of the dialect's prefix words split
; after it, the rest read again
(def %basic-spans
  (fn (_ dialect toks)
    (let ((prefixes (dialect get-or () (lit prefix-words))))
      (let ((go (fn (self ts acc)
                  (if (null? ts) (List reverse acc)
                    (let ((t (first ts)))
                      (match
                        ((%basic-kw? t "REM")
                          (List reverse (pair (list (lit rem) (Str8 append "REM" (%basic-joined (rest ts)))) acc)))
                        ((%basic-kw? t "DATA")
                          (let ((upto (fn (self xs got)
                                        (match
                                          ((null? xs) (pair (List reverse got) ()))
                                          ((and (eq? (first (first xs)) (lit c)) (str=? (List second (first xs)) ":"))
                                            (pair (List reverse (pair (first xs) got)) (rest xs)))
                                          (#t (self (rest xs) (pair (first xs) got)))))))
                            (let ((cut (upto (rest ts) ())))
                              (self (rest cut)
                                    (pair (list (lit data) (Str8 append "DATA" (%basic-joined (first cut)))) acc)))))
                        ((eq? (first t) (lit name))
                          (let ((text (List second t)))
                            (let ((p (List find (fn (_ p) (and (int< (Str8 length p) (Str8 length text))
                                                               (Str8 starts? p text)))
                                       prefixes)))
                              (if (null? p) (self (rest ts) (pair t acc))
                                (let ((k (Str8 length p)))
                                  (self (List append (%basic-read dialect (Str8 sub k (int- (Str8 length text) k) text))
                                                     (rest ts))
                                        (pair (list (lit kw) p) acc)))))))
                        (#t (self (rest ts) (pair t acc)))))))))
        (go toks ())))))

; TEXT's tokens, blanks included, the spans made
(def %basic-read
  (fn (_ dialect text) (%basic-spans dialect ((%basic-lexer dialect) read-str text))))

; TEXT's tokens without the blanks, each alias spelled as the word it
; stands for, and each string constant (str TEXT ORD), ORD its place among
; the line's strings
(def basic-lex
  (fn (_ dialect text)
    (let ((aliases (dialect get (lit aliases))))
      (let ((go (fn (self toks k acc)
                  (if (null? toks) (List reverse acc)
                    (let ((tok (first toks)))
                      (match
                        ((eq? (first tok) (lit blank)) (self (rest toks) k acc))
                        ((eq? (first tok) (lit kw))
                          (let ((hit (List find (fn (_ a) (str=? (first a) (List second tok))) aliases)))
                            (self (rest toks) k (pair (if (null? hit) tok (list (lit kw) (rest hit))) acc))))
                        ((eq? (first tok) (lit str))
                          (self (rest toks) (int+ k 1) (pair (list (lit str) (List second tok) k) acc)))
                        (#t (self (rest toks) k (pair tok acc)))))))))
        (go (%basic-read dialect text) 0 ())))))

; Where a span token's own text starts: past REM's, ''s and DATA's word,
; which is folded with the rest
(def %basic-span-skip
  (fn (_ tok)
    (match
      ((eq? (first tok) (lit rem)) (if (Str8 starts? "'" (List second tok)) 1 3))
      ((eq? (first tok) (lit data)) 4)
      (#t 0))))

; TEXT with every byte outside a string, a remark and DATA's items
; upper-cased, so `print a` is PRINT A.  The spans are found by lexing the
; upper-cased text, whose bytes stand where TEXT's do.
(def basic-fold
  (fn (_ dialect text)
    (let ((up (Str8 upcase text)))
      (if (str=? up text) text
        (let ((go (fn (self toks at acc)
                    (if (null? toks) (Str8 join "" (List reverse acc))
                      (let ((tok (first toks)))
                        (let ((n (Str8 length (List second tok)))
                              (k (if (eq? (first tok) (lit str)) 0 (%basic-span-skip tok))))
                          (self (rest toks) (int+ at n)
                                (if (or (eq? (first tok) (lit str)) (int< 0 k))
                                  (pair (Str8 sub (int+ at k) (int- n k) text) (pair (Str8 sub at k up) acc))
                                  (pair (Str8 sub at n up) acc)))))))))
          (go (%basic-read dialect up) 0 ()))))))

; --- CRUNCH ---------------------------------------------------------------

; The bytes WORD is stored as: the dialect's token for it, or 128 and its
; place among the words
(def %basic-token
  (fn (_ dialect word)
    (let ((words (dialect get (lit words))) (tokens (dialect get-or () (lit tokens))))
      (if (null? tokens) (list (int+ 128 (List index-of word words)))
        (List ref (List index-of word words) tokens)))))

; TEXT's bytes, as a list
(def %basic-bytes
  (fn (_ text)
    (let ((go (fn (self i acc) (if (int< i 0) acc (self (int- i 1) (pair (str-byte-ref text i) acc))))))
      (go (int- (Str8 length text) 1) ()))))

; TEXT, a stored line after its number, as CRUNCH stores it: (BYTES STRS
; DATAS), BYTES the line's bytes, STRS the offset of each string constant's
; first byte (past its quote) in order, and DATAS each DATA item's.  A
; reserved word is its token; ? is PRINT's; a remark, a string and DATA's
; items to the colon are copied; the dialect's words that CRUNCH puts a
; colon before have one, and ' is stored as :REM'.
(def basic-crunch
  (fn (_ dialect text)
    (let ((out (Dict make)) (aliases (dialect get (lit aliases)))
          (colons (dialect get-or () (lit colon-before))))
      (out set! (lit bytes) ())
      (out set! (lit strs) ())
      (out set! (lit datas) ())
      (out set! (lit at) 0)
      (let ((put (fn (_ byte)
                   (out set! (lit bytes) (pair byte (out get (lit bytes))))
                   (out set! (lit at) (int+ (out get (lit at)) 1))))
            (mark (fn (_ key) (out set! key (pair (out get (lit at)) (out get key))))))
        (let ((put-all (fn (_ bs) (List for-each put bs)))
              (word (fn (_ w) (%basic-token dialect w))))
          ; DATA's items in TEXT from I: each item's first byte past its
          ; blanks marked, an empty item where it ends
          (let ((items (fn (_ text i)
                         (let ((n (Str8 length text)))
                           (let ((go (fn (self i fresh quoted)
                                       (if (not (int< i n)) (when fresh (mark (lit datas)))
                                         (let ((b (str-byte-ref text i)))
                                           (match
                                             (quoted (do (put b) (self (int+ i 1) #f (not (int= b 34)))))
                                             ((int= b 32) (do (put 32) (self (int+ i 1) fresh #f)))
                                             ((int= b 58) (do (when fresh (mark (lit datas))) (put 58)))
                                             ((int= b 44)
                                               (do (when fresh (mark (lit datas))) (put 44) (self (int+ i 1) #t #f)))
                                             ((int= b 34)
                                               (do (put 34) (when fresh (mark (lit datas))) (self (int+ i 1) #f #t)))
                                             (#t (do (when fresh (mark (lit datas))) (put b) (self (int+ i 1) #f #f)))))))))
                             (go i #t #f))))))
            (List for-each
              (fn (_ tok)
                (let ((tag (first tok)) (text (List second tok)))
                  (match
                    ((eq? tag (lit kw))
                      (let ((hit (List find (fn (_ a) (str=? (first a) text)) aliases)))
                        (let ((w (if (null? hit) text (rest hit))))
                          (when (List includes? w colons) (put 58))
                          (put-all (word w)))))
                    ((eq? tag (lit rem))
                      (if (Str8 starts? "'" text)
                        (do (put 58) (put-all (word "REM")) (put-all (word "'"))
                            (put-all (List drop 1 (%basic-bytes text))))
                        (do (put-all (word "REM")) (put-all (List drop 3 (%basic-bytes text))))))
                    ((eq? tag (lit data)) (do (put-all (word "DATA")) (items text 4)))
                    ((eq? tag (lit str))
                      (do (put 34) (mark (lit strs)) (put-all (List drop 1 (%basic-bytes text)))))
                    (#t (put-all (%basic-bytes text))))))
              (%basic-read dialect text))
            (list (List reverse (out get (lit bytes)))
                  (List reverse (out get (lit strs)))
                  (List reverse (out get (lit datas))))))))))

; The text of crunched BYTES, each token its reserved word, as LIST prints
; it; a byte that starts no token is kept
(def basic-detokenize
  (fn (_ dialect bytes)
    (let ((words (dialect get (lit words))))
      (let ((pairs (List map (fn (_ w) (pair (%basic-token dialect w) w)) words)))
        (let ((match-at (fn (_ bs)
                          (List find
                            (fn (_ p) (let ((k (List length (first p))))
                                        (and (not (int< (List length bs) k)) (equal? (List take k bs) (first p)))))
                            pairs))))
          (let ((go (fn (self bs acc)
                      (if (null? bs) (Str8 join "" (List reverse acc))
                        (if (int< (first bs) 128) (self (rest bs) (pair (bytes->str (list (first bs))) acc))
                          (let ((hit (match-at bs)))
                            (if (null? hit) (self (rest bs) (pair (bytes->str (list (first bs))) acc))
                              (self (List drop (List length (first hit)) bs) (pair (rest hit) acc)))))))))
            (go bytes ())))))))

(provide basic/lex basic-lex basic-fold basic-crunch basic-detokenize)
