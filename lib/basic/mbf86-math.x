; # x-basic -- BASIC on x-lang
;
; ## lib/basic/mbf86-math.x -- the 8086 BASIC's maths functions
;
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)
;
; SQR, LOG, EXP, SIN, COS, TAN, ATN, X^Y and RND as MATH1.ASM and MATH2.ASM
; compute them: the same steps in the same order, Hart's coefficients and
; the constants as the source writes them, in octal.  Each takes and gives
; a single: the function dispatch forces its argument to one (FRCSNG), and
; ^ both its operands.  SIN and COS reduce the angle in double precision.
;
; Function dispatch and $FPWR set the once-only overflow mode: an overflow
; or a division by zero inside goes on with the largest number, and only
; the first is printed.  Here each goes on so, and the first is raised at
; the end, carrying the answer.

(module basic/mbf86-math)
(import x/type/list)
(import x/type/vector)
(import x/type/err)
(import x/type/assoc)
(import x/core/doors int+ int- int* int/ int% int< int= int<< int>> int&)
(import basic/mbf86
  m86-int m86-zero? m86-infinity m86-raise m86->single m86->double m86-floor
  m86-neg m86-abs m86-add m86-sub m86-mul m86-div m86-cmp m86->bytes m86-from-bytes)

; --- constants ------------------------------------------------------------

(def %ma-octal
  (fn (self n) (if (int< n 10) n (int+ (int* (self (int/ n 10)) 8) (int% n 10)))))

; A single from its four bytes, low first, in octal
(def %ma-single (fn (_ bytes) (m86-from-bytes 4 (List map %ma-octal bytes))))

; A single from the BX and DX words a routine loads, in octal
(def %ma-bxdx
  (fn (_ bx dx)
    (let ((b (%ma-octal bx)) (d (%ma-octal dx)))
      (m86-from-bytes 4 (list (int& d 255) (int>> d 8) (int& b 255) (int>> b 8))))))

(def %ma-zero (m86-from-bytes 4 (list 0 0 0 0)))
(def %ma-one (%ma-bxdx 100400 0))
(def %ma-one-double (m86->double %ma-one))
(def %ma-quarter-double (m86->double (%ma-single (list 0 0 0 177))))

(def %ma-exp (fn (_ v) (List third v)))
(def %ma-neg? (fn (_ v) (List second v)))
(def %ma-mant (fn (_ v) (List ref 3 v)))

; --- going on past an overflow --------------------------------------------

; The box an operation in the once-only mode keeps the first overflow's
; label in
(def %ma-box (fn (_) (Vector make 1 ())))

; The label's raise recorded in O, and V, the number it goes on with
(def %ma-raise
  (fn (_ o label v)
    (do (when (null? (Vector ref 0 o)) (Vector set! 0 label o)) v)))

; What THUNK answers, an overflow or a division by zero in it going on
(def %ma-go-on
  (fn (_ o thunk)
    (guard (e (let ((label (Err label e)))
                (if (or (eq? label (lit basic-overflow)) (eq? label (lit basic-div0)))
                  (%ma-raise o label (Assoc get (lit value) (e data)))
                  (error e))))
      (thunk))))

(def %ma-add (fn (_ o a b) (%ma-go-on o (fn (_) (m86-add a b)))))
(def %ma-sub (fn (_ o a b) (%ma-go-on o (fn (_) (m86-sub a b)))))
(def %ma-mul (fn (_ o a b) (%ma-go-on o (fn (_) (m86-mul a b)))))
(def %ma-div (fn (_ o a b) (%ma-go-on o (fn (_) (m86-div a b)))))

; F of a fresh box, and the first overflow in it raised with the answer
(def %ma-once
  (fn (_ f)
    (let ((o (%ma-box)))
      (let ((v (f o)))
        (let ((label (Vector ref 0 o)))
          (if (null? label) v (m86-raise label v)))))))

; F as a function of one number, made a single and run once-only
(def %ma-function
  (fn (_ f)
    (fn (_ x) (%ma-once (fn (_ o) (f o (%ma-go-on o (fn (_) (m86->single x)))))))))

; --- helpers --------------------------------------------------------------

; V's largest whole number not above it, an x integer, as QINT leaves it:
; past 2^24 its shift count wraps and it is 0
(def %ma-qint
  (fn (_ v)
    (let ((f (m86-floor v)))
      (if (m86-zero? f) 0
        (let ((top (int+ 128 (if (int= (first f) 8) 56 24))))
          (let ((n (if (int< top (%ma-exp f)) 0 (int>> (%ma-mant f) (int- top (%ma-exp f))))))
            (if (%ma-neg? f) (int- 0 n) n)))))))

(def %ma-whole? (fn (_ v) (int= (m86-cmp (m86-floor v) v) 0)))

