; # x-basic -- BASIC on x-lang
;
; ## lib/basic/mbf.x -- Microsoft binary format numbers
;
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)
;
; The floating point of Microsoft's BASICs, made of integers.  A number is a
; pair (M . E): the value M * 2^E, where M is zero or a signed mantissa whose
; magnitude has exactly 40 bits, its top bit set.  That is the 6502's
; floating accumulator: four mantissa bytes and the FACOV guard byte below
; them.  Packed, the 6502's five bytes are an exponent in excess 128 and the
; four mantissa bytes, the top mantissa bit holding the sign; (mbf-bytes ...)
; reads that form, and a packed number's guard byte is zero.
;
; The arithmetic is the 6502's, guard byte and all.  A result keeps its guard
; byte, bits shifted past it are dropped, and (mbf-round a) rounds as ROUND
; does: up when the guard's top bit is set.  The 6502 rounds when a number
; goes to memory: a variable, the operand stack, a constant's temporary.
; The operand that comes from memory is rounded here by the routine taking
; it: the multiplier, and both sides of a division.  A result whose packed
; exponent passes 255 is ?OV; one under 1 is zero, silently.

(module basic/mbf)
(import x/type/list)
(import x/type/err)
(import x/type/str)
(import x/core/doors int+ int- int* int/ int% int< int= int<< int>> int& str-byte-ref)

; The accumulator's width, and the guard bits at its bottom
(def %mbf-bits 40)
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

