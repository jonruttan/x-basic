; # x-basic -- BASIC on x-lang
;
; ## lib/basic/mbf86.x -- the 8086 BASIC's numbers
;
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)
;
; GW-BASIC's three numeric types, as Microsoft's MIT-licensed 8086 source
; (MATH1.ASM, MATH2.ASM) computes them, made of integers.
;
; A number is a list whose first item is its VALTYP: (2 N) an integer, N
; from -32768 to 32767; (4 NEG EXP MANT) a single and (8 NEG EXP MANT) a
; double, EXP the exponent in excess 128 (0 for zero) and MANT the 24 or 56
; bit mantissa with its top bit set, so the value is MANT * 2^(EXP - 128 -
; bits).  Packed, a single is four bytes and a double eight, low first: the
; mantissa without its top bit, the sign in that bit's place, the exponent.
;
; The arithmetic is the 8086's.  A single works in 32 bits, the mantissa
; and a guard byte whose bit $20 is a sticky bit; $ROUNS keeps the guard
; byte's top three bits and rounds half to even.  A double works in 64 bits
; with an overflow byte.  The multiplies keep what the source keeps: a
; single's drops the lowest partial product's low word; a double's is
; exact, its low bytes a sticky bit.  The divides are exact, rounded half
; to even.  A double goes to a single on the byte below the single's
; mantissa alone, half rounding up.
;
; Where the 8086 BASIC prints "Overflow" or "Division by zero" and goes on
; with the largest number, these raise 'basic-overflow or 'basic-div0, the
; text the kind and sign ("4+", "8-") and that number the value in its
; data (m86-raise).  An
; integer that will not fit is ?OV, 'basic "OV", as FRCINT's error is.

(module basic/mbf86)
(import x/type/list)
(import x/type/str)
(import x/type/vector)
(import x/type/err)
(import x/core/doors int+ int- int* int/ int% int< int= int<< int>> int& int| str-byte-ref)

(def %m86-mask32 (int- (int<< 1 32) 1))
(def %m86-two24 (int<< 1 24))
(def %m86-two56 (int<< 1 56))
(def %m86-mask56 (int- (int<< 1 56) 1))

; --- values ---------------------------------------------------------------

(def m86-int (fn (_ n) (list 2 n)))
(def m86-kind (fn (_ v) (first v)))
(def m86-integer (fn (_ v) (List second v)))

(def %m86-neg? (fn (_ v) (List second v)))
(def %m86-exp (fn (_ v) (List third v)))
(def %m86-mant (fn (_ v) (List ref 3 v)))
(def %m86-bits (fn (_ k) (if (int= k 8) 56 24)))