; C0*X^N + ... + CN ($POLY): the first coefficient, then each sum times X
; plus the next
(def %ma-poly
  (fn (_ o x coefs)
    (List fold (fn (_ acc c) (%ma-add o (%ma-mul o acc x) c)) (first coefs) (rest coefs))))

; X times the polynomial in X^2 ($POLYX)
(def %ma-polyx
  (fn (_ o x coefs) (%ma-mul o (%ma-poly o (%ma-mul o x x) coefs) x)))

; --- SQR ------------------------------------------------------------------

; The root bit by bit ($SQR): the mantissa and a zero byte, halved when the
; exponent is odd, two bits at a time into the remainder for 25 result bits,
; then the last of them rounding.  The rounding can carry out of 24 bits,
; and then the top bit is lost: the source clears it as the sign.
(def %ma-sqr
  (fn (_ o x)
    (match
      ((%ma-neg? x) (Err raise (lit basic) "FC"))
      ((m86-zero? x) x)
      (#t
        (let ((e (%ma-exp x)) (mask32 (int- (int<< 1 32) 1)))
          (let ((odd (int& e 1)))
            (let ((go (fn (self i v rem q)
                        (if (int= i 25) q
                          (let ((rem (int+ (int<< rem 2) (int>> v 30)))
                                (q (int+ (int<< q 1) 1)))
                            (if (int< rem q) (self (int+ i 1) (int& (int<< v 2) mask32) rem (int- q 1))
                              (self (int+ i 1) (int& (int<< v 2) mask32) (int- rem q) (int+ q 1))))))))
              (let ((root (int>> (go 0 (int>> (int<< (%ma-mant x) 8) odd) 0 0) 1)))
                (let ((r (int+ (int>> root 1) (int& root 1))))
                  (list 4 #f (int+ (int+ (int>> e 1) 64) odd)
                        (int+ (int& r (int- (int<< 1 23) 1)) (int<< 1 23))))))))))))

; --- LOG and EXP ----------------------------------------------------------

; Hart 2524: LOG2 of the fraction as P/Q
(def %ma-logp
  (List map %ma-single
    (list (list 232 367 31 203) (list 44 143 103 203) (list 165 315 215 204) (list 251 177 203 202))))
(def %ma-logq
  (List map %ma-single
    (list (list 0 0 0 201) (list 342 260 115 203) (list 12 162 21 203) (list 364 4 65 177))))
(def %ma-ln2 (%ma-bxdx 100061 71030))

