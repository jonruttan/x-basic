; # x-basic -- BASIC on x-lang
;
; ## basic/mbf-math.x -- the 6502's maths functions
;
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)
;
; LOG, EXP, X^Y, SQR, SIN, COS, TAN, ATN and RND as m6502.asm computes them:
; the same steps in the same order, its polynomial tables, and its
; constants, written here in octal as the source writes them.  A value is
; rounded where the source moves it to memory (MOVMF, MOVAF), and nowhere
; else, so each result carries the guard byte the 6502's would.
;
; The source's KIM-1 ROM build answers ?FC for SIN, COS, TAN and ATN; its
; tape build, the one asking WANT SIN-COS-TAN-ATN at start, has them.  These
; are that build's.

(module basic/mbf-math)
(import x/type/list)
(import x/type/err)
(import x/core/doors int+ int- int< int= int& int| int<< int>>)
(import basic/mbf
  mbf-zero mbf-zero? mbf-octal mbf-bytes mbf-int mbf-neg mbf-abs mbf-sgn mbf-cmp
  mbf-round mbf-add mbf-sub mbf-mul mbf-div mbf-floor mbf->int mbf-exponent
  mbf-mantissa mbf-fac mbf-with-exponent)

(def %mm-one (mbf-octal 201 0 0 0 0))
(def %mm-half (mbf-octal 200 0 0 0 0))
(def %mm-quarter (mbf-octal 177 0 0 0 0))

; --- polynomials ----------------------------------------------------------

; C0*X^N + C1*X^(N-1) + ... + CN as POLY runs it: X saved rounded, the
; first product X * C0, and each after it the sum times the saved X
(def %mm-poly
  (fn (_ x coefs)
    (let ((xr (mbf-round x)))
      (List fold (fn (_ acc c) (mbf-add (mbf-mul acc xr) c))
                 (mbf-add (mbf-mul xr (first coefs)) (first (rest coefs)))
                 (rest (rest coefs))))))

; X times the polynomial in X^2 (POLYX), X saved rounded
(def %mm-polyx
  (fn (_ x coefs)
    (let ((xr (mbf-round x)))
      (mbf-mul (%mm-poly (mbf-mul xr xr) coefs) xr))))

; --- LOG and EXP ----------------------------------------------------------

(def %mm-sqr-half (mbf-octal 200 65 4 363 64))
(def %mm-sqr-two (mbf-octal 201 65 4 363 64))
(def %mm-neg-half (mbf-octal 200 200 0 0 0))
(def %mm-ln2 (mbf-octal 200 61 162 27 370))

(def %mm-logcn2
  (list (mbf-octal 177 136 126 313 171)
        (mbf-octal 200 23 233 13 144)
        (mbf-octal 200 166 70 223 26)
        (mbf-octal 202 70 252 73 40)))

; The natural log; ?FC for zero or less.  The exponent is split off, the
; fraction F in [.5, 1) taken through 1 - SQR(2) / (F + SQR(.5)), and the
; sum scaled by LN(2).
(def mbf-log
  (fn (_ x)
    (if (not (int< 0 (mbf-sgn x))) (Err raise (lit basic) "FC")
      (let ((e (int- (mbf-exponent x) 128))
            (f (mbf-with-exponent x 128)))
        (let ((z (mbf-sub %mm-one (mbf-div %mm-sqr-two (mbf-add f %mm-sqr-half)))))
          (mbf-mul (mbf-add (mbf-round (mbf-add (%mm-polyx z %mm-logcn2) %mm-neg-half))
                            (mbf-int e))
                   %mm-ln2))))))

(def %mm-log2e (mbf-octal 201 70 252 73 51))

(def %mm-expcon
  (list (mbf-octal 161 64 130 76 126)
        (mbf-octal 164 26 176 263 33)
        (mbf-octal 167 57 356 343 205)
        (mbf-octal 172 35 204 34 52)
        (mbf-octal 174 143 131 130 12)
        (mbf-octal 176 165 375 347 306)
        (mbf-octal 200 61 162 30 20)
        (mbf-octal 201 0 0 0 0)))

