; # x-basic -- BASIC on x-lang
;
; ## basic/mbf.x -- Microsoft binary format numbers
;
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)
;
; The floating point of Microsoft's BASICs, made of integers.  A number is a
; pair (M . E): the value M * 2^E, where M is zero or a signed mantissa whose
; magnitude has exactly `bits` bits, its top bit set.  Packed, the 6502's
; five bytes are an exponent in excess 128 and four mantissa bytes, the top
; mantissa bit holding the sign; (mbf-bytes ...) reads that form.
;
; Arithmetic keeps eight guard bits below the mantissa, as the 6502's FACOV
; byte does, and rounds as its ROUND does: up when the guard's top bit is
; set.  Bits shifted past the guard byte are dropped.  A result whose
; packed exponent passes 255 is ?OV; one under 1 is zero, silently.
;
; A format is the mantissa width: 32 for the 6502's five-byte numbers.

(module basic/mbf)
(import x/type/list)
(import x/type/err)
(import x/core/doors int+ int- int* int/ int% int< int= int<< int>> int&)

; The mantissa width of the numbers made here, and the guard bits below it
(def %mbf-bits 32)
(def %mbf-guard 8)

(def mbf-zero (pair 0 0))

(def mbf-zero? (fn (_ a) (int= (first a) 0)))

; --- making a number ------------------------------------------------------