; The natural log ($LOG): ?FC for zero or less, 0 for 1; the exponent split
; off and added to LOG2 of the fraction in [.5, 1), the sum times LN(2)
(def %ma-log
  (fn (_ o x)
    (match
      ((or (m86-zero? x) (%ma-neg? x)) (Err raise (lit basic) "FC"))
      ((int= (m86-cmp x %ma-one) 0) %ma-zero)
      (#t
        (let ((f (list 4 #f 128 (%ma-mant x))))
          (let ((pq (%ma-div o (%ma-poly o f %ma-logp) (%ma-poly o f %ma-logq))))
            (%ma-mul o (%ma-add o (m86->single (m86-int (int- (%ma-exp x) 128))) pq) %ma-ln2)))))))

(def %ma-log2e (%ma-bxdx 100470 125073))

; Hart 1302: 2 to a fraction
(def %ma-expcn
  (List map %ma-single
    (list (list 174 210 131 164) (list 340 227 46 167) (list 304 35 36 172) (list 136 120 143 174)
          (list 32 376 165 176) (list 30 162 61 200) (list 0 0 0 201))))

; e to the X ($EXP): Y = X * LOG2(e); 2^INT(Y) made as an exponent, 2 to
; the fraction by the polynomial, and the two multiplied.  At 128 or more
; Y overflows, or is 0 when negative; under 2^-24 the answer is 1.
(def %ma-exp-of
  (fn (_ o x)
    (let ((y (%ma-mul o x %ma-log2e)))
      (match
        ((not (int< (%ma-exp y) 136))
          (if (%ma-neg? y) %ma-zero (%ma-raise o (lit basic-overflow) (m86-infinity 4 #f))))
        ((int< (%ma-exp y) 104) %ma-one)
        (#t
          (let ((n (%ma-qint y)))
            ; 2^N's exponent byte, which wraps to 0 for 127
            (let ((ah (int& (int+ (int& n 255) 129) 255)))
              (if (int= ah 0) (%ma-raise o (lit basic-overflow) (m86-infinity 4 #f))
                (%ma-mul o (%ma-poly o (%ma-sub o y (m86->single (m86-int n))) %ma-expcn)
                         (list 4 #f ah (int<< 1 23)))))))))))

; --- SIN, COS and TAN -----------------------------------------------------

; Hart 3341
(def %ma-sincn
  (List map %ma-single
    (list (list 373 327 36 206) (list 145 46 231 207) (list 130 64 43 207) (list 341 135 245 206)
          (list 333 17 111 203))))

; 1/(2*PI), a double whose low bytes the source chose for singles
(def %ma-in2pi (m86-from-bytes 8 (List map %ma-octal (list 13 104 116 156 203 371 42 176))))
(def %ma-2pi (%ma-bxdx 101511 7733))

; V - INT(V), a double (RR1, RR2): INT(V) - V negated
(def %ma-frac
  (fn (_ o v) (m86-neg (%ma-sub o (m86-floor v) v))))

; X / (2*PI) less its whole part, a double (RR)
(def %ma-turns
  (fn (_ o x) (%ma-frac o (%ma-mul o (m86->double x) %ma-in2pi))))

; The sine of the angle T turns, 0 <= T < 1 (SIN30): T times 4 split into
; the quadrant and the angle in it; the angle taken from 1 in quadrants 1
; and 3; divided by 4 again and made a single; times 2*PI when it is small,
; else Hart's polynomial; negated in quadrants 2 and 3.  The source adds 2
; to the exponent whatever it is; a zero comes out zero either way.
(def %ma-sin-turns
  (fn (_ o t)
    (let ((t4 (if (m86-zero? t) t (list 8 (%ma-neg? t) (int+ (%ma-exp t) 2) (%ma-mant t)))))
      (let ((q (%ma-qint t4)))
        (let ((a (%ma-frac o t4)))
          (let ((a (if (int= (int& q 1) 1) (%ma-sub o %ma-one-double a) a)))
            (let ((s (m86->single
                       (if (int< (%ma-exp a) 3) (m86->double %ma-zero)
                         (list 8 (%ma-neg? a) (int- (%ma-exp a) 2) (%ma-mant a))))))
              (let ((r (if (int< (%ma-exp s) 116) (%ma-mul o s %ma-2pi) (%ma-polyx o s %ma-sincn))))
                (if (int< 1 q) (m86-neg r) r)))))))))

; SIN(-X) = -SIN(X); under 2^-9 SIN(X) is X
(def %ma-sin
  (fn (_ o x)
    (if (int< (%ma-exp x) 119) x
      (let ((r (%ma-sin-turns o (%ma-turns o (m86-abs x)))))
        (if (%ma-neg? x) (m86-neg r) r)))))

; COS(X) = SIN(X + PI/2): a quarter turn added to the reduced angle
(def %ma-cos
  (fn (_ o x)
    (%ma-sin-turns o (%ma-frac o (%ma-add o (%ma-turns o (m86-abs x)) %ma-quarter-double)))))

(def %ma-tan
  (fn (_ o x) (%ma-div o (%ma-sin o x) (%ma-cos o x))))

; --- ATN ------------------------------------------------------------------

(def %ma-atnc1 (List map %ma-single (list (list 327 263 135 201) (list 0 0 200 201))))
; Hart 4940
(def %ma-atnc2
  (List map %ma-single
    (list (list 142 65 203 176) (list 120 44 114 176) (list 171 251 252 177) (list 0 0 0 201))))
(def %ma-tan15 (%ma-bxdx 77411 30242))
(def %ma-sqr3 (%ma-bxdx 100535 131727))
(def %ma-pi2 (%ma-bxdx 100511 7733))
(def %ma-pi6 (%ma-bxdx 100006 5222))

; The arctangent ($ATAN): ATN(-X) = -ATN(X); from 1 up, PI/2 - ATN(1/X);
; from TAN(PI/12) up, PI/6 + ATN((X*SQR(3)-1)/(X+SQR(3))); then Hart's
; polynomial
(def %ma-atn
  (fn (_ o x)
    (let ((big (not (int< (%ma-exp x) 129))))
      (let ((a (if big (%ma-div o %ma-one (m86-abs x)) (m86-abs x))))
        (let ((mid (not (int< (m86-cmp a %ma-tan15) 0))))
          (let ((r (%ma-polyx o (if mid (%ma-div o (%ma-poly o a %ma-atnc1) (%ma-add o a %ma-sqr3)) a)
                              %ma-atnc2)))
            (let ((r (if mid (%ma-add o r %ma-pi6) r)))
              (let ((r (if big (%ma-sub o %ma-pi2 r) r)))
                (if (%ma-neg? x) (m86-neg r) r)))))))))

; --- X^Y ------------------------------------------------------------------

; X to the whole N, 0 < N < 32768 (XTON, Knuth's A1-A5): Y = Y * Z for
; each bit of N, low first, Z squared between
(def %ma-xton
  (fn (_ o x n)
    (let ((go (fn (self y z n)
                (let ((y (if (int= (int& n 1) 1) (%ma-mul o y z) y)) (n (int>> n 1)))
                  (if (int= n 0) y (self y (%ma-mul o z z) n))))))
      (go %ma-one x n))))

(def %ma-32768 (%ma-bxdx 110000 0))

; X^Y, Y not negative (FP30A): a whole Y under 32768 by multiplying, else
; EXP(Y * LOG(|X|)), negated when X is negative and Y odd
(def %ma-power-up
  (fn (_ o x y)
    (if (and (%ma-whole? y) (int< (m86-cmp y %ma-32768) 0)) (%ma-xton o x (%ma-qint y))
      (let ((r (%ma-exp-of o (%ma-mul o (%ma-log o (m86-abs x)) y))))
        (if (and (%ma-neg? x) (int= (int& (%ma-qint y) 1) 1)) (m86-neg r) r)))))

; X^Y ($FPWR): 1 when Y is 0; 0 when X is, a division by zero for a
; negative Y; a negative X only to a whole Y under 2^25, ?FC else.  A
; negative Y is X^-Y inverted, and an overflow when X^-Y is too small, its
; sign X's when -Y is odd.
(def %ma-power
  (fn (_ o x y)
    (match
      ((m86-zero? y) (%ma-exp-of o y))
      ((m86-zero? x)
        (if (%ma-neg? y) (%ma-raise o (lit basic-div0) (m86-infinity 4 #f)) %ma-zero))
      ((and (%ma-neg? x) (or (not (int< (%ma-exp y) 153)) (not (%ma-whole? y))))
        (Err raise (lit basic) "FC"))
      ((not (%ma-neg? y)) (%ma-power-up o x y))
      (#t
        (let ((y (m86-abs y)))
          (let ((r (%ma-power-up o x y)))
            (if (not (m86-zero? r)) (%ma-div o %ma-one r)
              (%ma-raise o (lit basic-overflow)
                (m86-infinity 4 (and (%ma-neg? x) (int= (int& (%ma-qint y) 1) 1)))))))))))

; --- RND ------------------------------------------------------------------

(def %ma-mask24 (int- (int<< 1 24) 1))

; RNDCOP, the seed CLEAR puts back: $4FC752
(def m86-rnd-seed (int+ (%ma-octal 122) (int+ (int<< (%ma-octal 307) 8) (int<< (%ma-octal 117) 16))))

; The 24 bits S over 2^24, a single ($NORMS from exponent $80)
(def %ma-unit
  (fn (_ s)
    (if (int= s 0) %ma-zero
      (let ((go (fn (self m e) (if (int< m (int<< 1 23)) (self (int<< m 1) (int- e 1)) (list 4 #f e m)))))
        (go s 128)))))

; RND(X) from the seed S, as (VALUE . SEED) ($RND): 0 gives the last number
; again; a negative X makes its low three bytes the seed first; then the
; next, S * 214013 + 2531011 in 24 bits
(def m86-rnd
  (fn (_ x s)
    (let ((x (m86->single x)))
      (if (m86-zero? x) (pair (%ma-unit s) s)
        (let ((s (if (%ma-neg? x)
                   (let ((b (m86->bytes x))) (int+ (first b) (int+ (int<< (List second b) 8) (int<< (List third b) 16))))
                   s)))
          (let ((s (int& (int+ (int* s 214013) 2531011) %ma-mask24)))
            (pair (%ma-unit s) s)))))))

; RANDOMIZE N on the seed S (STRNDS): N's word in its upper two bytes, then
; one RND(1) taken
(def m86-randomize
  (fn (_ n s)
    (rest (m86-rnd %ma-one (int+ (int& s 255) (int<< (int& n 65535) 8))))))

; --- the functions --------------------------------------------------------

(def m86-sqr (%ma-function %ma-sqr))
(def m86-log (%ma-function %ma-log))
(def m86-exp (%ma-function %ma-exp-of))
(def m86-sin (%ma-function %ma-sin))
(def m86-cos (%ma-function %ma-cos))
(def m86-tan (%ma-function %ma-tan))
(def m86-atn (%ma-function %ma-atn))

; X^Y, each made a single first (EXPSTK, FPWRQ)
(def m86-power
  (fn (_ x y)
    (%ma-once
      (fn (_ o)
        (%ma-power o (%ma-go-on o (fn (_) (m86->single x))) (%ma-go-on o (fn (_) (m86->single y))))))))

(provide basic/mbf86-math
  m86-sqr m86-log m86-exp m86-sin m86-cos m86-tan m86-atn m86-power
  m86-rnd m86-rnd-seed m86-randomize)
