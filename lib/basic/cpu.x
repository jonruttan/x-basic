; # x-basic -- BASIC on x-lang
;
; ## lib/basic/cpu.x -- a 6502 running code in the byte image
;
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)
;
; The NMOS 6502's documented instructions, decimal mode as the NMOS part
; computes it, JMP indirect's page wrap included, over a 64K vector of
; bytes.  A call runs a routine as JSR would, to the RTS that returns from
; it.  A hook is a function run when the program counter reaches its
; address, in place of the code there, followed by an RTS: the ROM
; routines a caller reaches are hooks.  BRK and the undocumented opcodes
; stop the call.

(module basic/cpu)
(import x/type/list)
(import x/type/str)
(import x/type/vector)
(import x/type/dict)
(import x/type/err)
(import x/core/doors int+ int- int< int= int& int| int<< int>>)

(def %cpu-c 1)
(def %cpu-z 2)
(def %cpu-i 4)
(def %cpu-d 8)
(def %cpu-b 16)
(def %cpu-u 32)
(def %cpu-v 64)
(def %cpu-n 128)

(def %cpu-xor (fn (_ a b) (int- (int| a b) (int& a b))))

; V as N upper-case hex digits
(def %cpu-hex
  (fn (_ v n)
    (if (int= n 0) ""
      (Str8 append (%cpu-hex (int>> v 4) (int- n 1)) (Str8 sub (int& v 15) 1 "0123456789ABCDEF")))))

; A 6502 over BYTES, a vector of 65536: registers zero, the stack pointer
; $FF, the flags with I and the unused bit set
(def cpu-make
  (fn (_ bytes)
    (let ((c (Dict make)))
      (c set! (lit bytes) bytes)
      (c set! (lit a) 0)
      (c set! (lit x) 0)
      (c set! (lit y) 0)
      (c set! (lit s) 255)
      (c set! (lit p) (int| %cpu-u %cpu-i))
      (c set! (lit pc) 0)
      c)))

(def %cpu-rd (fn (_ c a) (Vector ref (int& a 65535) (c get (lit bytes)))))
(def %cpu-wr (fn (_ c a v) (Vector set! (int& a 65535) (int& v 255) (c get (lit bytes)))))
(def %cpu-word (fn (_ c a) (int+ (%cpu-rd c a) (int<< (%cpu-rd c (int+ a 1)) 8))))

(def %cpu-flag? (fn (_ c bit) (not (int= (int& (c get (lit p)) bit) 0))))
(def %cpu-flag!
  (fn (_ c bit on)
    (c set! (lit p)
      (if on (int| (c get (lit p)) bit) (int- (int| (c get (lit p)) bit) bit)))))

; Z and N from V, V answered
(def %cpu-nz!
  (fn (_ c v)
    (%cpu-flag! c %cpu-z (int= v 0))
    (%cpu-flag! c %cpu-n (not (int< v 128)))
    v))

; The register K set to V, its flags set
(def %cpu-load! (fn (_ c k v) (c set! k (%cpu-nz! c (int& v 255)))))

(def %cpu-push!
  (fn (_ c v)
    (%cpu-wr c (int+ 256 (c get (lit s))) v)
    (c set! (lit s) (int& (int- (c get (lit s)) 1) 255))))

(def %cpu-pull!
  (fn (_ c)
    (c set! (lit s) (int& (int+ (c get (lit s)) 1) 255))
    (%cpu-rd c (int+ 256 (c get (lit s))))))

; The byte at PC, PC moved past it
(def %cpu-next!
  (fn (_ c)
    (let ((pc (c get (lit pc))))
      (c set! (lit pc) (int& (int+ pc 1) 65535))
      (%cpu-rd c pc))))

(def %cpu-next-word!
  (fn (_ c)
    (let ((lo (%cpu-next! c)))
      (int+ lo (int<< (%cpu-next! c) 8)))))

; The zero-page pointer at P: its two bytes, the second wrapping in page 0
(def %cpu-zp-word (fn (_ c p) (int+ (%cpu-rd c p) (int<< (%cpu-rd c (int& (int+ p 1) 255)) 8))))