; MAG shifted until it has W bits, and the exponent moved to match:
; (MAG . E).  Bits shifted out at the bottom are dropped.
(def %mbf-fit
  (fn (_ mag e w)
    (let ((top (int<< 1 w)) (half (int<< 1 (int- w 1))))
      (let ((go (fn (self m e)
                  (match
                    ((not (int< m top)) (self (int>> m 1) (int+ e 1)))
                    ((int< m half) (self (int<< m 1) (int- e 1)))
                    (#t (pair m e))))))
        (go mag e)))))

; The number NEG? MAG * 2^E, MAG any magnitude under 2^62: normalised to
; the mantissa and its guard byte, rounded, and checked against the
; exponent's range
(def %mbf-make
  (fn (_ neg mag e)
    (if (int= mag 0) mbf-zero
      (let ((fit (%mbf-fit mag e (int+ %mbf-bits %mbf-guard))))
        (let ((m (int>> (first fit) %mbf-guard))
              (up (not (int= (int& (first fit) 128) 0)))
              (e2 (int+ (rest fit) %mbf-guard)))
          (let ((r (if up (int+ m 1) m)))
            (let ((over (int= r (int<< 1 %mbf-bits))))
              (let ((mant (if over (int>> r 1) r))
                    (ex (if over (int+ e2 1) e2)))
                (let ((packed (int+ (int+ ex %mbf-bits) 128)))
                  (match
                    ((int< 255 packed) (Err raise (lit basic) "OV"))
                    ((int< packed 1) mbf-zero)
                    (#t (pair (if neg (int- 0 mant) mant) ex))))))))))))

; The packed bytes EXP M1 M2 M3 M4, M1's top bit the sign
(def mbf-bytes
  (fn (_ ex m1 m2 m3 m4)
    (if (int= ex 0) mbf-zero
      (let ((mant (int+ (int<< (int+ (int& m1 127) 128) 24)
                        (int+ (int<< m2 16) (int+ (int<< m3 8) m4)))))
        (pair (if (int< m1 128) mant (int- 0 mant)) (int- ex 160))))))

; The integer N, exactly when it fits the mantissa
(def mbf-int
  (fn (_ n)
    (if (int< n 0) (%mbf-make #t (int- 0 n) 0) (%mbf-make #f n 0))))

; --- reading a number's parts ---------------------------------------------

(def %mbf-neg? (fn (_ a) (int< (first a) 0)))
(def %mbf-mag (fn (_ a) (if (int< (first a) 0) (int- 0 (first a)) (first a))))

(def mbf-neg (fn (_ a) (pair (int- 0 (first a)) (rest a))))
(def mbf-abs (fn (_ a) (if (%mbf-neg? a) (mbf-neg a) a)))

; -1, 0 or 1
(def mbf-sgn
  (fn (_ a)
    (match
      ((int= (first a) 0) 0)
      ((int< (first a) 0) -1)
      (#t 1))))

; -1, 0 or 1 as A is below, equal to or above B
(def mbf-cmp
  (fn (_ a b)
    (let ((sa (mbf-sgn a)) (sb (mbf-sgn b)))
      (match
        ((int< sa sb) -1)
        ((int< sb sa) 1)
        ((int= sa 0) 0)
        (#t
          (let ((by-mag
                  (match
                    ((int< (rest a) (rest b)) -1)
                    ((int< (rest b) (rest a)) 1)
                    ((int< (%mbf-mag a) (%mbf-mag b)) -1)
                    ((int< (%mbf-mag b) (%mbf-mag a)) 1)
                    (#t 0))))
            (if (int< sa 0) (int- 0 by-mag) by-mag)))))))

; --- arithmetic -----------------------------------------------------------

(def mbf-add
  (fn (_ a b)
    (match
      ((mbf-zero? a) b)
      ((mbf-zero? b) a)
      ((int< (rest a) (rest b)) (mbf-add b a))
      (#t
        (let ((d (int- (rest a) (rest b))))
          (if (int< (int+ (int+ %mbf-bits %mbf-guard) 1) d) a
            (let ((big (int<< (%mbf-mag a) %mbf-guard))
                  (small (int>> (int<< (%mbf-mag b) %mbf-guard) d))
                  (e (int- (rest a) %mbf-guard)))
              (match
                ((eq? (%mbf-neg? a) (%mbf-neg? b))
                  (%mbf-make (%mbf-neg? a) (int+ big small) e))
                ((int< small big) (%mbf-make (%mbf-neg? a) (int- big small) e))
                (#t (%mbf-make (%mbf-neg? b) (int- small big) e))))))))))

(def mbf-sub (fn (_ a b) (mbf-add a (mbf-neg b))))

; The product's top bits: P >> 24 for two 32-bit mantissas, taken from their
; 16-bit halves so no partial product passes the word
(def mbf-mul
  (fn (_ a b)
    (if (or (mbf-zero? a) (mbf-zero? b)) mbf-zero
      (let ((x (%mbf-mag a)) (y (%mbf-mag b)))
        (let ((xh (int>> x 16)) (xl (int& x 65535))
              (yh (int>> y 16)) (yl (int& y 65535)))
          (let ((top (int+ (int<< (int* xh yh) 8)
                           (int>> (int+ (int+ (int* xh yl) (int* xl yh))
                                        (int>> (int* xl yl) 16))
                                  8))))
            (%mbf-make (not (eq? (%mbf-neg? a) (%mbf-neg? b))) top
                       (int+ (int+ (rest a) (rest b)) 24))))))))

; The quotient to 41 bits, in two steps of long division so no dividend
; passes the word
(def mbf-div
  (fn (_ a b)
    (match
      ((mbf-zero? b) (Err raise (lit basic) "/0"))
      ((mbf-zero? a) mbf-zero)
      (#t
        (let ((x (int<< (%mbf-mag a) 21)) (y (%mbf-mag b)))
          (let ((q1 (int/ x y)) (r1 (int% x y)))
            (let ((q (int+ (int<< q1 20) (int/ (int<< r1 20) y))))
              (%mbf-make (not (eq? (%mbf-neg? a) (%mbf-neg? b))) q
                         (int- (int- (rest a) (rest b)) 41)))))))))

; The largest integer not above A (BASIC's INT)
(def mbf-floor
  (fn (_ a)
    (if (not (int< (rest a) 0)) a
      (let ((sh (int- 0 (rest a))))
        (if (int< 62 sh) (if (%mbf-neg? a) (mbf-int -1) mbf-zero)
          (let ((whole (int>> (%mbf-mag a) sh)))
            (let ((exact (int= (int<< whole sh) (%mbf-mag a))))
              (match
                ((not (%mbf-neg? a)) (mbf-int whole))
                (exact (mbf-int (int- 0 whole)))
                (#t (mbf-int (int- -1 whole)))))))))))

; A truncated toward zero, as an x integer; ?FC when its magnitude passes
; LIMIT
(def mbf->int
  (fn (_ a limit)
    (let ((mag (if (not (int< (rest a) 0))
                 (if (int< 30 (rest a)) (int+ limit 1) (int<< (%mbf-mag a) (rest a)))
                 (if (int< 62 (int- 0 (rest a))) 0 (int>> (%mbf-mag a) (int- 0 (rest a)))))))
      (if (int< limit mag) (Err raise (lit basic) "FC")
        (if (%mbf-neg? a) (int- 0 mag) mag)))))

; --- decimal text ---------------------------------------------------------

(def %mbf-ten (mbf-int 10))

; The packed constants FOUT scales by, from the 6502 source
(def %mbf-nz0999 (mbf-bytes 155 62 188 31 253))
(def %mbf-nz9999 (mbf-bytes 158 110 107 39 253))
(def %mbf-nzmil (mbf-bytes 158 110 107 40 0))
(def %mbf-half (mbf-bytes 128 0 0 0 0))

; The integer part of a positive A (QINT)
(def %mbf-qint
  (fn (_ a)
    (if (not (int< (rest a) 0)) (int<< (first a) (rest a))
      (int>> (first a) (int- 0 (rest a))))))

; Digits of a positive integer
(def %mbf-digits
  (fn (_ n)
    (let ((go (fn (self n acc)
                (if (int= n 0) acc
                  (self (int/ n 10) (pair (int+ 48 (int% n 10)) acc))))))
      (go n ()))))

(def %mbf-zeros
  (fn (_ n) (if (int< n 1) () (pair 48 (%mbf-zeros (int- n 1))))))

; A's digits as FOUT makes them: (DIGITS . EXP), nine digit bytes with
; trailing zeros removed, and the power of ten of the first
(def %mbf-scale
  (fn (_ a)
    (let ((start (if (int< (mbf-cmp a (mbf-int 1)) 0)
                   (pair (mbf-mul a %mbf-nzmil) -9)
                   (pair a 0))))
      (let ((go (fn (self x k)
                  (match
                    ((int< 0 (mbf-cmp x %mbf-nz9999)) (self (mbf-div x %mbf-ten) (int+ k 1)))
                    ((int< (mbf-cmp x %mbf-nz0999) 0) (self (mbf-mul x %mbf-ten) (int- k 1)))
                    (#t
                      (let ((n (%mbf-qint (mbf-add x %mbf-half))))
                        (if (int< n 1000000000) (pair n k) (pair (int/ n 10) (int+ k 1)))))))))
        (let ((got (go (first start) (rest start))))
          (pair (List reverse
                  (List drop-while (fn (_ c) (int= c 48))
                    (List reverse (%mbf-digits (first got)))))
                (int+ (rest got) 8)))))))

; A as BASIC prints it: a sign or a space, then fixed notation from .01 to
; 999999999, and E notation outside it
(def mbf->str
  (fn (_ a)
    (if (mbf-zero? a) " 0"
      (let ((got (%mbf-scale (mbf-abs a))))
        (let ((ds (first got)) (k (rest got)))
          (let ((body
                  (match
                    ((and (not (int< k -2)) (int< k 9))
                      (if (int< k 0)
                        (pair 46 (List append (%mbf-zeros (int- (int- 0 k) 1)) ds))
                        (let ((whole (List append ds (%mbf-zeros (int- (int+ k 1) (List length ds))))))
                          (let ((int-part (List take (int+ k 1) whole))
                                (frac (List drop (int+ k 1) whole)))
                            (if (null? frac) int-part
                              (List append int-part (pair 46 frac)))))))
                    (#t
                      (let ((ex (if (int< k 0) (int- 0 k) k)))
                        (List append
                          (pair (first ds)
                                (if (null? (rest ds)) () (pair 46 (rest ds))))
                          (pair 69 (pair (if (int< k 0) 45 43)
                                         (if (int< ex 10) (pair 48 (%mbf-digits ex))
                                           (%mbf-digits ex))))))))))
            (bytes->str (pair (if (%mbf-neg? a) 45 32) body))))))))

; The number whose decimal digits are DIGITS (bytes), POINT of them after
; the decimal point, times ten to EXP: built as FIN builds it, a digit at a
; time and then a power of ten at a time, rounding at each step
(def mbf-from-digits
  (fn (_ digits point exp)
    (let ((acc (List fold (fn (_ n c) (mbf-add (mbf-mul n %mbf-ten) (mbf-int (int- c 48))))
                          mbf-zero digits)))
      (let ((go (fn (self n k)
                  (match
                    ((int< 0 k) (self (mbf-mul n %mbf-ten) (int- k 1)))
                    ((int< k 0) (self (mbf-div n %mbf-ten) (int+ k 1)))
                    (#t n)))))
        (go acc (int- exp point))))))

(provide basic/mbf
  mbf-zero mbf-zero? mbf-bytes mbf-int mbf-neg mbf-abs mbf-sgn mbf-cmp
  mbf-add mbf-sub mbf-mul mbf-div mbf-floor mbf->int mbf->str mbf-from-digits)