; e to the X: Y = X * LOG2(e), 2 to Y's fraction by the polynomial, and
; Y's integer part added to the exponent.  Before it is split, Y gains 80
; in its guard byte; its integer part is taken from its four mantissa
; bytes.  ?OV when too large; zero when too small.
(def mbf-exp
  (fn (_ x)
    (let ((y0 (mbf-mul x %mm-log2e)))
      (let ((y (if (mbf-zero? y0) y0
                 (mbf-fac (int< (mbf-sgn y0) 0) (int+ (mbf-mantissa y0) 80) (rest y0)))))
        (if (not (int< (mbf-exponent y) 136))
          (if (int< (mbf-sgn y) 0) mbf-zero (Err raise (lit basic) "OV"))
          (let ((i (mbf-floor (mbf-fac (int< (mbf-sgn y) 0)
                                       (int- (mbf-mantissa y) (int& (mbf-mantissa y) 255))
                                       (rest y)))))
            (let ((n (mbf->int i 255)))
              (match
                ((int= n 127) (Err raise (lit basic) "OV"))
                ((int= n -128) mbf-zero)
                (#t
                  (let ((p (%mm-poly (mbf-neg (mbf-sub i y)) %mm-expcon)))
                    (mbf-fac #f (mbf-mantissa p) (int+ (rest p) n))))))))))))

; --- powers ---------------------------------------------------------------

; Whether the integer I is odd; one too large to hold its bits whole is
; even
(def %mm-odd?
  (fn (_ i)
    (if (not (int< (rest i) 0)) #f
      (if (int< 62 (int- 0 (rest i))) #f
        (int= 1 (int& (int>> (mbf-mantissa i) (int- 0 (rest i))) 1))))))

; X^Y (FPWRT), X rounded as the operand stack holds it: EXP(0) when Y is
; 0, 0 when X is; a negative X only to an integer power, its sign by the
; power's parity; else EXP(LOG(X) * Y), Y rounded
(def mbf-power
  (fn (_ x y)
    (match
      ((mbf-zero? y) (mbf-exp y))
      ((mbf-zero? x) mbf-zero)
      (#t
        (let ((yr (mbf-round y)))
          (if (int< 0 (mbf-sgn x)) (mbf-exp (mbf-mul (mbf-log x) yr))
            (let ((i (mbf-floor yr)))
              (if (not (int= (mbf-cmp i yr) 0)) (Err raise (lit basic) "FC")
                (let ((r (mbf-exp (mbf-mul (mbf-log (mbf-abs x)) yr))))
                  (if (%mm-odd? i) (mbf-neg r) r))))))))))

; X^.5, X rounded (SQR)
(def mbf-sqr (fn (_ x) (mbf-power (mbf-round x) %mm-half)))

; --- SIN, COS, TAN, ATN ---------------------------------------------------

(def %mm-two-pi (mbf-octal 203 111 17 332 242))
(def %mm-pi-half (mbf-octal 201 111 17 332 242))

(def %mm-sincon
  (list (mbf-octal 204 346 32 55 33)
        (mbf-octal 206 50 7 373 370)
        (mbf-octal 207 231 150 211 1)
        (mbf-octal 207 43 65 337 341)
        (mbf-octal 206 245 135 347 50)
        (mbf-octal 203 111 17 332 242)))

; X in turns, folded to the quarter turn about 0 the series is good for:
; (Z . FLIPPED), FLIPPED when the fold went through the half turn, which
; TAN's cosine reads (TANSGN)
(def %mm-fold
  (fn (_ x)
    (let ((t (mbf-round (mbf-div x %mm-two-pi))))
      (let ((f (mbf-sub t (mbf-floor t))))
        (let ((a (mbf-sub %mm-quarter f)))
          (if (not (int< (mbf-sgn a) 0))
            (pair (mbf-add (mbf-neg a) %mm-quarter) #f)
            (let ((b (mbf-add a %mm-half)))
              (if (int< (mbf-sgn b) 0)
                (pair (mbf-neg (mbf-add b %mm-quarter)) #f)
                (pair (mbf-neg (mbf-add (mbf-neg b) %mm-quarter)) #t)))))))))

(def mbf-sin
  (fn (_ x) (%mm-polyx (first (%mm-fold x)) %mm-sincon)))

(def mbf-cos (fn (_ x) (mbf-sin (mbf-add x %mm-pi-half))))

; SIN over COS, the cosine taken from the angle SIN folded, as POLYX saved
; it: a quarter turn less its size, the sign the fold's
(def mbf-tan
  (fn (_ x)
    (let ((folded (%mm-fold x)))
      (let ((s (%mm-polyx (first folded) %mm-sincon))
            (w (mbf-add (mbf-neg (mbf-abs (mbf-round (first folded)))) %mm-quarter)))
        (mbf-div s (%mm-polyx (if (rest folded) (mbf-neg w) w) %mm-sincon))))))

(def %mm-atncon
  (list (mbf-octal 166 263 203 275 323)
        (mbf-octal 171 36 364 246 365)
        (mbf-octal 173 203 374 260 20)
        (mbf-octal 174 14 37 147 312)
        (mbf-octal 174 336 123 313 301)
        (mbf-octal 175 24 144 160 114)
        (mbf-octal 175 267 352 121 172)
        (mbf-octal 175 143 60 210 176)
        (mbf-octal 176 222 104 231 72)
        (mbf-octal 176 114 314 221 307)
        (mbf-octal 177 252 252 252 23)
        (mbf-octal 201 0 0 0 0)))

; The arctangent: of |X|, or of 1/|X| taken from a quarter turn when |X| is
; 1 or more, the sign put back
(def mbf-atn
  (fn (_ x)
    (let ((a (mbf-abs x)))
      (let ((big (not (int< (mbf-exponent a) 129))))
        (let ((p (%mm-polyx (if big (mbf-div %mm-one a) a) %mm-atncon)))
          (let ((r (if big (mbf-sub %mm-pi-half p) p)))
            (if (int< (mbf-sgn x) 0) (mbf-neg r) r)))))))

; --- RND ------------------------------------------------------------------

; The seed at start (RNDX)
(def mbf-rnd-seed (mbf-bytes 128 79 199 82 89))

; The multiplier and the addend.  The source assembles each in four bytes in
; this five-byte build, so each one's fifth byte is the byte that follows it:
; the addend's first, and the first of the RND routine (JSR, octal 040).
(def %mm-rmulzc (mbf-octal 230 65 104 172 150))
(def %mm-raddzc (mbf-octal 150 50 261 106 40))

; A's first and last mantissa bytes swapped, its exponent byte the guard
; below them, normalised as a fraction and rounded: RND1 and STRNEX.  Only
; Commodore's build swaps the middle two as well.
(def %mm-scramble
  (fn (_ a)
    (if (mbf-zero? a) mbf-zero
      (let ((m (int>> (mbf-mantissa a) 8)))
        (let ((b1 (int>> m 24)) (b2 (int& (int>> m 16) 255))
              (b3 (int& (int>> m 8) 255)) (b4 (int& m 255)))
          (mbf-round
            (mbf-fac #f
              (int| (int<< (int| (int<< b4 24) (int| (int<< b2 16) (int| (int<< b3 8) b1))) 8)
                    (mbf-exponent a))
              -40)))))))

; RND(X) given the last value: (VALUE . NEXT-SEED).  A negative X seeds the
; sequence with itself, zero repeats the last, and a positive X takes the
; next.
(def mbf-rnd
  (fn (_ x seed)
    (match
      ((int< (mbf-sgn x) 0) (let ((v (%mm-scramble x))) (pair v v)))
      ((mbf-zero? x) (pair seed seed))
      (#t (let ((v (%mm-scramble (mbf-add (mbf-mul seed %mm-rmulzc) %mm-raddzc))))
            (pair v v))))))

(provide basic/mbf-math
  mbf-log mbf-exp mbf-power mbf-sqr mbf-sin mbf-cos mbf-tan mbf-atn
  mbf-rnd-seed mbf-rnd)