(def %m86-zero (fn (_ k) (list k #f 0 0)))

; A float, zero when its exponent is
(def %m86-make
  (fn (_ k neg e m) (if (int= e 0) (%m86-zero k) (list k neg e m))))

(def m86-zero?
  (fn (_ v) (if (int= (first v) 2) (int= (List second v) 0) (int= (%m86-exp v) 0))))

(def %m86-word? (fn (_ n) (and (not (int< n -32768)) (not (int< 32767 n)))))

; --- the overflow ---------------------------------------------------------

(def %m86-sign-text
  (fn (_ k neg) (Str8 append (if (int= k 8) "8" "4") (if neg "-" "+"))))

; The largest number of kind K and sign NEG, as DOINF gives it
(def m86-infinity
  (fn (_ k neg) (list k neg 255 (if (int= k 8) %m86-mask56 (int- %m86-two24 1)))))

; The overflow or the division by zero LABEL raised with V, the number the
; BASIC goes on with, as its value
(def m86-raise
  (fn (_ label v)
    (Err raise label (%m86-sign-text (first v) (%m86-neg? v)) (list (pair (lit value) v)))))

(def %m86-overflow (fn (_ k neg) (m86-raise (lit basic-overflow) (m86-infinity k neg))))
(def %m86-div0 (fn (_ k neg) (m86-raise (lit basic-div0) (m86-infinity k neg))))
(def %m86-ov (fn (_) (Err raise (lit basic) "OV")))

; --- single precision -----------------------------------------------------

; R, the 24-bit mantissa and the guard byte, rounded and packed ($ROUNM): up
; when the guard's top bit is set, to even when it is exactly half
(def %s-rounm
  (fn (_ neg e r)
    (let ((ah (int& r 255)) (m (int>> r 8)))
      (if (int< ah 128) (%m86-make 4 neg e m)
        (let ((m1 (int+ m 1)))
          (match
            ((int= m1 %m86-two24)
              (if (int= e 255) (%m86-overflow 4 neg) (%m86-make 4 neg (int+ e 1) (int<< 1 23))))
            ; DX wrapped: the result is even
            ((int= (int& m1 65535) 0) (%m86-make 4 neg e m1))
            ((int= ah 128) (%m86-make 4 neg e (int- m1 (int& m1 1))))
            (#t (%m86-make 4 neg e m1))))))))

; $ROUNS: the guard byte's low five bits cleared first
(def %s-rounds
  (fn (_ neg e r) (%s-rounm neg e (int- r (int& r 31)))))

; $NORMS: R shifted left, a byte while its top byte is zero, then a bit,
; the exponent following; zero when the exponent runs out
(def %s-norms
  (fn (_ neg e r)
    (let ((go (fn (self e r)
                (let ((bl (int>> r 24)))
                  (match
                    ((not (int< bl 128)) (%s-rounds neg e r))
                    ((not (int= bl 0))
                      (if (int= e 1) (%m86-zero 4) (self (int- e 1) (int& (int<< r 1) %m86-mask32))))
                    ((int< e 9) (%m86-zero 4))
                    (#t (self (int- e 8) (int& (int<< r 8) %m86-mask32))))))))
      (if (int= r 0) (%m86-zero 4) (go e r)))))

; The smaller addend S, 32 bits, shifted right D bits as $FADDS shifts it:
; a byte at a time while it can, then a bit, any bit lost setting $20
(def %s-align
  (fn (_ s d)
    (match
      ((int= d 0) s)
      ((not (int< d 8))
        (let ((t (int>> s 8)))
          (let ((t (if (int= (int& s 255) 0) t (int| t 32))))
            (%s-align (if (int= (int& t 31) 0) t (int| t 32)) (int- d 8)))))
      (#t
        (let ((t (int>> s 1)))
          (%s-align (if (int= (int& t 16) 0) t (int| t 32)) (int- d 1)))))))

; A + B, singles ($FADDS)
(def %s-add
  (fn (_ a b)
    (match
      ((int= (%m86-exp b) 0) a)
      ((int= (%m86-exp a) 0) b)
      (#t
        (let ((swap (int< (%m86-exp a) (%m86-exp b))))
          (let ((x (if swap b a)) (y (if swap a b)))
            (let ((d (int- (%m86-exp x) (%m86-exp y))) (neg (%m86-neg? x)) (e (%m86-exp x)))
              ; the smaller is lost past 24 bits, and the larger kept as it is
              (if (not (int< d 25)) x
                (let ((s (%s-align (int<< (%m86-mant y) 8) d)) (big (int<< (%m86-mant x) 8)))
                  (if (eq? (%m86-neg? x) (%m86-neg? y))
                    (let ((r (int+ big s)))
                      (if (int< r (int<< 1 32)) (%s-rounds neg e r)
                        (if (int= e 255) (%m86-overflow 4 neg)
                          (%s-rounds neg (int+ e 1) (int>> r 1)))))
                    (let ((r (int- big s)))
                      (if (int< r 0) (%s-norms (not neg) e (int- 0 r)) (%s-norms neg e r)))))))))))))

; The product's exponent as $AEXPS sums them: nil when it underflows, ?OV
; past 255
(def %m86-aexps
  (fn (_ k neg e1 e2)
    (let ((raw (int- (int+ e1 e2) 257)))
      (match
        ((int< raw 0) (if (int< (int+ raw 128) 0) () (int+ raw 128)))
        ((int< raw 128) (int+ raw 128))
        (#t (%m86-overflow k neg))))))

; A * B, singles ($FMULS): the 48-bit product from four 16-bit partial
; products, the lowest one's low word dropped
(def %s-mul
  (fn (_ a b)
    (if (or (int= (%m86-exp a) 0) (int= (%m86-exp b) 0)) (%m86-zero 4)
      (let ((neg (not (eq? (%m86-neg? a) (%m86-neg? b)))))
        (let ((e (%m86-aexps 4 neg (%m86-exp a) (%m86-exp b))))
          (if (null? e) (%m86-zero 4)
            (let ((ma (%m86-mant a)) (mb (%m86-mant b)))
              (let ((ah (int>> ma 16)) (al (int& ma 65535)) (bh (int>> mb 16)) (bl (int& mb 65535)))
                (let ((s (int+ (int+ (int>> (int* al bl) 16) (int* al bh))
                               (int+ (int* bl ah) (int<< (int* ah bh) 16)))))
                  (if (not (int< s (int<< 1 31)))
                    (if (int= e 255) (%m86-overflow 4 neg) (%s-rounds neg (int+ e 1) s))
                    (%s-rounds neg e (int& (int<< s 1) %m86-mask32))))))))))))

; A quotient Q of BITS bits with a sticky bit at its bottom, normalised and
; rounded half to even on its low byte, as $SDIV and $DDIV finish
(def %m86-div-round
  (fn (_ k neg e q bits)
    (let ((top (int<< 1 (int- bits 1))) (mask (int- (int<< 1 bits) 1)) (mbits (int- bits 8)))
      (let ((norm (if (not (int< q top))
                    (if (int= e 255) (%m86-overflow k neg) (pair (int+ e 1) q))
                    (if (int= e 0) () (pair e (int& (int<< q 1) mask))))))
        (if (null? norm) (%m86-zero k)
          (let ((e (first norm)) (q (rest norm)))
            (let ((dl (int& q 255)) (m (int>> q 8)))
              (if (or (int< 128 dl) (and (int= dl 128) (int= (int& m 1) 1)))
                (let ((m1 (int+ m 1)))
                  (if (int= m1 (int<< 1 mbits))
                    (if (int= e 255) (%m86-overflow k neg)
                      (%m86-make k neg (int+ e 1) (int<< 1 (int- mbits 1))))
                    (%m86-make k neg e m1)))
                (%m86-make k neg e m)))))))))

; The exponent of A / B, or nil when it underflows; ?OV past 255
(def %m86-dexp
  (fn (_ k neg a b)
    (let ((diff (int- (%m86-exp a) (%m86-exp b))))
      (match
        ((int< 127 diff) (%m86-overflow k neg))
        ((int< diff -128) ())
        (#t (int+ diff 128))))))

; A / B, singles ($SDIV): 32 quotient bits, a remainder setting the last
(def %s-div
  (fn (_ a b)
    (match
      ((int= (%m86-exp b) 0) (%m86-div0 4 (%m86-neg? a)))
      ((int= (%m86-exp a) 0) (%m86-zero 4))
      (#t
        (let ((neg (not (eq? (%m86-neg? a) (%m86-neg? b)))))
          (let ((e (%m86-dexp 4 neg a b)))
            (if (null? e) (%m86-zero 4)
              (let ((n (int<< (%m86-mant a) 31)) (d (%m86-mant b)))
                (let ((q (int/ n d)))
                  (%m86-div-round 4 neg e (if (int= (int% n d) 0) q (int| q 1)) 32))))))))))

; --- double precision -----------------------------------------------------

; A double at work is (M . O): the 56-bit mantissa and the overflow byte.

; M and O rounded and packed ($ROUND): half adds to the overflow byte, and
; a carry rounds up, to even when the byte was exactly half
(def %d-round
  (fn (_ neg e m o)
    (if (int< o 128) (%m86-make 8 neg e m)
      (let ((m1 (int+ m 1)))
        (let ((up (if (int= m1 %m86-two56)
                    (if (int= e 255) (%m86-overflow 8 neg) (pair (int+ e 1) (int<< 1 55)))
                    (pair e m1))))
          (let ((m2 (rest up)))
            (%m86-make 8 neg (first up) (if (int= o 128) (int- m2 (int& m2 1)) m2))))))))

; $NORMD: shifted left a byte while the top byte is zero, then a bit; zero
; when the exponent or the 57 bits allowed run out
(def %d-normd
  (fn (_ neg e m o)
    (let ((go (fn (self e m o dl)
                (let ((top (int>> m 48)))
                  (match
                    ((not (int< top 128)) (%d-round neg e m o))
                    ((not (int= top 0))
                      (if (or (int= e 1) (int= dl 1)) (%m86-zero 8)
                        (self (int- e 1) (int& (int| (int<< m 1) (int>> o 7)) %m86-mask56)
                              (int& (int<< o 1) 255) (int- dl 1))))
                    ((or (int< e 9) (int< dl 9)) (%m86-zero 8))
                    (#t (self (int- e 8) (int& (int| (int<< m 8) o) %m86-mask56) 0 (int- dl 8))))))))
      (if (and (int= m 0) (int= o 0)) (%m86-zero 8) (go e m o 57)))))

; The smaller addend (M . O) shifted right D bits as $SHRA shifts it: a byte
; at a time, the old overflow byte's $20 kept, then a bit, bit $10 setting $20
(def %d-align
  (fn (_ m o d)
    (match
      ((int= d 0) (pair m o))
      ((not (int< d 8))
        (%d-align (int>> m 8) (int| (int& m 255) (int& o 32)) (int- d 8)))
      (#t
        (let ((o2 (int| (int<< (int& m 1) 7) (int>> o 1))))
          (%d-align (int>> m 1) (if (int= (int& o2 16) 0) o2 (int| o2 32)) (int- d 1)))))))

; A + B, doubles ($FADDD)
(def %d-add
  (fn (_ a b)
    (match
      ((int= (%m86-exp b) 0) a)
      ((int= (%m86-exp a) 0) b)
      (#t
        (let ((swap (int< (%m86-exp a) (%m86-exp b))))
          (let ((x (if swap b a)) (y (if swap a b)))
            (let ((d (int- (%m86-exp x) (%m86-exp y))) (neg (%m86-neg? x)) (e (%m86-exp x)))
              (if (not (int< d 57)) x
                (let ((s (%d-align (%m86-mant y) 0 d)) (mx (%m86-mant x)))
                  (if (eq? (%m86-neg? x) (%m86-neg? y))
                    (let ((m (int+ mx (first s))) (o (rest s)))
                      (if (int< m %m86-two56) (%d-round neg e m o)
                        (if (int= e 255) (%m86-overflow 8 neg)
                          (%d-round neg (int+ e 1) (int>> m 1) (int| (int<< (int& m 1) 7) (int>> o 1))))))
                    (let ((borrow (if (int= (rest s) 0) 0 1)))
                      (let ((m (int- (int- mx (first s)) borrow)) (o (int& (int- 0 (rest s)) 255)))
                        (if (not (int< m 0)) (%d-normd neg e m o)
                          (if (int= o 0) (%d-normd (not neg) e (int- 0 m) 0)
                            (%d-normd (not neg) e (int- -1 m) (int- 256 o))))))))))))))))

; MA * MB, 56-bit mantissas, as (HI . LO): the 112-bit product in two
; 56-bit halves, made of 28-bit pieces
(def %d-product
  (fn (_ ma mb)
    (let ((m28 (int- (int<< 1 28) 1)))
      (let ((a1 (int>> ma 28)) (a0 (int& ma m28)) (b1 (int>> mb 28)) (b0 (int& mb m28)))
        (let ((mid (int+ (int* a1 b0) (int* a0 b1))))
          (let ((t (int+ (int* a0 b0) (int<< (int& mid m28) 28))))
            (pair (int+ (int+ (int* a1 b1) (int>> mid 28)) (int>> t 56))
                  (int& t %m86-mask56))))))))

; A * B, doubles ($FMULD): the exact product, its bytes below the overflow
; byte a sticky bit
(def %d-mul
  (fn (_ a b)
    (if (or (int= (%m86-exp a) 0) (int= (%m86-exp b) 0)) (%m86-zero 8)
      (let ((neg (not (eq? (%m86-neg? a) (%m86-neg? b)))))
        (let ((e (%m86-aexps 8 neg (%m86-exp a) (%m86-exp b))))
          (if (null? e) (%m86-zero 8)
            (let ((p (%d-product (%m86-mant a) (%m86-mant b))))
              (let ((m (first p))
                    (o (let ((o (int& (int>> (rest p) 48) 255)))
                         (if (int= (int& (rest p) (int- (int<< 1 48) 1)) 0) o (int| o 32)))))
                (if (not (int< m (int<< 1 55)))
                  (if (int= e 255) (%m86-overflow 8 neg) (%d-round neg (int+ e 1) m o))
                  (%d-round neg e (int& (int| (int<< m 1) (int>> o 7)) %m86-mask56) (int& (int<< o 1) 255)))))))))))

; floor(N * 2^63 / D), N and D mantissas, by long division: (HI LO REM),
; HI and LO its 32-bit halves
(def %d-quotient
  (fn (_ n d)
    (let ((go (fn (self i r hi lo)
                (if (int= i 64) (list hi lo r)
                  (let ((r2 (if (int= i 0) r (int<< r 1))))
                    (let ((bit (if (int< r2 d) 0 1)))
                      (let ((r3 (if (int= bit 0) r2 (int- r2 d))))
                        (if (int< i 32)
                          (self (int+ i 1) r3 (int| (int<< hi 1) bit) lo)
                          (self (int+ i 1) r3 hi (int| (int<< lo 1) bit))))))))))
      (go 0 n 0 0))))

; A / B, doubles ($DDIV): 64 quotient bits, a remainder setting the last
(def %d-div
  (fn (_ a b)
    (let ((neg (not (eq? (%m86-neg? a) (%m86-neg? b)))))
      (match
        ((int= (%m86-exp b) 0) (%m86-div0 8 neg))
        ((int= (%m86-exp a) 0) (%m86-zero 8))
        (#t
          (let ((e (%m86-dexp 8 neg a b)))
            (if (null? e) (%m86-zero 8)
              (let ((q (%d-quotient (%m86-mant a) (%m86-mant b))))
                (let ((hi (first q)) (lo (if (int= (List third q) 0) (List second q) (int| (List second q) 1))))
                  ; the quotient's 64 bits are worked in halves, as the
                  ; word does not hold them
                  (let ((norm (if (not (int< hi (int<< 1 31)))
                                (if (int= e 255) (%m86-overflow 8 neg) (list (int+ e 1) hi lo))
                                (if (int= e 0) ()
                                  (list e (int& (int| (int<< hi 1) (int>> lo 31)) %m86-mask32)
                                        (int& (int<< lo 1) %m86-mask32))))))
                    (if (null? norm) (%m86-zero 8)
                      (let ((e (first norm)) (hi (List second norm)) (lo (List third norm)))
                        (let ((dl (int& lo 255)) (m (int| (int<< hi 24) (int>> lo 8))))
                          (if (or (int< 128 dl) (and (int= dl 128) (int= (int& m 1) 1)))
                            (let ((m1 (int+ m 1)))
                              (if (int= m1 %m86-two56)
                                (if (int= e 255) (%m86-overflow 8 neg) (%m86-make 8 neg (int+ e 1) (int<< 1 55)))
                                (%m86-make 8 neg e m1)))
                            (%m86-make 8 neg e m)))))))))))))))

; --- conversions ----------------------------------------------------------

; The integer N as a single ($FLT): exact
(def %m86-flt
  (fn (_ n)
    (if (int= n 0) (%m86-zero 4)
      (%s-norms (int< n 0) 144 (int<< (if (int< n 0) (int- 0 n) n) 16)))))

; A double as a single ($CSD): the byte below the single's mantissa, its
; bit $40 set, rounds; the bytes below it are not looked at
(def %m86-csd
  (fn (_ v)
    (if (int= (%m86-exp v) 0) (%m86-zero 4)
      (let ((m (%m86-mant v)))
        (%s-rounm (%m86-neg? v) (%m86-exp v)
          (int| (int<< (int>> m 32) 8) (int| (int& (int>> m 24) 255) 64)))))))

; A single as a double ($CDS): exact
(def %m86-cds
  (fn (_ v) (list 8 (%m86-neg? v) (%m86-exp v) (int<< (%m86-mant v) 32))))

(def m86->single
  (fn (_ v)
    (match
      ((int= (first v) 2) (%m86-flt (m86-integer v)))
      ((int= (first v) 8) (%m86-csd v))
      (#t v))))

(def m86->double
  (fn (_ v)
    (match
      ((int= (first v) 2) (%m86-cds (%m86-flt (m86-integer v))))
      ((int= (first v) 4) (%m86-cds v))
      (#t v))))

; V as an integer (FRCINT): the top 16 mantissa bits shifted into place and
; rounded on the last bit out, half away from zero; ?OV outside
; -32768..32767
(def m86-cint
  (fn (_ v)
    (if (int= (first v) 2) v
      (let ((e (int- (%m86-exp v) 128))
            (m24 (if (int= (first v) 8) (int>> (%m86-mant v) 32) (%m86-mant v)))
            (neg (%m86-neg? v)))
        (match
          ((or (int< e 0) (int= (%m86-exp v) 0)) (m86-int 0))
          ((int< 16 e) (%m86-ov))
          ; only -32768 has 16 bits; its next byte's top bit rounds it out
          ((int= e 16)
            (if (and neg (int= (int>> m24 8) 32768) (int< (int& m24 255) 128)) (m86-int -32768) (%m86-ov)))
          (#t
            (let ((u (int>> m24 8)) (cl (int- 16 e)))
              (let ((r (int+ (int>> u cl) (int& (int>> u (int- cl 1)) 1))))
                (match
                  ((not (int= r 32768)) (m86-int (if neg (int- 0 r) r)))
                  (neg (m86-int -32768))
                  (#t (%m86-ov)))))))))))

; |N| < 2^bits as a number of kind K, exactly
(def %m86-whole
  (fn (_ k neg n)
    (if (int= n 0) (%m86-zero k)
      (let ((top (int<< 1 (int- (%m86-bits k) 1))))
        (let ((go (fn (self m e) (if (int< m top) (self (int<< m 1) (int- e 1)) (list k neg e m)))))
          (go n (int+ 128 (%m86-bits k))))))))

; The largest whole number not above V, of V's kind ($INT, $DINT)
(def m86-floor
  (fn (_ v)
    (if (or (int= (first v) 2) (m86-zero? v)) v
      (let ((k (first v)) (top (int+ 128 (%m86-bits (first v)))))
        (if (not (int< (%m86-exp v) top)) v
          (let ((sh (int- top (%m86-exp v))) (m (%m86-mant v)))
            (let ((whole (if (int< 62 sh) 0 (int>> m sh))))
              (let ((exact (and (int< sh 63) (int= (int<< whole sh) m))))
                (if (not (%m86-neg? v)) (%m86-whole k #f whole)
                  (%m86-whole k #t (if exact whole (int+ whole 1))))))))))))

; --- arithmetic -----------------------------------------------------------

; The kind two operands meet in: double if either is, then single
(def %m86-meet
  (fn (_ a b)
    (if (or (int= (first a) 8) (int= (first b) 8)) 8 (if (or (int= (first a) 4) (int= (first b) 4)) 4 2))))

(def %m86-as (fn (_ k v) (if (int= k 8) (m86->double v) (m86->single v))))

(def m86-neg
  (fn (_ v)
    (match
      ((int= (first v) 2)
        (if (int= (m86-integer v) -32768) (m86-neg (%m86-flt -32768)) (m86-int (int- 0 (m86-integer v)))))
      ((m86-zero? v) v)
      (#t (list (first v) (not (%m86-neg? v)) (%m86-exp v) (%m86-mant v))))))

(def m86-abs
  (fn (_ v)
    (if (int= (first v) 2)
      (if (int< (m86-integer v) 0) (m86-neg v) v)
      (if (%m86-neg? v) (m86-neg v) v))))

; -1, 0 or 1, an integer
(def m86-sgn
  (fn (_ v)
    (m86-int
      (if (int= (first v) 2)
        (match ((int< (m86-integer v) 0) -1) ((int= (m86-integer v) 0) 0) (#t 1))
        (match ((m86-zero? v) 0) ((%m86-neg? v) -1) (#t 1))))))

; A + B, A - B and A * B: integers stay integers until they will not fit,
; then are floated and the singles' arithmetic done (IADD, ISUB, IMULT)
(def m86-add
  (fn (_ a b)
    (let ((k (%m86-meet a b)))
      (match
        ((int= k 2)
          (let ((s (int+ (m86-integer a) (m86-integer b))))
            (if (%m86-word? s) (m86-int s) (%s-add (%m86-flt (m86-integer a)) (%m86-flt (m86-integer b))))))
        ((int= k 4) (%s-add (m86->single a) (m86->single b)))
        (#t (%d-add (m86->double a) (m86->double b)))))))

(def m86-sub
  (fn (_ a b)
    (if (and (int= (%m86-meet a b) 2) (int= (m86-integer b) -32768))
      ; ISUB: -32768.0 less A, negated, then made an integer again
      (m86-cint (m86-neg (%s-add (%m86-flt -32768) (m86-neg (%m86-flt (m86-integer a))))))
      (m86-add a (m86-neg b)))))

(def m86-mul
  (fn (_ a b)
    (let ((k (%m86-meet a b)))
      (match
        ((int= k 2)
          (let ((p (int* (m86-integer a) (m86-integer b))))
            (if (%m86-word? p) (m86-int p) (%s-mul (%m86-flt (m86-integer a)) (%m86-flt (m86-integer b))))))
        ((int= k 4) (%s-mul (m86->single a) (m86->single b)))
        (#t (%d-mul (m86->double a) (m86->double b)))))))

; A / B: a single unless a double is in it (INTDIV floats integers)
(def m86-div
  (fn (_ a b)
    (if (int= (%m86-meet a b) 8) (%d-div (m86->double a) (m86->double b))
      (%s-div (m86->single a) (m86->single b)))))

; A \ B, each made an integer first (IDIV): truncated toward zero; the one
; quotient that will not fit, -32768 \ -1, a single
(def m86-idiv
  (fn (_ a b)
    (let ((x (m86-integer (m86-cint a))) (y (m86-integer (m86-cint b))))
      (match
        ((int= y 0) (%m86-div0 4 (int< x 0)))
        ((and (int= x -32768) (int= y -1)) (m86-neg (%m86-flt -32768)))
        (#t (m86-int (int/ x y)))))))

; A MOD B, each made an integer first (IMOD): the remainder, its sign A's
(def m86-mod
  (fn (_ a b)
    (let ((x (m86-integer (m86-cint a))) (y (m86-integer (m86-cint b))))
      (match
        ((int= x y) (m86-int 0))
        ((int= y 0) (%m86-div0 4 (int< x 0)))
        (#t (m86-int (int% x y)))))))

; -1, 0 or 1 as A is below, equal to or above B, compared exactly in the
; kind they meet in
(def m86-cmp
  (fn (_ a b)
    (let ((k (%m86-meet a b)))
      (if (int= k 2)
        (let ((x (m86-integer a)) (y (m86-integer b)))
          (match ((int< x y) -1) ((int< y x) 1) (#t 0)))
        (let ((a (%m86-as k a)) (b (%m86-as k b)))
          (let ((sa (m86-integer (m86-sgn a))) (sb (m86-integer (m86-sgn b))))
            (match
              ((int< sa sb) -1)
              ((int< sb sa) 1)
              ((int= sa 0) 0)
              (#t
                (let ((c (match
                           ((int< (%m86-exp a) (%m86-exp b)) -1)
                           ((int< (%m86-exp b) (%m86-exp a)) 1)
                           ((int< (%m86-mant a) (%m86-mant b)) -1)
                           ((int< (%m86-mant b) (%m86-mant a)) 1)
                           (#t 0))))
                  (if (int< sa 0) (int- 0 c) c))))))))))

; --- packed bytes ---------------------------------------------------------

; V's bytes as memory holds them, low first
(def m86->bytes
  (fn (_ v)
    (let ((k (first v)))
      (if (int= k 2)
        (let ((w (int& (m86-integer v) 65535))) (list (int& w 255) (int>> w 8)))
        (let ((n (int- k 1)) (m (%m86-mant v)))
          (if (m86-zero? v) (List map (fn (_ i) 0) (List range 0 k))
            (List append
              (List map (fn (_ i) (int& (int>> m (int* 8 i)) 255)) (List range 0 (int- n 1)))
              (list (int| (int& (int>> m (int* 8 (int- n 1))) 127) (if (%m86-neg? v) 128 0))
                    (%m86-exp v)))))))))

; The number of kind K in BYTES, low first
(def m86-from-bytes
  (fn (_ k bytes)
    (if (int= k 2)
      (let ((w (int| (first bytes) (int<< (List second bytes) 8))))
        (m86-int (if (int< w 32768) w (int- w 65536))))
      (let ((n (int- k 1)))
        (let ((ex (List ref n bytes)) (top (List ref (int- n 1) bytes)))
          (if (int= ex 0) (%m86-zero k)
            (list k (not (int< top 128)) ex
              (List fold (fn (_ m i) (int| m (int<< (List ref i bytes) (int* 8 i))))
                (int<< (int| top 128) (int* 8 (int- n 1)))
                (List range 0 (int- n 1))))))))))

; A table's bytes as the source writes them, in octal: 201 is $81
(def %m86-octal
  (fn (_ n) (int+ (int* (int/ n 100) 64) (int+ (int* (int% (int/ n 10) 10) 8) (int% n 10)))))

(def %m86-octal-double
  (fn (_ bytes) (m86-from-bytes 8 (List map %m86-octal bytes))))

; --- constants ------------------------------------------------------------

(def %m86-half-single (list 4 #f 128 (int<< 1 23)))
(def %m86-half-double (list 8 #f 128 (int<< 1 55)))
(def %m86-ten-single (list 4 #f 132 (int<< 10 20)))
(def %m86-ten-double (list 8 #f 132 (int<< 10 52)))

; $DPM01, .1, which $DIV10 multiplies a double by
(def %m86-tenth (%m86-octal-double (list 315 314 314 314 314 314 114 175)))

; HIDBL, 9999999999999999., the largest double a half can be added to
(def %m86-hidbl (%m86-octal-double (list 375 377 3 277 311 33 16 266)))

; The double powers of ten 10^0 to 10^38, $DP00 on: those past 10^24 as
; the source rounds them
(def %m86-powers
  (Vector from-list
    (List map %m86-octal-double
      (list
        (list 0 0 0 0 0 0 0 201) (list 0 0 0 0 0 0 40 204) (list 0 0 0 0 0 0 110 207)
        (list 0 0 0 0 0 0 172 212) (list 0 0 0 0 0 100 34 216) (list 0 0 0 0 0 120 103 221)
        (list 0 0 0 0 0 44 164 224) (list 0 0 0 0 200 226 30 230) (list 0 0 0 0 40 274 76 233)
        (list 0 0 0 0 50 153 156 236) (list 0 0 0 0 371 2 25 242) (list 0 0 0 100 267 103 72 245)
        (list 0 0 0 20 245 324 150 250) (list 0 0 0 52 347 204 21 254) (list 0 0 200 364 40 346 65 257)
        (list 0 0 240 61 251 137 143 262) (list 0 0 4 277 311 33 16 266) (list 0 0 305 56 274 242 61 271)
        (list 0 100 166 72 153 13 136 274) (list 0 350 211 4 43 307 12 300) (list 0 142 254 305 353 170 55 303)
        (list 200 172 27 267 46 327 130 306) (list 220 254 156 62 170 206 7 312) (list 264 127 12 77 26 150 51 315)
        (list 241 355 314 316 33 302 123 320) (list 205 24 100 141 121 131 4 324) (list 246 31 220 271 245 157 45 327)
        (list 17 40 364 47 217 313 116 332) (list 12 224 370 170 71 77 1 336) (list 14 271 66 327 7 217 41 341)
        (list 117 147 4 315 311 362 111 344) (list 43 201 105 100 174 157 174 347) (list 266 160 53 250 255 305 35 353)
        (list 343 114 66 22 31 67 105 356) (list 34 340 303 126 337 204 166 361) (list 21 154 72 226 13 23 32 365)
        (list 26 7 311 173 316 227 100 370) (list 333 110 273 32 302 275 160 373) (list 211 15 265 120 231 166 26 377)))))

; $FOTB: by a number's exponent byte, the power of ten $FOTNV scales it by
; toward 10^6, or 0 when it is there
(def %m86-fotb
  (Vector from-list
    (list
      38 38 38 38 38 38 38 38  38 38 38 38 38 38 38 38  38 38 38 38 38 38 38 38
      38 37 37 37 36 36 36 35  35 35 34 34 34 34 33 33  33 32 32 32 31 31 31 31
      30 30 30 29 29 29 29 28  28 28 27 27 27 26 26 26  25 25 25 25 24 24 24 23
      23 23 23 22 22 22 22 21  21 21 20 20 20 19 19 19  19 18 18 18 17 17 17 16
      16 16 16 15 15 15 14 14  14 13 13 13 13 12 12 12  11 11 11 10 10 10 10 9
      9 9 8 8 8 7 7 7  6 6 6 6 5 5 5 4  4 4 3 3 3 3 2 2
      2 1 1 1 0 0 0 0  -1 -1 -1 -2 -2 -2 -3 -3  -3 -3 -4 -4 -4 -5 -5 -5
      -6 -6 -6 -6 -7 -7 -7 -8  -8 -8 -9 -9 -9 -9 -10 -10  -10 -11 -11 -11 -12 -12 -12 -12
      -13 -13 -13 -14 -14 -14 -15 -15  -15 -15 -16 -16 -16 -17 -17 -17  -18 -18 -18 -18 -19 -19 -19 -20
      -20 -20 -21 -21 -21 -21 -22 -22  -22 -23 -23 -23 -24 -24 -24 -25  -25 -25 -25 -26 -26 -26 -27 -27
      -27 -28 -28 -28 -28 -29 -29 -29  -30 -30 -30 -31 -31 -31 -31 -32)))

; V, any kind, times ten to the K (MDPTEN): worked as a double by the
; table's powers, two divides past 10^-38, and made a single again unless
; it was a double; ?OV past 10^38
(def %m86-scale10
  (fn (_ v k)
    (let ((kind (first v)) (d (m86->double v)))
      (let ((r (match
                 ((int= (%m86-exp d) 0) d)
                 ((int< 38 k) (%m86-overflow (if (int= kind 8) 8 4) (%m86-neg? d)))
                 ((not (int< k 0)) (%d-mul d (Vector ref k %m86-powers)))
                 ((not (int< k -38)) (%d-div d (Vector ref (int- 0 k) %m86-powers)))
                 ((int< (int+ k 38) -38) (%m86-zero 8))
                 (#t (%d-div (%d-div d (Vector ref (int- 0 (int+ k 38)) %m86-powers))
                             (Vector ref 38 %m86-powers))))))
        (if (int= kind 8) r (%m86-csd r))))))

; --- decimal text out -----------------------------------------------------

(def %m86-digits
  (fn (_ n)
    (let ((go (fn (self n acc) (if (int< n 10) (pair (int+ 48 n) acc) (self (int/ n 10) (pair (int+ 48 (int% n 10)) acc))))))
      (go n ()))))

; Whether the positive V is a whole number
(def %m86-whole?
  (fn (_ v)
    (let ((sh (int- (int+ 128 (%m86-bits (first v))) (%m86-exp v))))
      (match
        ((not (int< 0 sh)) #t)
        ((int< (%m86-bits (first v)) sh) #f)
        (#t (int= (int& (%m86-mant v) (int- (int<< 1 sh) 1)) 0))))))

; The positive V truncated, an x integer (QINT, $FTDNT)
(def %m86-trunc
  (fn (_ v)
    (let ((sh (int- (int+ 128 (%m86-bits (first v))) (%m86-exp v))))
      (match
        ((not (int< 0 sh)) (int<< (%m86-mant v) (int- 0 sh)))
        ((int< 62 sh) 0)
        (#t (int>> (%m86-mant v) sh))))))

(def %m86-mul10
  (fn (_ v) (if (int= (first v) 8) (%d-mul v %m86-ten-double) (%s-mul v %m86-ten-single))))

; Whether V's top 32 bits are under 10^6's as a single ($COMPM)
(def %m86-below-million?
  (fn (_ v)
    (let ((e (%m86-exp v)) (m (if (int= (first v) 8) (int>> (%m86-mant v) 32) (%m86-mant v))))
      (or (int< e 148) (and (int= e 148) (int< m 16000000))))))

; The positive V scaled so its 7 or 16 printable digits are its whole part
; ($FOTNV): (V . E), V times ten to the E the number
(def %m86-fotnv
  (fn (_ v)
    (let ((go (fn (self v e)
                (let ((t (Vector ref (%m86-exp v) %m86-fotb)))
                  (if (int= t 0) (pair v e) (self (%m86-scale10 v t) (int- e t)))))))
      (let ((got (let ((got (go v 0)))
                   (if (%m86-below-million? (first got)) (pair (%m86-mul10 (first got)) (int- (rest got) 1)) got))))
        (if (int= (first v) 4) got
          (let ((w (%d-mul (first got) (Vector ref 9 %m86-powers))) (e (int- (rest got) 9)))
            (if (int< 0 (m86-cmp w %m86-hidbl)) (pair (%d-mul w %m86-tenth) (int+ e 1)) (pair w e))))))))

; The scaled V's digits ($FOTCV): a half added unless it is whole, then
; its integer part's digits by powers of ten, the first counting past 9
; when the half carried it to the next power
(def %m86-fotcv
  (fn (_ v)
    (let ((single (int= (first v) 4)))
      (let ((n (%m86-trunc (if (%m86-whole? v) v
                             (if single (%s-add v %m86-half-single) (%d-add v %m86-half-double))))))
        (let ((go (fn (self n k acc)
                    (if (int< k 0) (List reverse acc)
                      (let ((p (List fold (fn (_ a i) (int* a 10)) 1 (List range 0 k))))
                        (self (int% n p) (int- k 1) (pair (int+ 48 (int/ n p)) acc)))))))
          (go n (if single 6 15) ()))))))

(def %m86-zeros (fn (_ n) (List map (fn (_ i) 48) (List range 0 n))))

; BYTES without trailing zeros, then without a trailing point
(def %m86-trim
  (fn (_ bytes)
    (let ((r (List drop-while (fn (_ b) (int= b 48)) (List reverse bytes))))
      (List reverse (if (and (not (null? r)) (int= (first r) 46)) (rest r) r)))))

(def %m86-trailing-zeros
  (fn (_ ds) (int- (List length ds) (List length (List drop-while (fn (_ b) (int= b 48)) (List reverse ds))))))

; DIGITS, the number DIGITS times ten to the E, laid out as $FOFMT lays
; it: fixed when its digits sit within the 7 or 16 places, E or D notation
; else, trailing zeros dropped
(def %m86-layout
  (fn (_ ds e letter)
    (let ((n (List length ds)))
      (let ((fixed (fn (_ p)
                     (%m86-trim
                       (if (int< p 0)
                         (pair 46 (List append (%m86-zeros (int- 0 p)) ds))
                         (List append (List take p ds) (pair 46 (List drop p ds)))))))
            (sci (fn (_)
                   (let ((x (int- (int+ e n) 1)))
                     (let ((ax (if (int< x 0) (int- 0 x) x)))
                       (List append (%m86-trim (pair (first ds) (pair 46 (rest ds))))
                         (list letter (if (int< x 0) 45 43) (int+ 48 (int/ ax 10)) (int+ 48 (int% ax 10)))))))))
        (match
          ((int< 0 e) (sci))
          ((not (int< (int+ e n) 0)) (fixed (int+ e n)))
          ((int< 0 (int+ (int+ (int+ e n) 1) (%m86-trailing-zeros ds))) (fixed (int+ e n)))
          (#t (sci)))))))

; V as PRINT and STR$ give it: a sign or a space, then the digits
(def m86->str
  (fn (_ v)
    (if (int= (first v) 2)
      (let ((n (m86-integer v)))
        (bytes->str (pair (if (int< n 0) 45 32) (%m86-digits (if (int< n 0) (int- 0 n) n)))))
      (if (m86-zero? v) " 0"
        (let ((got (%m86-fotnv (m86-abs v))))
          (bytes->str
            (pair (if (%m86-neg? v) 45 32)
                  (%m86-layout (%m86-fotcv (first got)) (rest got) (if (int= (first v) 8) 68 69)))))))))

; --- PRINT USING out ------------------------------------------------------

; PUFOUT builds the number in FBUFF and its routines move through it with
; BX; here a vector of slots: the buffer, BX, CH and CL (the counts $FOTED
; counts down to the point and the next comma) and $DPADR.  FBUFF is at
; %pu-fbuff, room before it for what $FOTZS and $PUFXE put ahead of the sign.
(def %pu-fbuff 4)

(def %pu-state
  (fn (_) (Vector from-list (list (Vector make 320 0) (int+ %pu-fbuff 1) 0 0 0))))

(def %pu-buf (fn (_ s) (Vector ref 0 s)))
(def %pu-bx (fn (_ s) (Vector ref 1 s)))
(def %pu-bx! (fn (_ s n) (Vector set! 1 n s)))
(def %pu-at (fn (_ s i) (Vector ref i (%pu-buf s))))
(def %pu-at! (fn (_ s i b) (Vector set! i b (%pu-buf s))))
(def %pu-regs! (fn (_ s ch cl) (do (Vector set! 2 (int& ch 255) s) (Vector set! 3 (int& cl 255) s))))

; B at BX, BX on
(def %pu-put!
  (fn (_ s b) (do (%pu-at! s (%pu-bx s) b) (%pu-bx! s (int+ (%pu-bx s) 1)))))

; $FOTED: the point when CH counts down to it, else a comma when CL does
(def %pu-foted!
  (fn (_ s)
    (let ((ch (int& (int- (Vector ref 2 s) 1) 255)))
      (if (int= ch 0)
        (do (Vector set! 4 (%pu-bx s) s) (%pu-put! s 46) (%pu-regs! s 0 0))
        (let ((cl (int& (int- (Vector ref 3 s) 1) 255)))
          (if (int= cl 0) (do (%pu-put! s 44) (%pu-regs! s ch 3)) (%pu-regs! s ch cl)))))))

; $FOTZ: N zeros
(def %pu-fotz!
  (fn (_ s n)
    (List for-each (fn (_ i) (%pu-put! s 48)) (List range 0 (int& n 255)))))

; $FOTZC: N zeros, $FOTED between them
(def %pu-fotzc!
  (fn (self s n)
    (do (%pu-put! s 48)
        (let ((n (int& (int- n 1) 255)))
          (unless (int= n 0) (%pu-foted! s) (self s n))))))

; DIGITS, $FOTED before each and after the last ($FOTCV, $FOTCI)
(def %pu-digits!
  (fn (_ s digits)
    (do (List for-each (fn (_ d) (%pu-foted! s) (%pu-put! s d)) digits)
        (%pu-foted! s))))

; The integer N's five digits ($FOTCI)
(def %pu-five
  (fn (_ n)
    (List map (fn (_ p) (int+ 48 (int% (int/ n p) 10))) (list 10000 1000 100 10 1))))

; CHRGTR on the buffer: BX on past blanks, the byte there
(def %pu-chrgt!
  (fn (self s)
    (do (%pu-bx! s (int+ (%pu-bx s) 1))
        (let ((b (%pu-at s (%pu-bx s))))
          (if (int= b 32) (self s) b)))))

(def %pu-end? (fn (_ b) (or (int= b 0) (int= b 58))))
(def %pu-digit? (fn (_ b) (and (not (int< b 48)) (int< b 58))))

; $FOTZS: leading zeros and commas made the fill, blanks or asterisks, a
; zero put back before a point or the end, then the floating $ and the
; sign; answers the sign when it trails, else nil
(def %pu-fotzs!
  (fn (_ s flags)
    (let ((fb (int+ %pu-fbuff 1)))
      (let ((sign (%pu-at s fb)) (star (not (int= (int& flags 32) 0)))
            (trails (not (int= (int& flags 4) 0))))
        (let ((sign (if (and star (int= sign 32) (not trails)) 42 sign)) (fill (if star 42 32)))
          (%pu-bx! s fb)
          (let ((scan (fn (self)
                        (do (%pu-at! s (%pu-bx s) fill)
                            (let ((b (%pu-chrgt! s)))
                              (match
                                ((%pu-end? b) (lit zero))
                                ((or (int= b 44) (int= b 48)) (self))
                                ((List includes? b (list 46 101 68)) (lit zero))
                                (#t (lit sign))))))))
            (when (eq? (scan) (lit zero))
              (%pu-bx! s (int- (%pu-bx s) 1)) (%pu-at! s (%pu-bx s) 48))
            (unless (int= (int& flags 16) 0)
              (%pu-bx! s (int- (%pu-bx s) 1)) (%pu-at! s (%pu-bx s) 36))
            (if trails sign
              (do (%pu-bx! s (int- (%pu-bx s) 1)) (%pu-at! s (%pu-bx s) sign) ()))))))))

; The buffer's bytes from I to its zero
(def %pu-from
  (fn (_ s i)
    (let ((go (fn (self i acc)
                (let ((b (%pu-at s i)))
                  (if (int= b 0) (List reverse acc) (self (int+ i 1) (pair b acc)))))))
      (go i ()))))

; $PUFXE: zero suppression, the trailing sign, then the field fitted to
; LEFT places before the point: leading blanks and asterisks dropped, and a
; leading zero before the point's digits, else a % ahead of it all
(def %pu-fixe!
  (fn (_ s flags left)
    (let ((end (%pu-bx s)))
      (let ((sign (%pu-fotzs! s flags)))
        (let ((end (if (null? sign) end (do (%pu-at! s end sign) (int+ end 1)))))
          (%pu-at! s end 0)
          (let ((fit (fn (self bx)
                       (if (int= (int- (int- (Vector ref 4 s) bx) left) 0) (%pu-from s bx)
                         (let ((b (%pu-at s bx)))
                           (if (or (int= b 32) (int= b 42)) (self (int+ bx 1))
                             (let ((start (int- bx 1)))
                               (%pu-bx! s start)
                               (let ((keep (fn (again acc)
                                             (let ((b (%pu-chrgt! s)))
                                               (match
                                                 ((List includes? b (list 45 43 36)) (again (pair b acc)))
                                                 ((and (int= b 48)
                                                       (do (%pu-bx! s (int+ (%pu-bx s) 1))
                                                           (%pu-digit? (%pu-chrgt! s))))
                                                   (let ((at (int- (%pu-bx s) 1)))
                                                     (List fold (fn (_ at b) (do (%pu-at! s (int- at 1) b) (int- at 1)))
                                                       at acc)))
                                                 (#t (do (%pu-at! s start 37) (lit percent))))))))
                                 (let ((got (keep ())))
                                   (if (eq? got (lit percent)) (%pu-from s start) (self got)))))))))))
            (fit (int+ %pu-fbuff 1))))))))

; $DIV10: times .1, a single by $DPM01 made one
(def %pu-div10
  (fn (_ v) (if (int= (first v) 8) (%d-mul v %m86-tenth) (%s-mul v (%m86-csd %m86-tenth)))))

(def %pu-div10s
  (fn (self v n) (if (int< n 1) v (self (%pu-div10 v) (int- n 1)))))

; $PUEXP: E or D, the sign and two digits
(def %pu-puexp!
  (fn (_ s kind x)
    (do (%pu-put! s (if (int= kind 8) 68 69))
        (%pu-put! s (if (int< x 0) 45 43))
        (let ((x (if (int< x 0) (int- 0 x) x)))
          (%pu-put! s (int+ 48 (int/ x 10)))
          (%pu-put! s (int+ 48 (int% x 10))))
        (%pu-at! s (%pu-bx s) 0))))

; Whether the sign takes a place of LEFT: some, and it leads
(def %pu-sign-place? (fn (_ flags left) (and (not (int= left 0)) (int= (int& flags 4) 0))))

; $PUFE: V, a positive single or double, in E or D notation
(def %pu-pufe!
  (fn (_ s v flags left right)
    (let ((kind (first v)) (zero (m86-zero? v)))
      (let ((n (if (int= kind 8) 16 7)))
        (let ((got (if zero (pair v 0) (%m86-fotnv v))))
          (let ((want (int- (int+ left (if (int= right 0) 0 (int- right 1)))
                            (if (%pu-sign-place? flags left) 1 0))))
            (let ((diff (int- want n)))
              (let ((r (if (not (int< diff 0)) (list (first got) (rest got) 0)
                         (let ((w (m86-floor ((if (int= kind 8) %d-add %s-add)
                                               (%pu-div10s (first got) (int- 0 diff))
                                               (if (int= kind 8) %m86-half-double %m86-half-single)))))
                           (let ((p (Vector ref (int+ n diff) %m86-powers)))
                             (if (int< (m86-cmp w (if (int= kind 8) p (%m86-csd p))) 0)
                               (list w (rest got) (int- 0 diff))
                               (list (%pu-div10 w) (int+ (rest got) 1) (int- 0 diff))))))))
                (let ((ch (int- (int+ (int+ (List third r) left) 1) (if (%pu-sign-place? flags left) 1 0))))
                  (%pu-regs! s ch 0)
                  (%pu-digits! s (%m86-fotcv (first r)))
                  (when (int< 0 diff) (%pu-fotzc! s diff) (%pu-foted! s))
                  (when (int= right 0)
                    (%pu-bx! s (int- (%pu-bx s) 1))
                    (unless (int= (%pu-at s (%pu-bx s)) 46) (%pu-bx! s (int+ (%pu-bx s) 1)))
                    (Vector set! 4 (%pu-bx s) s))
                  (%pu-puexp! s kind
                    (if zero (List second r)
                      (int+ (int- (int+ (List second r) n) left) (if (%pu-sign-place? flags left) 1 0))))
                  (%pu-fixe! s flags left))))))))))

; DPCOM: CH the places to the point, the sign's counted; CL to the first
; comma, when there are commas
(def %pu-dpcom!
  (fn (_ s flags ch dl cl)
    (let ((a (int+ (int- (int+ ch dl) cl) 1)))
      (let ((c (let ((go (fn (self c) (if (int< 0 c) (self (int- c 3)) c)))) (int+ (go (int- a 3)) 3))))
        (%pu-regs! s a (if (int= (int& flags 64) 0) 0 c))))))

; $PUIZ: no point when RIGHT is 0, else RIGHT - 1 zeros after it
(def %pu-puiz!
  (fn (_ s flags left right)
    (do (when (int= right 0) (%pu-bx! s (int- (%pu-bx s) 1)))
        (when (int< 1 right) (%pu-fotz! s (int- right 1)))
        (%pu-at! s (%pu-bx s) 0)
        (%pu-fixe! s flags left))))

; $PUF: V, a positive single or double, fixed: as FOUT gives it after a %
; from 10^16; else its digits rounded where RIGHT ends them
(def %pu-puf!
  (fn (_ s v flags left right)
    (let ((kind (first v)))
      (let ((n (if (int= kind 8) 16 7)))
        (if (not (int< (m86-cmp v (Vector ref 16 %m86-powers)) 0))
          (let ((t (m86->str v))) (pair 37 (List map (fn (_ i) (str-byte-ref t i)) (List range 0 (Str8 length t)))))
          (let ((got (if (m86-zero? v) (pair v 0) (%m86-fotnv v))))
            (let ((dl (rest got)))
              (if (not (int< dl 0))
                (do (let ((t (int- (int+ dl n) left))) (when (int< t 0) (%pu-fotz! s (int- 0 t))))
                    (%pu-dpcom! s flags n dl 0)
                    (%pu-digits! s (%m86-fotcv (first got)))
                    (unless (int= dl 0) (%pu-fotzc! s dl) (%pu-foted! s))
                    (%pu-puiz! s flags left right))
                (let ((dh (if (int= right 0) 0 (int- right 1))))
                  (let ((cl (if (int< (int+ dh dl) 0) (int+ dh dl) 0)))
                    (let ((w (%pu-div10s (first got) (int- 0 cl))))
                      (if (int< (int+ (int- dl cl) n) 0)
                        (do (%pu-fotz! s left)
                            (Vector set! 4 (%pu-bx s) s)
                            (%pu-put! s 46)
                            (%pu-fotz! s (int- dh n))
                            (%pu-regs! s 0 0))
                        (do (let ((t (int+ (int- (int- left n) dl) cl))) (unless (int< t 0) (%pu-fotz! s t)))
                            (%pu-dpcom! s flags n dl cl)))
                      (%pu-digits! s (%m86-fotcv w))
                      (if (int= right 0) (%pu-bx! s (Vector ref 4 s))
                        (let ((t (int- (int+ right dl) 1))) (unless (int< t 0) (%pu-fotz! s t))))
                      (%pu-fixe! s flags left))))))))))))

; V as PRINT USING prints it in a numeric field ($PUFOT): FLAGS as the
; scan sets them (64 commas, 32 asterisk fill, 16 floating $, 8 a + for a
; positive sign, 4 the sign after, 1 E notation), LEFT the places before
; the point, the sign's among them, RIGHT those after it and the point;
; the bytes
(def m86-using
  (fn (_ v flags left right)
    (let ((s (%pu-state)) (fb (int+ %pu-fbuff 1)))
      (%pu-at! s fb (if (int= (int& flags 8) 0) 32 43))
      (let ((neg (if (int= (first v) 2) (int< (m86-integer v) 0) (and (not (m86-zero? v)) (%m86-neg? v)))))
        (let ((v (if neg (do (%pu-at! s fb 45) (m86-neg v)) v)))
          (%pu-bx! s (int+ fb 1))
          (%pu-at! s (%pu-bx s) 48)
          (match
            ((not (int= (first v) 2))
              (if (int= (int& flags 1) 0) (%pu-puf! s v flags left right) (%pu-pufe! s v flags left right)))
            ((not (int= (int& flags 1) 0)) (%pu-pufe! s (m86->single v) flags left right))
            (#t
              (do (when (not (int< left 5)) (%pu-fotz! s (int- left 5)))
                  (%pu-regs! s 6 (if (int= (int& flags 64) 0) 0 3))
                  (%pu-digits! s (%pu-five (m86-integer v)))
                  (%pu-puiz! s flags left right)))))))))

; --- decimal text in ------------------------------------------------------

(def %m86-digit? (fn (_ b) (and (not (int< b 48)) (int< b 58))))

; One more digit D on the number read so far ($FIDIG): an integer while it
; fits, a single to seven digits, then a double
(def %m86-fidig
  (fn (_ v d)
    (match
      ((int= (first v) 2)
        (let ((n (m86-integer v)))
          (let ((t (int+ (int* n 10) d)))
            (if (and (int< n 3277) (int< t 32768)) (m86-int t) (%m86-fidig (%m86-flt n) d)))))
      ((int= (first v) 4)
        (if (%m86-below-million? v) (%s-add (%s-mul v %m86-ten-single) (%m86-flt d))
          (%m86-fidig (%m86-cds v) d)))
      (#t (%d-add (%d-mul v %m86-ten-double) (%m86-cds (%m86-flt d)))))))

; &H and &O constants ($OHCNS): (VALUE . END), ?OV past 16 bits
(def %m86-radix
  (fn (_ text i)
    (let ((n (Str8 length text)))
      (let ((at (fn (_ j) (if (int< j n) (str-byte-ref text j) 0))))
        (let ((hex (or (int= (at i) 72) (int= (at i) 104))))
          (let ((start (if (or hex (int= (at i) 79) (int= (at i) 111)) (int+ i 1) i))
                (base (if hex 16 8)))
            (let ((dv (fn (_ b)
                        (match
                          ((and (not (int< b 48)) (int< b (if hex 58 56))) (int- b 48))
                          ((and hex (not (int< b 65)) (int< b 71)) (int- b 55))
                          ((and hex (not (int< b 97)) (int< b 103)) (int- b 87))
                          (#t -1)))))
              (let ((go (fn (self j acc count)
                          (let ((d (dv (at j))))
                            (if (int< d 0)
                              (pair (m86-int (if (int< acc 32768) acc (int- acc 65536))) j)
                              (let ((acc (int+ (int* acc base) d)))
                                (if (or (int< 65535 acc) (and hex (int< 3 count))) (%m86-ov)
                                  (self (int+ j 1) acc (int+ count 1)))))))))
                (go start 0 0)))))))))

; The number at I in TEXT, read as FIN reads it: (VALUE . END), END past
; the last byte taken.  Blanks are skipped; a sign leads; digits make an
; integer, a single past 32767 or at a point or E, a double from the eighth
; digit or at D or #; ! makes a single and % is taken; E and D take an
; exponent, but not an E that starts ELSE or EQV.
(def m86-read
  (fn (_ text i)
    (let ((n (Str8 length text)))
      (let ((at (fn (_ j) (if (int< j n) (str-byte-ref text j) 0)))
            (skip (fn (self j)
                    (if (and (int< j n) (List includes? (str-byte-ref text j) (list 32 9 10)))
                      (self (int+ j 1)) j))))
        (let ((j0 (skip i)))
          (if (int= (at j0) 38) (%m86-radix text (int+ j0 1))
            (let ((neg (int= (at j0) 45))
                  (j1 (skip (if (or (int= (at j0) 45) (int= (at j0) 43)) (int+ j0 1) j0))))
              ; the number with its exponent K and AFTER digits past the point
              (let ((fine (fn (_ v k after)
                            (let ((x (int- k after)))
                              (if (int= x 0) v (%m86-scale10 v x)))))
                    (done (fn (_ v)
                            (let ((v (if neg (m86-neg v) v)))
                              (if (and (int= (first v) 4) (int= (m86-cmp v (m86-int -32768)) 0))
                                (m86-int -32768) v)))))
                ; the exponent after E or D at J: (K . END)
                (let ((exponent
                        (fn (_ j)
                          (let ((j (skip j)))
                            (let ((sign (match ((int= (at j) 45) -1) ((int= (at j) 43) 1) (#t 0))))
                              (let ((digits (fn (self j acc)
                                              (if (%m86-digit? (at j))
                                                (self (skip (int+ j 1))
                                                      (if (int< acc 3276) (int+ (int* acc 10) (int- (at j) 48)) 32767))
                                                (pair acc j)))))
                                (let ((got (digits (if (int= sign 0) j (skip (int+ j 1))) 0)))
                                  (pair (if (int< sign 0) (int- 0 (first got)) (first got)) (rest got)))))))))
                  (let ((go (fn (self j v point after)
                              (let ((c (at j)))
                                (match
                                  ((%m86-digit? c)
                                    (self (skip (int+ j 1)) (%m86-fidig v (int- c 48)) point (if point (int+ after 1) after)))
                                  ((int= c 46)
                                    (if point (pair (done (fine v 0 after)) j)
                                      (self (skip (int+ j 1)) (if (int= (first v) 2) (%m86-flt (m86-integer v)) v) #t after)))
                                  ((or (int= c 69) (int= c 101))
                                    (if (List includes? (at (skip (int+ j 1))) (list 76 108 81 113))
                                      (pair (done (fine v 0 after)) j)
                                      (let ((got (exponent (int+ j 1))))
                                        (pair (done (fine (if (int= (first v) 8) v (m86->single v)) (first got) after)) (rest got)))))
                                  ((or (int= c 68) (int= c 100))
                                    (let ((got (exponent (int+ j 1))))
                                      (pair (done (fine (m86->double v) (first got) after)) (rest got))))
                                  ((int= c 37) (pair (done (fine v 0 after)) (int+ j 1)))
                                  ((int= c 35) (pair (done (fine (m86->double v) 0 after)) (int+ j 1)))
                                  ((int= c 33) (pair (done (fine (m86->single v) 0 after)) (int+ j 1)))
                                  (#t (pair (done (fine v 0 after)) j)))))))
                    (go j1 (m86-int 0) #f 0)))))))))))

(provide basic/mbf86
  m86-int m86-kind m86-integer m86-zero? m86-infinity m86-raise m86->single m86->double m86-cint m86-floor
  m86-neg m86-abs m86-sgn m86-add m86-sub m86-mul m86-div m86-idiv m86-mod m86-cmp
  m86->bytes m86-from-bytes m86->str m86-using m86-read)
