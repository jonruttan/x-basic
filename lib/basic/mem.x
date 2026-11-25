; # x-basic -- BASIC on x-lang
;
; ## lib/basic/mem.x -- a BASIC's memory: program, variables, arrays, strings
;
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)
;
; A memory is a Dict: (lit bytes) the 64K image, the dialect's layout, and
; the pointers the source keeps, by name.  From TXTTAB up: the program's
; lines (link, number, crunched text, zero; two zeros at the end), then
; from VARTAB the simple variables, from ARYTAB the arrays, and free space
; to STREND.  Strings are given space from FRETOP down to it; MEMSIZ is the
; top.  These are the 6502's and the 8086's alike.
;
; How an entry lies is the layout's (the dialect's): a simple variable is
; its header, the name and type, and its value; an array its header, a
; length word (low, high), the count of its dimensions, each dimension's
; size from the last subscript to the first, then its elements with the
; first subscript varying fastest.  The layout says how long a header is,
; what type an entry holds (3 a string, whose value is a descriptor: its
; length and address), how long a value and an element are, what the
; length word counts, and the order of a size's bytes.
;
; An error is (Err raise 'basic "OM"), out of memory.

(module basic/mem)
(import x/type/list)
(import x/type/dict)
(import x/type/vector)
(import x/type/err)
(import x/core/doors int+ int- int* int< int= int& int>>)

(def %mem-fail (fn (_ code) (Err raise (lit basic) code)))

; --- bytes ----------------------------------------------------------------

(def mem-peek (fn (_ mem a) (Vector ref a (mem get (lit bytes)))))

(def mem-poke! (fn (_ mem a b) (Vector set! a b (mem get (lit bytes)))))

; The word at A, low byte first
(def mem-word
  (fn (_ mem a) (int+ (mem-peek mem a) (int* 256 (mem-peek mem (int+ a 1))))))

(def mem-word!
  (fn (_ mem a w)
    (mem-poke! mem a (int& w 255))
    (mem-poke! mem (int+ a 1) (int& (int>> w 8) 255))))

; BYTES, a list, written from A
(def mem-write!
  (fn (_ mem a bytes)
    (let ((go (fn (self a bs) (unless (null? bs) (do (mem-poke! mem a (first bs)) (self (int+ a 1) (rest bs)))))))
      (go a bytes))))

; N bytes from A, as a list
(def mem-read
  (fn (_ mem a n)
    (let ((go (fn (self i acc) (if (int< i a) acc (self (int- i 1) (pair (mem-peek mem i) acc))))))
      (go (int- (int+ a n) 1) ()))))

; N bytes from A to B, safe when the two overlap
(def mem-move!
  (fn (_ mem a b n)
    (if (int< a b)
      (let ((go (fn (self i) (unless (int< i 0) (do (mem-poke! mem (int+ b i) (mem-peek mem (int+ a i))) (self (int- i 1)))))))
        (go (int- n 1)))
      (let ((go (fn (self i) (when (int< i n) (mem-poke! mem (int+ b i) (mem-peek mem (int+ a i))) (self (int+ i 1))))))
        (go 0)))))

(def mem-zero!
  (fn (_ mem a n)
    (let ((go (fn (self i) (when (int< i n) (mem-poke! mem (int+ a i) 0) (self (int+ i 1))))))
      (go 0))))

; --- the memory -----------------------------------------------------------

; A memory laid out by LAYOUT whose program starts at START and whose top is
; TOP, the program empty
(def mem-make
  (fn (_ layout start top)
    (let ((mem (Dict make)))
      (mem set! (lit bytes) (Vector make 65536 0))
      (mem set! (lit layout) layout)
      (mem set! (lit txttab) start)
      (mem set! (lit memsiz) top)
      (mem-program! mem ())
      mem)))

(def mem-at (fn (_ mem key) (mem get key)))

; Variables, arrays and strings emptied (CLEARC)
(def mem-clear!
  (fn (_ mem)
    (mem set! (lit arytab) (mem get (lit vartab)))
    (mem set! (lit strend) (mem get (lit vartab)))
    (mem set! (lit fretop) (mem get (lit memsiz)))))

; --- strings: GETSPA and GARBA2 -------------------------------------------

; Each string descriptor's address in the image, as GARBA2 walks them: the
; simple string variables, then the string arrays' elements
(def %mem-descriptors
  (fn (_ mem)
    (let ((vars (let ((go (fn (self a end acc)
                            (if (not (int< a end)) (List reverse acc)
                              (let ((hl (%mem-header-length mem a)) (type (%mem-type mem a)))
                                (self (int+ a (int+ hl ((%mem-layout mem (lit value-size)) type))) end
                                      (if (int= type 3) (pair (int+ a hl) acc) acc)))))))
                  (go (mem get (lit vartab)) (mem get (lit arytab)) ())))
          (arrays (let ((go (fn (self a end acc)
                              (if (not (int< a end)) (List reverse acc)
                                (let ((next (int+ a (%mem-array-total mem a))))
                                  (if (int= (%mem-type mem a) 3)
                                    (let ((elems (fn (self e acc) (if (not (int< e next)) acc (self (int+ e 3) (pair e acc))))))
                                      (self next end (elems (%mem-elements mem a) acc)))
                                    (self next end acc)))))))
                    (go (mem get (lit arytab)) (mem get (lit strend)) ()))))
      (List append vars arrays))))

; Strings moved up to MEMSIZ, the highest below FRETOP first, one a pass;
; those below STREND, in the program's text, are left where they are
(def mem-collect!
  (fn (_ mem)
    (mem set! (lit fretop) (mem get (lit memsiz)))
    (let ((ds (%mem-descriptors mem)))
      (let ((pass (fn (self)
                    (let ((fretop (mem get (lit fretop))))
                      (let ((best (List fold
                                    (fn (_ best d)
                                      (if (int= (mem-peek mem d) 0) best
                                        (let ((a (mem-word mem (int+ d 1))))
                                          (if (or (not (int< a fretop)) (int< a (first best))) best (pair a d)))))
                                    (pair (mem get (lit strend)) ()) ds)))
                        (unless (null? (rest best))
                          (let ((d (rest best)) (a (first best)))
                            (let ((n (mem-peek mem d)))
                              (let ((to (int- fretop n)))
                                (mem-move! mem a to n)
                                (mem-word! mem (int+ d 1) to)
                                (mem set! (lit fretop) to)
                                (self))))))))))
        (pass)))))

; Space for N bytes of string, below FRETOP: its address.  A collection
; is tried once before ?OM.
(def mem-string-space!
  (fn (_ mem n)
    (let ((try (fn (_) (let ((a (int- (mem get (lit fretop)) n)))
                         (if (int< a (mem get (lit strend))) () a)))))
      (let ((a (let ((got (try))) (if (null? got) (do (mem-collect! mem) (try)) got))))
        (when (null? a) (%mem-fail "OM"))
        (mem set! (lit fretop) a)
        a))))

; A string's BYTES given space and written: its address
(def mem-string!
  (fn (_ mem bytes)
    (let ((a (mem-string-space! mem (List length bytes))))
      (mem-write! mem a bytes)
      a)))

; ?OM unless A is below FRETOP, a collection tried first (REASON)
(def mem-reason
  (fn (_ mem a)
    (unless (int< a (mem get (lit fretop)))
      (mem-collect! mem)
      (unless (int< a (mem get (lit fretop))) (%mem-fail "OM")))))

; FRETOP - STREND once the strings are collected, as FRE answers it
(def mem-free
  (fn (_ mem)
    (mem-collect! mem)
    (int- (mem get (lit fretop)) (mem get (lit strend)))))

; --- the program ----------------------------------------------------------

; LINES, each (NUMBER . BYTES) crunched, laid out from TXTTAB and linked,
; the variables cleared: each line's address, in order.  ?OM when they
; would reach the strings.
(def mem-program!
  (fn (_ mem lines)
    (let ((start (mem get (lit txttab))))
      (let ((end (List fold (fn (_ a l) (int+ a (int+ 5 (List length (rest l))))) start lines)))
        (when (mem has? (lit vartab)) (mem-reason mem (int+ end 2)))
        (mem-poke! mem (int- start 1) 0)
        (let ((go (fn (self a ls acc)
                    (if (null? ls)
                      (do (mem-word! mem a 0)
                          (mem set! (lit vartab) (int+ a 2))
                          (List reverse acc))
                      (let ((l (first ls)))
                        (let ((next (int+ a (int+ 5 (List length (rest l))))))
                          (mem-word! mem a next)
                          (mem-word! mem (int+ a 2) (first l))
                          (mem-write! mem (int+ a 4) (rest l))
                          (mem-poke! mem (int- next 1) 0)
                          (self next (rest ls) (pair a acc))))))))
          (let ((at (go start lines ())))
            (mem-clear! mem)
            at))))))

; --- the layout -----------------------------------------------------------

; The layout's door KEY
(def %mem-layout
  (fn (_ mem key) ((mem get (lit layout)) get key)))

(def %mem-peeker (fn (_ mem) (fn (_ a) (mem-peek mem a))))

; How long the header of the entry at A is, and its type
(def %mem-header-length
  (fn (_ mem a) ((%mem-layout mem (lit header-length)) (%mem-peeker mem) a)))

(def %mem-type
  (fn (_ mem a) ((%mem-layout mem (lit entry-type)) (%mem-peeker mem) a)))

; Whether the entry at A has the header bytes HEADER
(def %mem-named?
  (fn (_ mem a header)
    (let ((go (fn (self i hs) (or (null? hs) (and (int= (mem-peek mem (int+ a i)) (first hs)) (self (int+ i 1) (rest hs)))))))
      (and (int= (%mem-header-length mem a) (List length header)) (go 0 header)))))

; The whole length of the array at A, from its length word
(def %mem-array-total
  (fn (_ mem a)
    (let ((hl (%mem-header-length mem a)))
      ((%mem-layout mem (lit array-total)) (mem-word mem (int+ a hl)) hl))))

; Where the elements of the array at A start: past its header, the length
; word, the count of dimensions and two bytes for each
(def %mem-elements
  (fn (_ mem a)
    (let ((hl (%mem-header-length mem a)))
      (int+ a (int+ hl (int+ 3 (int* 2 (mem-peek mem (int+ a (int+ hl 2))))))))))

; --- variables ------------------------------------------------------------

; The entry of the simple variable whose header is HEADER, or nil
(def mem-var
  (fn (_ mem header)
    (let ((end (mem get (lit arytab))))
      (let ((go (fn (self a)
                  (match
                    ((not (int< a end)) ())
                    ((%mem-named? mem a header) a)
                    (#t (self (int+ a (int+ (%mem-header-length mem a)
                                            ((%mem-layout mem (lit value-size)) (%mem-type mem a))))))))))
        (go (mem get (lit vartab)))))))