; The 40-bit MANT and exponent E checked against the exponent's range
(def %mbf-checked
  (fn (_ neg mant e)
    (let ((packed (int+ (int+ e %mbf-bits) 128)))
      (match
        ((int< 255 packed) (Err raise (lit basic) "OV"))
        ((int< packed 1) mbf-zero)
        (#t (pair (if neg (int- 0 mant) mant) e))))))

; The number NEG? MAG * 2^E, MAG any magnitude under 2^62, as the
; accumulator holds it: normalised (NORMAL), the bits below the guard byte
; dropped
(def %mbf-fac
  (fn (_ neg mag e)
    (if (int= mag 0) mbf-zero
      (let ((fit (%mbf-fit mag e %mbf-bits)))
        (%mbf-checked neg (first fit) (rest fit))))))

(def %mbf-neg? (fn (_ a) (int< (first a) 0)))
(def %mbf-mag (fn (_ a) (if (int< (first a) 0) (int- 0 (first a)) (first a))))

; A rounded to its four mantissa bytes, the guard byte cleared (ROUND)
(def mbf-round
  (fn (_ a)
    (if (mbf-zero? a) a
      (let ((m (%mbf-mag a)))
        (if (int= (int& m 128) 0) (%mbf-checked (%mbf-neg? a) (int- m (int& m 255)) (rest a))
          (let ((r (int+ (int>> m %mbf-guard) 1)))
            (if (int= r (int<< 1 32))
              (%mbf-checked (%mbf-neg? a) (int<< 1 39) (int+ (rest a) 1))
              (%mbf-checked (%mbf-neg? a) (int<< r %mbf-guard) (rest a)))))))))

; The number NEG? MAG * 2^E, normalised and rounded
(def %mbf-make
  (fn (_ neg mag e) (mbf-round (%mbf-fac neg mag e))))

; The packed bytes EXP M1 M2 M3 M4, M1's top bit the sign
(def mbf-bytes
  (fn (_ ex m1 m2 m3 m4)
    (if (int= ex 0) mbf-zero
      (let ((mant (int+ (int<< (int+ (int& m1 127) 128) 32)
                        (int+ (int<< m2 24) (int+ (int<< m3 16) (int<< m4 8))))))
        (pair (if (int< m1 128) mant (int- 0 mant)) (int- ex 168))))))

; A's packed bytes (EXP M1 M2 M3 M4), as MOVMF stores it rounded
(def mbf->bytes
  (fn (_ a)
    (let ((r (mbf-round a)))
      (if (mbf-zero? r) (list 0 0 0 0 0)
        (let ((m (%mbf-mag r)))
          (list (int+ (rest r) 168)
                (int+ (int& (int>> m 32) 127) (if (%mbf-neg? r) 128 0))
                (int& (int>> m 24) 255) (int& (int>> m 16) 255) (int& (int>> m 8) 255)))))))

; The integer N, exactly when it fits the mantissa (FLOAT)
(def mbf-int
  (fn (_ n)
    (if (int< n 0) (%mbf-make #t (int- 0 n) 0) (%mbf-make #f n 0))))

; --- reading a number's parts ---------------------------------------------

(def mbf-neg (fn (_ a) (pair (int- 0 (first a)) (rest a))))
(def mbf-abs (fn (_ a) (if (%mbf-neg? a) (mbf-neg a) a)))

; -1, 0 or 1
(def mbf-sgn
  (fn (_ a)
    (match
      ((int= (first a) 0) 0)
      ((int< (first a) 0) -1)
      (#t 1))))

; -1, 0 or 1 as A is below, equal to or above B, each rounded as FCOMP
; reads it
(def mbf-cmp
  (fn (_ a b)
    (let ((a (mbf-round a)) (b (mbf-round b)))
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
              (if (int< sa 0) (int- 0 by-mag) by-mag))))))))

; --- arithmetic -----------------------------------------------------------

; A + B as FADD adds: the smaller shifted right to the larger's bytes, the
; bits past its guard byte dropped
(def mbf-add
  (fn (_ a b)
    (match
      ((mbf-zero? a) b)
      ((mbf-zero? b) a)
      ((int< (rest a) (rest b)) (mbf-add b a))
      (#t
        (let ((d (int- (rest a) (rest b))))
          (let ((big (%mbf-mag a))
                (small (if (int< %mbf-bits d) 0 (int>> (%mbf-mag b) d)))
                (e (rest a)))
            (match
              ((eq? (%mbf-neg? a) (%mbf-neg? b)) (%mbf-fac (%mbf-neg? a) (int+ big small) e))
              ((int< small big) (%mbf-fac (%mbf-neg? a) (int- big small) e))
              (#t (%mbf-fac (%mbf-neg? b) (int- small big) e)))))))))

(def mbf-sub (fn (_ a b) (mbf-add a (mbf-neg b))))

; One multiplier byte B as MLTPLY runs it on the 32-bit RES and the guard
; byte OV: B's bits from the lowest, Y added for a set bit, RES and OV
; shifted right one, the bit leaving OV dropped.  (RES . OV).
(def %mbf-mult-byte
  (fn (_ b y res ov)
    (let ((go (fn (self i res ov)
                (if (int= i 8) (pair res ov)
                  (let ((sum (if (int= (int& (int>> b i) 1) 0) res (int+ res y))))
                    (self (int+ i 1)
                          (int>> sum 1)
                          (int+ (int>> ov 1) (int<< (int& sum 1) 7))))))))
      (go 0 res ov))))

; The accumulator's 40 bits X times the 32-bit Y as FMULT runs it, X's
; bytes from the guard byte up: the 40-bit product.  A zero byte below the
; top one is a shift of RES a byte, its low byte the new OV (MULSHF), and
; one bit more when the carry is clear coming in: SHIFTR counts the carry
; as a bit, and a shifted byte leaves it clear.  That bit is lost, OV left
; as it was.  C0 is the carry MULDIV leaves, set when the exponents' sum
; does not pass 255.
(def %mbf-mult
  (fn (_ x y c0)
    (let ((go (fn (self k x c res ov)
                (if (int= k 5) (int+ (int<< res 8) ov)
                  (let ((b (int& x 255)))
                    (if (and (int= b 0) (int< k 4))
                      (let ((r (int>> res 8)))
                        (self (int+ k 1) (int>> x 8) #f (if c r (int>> r 1)) (int& res 255)))
                      (let ((got (%mbf-mult-byte b y res ov)))
                        (self (int+ k 1) (int>> x 8) #t (first got) (rest got)))))))))
      (go 0 x c0 0 0))))

; A * B, A the accumulator, B rounded as the memory operand is (FMULT)
(def mbf-mul
  (fn (_ a b)
    (if (or (mbf-zero? a) (mbf-zero? b)) mbf-zero
      (let ((b (mbf-round b)))
        (let ((packed (int+ (int+ (rest a) (rest b)) 208)))
          (match
            ((int< 255 packed) (Err raise (lit basic) "OV"))
            ((int< packed 1) mbf-zero)
            (#t (%mbf-fac (not (eq? (%mbf-neg? a) (%mbf-neg? b)))
                          (%mbf-mult (%mbf-mag a) (int>> (%mbf-mag b) %mbf-guard) (int< packed 128))
                          (int+ (int+ (rest a) (rest b)) %mbf-bits)))))))))

; A / B, both rounded, as FDIV divides: 34 quotient bits, the last two in
; the guard byte.  The quotient is taken in two steps of long division so
; no dividend passes the word.
(def mbf-div
  (fn (_ a b)
    (match
      ((mbf-zero? b) (Err raise (lit basic) "/0"))
      ((mbf-zero? a) mbf-zero)
      (#t
        (let ((a (mbf-round a)) (b (mbf-round b)))
          (let ((packed (int+ (int- (rest a) (rest b)) 129)))
            (match
              ((int< 255 packed) (Err raise (lit basic) "OV"))
              ((int< packed 1) mbf-zero)
              (#t
                (let ((x (int<< (int>> (%mbf-mag a) %mbf-guard) 21))
                      (y (int>> (%mbf-mag b) %mbf-guard)))
                  (let ((q1 (int/ x y)) (r1 (int% x y)))
                    (%mbf-fac (not (eq? (%mbf-neg? a) (%mbf-neg? b)))
                              (int+ (int<< q1 12) (int/ (int<< r1 12) y))
                              (int- (int- (rest a) (rest b)) 33)))))))))))))

; The largest integer not above A (BASIC's INT).  A packed exponent of 160
; or more, a whole number of mantissa bytes, is left as it is.
(def mbf-floor
  (fn (_ a)
    (if (not (int< (rest a) -8)) a
      (let ((sh (int- 0 (rest a))))
        (if (int< 62 sh) (if (%mbf-neg? a) (mbf-int -1) mbf-zero)
          (let ((whole (int>> (%mbf-mag a) sh)))
            (let ((exact (int= (int<< whole sh) (%mbf-mag a))))
              (match
                ((not (%mbf-neg? a)) (mbf-int whole))
                (exact (mbf-int (int- 0 whole)))
                (#t (mbf-int (int- -1 whole)))))))))))

; A truncated toward zero, as an x integer; ?FC when its magnitude passes
; LIMIT, which is under 2^39
(def mbf->int
  (fn (_ a limit)
    (let ((mag (if (not (int< (rest a) 0)) (if (mbf-zero? a) 0 (int+ limit 1))
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

; A times ten as MUL10 makes it: A rounded, then four times itself added,
; which is exact
(def %mbf-mul10
  (fn (_ a)
    (let ((r (mbf-round a)))
      (if (mbf-zero? r) r (%mbf-fac (%mbf-neg? r) (int* (%mbf-mag r) 10) (rest r))))))

; A rounded and divided by ten (DIV10)
(def %mbf-div10 (fn (_ a) (mbf-div a %mbf-ten)))

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
; trailing zeros removed, and the power of ten of the first.  A number under
; 1 is first multiplied by 10^9; then it is divided or multiplied by ten
; until it is from 99999999.9499 to 999999999.499, a half added unless it
; is that top exactly, and its integer part taken.
(def %mbf-scale
  (fn (_ a)
    (let ((start (if (int< (mbf-exponent a) 129)
                   (pair (mbf-mul a %mbf-nzmil) -9)
                   (pair a 0))))
      (let ((go (fn (self x k)
                  (let ((top (mbf-cmp x %mbf-nz9999)))
                    (match
                      ((int= top 0) (pair (%mbf-qint x) k))
                      ((int< 0 top) (self (%mbf-div10 x) (int+ k 1)))
                      ((int< 0 (mbf-cmp x %mbf-nz0999))
                        (pair (%mbf-qint (mbf-add x %mbf-half)) k))
                      (#t (self (%mbf-mul10 x) (int- k 1))))))))
        (let ((got (go (first start) (rest start))))
          (let ((n (first got)) (k (rest got)))
            (let ((fit (if (int< n 1000000000) (pair n k) (pair (int/ n 10) (int+ k 1)))))
              (pair (List reverse
                      (List drop-while (fn (_ c) (int= c 48))
                        (List reverse (%mbf-digits (first fit)))))
                    (int+ (rest fit) 8)))))))))

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
; time (MUL10, then the digit added to the rounded sum) and then a power of
; ten at a time
(def mbf-from-digits
  (fn (_ digits point exp)
    (let ((acc (List fold (fn (_ n c) (mbf-add (mbf-round (%mbf-mul10 n)) (mbf-int (int- c 48))))
                          mbf-zero digits)))
      (let ((go (fn (self n k)
                  (match
                    ((int< 0 k) (self (%mbf-mul10 n) (int- k 1)))
                    ((int< k 0) (self (%mbf-div10 n) (int+ k 1)))
                    (#t n)))))
        (go acc (int- exp point))))))

; The number at I in TEXT, as FIN reads a constant with the blanks gone:
; digits, a point and digits, then E, a sign and digits, only the first
; three of those counted.  (NUMBER . END), or nil when no digit or point is
; at I.
(def mbf-read
  (fn (_ text i)
    (let ((n (Str8 length text)))
      (let ((at (fn (_ j) (if (int< j n) (str-byte-ref text j) 0))))
        (let ((digit? (fn (_ j) (let ((c (at j))) (and (not (int< c 48)) (not (int< 57 c))))))
              (digits (fn (self j acc) (if (and (int< j n) (let ((c (at j))) (and (not (int< c 48)) (not (int< 57 c)))))
                                         (self (int+ j 1) (pair (at j) acc))
                                         (pair (List reverse acc) j)))))
          (if (not (or (digit? i) (int= (at i) 46))) ()
            (let ((whole (digits i ())))
              (let ((frac (if (int= (at (rest whole)) 46) (digits (int+ (rest whole) 1) ()) (pair () (rest whole)))))
                (let ((ex (if (int= (at (rest frac)) 69)
                            (let ((j (int+ (rest frac) 1)))
                              (let ((neg (int= (at j) 45)))
                                (let ((ds (digits (if (or neg (int= (at j) 43)) (int+ j 1) j) ())))
                                  (let ((k (List fold (fn (_ k b) (int+ (int* k 10) (int- b 48))) 0 (List take 3 (first ds)))))
                                    (pair (if neg (int- 0 k) k) (rest ds))))))
                            (pair 0 (rest frac)))))
                  (pair (mbf-from-digits (List append (first whole) (first frac)) (List length (first frac)) (first ex))
                        (rest ex)))))))))))

; --- parts ----------------------------------------------------------------

; The packed bytes as the source writes them, in octal: (mbf-octal 201 0 0 0
; 0) is 1
(def %mbf-octal-byte
  (fn (_ n) (int+ (int* (int/ n 100) 64) (int+ (int* (int% (int/ n 10) 10) 8) (int% n 10)))))

(def mbf-octal
  (fn (_ ex m1 m2 m3 m4)
    (mbf-bytes (%mbf-octal-byte ex) (%mbf-octal-byte m1) (%mbf-octal-byte m2)
               (%mbf-octal-byte m3) (%mbf-octal-byte m4))))

; A's exponent as packed, in excess 128; 0 for zero
(def mbf-exponent
  (fn (_ a) (if (mbf-zero? a) 0 (int+ (int+ (rest a) %mbf-bits) 128))))

; A's 40-bit magnitude, its top bit set, the guard byte at its bottom
(def mbf-mantissa (fn (_ a) (%mbf-mag a)))

; The number NEG? MAG * 2^E as the accumulator holds it, unrounded: ?OV
; when too large, zero when too small
(def mbf-fac (fn (_ neg mag e) (%mbf-fac neg mag e)))

; A with its packed exponent set to EX, its guard byte kept: the mantissa
; as a fraction in [.5, 1) when EX is 128
(def mbf-with-exponent
  (fn (_ a ex) (pair (first a) (int- ex (int+ %mbf-bits 128)))))

(provide basic/mbf
  mbf-zero mbf-zero? mbf-bytes mbf->bytes mbf-octal mbf-int mbf-neg mbf-abs mbf-sgn mbf-cmp
  mbf-round mbf-add mbf-sub mbf-mul mbf-div mbf-floor mbf->int mbf->str
  mbf-from-digits mbf-read mbf-exponent mbf-mantissa mbf-fac mbf-with-exponent)