; The address MODE names, its operand read; nil for implied and the
; accumulator
(def %cpu-address
  (fn (_ c mode)
    (match
      ((eq? mode (lit imm)) (let ((pc (c get (lit pc)))) (%cpu-next! c) pc))
      ((eq? mode (lit zp)) (%cpu-next! c))
      ((eq? mode (lit zpx)) (int& (int+ (%cpu-next! c) (c get (lit x))) 255))
      ((eq? mode (lit zpy)) (int& (int+ (%cpu-next! c) (c get (lit y))) 255))
      ((eq? mode (lit abs)) (%cpu-next-word! c))
      ((eq? mode (lit absx)) (int& (int+ (%cpu-next-word! c) (c get (lit x))) 65535))
      ((eq? mode (lit absy)) (int& (int+ (%cpu-next-word! c) (c get (lit y))) 65535))
      ((eq? mode (lit indx)) (%cpu-zp-word c (int& (int+ (%cpu-next! c) (c get (lit x))) 255)))
      ((eq? mode (lit indy)) (int& (int+ (%cpu-zp-word c (%cpu-next! c)) (c get (lit y))) 65535))
      ((eq? mode (lit ind))
        (let ((p (%cpu-next-word! c)))
          (int+ (%cpu-rd c p)
                (int<< (%cpu-rd c (int| (int& p 65280) (int& (int+ p 1) 255))) 8))))
      (#t ()))))

(def %cpu-carry (fn (_ c) (if (%cpu-flag? c %cpu-c) 1 0)))

(def %cpu-adc!
  (fn (_ c m)
    (let ((a (c get (lit a))) (cy (%cpu-carry c)))
      (if (%cpu-flag? c %cpu-d)
        (let ((lo (int+ (int+ (int& a 15) (int& m 15)) cy)))
          (let ((al (if (int< lo 10) lo (int+ (int& (int+ lo 6) 15) 16))))
            (let ((s (int+ (int+ (int& a 240) (int& m 240)) al)))
              (%cpu-flag! c %cpu-z (int= (int& (int+ (int+ a m) cy) 255) 0))
              (%cpu-flag! c %cpu-n (not (int= (int& s 128) 0)))
              (%cpu-flag! c %cpu-v
                (not (int= (int& (int& (%cpu-xor (%cpu-xor a m) 255) (%cpu-xor a s)) 128) 0)))
              (let ((t (if (int< s 160) s (int+ s 96))))
                (%cpu-flag! c %cpu-c (not (int< t 256)))
                (c set! (lit a) (int& t 255))))))
        (let ((s (int+ (int+ a m) cy)))
          (%cpu-flag! c %cpu-c (not (int< s 256)))
          (%cpu-flag! c %cpu-v
            (not (int= (int& (int& (%cpu-xor (%cpu-xor a m) 255) (%cpu-xor a s)) 128) 0)))
          (%cpu-load! c (lit a) s))))))

(def %cpu-sbc!
  (fn (_ c m)
    (if (not (%cpu-flag? c %cpu-d)) (%cpu-adc! c (%cpu-xor m 255))
      (let ((a (c get (lit a))) (cy (%cpu-carry c)))
        ; the flags are the binary subtraction's, the result the decimal one
        (do (%cpu-flag! c %cpu-d #f)
            (%cpu-adc! c (%cpu-xor m 255))
            (%cpu-flag! c %cpu-d #t)
            (let ((lo (int- (int- (int+ (int& a 15) cy) (int& m 15)) 1)))
              (let ((al (if (int< lo 0) (int- (int& (int- lo 6) 15) 16) lo)))
                (let ((s (int+ (int- (int& a 240) (int& m 240)) al)))
                  (c set! (lit a) (int& (if (int< s 0) (int- s 96) s) 255))))))))))

(def %cpu-compare!
  (fn (_ c r m)
    (%cpu-flag! c %cpu-c (not (int< r m)))
    (%cpu-nz! c (int& (int- r m) 255))))

; Shift ops on V with the carry: the result, the carry set
(def %cpu-shift
  (fn (_ c op v)
    (let ((cy (%cpu-carry c)))
      (match
        ((eq? op (lit asl)) (do (%cpu-flag! c %cpu-c (not (int< v 128))) (%cpu-nz! c (int& (int<< v 1) 255))))
        ((eq? op (lit lsr)) (do (%cpu-flag! c %cpu-c (int= (int& v 1) 1)) (%cpu-nz! c (int>> v 1))))
        ((eq? op (lit rol)) (do (%cpu-flag! c %cpu-c (not (int< v 128))) (%cpu-nz! c (int& (int| (int<< v 1) cy) 255))))
        (#t (do (%cpu-flag! c %cpu-c (int= (int& v 1) 1)) (%cpu-nz! c (int| (int>> v 1) (int<< cy 7)))))))))

(def %cpu-branch!
  (fn (_ c taken)
    (let ((off (%cpu-next! c)))
      (when taken
        (c set! (lit pc)
          (int& (int+ (c get (lit pc)) (if (int< off 128) off (int- off 256))) 65535))))))

(def %cpu-rts!
  (fn (_ c)
    (let ((lo (%cpu-pull! c)))
      (let ((hi (%cpu-pull! c)))
        (c set! (lit pc) (int& (int+ (int+ lo (int<< hi 8)) 1) 65535))))))

; The instruction OP with operand address A (nil for implied), run
(def %cpu-op!
  (fn (_ c op a)
    (match
      ((eq? op (lit lda)) (%cpu-load! c (lit a) (%cpu-rd c a)))
      ((eq? op (lit ldx)) (%cpu-load! c (lit x) (%cpu-rd c a)))
      ((eq? op (lit ldy)) (%cpu-load! c (lit y) (%cpu-rd c a)))
      ((eq? op (lit sta)) (%cpu-wr c a (c get (lit a))))
      ((eq? op (lit stx)) (%cpu-wr c a (c get (lit x))))
      ((eq? op (lit sty)) (%cpu-wr c a (c get (lit y))))
      ((eq? op (lit adc)) (%cpu-adc! c (%cpu-rd c a)))
      ((eq? op (lit sbc)) (%cpu-sbc! c (%cpu-rd c a)))
      ((eq? op (lit and)) (%cpu-load! c (lit a) (int& (c get (lit a)) (%cpu-rd c a))))
      ((eq? op (lit ora)) (%cpu-load! c (lit a) (int| (c get (lit a)) (%cpu-rd c a))))
      ((eq? op (lit eor)) (%cpu-load! c (lit a) (%cpu-xor (c get (lit a)) (%cpu-rd c a))))
      ((eq? op (lit cmp)) (%cpu-compare! c (c get (lit a)) (%cpu-rd c a)))
      ((eq? op (lit cpx)) (%cpu-compare! c (c get (lit x)) (%cpu-rd c a)))
      ((eq? op (lit cpy)) (%cpu-compare! c (c get (lit y)) (%cpu-rd c a)))
      ((eq? op (lit bit))
        (let ((m (%cpu-rd c a)))
          (%cpu-flag! c %cpu-z (int= (int& m (c get (lit a))) 0))
          (%cpu-flag! c %cpu-n (not (int= (int& m 128) 0)))
          (%cpu-flag! c %cpu-v (not (int= (int& m 64) 0)))))
      ((List includes? op (list (lit asl) (lit lsr) (lit rol) (lit ror)))
        (if (null? a) (c set! (lit a) (%cpu-shift c op (c get (lit a))))
          (%cpu-wr c a (%cpu-shift c op (%cpu-rd c a)))))
      ((eq? op (lit inc)) (%cpu-wr c a (%cpu-nz! c (int& (int+ (%cpu-rd c a) 1) 255))))
      ((eq? op (lit dec)) (%cpu-wr c a (%cpu-nz! c (int& (int- (%cpu-rd c a) 1) 255))))
      ((eq? op (lit inx)) (%cpu-load! c (lit x) (int+ (c get (lit x)) 1)))
      ((eq? op (lit iny)) (%cpu-load! c (lit y) (int+ (c get (lit y)) 1)))
      ((eq? op (lit dex)) (%cpu-load! c (lit x) (int- (c get (lit x)) 1)))
      ((eq? op (lit dey)) (%cpu-load! c (lit y) (int- (c get (lit y)) 1)))
      ((eq? op (lit tax)) (%cpu-load! c (lit x) (c get (lit a))))
      ((eq? op (lit tay)) (%cpu-load! c (lit y) (c get (lit a))))
      ((eq? op (lit txa)) (%cpu-load! c (lit a) (c get (lit x))))
      ((eq? op (lit tya)) (%cpu-load! c (lit a) (c get (lit y))))
      ((eq? op (lit tsx)) (%cpu-load! c (lit x) (c get (lit s))))
      ((eq? op (lit txs)) (c set! (lit s) (c get (lit x))))
      ((eq? op (lit pha)) (%cpu-push! c (c get (lit a))))
      ((eq? op (lit php)) (%cpu-push! c (int| (c get (lit p)) (int| %cpu-b %cpu-u))))
      ((eq? op (lit pla)) (%cpu-load! c (lit a) (%cpu-pull! c)))
      ((eq? op (lit plp))
        (c set! (lit p) (int| (int- (int| (%cpu-pull! c) %cpu-b) %cpu-b) %cpu-u)))
      ((eq? op (lit jmp)) (c set! (lit pc) a))
      ((eq? op (lit jsr))
        (let ((back (int& (int- (c get (lit pc)) 1) 65535)))
          (%cpu-push! c (int>> back 8))
          (%cpu-push! c (int& back 255))
          (c set! (lit pc) a)))
      ((eq? op (lit rti))
        (do (c set! (lit p) (int| (int- (int| (%cpu-pull! c) %cpu-b) %cpu-b) %cpu-u))
            (let ((lo (%cpu-pull! c)))
              (c set! (lit pc) (int+ lo (int<< (%cpu-pull! c) 8))))))
      ((eq? op (lit bpl)) (%cpu-branch! c (not (%cpu-flag? c %cpu-n))))
      ((eq? op (lit bmi)) (%cpu-branch! c (%cpu-flag? c %cpu-n)))
      ((eq? op (lit bvc)) (%cpu-branch! c (not (%cpu-flag? c %cpu-v))))
      ((eq? op (lit bvs)) (%cpu-branch! c (%cpu-flag? c %cpu-v)))
      ((eq? op (lit bcc)) (%cpu-branch! c (not (%cpu-flag? c %cpu-c))))
      ((eq? op (lit bcs)) (%cpu-branch! c (%cpu-flag? c %cpu-c)))
      ((eq? op (lit bne)) (%cpu-branch! c (not (%cpu-flag? c %cpu-z))))
      ((eq? op (lit beq)) (%cpu-branch! c (%cpu-flag? c %cpu-z)))
      ((eq? op (lit clc)) (%cpu-flag! c %cpu-c #f))
      ((eq? op (lit sec)) (%cpu-flag! c %cpu-c #t))
      ((eq? op (lit cli)) (%cpu-flag! c %cpu-i #f))
      ((eq? op (lit sei)) (%cpu-flag! c %cpu-i #t))
      ((eq? op (lit cld)) (%cpu-flag! c %cpu-d #f))
      ((eq? op (lit sed)) (%cpu-flag! c %cpu-d #t))
      ((eq? op (lit clv)) (%cpu-flag! c %cpu-v #f))
      ((eq? op (lit nop)) ())
      (#t ()))))

; Each documented opcode's (OPCODE OP MODE)
(def %cpu-opcodes
  (List append
    (List map (fn (_ e) (list (first e) (lit lda) (List second e)))
      (list (list 169 (lit imm)) (list 165 (lit zp)) (list 181 (lit zpx)) (list 173 (lit abs))
            (list 189 (lit absx)) (list 185 (lit absy)) (list 161 (lit indx)) (list 177 (lit indy))))
    (List map (fn (_ e) (list (first e) (lit ldx) (List second e)))
      (list (list 162 (lit imm)) (list 166 (lit zp)) (list 182 (lit zpy)) (list 174 (lit abs)) (list 190 (lit absy))))
    (List map (fn (_ e) (list (first e) (lit ldy) (List second e)))
      (list (list 160 (lit imm)) (list 164 (lit zp)) (list 180 (lit zpx)) (list 172 (lit abs)) (list 188 (lit absx))))
    (List map (fn (_ e) (list (first e) (lit sta) (List second e)))
      (list (list 133 (lit zp)) (list 149 (lit zpx)) (list 141 (lit abs)) (list 157 (lit absx))
            (list 153 (lit absy)) (list 129 (lit indx)) (list 145 (lit indy))))
    (list (list 134 (lit stx) (lit zp)) (list 150 (lit stx) (lit zpy)) (list 142 (lit stx) (lit abs))
          (list 132 (lit sty) (lit zp)) (list 148 (lit sty) (lit zpx)) (list 140 (lit sty) (lit abs)))
    ; the eight groups the ALU instructions share: base + 0x09 imm, 0x05 zp,
    ; 0x15 zpx, 0x0D abs, 0x1D absx, 0x19 absy, 0x01 indx, 0x11 indy
    (List fold
      (fn (_ acc g)
        (List append acc
          (List map (fn (_ e) (list (int+ (first g) (first e)) (List second g) (List second e)))
            (list (list 9 (lit imm)) (list 5 (lit zp)) (list 21 (lit zpx)) (list 13 (lit abs))
                  (list 29 (lit absx)) (list 25 (lit absy)) (list 1 (lit indx)) (list 17 (lit indy))))))
      ()
      (list (list 0 (lit ora)) (list 32 (lit and)) (list 64 (lit eor)) (list 96 (lit adc))
            (list 192 (lit cmp)) (list 224 (lit sbc))))
    (list (list 224 (lit cpx) (lit imm)) (list 228 (lit cpx) (lit zp)) (list 236 (lit cpx) (lit abs))
          (list 192 (lit cpy) (lit imm)) (list 196 (lit cpy) (lit zp)) (list 204 (lit cpy) (lit abs))
          (list 36 (lit bit) (lit zp)) (list 44 (lit bit) (lit abs)))
    ; shifts: base + 0x0A acc, 0x06 zp, 0x16 zpx, 0x0E abs, 0x1E absx
    (List fold
      (fn (_ acc g)
        (List append acc
          (List map (fn (_ e) (list (int+ (first g) (first e)) (List second g) (List second e)))
            (list (list 10 (lit acc)) (list 6 (lit zp)) (list 22 (lit zpx)) (list 14 (lit abs)) (list 30 (lit absx))))))
      ()
      (list (list 0 (lit asl)) (list 32 (lit rol)) (list 64 (lit lsr)) (list 96 (lit ror))))
    (list (list 230 (lit inc) (lit zp)) (list 246 (lit inc) (lit zpx)) (list 238 (lit inc) (lit abs)) (list 254 (lit inc) (lit absx))
          (list 198 (lit dec) (lit zp)) (list 214 (lit dec) (lit zpx)) (list 206 (lit dec) (lit abs)) (list 222 (lit dec) (lit absx))
          (list 232 (lit inx) (lit imp)) (list 200 (lit iny) (lit imp)) (list 202 (lit dex) (lit imp)) (list 136 (lit dey) (lit imp))
          (list 170 (lit tax) (lit imp)) (list 168 (lit tay) (lit imp)) (list 138 (lit txa) (lit imp)) (list 152 (lit tya) (lit imp))
          (list 186 (lit tsx) (lit imp)) (list 154 (lit txs) (lit imp))
          (list 72 (lit pha) (lit imp)) (list 8 (lit php) (lit imp)) (list 104 (lit pla) (lit imp)) (list 40 (lit plp) (lit imp))
          (list 76 (lit jmp) (lit abs)) (list 108 (lit jmp) (lit ind)) (list 32 (lit jsr) (lit abs))
          (list 96 (lit rts) (lit imp)) (list 64 (lit rti) (lit imp))
          (list 16 (lit bpl) (lit imp)) (list 48 (lit bmi) (lit imp)) (list 80 (lit bvc) (lit imp)) (list 112 (lit bvs) (lit imp))
          (list 144 (lit bcc) (lit imp)) (list 176 (lit bcs) (lit imp)) (list 208 (lit bne) (lit imp)) (list 240 (lit beq) (lit imp))
          (list 24 (lit clc) (lit imp)) (list 56 (lit sec) (lit imp)) (list 88 (lit cli) (lit imp)) (list 120 (lit sei) (lit imp))
          (list 216 (lit cld) (lit imp)) (list 248 (lit sed) (lit imp)) (list 184 (lit clv) (lit imp))
          (list 234 (lit nop) (lit imp)))))

; The opcodes by byte: (OP . MODE), nil for BRK and the undocumented ones
(def %cpu-table
  (let ((v (Vector make 256 ())))
    (List for-each (fn (_ e) (Vector set! (first e) (pair (List second e) (List third e)) v)) %cpu-opcodes)
    v))

; How many instructions run between collects
(def %cpu-sweep-every 65536)

; The routine at ADDR called as JSR calls it, run to the RTS that returns
; from it, HOOKS a dict of address -> (fn (_ cpu)) run in place of the code
; there.  BRK or an undocumented opcode raises a label 'cpu Err naming its
; byte and address.
(def cpu-call!
  (fn (_ c addr hooks)
    ; a return address pushed as JSR pushes one, then the run stops at the
    ; RTS that pulls it
    (%cpu-push! c 255)
    (%cpu-push! c 254)
    (let ((base (c get (lit s))))
      (c set! (lit pc) addr)
      (let ((rts (fn (_) (let ((done (int= (c get (lit s)) base))) (%cpu-rts! c) done))))
        (let ((go (fn (self k)
                    (let ((pc (c get (lit pc))))
                      (when (int= k %cpu-sweep-every) (Heap collect))
                      (if (hooks has? pc)
                        (do ((hooks get pc) c)
                            (unless (rts) (self (int& (int+ k 1) 131071))))
                        (let ((byte (%cpu-next! c)))
                          (let ((e (Vector ref byte %cpu-table)))
                            (match
                              ((null? e) (Err raise (lit cpu) (Str8 append "OPCODE " (%cpu-hex byte 2) " AT " (%cpu-hex pc 4))))
                              ((eq? (first e) (lit rts)) (unless (rts) (self (int& (int+ k 1) 131071))))
                              (#t (do (%cpu-op! c (first e) (%cpu-address c (rest e)))
                                      (self (int& (int+ k 1) 131071))))))))))))
          (go 0))))))

(provide basic/cpu cpu-make cpu-call!)