; A new entry, HEADER and SIZE zero bytes of value, at ARYTAB, the arrays
; moved up past it
(def mem-var-new!
  (fn (_ mem header size)
    (let ((a (mem get (lit arytab))) (end (mem get (lit strend))) (n (int+ (List length header) size)))
      (mem-reason mem (int+ end n))
      (mem-move! mem a (int+ a n) (int- end a))
      (mem set! (lit arytab) (int+ a n))
      (mem set! (lit strend) (int+ end n))
      (mem-zero! mem a n)
      (mem-write! mem a header)
      a)))

; The entry of HEADER, made with SIZE bytes of value when there is none
(def mem-var!
  (fn (_ mem header size)
    (let ((a (mem-var mem header))) (if (null? a) (mem-var-new! mem header size) a))))

; --- arrays ---------------------------------------------------------------

; The array whose header is HEADER, or nil
(def mem-array
  (fn (_ mem header)
    (let ((end (mem get (lit strend))))
      (let ((go (fn (self a)
                  (match
                    ((not (int< a end)) ())
                    ((%mem-named? mem a header) a)
                    (#t (self (int+ a (%mem-array-total mem a))))))))
        (go (mem get (lit arytab)))))))

; A new array HEADER at STREND of SIZES (each bound + 1, the first
; subscript's first) and ELEMENT bytes an element, zeroed: its address
(def mem-array-new!
  (fn (_ mem header sizes element)
    (let ((a (mem get (lit strend))) (nd (List length sizes)) (hl (List length header)))
      (let ((from (int+ a (int+ hl (int+ 3 (int* 2 nd)))))
            (count (List fold (fn (_ n s) (int* n s)) 1 sizes)))
        (mem-reason mem from)
        (let ((end (int+ from (int* count element))))
          (unless (int< end 65536) (%mem-fail "OM"))
          (mem-reason mem end)
          (mem set! (lit strend) end)
          (mem-zero! mem a (int- end a))
          (mem-write! mem a header)
          (mem-word! mem (int+ a hl) ((%mem-layout mem (lit array-field)) (int- end a) hl))
          (mem-poke! mem (int+ a (int+ hl 2)) nd)
          (let ((go (fn (self at ss)
                      (unless (null? ss)
                        (mem-write! mem at ((%mem-layout mem (lit dim-bytes)) (first ss)))
                        (self (int+ at 2) (rest ss))))))
            (go (int+ a (int+ hl 3)) (List reverse sizes)))
          a)))))

; The array at A taken out, the arrays past it moved down over it and
; STREND with them (ERASE): how many bytes it was
(def mem-array-erase!
  (fn (_ mem a)
    (let ((n (%mem-array-total mem a)) (end (mem get (lit strend))))
      (mem-move! mem (int+ a n) a (int- end (int+ a n)))
      (mem set! (lit strend) (int- end n))
      n)))

; The address of the element at INDEX (counted with the first subscript
; fastest) of the array at A, ELEMENT bytes an element
(def mem-element
  (fn (_ mem a index element)
    (int+ (%mem-elements mem a) (int* index element))))

(provide basic/mem
  mem-peek mem-poke! mem-word mem-word! mem-write! mem-read mem-move! mem-make mem-at
  mem-clear! mem-collect! mem-string-space! mem-string! mem-reason mem-free mem-program!
  mem-var mem-var-new! mem-var! mem-array mem-array-new! mem-array-erase! mem-element)
