; # x-basic -- BASIC on x-lang
;
; ## lib/basic/exec.x -- the machine: the program, its variables, and running it
;
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)
;
; A machine is a Dict: the dialect, the program's lines, the variables and
; arrays, the stack FOR and GOSUB share, the DATA not yet read, the output
; column, and the line running.  A line typed with a number is stored; one
; without is run at once and followed by the dialect's ready prompt.
;
; A position is (INDEX . STATEMENTS): the line's place in the program, -1
; for the line typed, and the statements still to run on it.  A statement
; answers nil to go on, a position to go to, next-line to skip the rest of
; its line, or end or stop.
;
; An error is (Err raise 'basic CODE), CODE as the dialect prints it.  A
; statement this bundle does not run yet raises 'basic-todo with its word.

(module basic/exec)
(import x/type/list)
(import x/type/str)
(import x/type/dict)
(import x/type/vector)
(import x/type/err)
(import x/core/doors int+ int- int* int/ int% int< int= int<< int>> int& int| str-byte-ref)
(import basic/mbf
  mbf-zero mbf-zero? mbf-bytes mbf->bytes mbf-int mbf-neg mbf-abs mbf-sgn mbf-cmp mbf-round mbf-add mbf-sub
  mbf-mul mbf-div mbf-floor mbf->int mbf->str)
(import basic/mbf-math
  mbf-log mbf-exp mbf-power mbf-sqr mbf-sin mbf-cos mbf-tan mbf-atn mbf-rnd-seed mbf-rnd)
(import basic/lex basic-lex basic-fold basic-crunch)
(import basic/parse basic-parse-line basic-parse-value basic-items)
(import basic/mem
  mem-peek mem-poke! mem-word mem-word! mem-write! mem-read mem-make mem-at mem-clear! mem-string!
  mem-free mem-program! mem-var mem-var! mem-array mem-array-new! mem-element)

(def %bx-fail (fn (_ code) (Err raise (lit basic) code)))
(def %bx-todo (fn (_ word) (Err raise (lit basic-todo) word)))

; --- the machine ----------------------------------------------------------

; A machine for DIALECT, writing text with OUT and N zero bytes with
; (ZEROS N), reading lines with IN (a function answering the next line, or
; nil at the end) and keys with KEY (one answering the next key's byte,
; waited for, or nil at the end; the terminal shows the key, as a KIM's
; does, and the machine's column does not count it)
(def basic-machine
  (fn (_ dialect out zeros in key)
    (let ((m (Dict make)))
      (m set! (lit dialect) dialect)
      (m set! (lit out) out)
      (m set! (lit zeros) zeros)
      (m set! (lit in) in)
      (m set! (lit key) key)
      (m set! (lit col) 0)
      ; NULL's count, the zero bytes after each new line; NEW and CLEAR
      ; leave it
      (m set! (lit nulls) 0)
      ; whether a typed line is upper-cased outside its strings, REM and DATA
      (m set! (lit fold-case) (dialect get-or #t (lit fold-case)))
      ; the line's width and the column past which a comma starts a new
      ; line (LINWID, NCMWID)
      (%bx-width! m (dialect get (lit width))
        (let ((zone (dialect get (lit zone))))
          (int* (int- (int/ (dialect get (lit width)) zone) 1) zone)))
      ; memory up to the dialect's top of RAM, as a blank MEMORY SIZE? finds
      (m set! (lit mem) (mem-make (dialect get (lit txttab)) (dialect get (lit ram-top))))
      (m set! (lit lines) ())
      ; RND's last value; CLEAR and RUN leave it
      (m set! (lit rnd) mbf-rnd-seed)
      (%bx-index! m ())
      (%bx-clear! m)
      m)))

(def %bx-width!
  (fn (_ m width last-comma)
    (m set! (lit width) width)
    (m set! (lit last-comma) last-comma)))

(def %bx-mem (fn (_ m) (m get (lit mem))))

; Variables, arrays and the stack emptied, and DATA read from the start
(def %bx-clear!
  (fn (_ m)
    (mem-clear! (%bx-mem m))
    ; where each simple variable's value is in memory, by name; the value
    ; itself is only in memory, so a POKE into it is read back
    (m set! (lit var-at) (Dict make))
    ; each array by name: (BOUNDS OFFSET), OFFSET its header's from ARYTAB
    (m set! (lit arrays) (Dict make))
    ; DEF's functions, by name: (ARG FORMULA INDEX), INDEX the DEF's line
    (m set! (lit fns) (Dict make))
    (m set! (lit stack) ())
    (m set! (lit cont) ())
    (%bx-restore! m)))

; The program as a vector, each line number's place in it, and each line's
; address in memory, ADDRS
(def %bx-index!
  (fn (_ m addrs)
    (let ((v (Vector from-list (m get (lit lines)))) (at (Dict make)))
      (Vector for-each (fn (_ i) (at set! (first (Vector ref i v)) i))
        (Vector from-list (List range 0 (Vector length v))))
      (m set! (lit prog) v)
      (m set! (lit at) at)
      (m set! (lit addrs) (Vector from-list addrs)))))

(def %bx-line-ref (fn (_ m i) (Vector ref i (m get (lit prog)))))

; Where the text of line INDEX starts in memory, past its link and number
(def %bx-line-text (fn (_ m i) (int+ (Vector ref i (m get (lit addrs))) 4)))

; The place of line number N
(def %bx-find
  (fn (_ m n)
    (let ((i ((m get (lit at)) get n)))
      (if (null? i) (%bx-fail "US") i))))

; The program LINES laid out in memory, then made the machine's: ?OM leaves
; the program as it was
(def %bx-program!
  (fn (_ m lines)
    (let ((addrs (mem-program! (%bx-mem m)
                   (List map (fn (_ l) (pair (first l) (first (List ref 3 l)))) lines))))
      (m set! (lit lines) lines)
      (%bx-index! m addrs)
      (%bx-clear! m))))

; Line N's text stored, or the line removed when TEXT is blank.  A line is
; (NUMBER TEXT STATEMENTS CRUNCHED), CRUNCHED as basic-crunch gives it.
(def %bx-store!
  (fn (_ m n text)
    (let ((kept (List filter (fn (_ l) (not (int= (first l) n))) (m get (lit lines))))
          (dialect (m get (lit dialect))))
      (%bx-program! m
        (if (= (Str8 length (Str8 trim text)) 0) kept
          (let ((line (list n text (basic-parse-line (basic-lex dialect text)) (basic-crunch dialect text))))
            (List append (List filter (fn (_ l) (int< (first l) n)) kept)
                         (pair line (List filter (fn (_ l) (int< n (first l))) kept)))))))))

; --- output ---------------------------------------------------------------

; TEXT written, a new line begun wherever the line is full
(def %bx-out
  (fn (_ m text)
    (let ((width (m get (lit width))) (n (Str8 length text)))
      (let ((room (int- width (m get (lit col)))))
        (if (not (int< room n))
          (do ((m get (lit out)) text)
              (m set! (lit col) (int+ (m get (lit col)) n)))
          (do ((m get (lit out)) (Str8 sub 0 room text))
              (%bx-newline m)
              (%bx-out m (Str8 sub room (int- n room) text))))))))

; The zero bytes CRDO prints after a new line, NULL's count of them
(def %bx-nulls
  (fn (_ m)
    (when (int< 0 (m get (lit nulls))) ((m get (lit zeros)) (m get (lit nulls))))
    (m set! (lit col) 0)))

(def %bx-newline
  (fn (_ m)
    ((m get (lit out)) "\n")
    (%bx-nulls m)))

(def %bx-spaces
  (fn (_ m n) (when (int< 0 n) (%bx-out m (Str8 repeat n " ")))))

; --- values ---------------------------------------------------------------

; A number is an MBF pair.  A string is its text when it has no place in
; memory yet (a function's answer, a constant typed at the prompt, a reply
; to INPUT), or #(TEXT ADDRESS VAR?) when it has one: in the program's text
; or in string space, VAR? when it was read from a variable.
(def %bx-num? (fn (_ v) (pair? v)))

(def %bx-number
  (fn (_ v) (if (pair? v) v (%bx-fail "TM"))))

(def %bx-placed (fn (_ text a var?) (Vector from-list (list text a var?))))

; V's text, ?TM for a number
(def %bx-string
  (fn (_ v)
    (match
      ((pair? v) (%bx-fail "TM"))
      ((str? v) v)
      (#t (Vector ref 0 v)))))

; V checked to be a string, its place kept
(def %bx-string-value
  (fn (_ v) (do (%bx-string v) v)))

; The string at the descriptor D in memory, read from it
(def %bx-string-at
  (fn (_ m d)
    (let ((mem (%bx-mem m)))
      (let ((n (mem-peek mem d)) (a (mem-word mem (int+ d 1))))
        (%bx-placed (if (int= n 0) "" (bytes->str (mem-read mem a n))) a #t)))))

; The string V put at the descriptor D (GETSPT and COPY): text with no
; place is given space; a string read from a variable is copied when it is
; in string space; one in the program's text is pointed at where it is
(def %bx-string-to!
  (fn (_ m d v)
    (let ((mem (%bx-mem m)) (text (%bx-string v)))
      (let ((n (Str8 length text)))
        (let ((a (if (or (str? v)
                         (and (Vector ref 2 v) (not (int< (Vector ref 1 v) (mem-at mem (lit fretop))))))
                   (if (int= n 0) 0 (mem-string! mem (%bx-bytes text)))
                   (Vector ref 1 v))))
          (mem-word! mem (int+ d 1) a)
          (%bx-poke-byte! m d n))))))

(def %bx-poke-byte! (fn (_ m a b) (mem-write! (%bx-mem m) a (list b))))

; TEXT's bytes, as a list
(def %bx-bytes
  (fn (_ text)
    (let ((go (fn (self i acc) (if (int< i 0) acc (self (int- i 1) (pair (str-byte-ref text i) acc))))))
      (go (int- (Str8 length text) 1) ()))))

; A number as an integer from LO to HI, by INT; ?FC outside
(def %bx-int-in
  (fn (_ v lo hi)
    (let ((n (mbf->int (mbf-floor (%bx-number v)) 65536)))
      (if (or (int< n lo) (int< hi n)) (%bx-fail "FC") n))))

(def %bx-byte (fn (_ v) (%bx-int-in v 0 255)))
; An address, as GETADR takes one: ?FC below 0 or past 65535
(def %bx-address (fn (_ v) (%bx-int-in v 0 65535)))
(def %bx-word (fn (_ v) (%bx-int-in v -32768 32767)))

(def %bx-truth (fn (_ b) (if b (mbf-int -1) mbf-zero)))

; A string no longer than 255
(def %bx-checked
  (fn (_ s) (if (int< 255 (Str8 length s)) (%bx-fail "LS") s)))

(def %bx-string-name? (fn (_ name) (Str8 ends? "$" name)))
(def %bx-int-name? (fn (_ name) (Str8 ends? "%" name)))

(def %bx-default
  (fn (_ name) (if (%bx-string-name? name) "" mbf-zero)))

; A number V made fit to be stored in NAME; a string is checked and keeps
; its place
(def %bx-fit
  (fn (_ name v)
    (match
      ((%bx-string-name? name) (%bx-string-value v))
      ((%bx-int-name? name) (mbf-int (%bx-word v)))
      (#t (mbf-round (%bx-number v))))))

; --- variables and arrays -------------------------------------------------

; NAME's two bytes in memory (PTRGET): the letters, the second 0 when there
; is one; a string's second with its top bit on, an integer's both
(def %bx-name-bytes
  (fn (_ name)
    (let ((base (if (or (%bx-string-name? name) (%bx-int-name? name))
                  (Str8 sub 0 (int- (Str8 length name) 1) name) name)))
      (let ((n1 (str-byte-ref base 0))
            (n2 (if (int< 1 (Str8 length base)) (str-byte-ref base 1) 0)))
        (match
          ((%bx-string-name? name) (pair n1 (int| n2 128)))
          ((%bx-int-name? name) (pair (int| n1 128) (int| n2 128)))
          (#t (pair n1 n2)))))))

; The bytes an element of NAME's array takes
(def %bx-element-size
  (fn (_ name)
    (match ((%bx-string-name? name) 3) ((%bx-int-name? name) 2) (#t 5))))

; The value bytes of the number V for NAME
(def %bx-number-bytes
  (fn (_ name v)
    (if (%bx-int-name? name)
      (let ((w (int& (mbf->int v 65536) 65535))) (list (int>> w 8) (int& w 255)))
      (mbf->bytes v))))

; Where NAME's value is in memory, or nil when it has no entry
(def %bx-var-at
  (fn (_ m name)
    (let ((at (m get (lit var-at))))
      (if (at has? name) (at get name)
        (let ((nb (%bx-name-bytes name)))
          (let ((e (mem-var (%bx-mem m) (first nb) (rest nb))))
            (if (null? e) ()
              (do (at set! name (int+ e 2)) (int+ e 2)))))))))

; Where NAME's value is, its entry made when it has none
(def %bx-var-at!
  (fn (_ m name)
    (let ((a (%bx-var-at m name)))
      (if (not (null? a)) a
        (let ((nb (%bx-name-bytes name)))
          (let ((a (int+ (mem-var! (%bx-mem m) (first nb) (rest nb)) 2)))
            ((m get (lit var-at)) set! name a)
            a))))))

; The number V stored in the simple variable NAME, its bytes written
(def %bx-number-set!
  (fn (_ m name v)
    (mem-write! (%bx-mem m) (%bx-var-at! m name) (%bx-number-bytes name v))))

; The number for NAME in the bytes at A: an integer's word hi then lo, a
; real's five bytes as MOVFM loads them
(def %bx-number-at
  (fn (_ m name a)
    (let ((mem (%bx-mem m)))
      (if (%bx-int-name? name)
        (mbf-int (%bx-signed (int+ (int<< (mem-peek mem a) 8) (mem-peek mem (int+ a 1)))))
        (mbf-bytes (mem-peek mem a) (mem-peek mem (int+ a 1)) (mem-peek mem (int+ a 2))
                   (mem-peek mem (int+ a 3)) (mem-peek mem (int+ a 4)))))))

; The simple variable NAME's number, zero when it has no entry (ISVAR
; makes none)
(def %bx-number-of
  (fn (_ m name)
    (let ((a (%bx-var-at m name))) (if (null? a) mbf-zero (%bx-number-at m name a)))))

; An array of NAME, each subscript to BOUNDS: (BOUNDS OFFSET), OFFSET its
; header's from ARYTAB, which a new simple variable moves but not that
(def %bx-array-make
  (fn (_ m name bounds)
    (let ((nb (%bx-name-bytes name)) (sizes (List map (fn (_ b) (int+ b 1)) bounds)))
      (let ((a (mem-array-new! (%bx-mem m) (first nb) (rest nb) sizes (%bx-element-size name))))
        (list bounds (int- a (mem-at (%bx-mem m) (lit arytab))))))))

; Where the element K of NAME's array A is
(def %bx-element-at
  (fn (_ m name a k)
    (let ((mem (%bx-mem m)))
      (mem-element mem (int+ (mem-at mem (lit arytab)) (List second a)) k (%bx-element-size name)))))

; NAME's array, made with COUNT subscripts of the dialect's size when it
; has not been
(def %bx-array
  (fn (_ m name count)
    (let ((arrays (m get (lit arrays))))
      (unless (arrays has? name)
        (arrays set! name
          (%bx-array-make m name
            (List map (fn (_ i) (int- ((m get (lit dialect)) get (lit array-size)) 1))
                      (List range 0 count)))))
      (arrays get name))))

; The element of SUBSCRIPTS in the array A, counted with the first
; subscript fastest (GETDEF)
(def %bx-slot
  (fn (_ a subscripts)
    (unless (int= (List length subscripts) (List length (first a))) (%bx-fail "BS"))
    (List fold
      (fn (_ at pr)
        (let ((i (%bx-int-in (rest pr) 0 32767)))
          (when (int< (first pr) i) (%bx-fail "BS"))
          (int+ (int* at (int+ (first pr) 1)) i)))
      0 (List reverse (List zip (first a) subscripts)))))

(def %bx-get
  (fn (_ m target)
    (let ((name (List second target)))
      (if (eq? (first target) (lit var))
        (if (%bx-string-name? name)
          (let ((a (%bx-var-at m name))) (if (null? a) "" (%bx-string-at m a)))
          (%bx-number-of m name))
        (let ((args (List map (fn (_ e) (%bx-eval m e)) (List third target))))
          (let ((a (%bx-array m name (List length args))))
            (let ((at (%bx-element-at m name a (%bx-slot a args))))
              (if (%bx-string-name? name) (%bx-string-at m at) (%bx-number-at m name at)))))))))

(def %bx-set!
  (fn (_ m target v)
    (let ((name (List second target)))
      (if (eq? (first target) (lit var))
        (if (%bx-string-name? name)
          (%bx-string-to! m (%bx-var-at! m name) (%bx-fit name v))
          (%bx-number-set! m name (%bx-fit name v)))
        (let ((args (List map (fn (_ e) (%bx-eval m e)) (List third target))))
          (let ((a (%bx-array m name (List length args))) (fit (%bx-fit name v)))
            (let ((at (%bx-element-at m name a (%bx-slot a args))))
              (if (%bx-string-name? name) (%bx-string-to! m at fit)
                (mem-write! (%bx-mem m) at (%bx-number-bytes name fit))))))))))

; --- expressions ----------------------------------------------------------

; A 16-bit two's complement word as a signed integer
(def %bx-signed
  (fn (_ w) (if (int< w 32768) w (int- w 65536))))

(def %bx-op
  (fn (_ m word a b)
    (match
      ((str=? word "+")
        (if (and (not (pair? a)) (not (pair? b))) (%bx-checked (Str8 append (%bx-string a) (%bx-string b)))
          (mbf-add (mbf-round (%bx-number a)) (%bx-number b))))
      ((str=? word "-") (mbf-sub (mbf-round (%bx-number a)) (%bx-number b)))
      ((str=? word "*") (mbf-mul (%bx-number b) (%bx-number a)))
      ((str=? word "/") (mbf-div (%bx-number a) (%bx-number b)))
      ((str=? word "^") (mbf-power (mbf-round (%bx-number a)) (%bx-number b)))
      ((str=? word "AND")
        (mbf-int (%bx-signed (int& (int& (%bx-word a) 65535) (int& (%bx-word b) 65535)))))
      (#t
        (mbf-int (%bx-signed (int| (int& (%bx-word a) 65535) (int& (%bx-word b) 65535))))))))

; -1, 0 or 1 comparing two strings byte by byte
(def %bx-str-cmp
  (fn (_ a b)
    (let ((na (Str8 length a)) (nb (Str8 length b)))
      (let ((go (fn (self i)
                  (match
                    ((int= i na) (if (int= i nb) 0 -1))
                    ((int= i nb) 1)
                    ((int< (str-byte-ref a i) (str-byte-ref b i)) -1)
                    ((int< (str-byte-ref b i) (str-byte-ref a i)) 1)
                    (#t (self (int+ i 1)))))))
        (go 0)))))

(def %bx-rel
  (fn (_ mask a b)
    (let ((c (match
               ((and (pair? a) (pair? b)) (mbf-cmp a b))
               ((or (pair? a) (pair? b)) (%bx-fail "TM"))
               (#t (%bx-str-cmp (%bx-string a) (%bx-string b))))))
      (%bx-truth (not (int= 0 (int& mask (match ((int< c 0) 1) ((int= c 0) 2) (#t 4)))))))))

; The number at the start of TEXT, as VAL and INPUT read it, or nil
(def %bx-value
  (fn (_ m text)
    (let ((ts (basic-lex (m get (lit dialect)) text)))
      (let ((got (basic-parse-value ts)))
        (if (null? got) () (pair (%bx-eval m (first got)) (rest got)))))))

(def %bx-call
  (fn (_ m word args)
    (let ((a (first args)))
      (match
        ((str=? word "SGN") (mbf-int (mbf-sgn (%bx-number a))))
        ((str=? word "INT") (mbf-floor (%bx-number a)))
        ((str=? word "ABS") (mbf-abs (%bx-number a)))
        ((str=? word "LEN") (mbf-int (Str8 length (%bx-string a))))
        ((str=? word "STR$") (mbf->str (%bx-number a)))
        ((str=? word "VAL")
          (let ((got (%bx-value m (%bx-string a)))) (if (null? got) mbf-zero (first got))))
        ((str=? word "ASC")
          (if (= (Str8 length (%bx-string a)) 0) (%bx-fail "FC") (mbf-int (str-byte-ref (%bx-string a) 0))))
        ((str=? word "CHR$") (bytes->str (list (%bx-byte a))))
        ((str=? word "LEFT$")
          (let ((s (%bx-string a)) (n (%bx-byte (List second args))))
            (if (int< (Str8 length s) n) s (Str8 sub 0 n s))))
        ((str=? word "RIGHT$")
          (let ((s (%bx-string a)) (n (%bx-byte (List second args))))
            (if (int< (Str8 length s) n) s (Str8 sub (int- (Str8 length s) n) n s))))
        ((str=? word "MID$")
          (let ((s (%bx-string a)) (i (%bx-byte (List second args)))
                (n (if (null? (rest (rest args))) 255 (%bx-byte (List third args)))))
            (when (int= i 0) (%bx-fail "FC"))
            (let ((left (int- (Str8 length s) (int- i 1))))
              (if (int< left 1) ""
                (Str8 sub (int- i 1) (if (int< left n) left n) s)))))
        ((str=? word "POS") (mbf-int (m get (lit col))))
        ; the strings collected, then FRETOP - STREND as a signed word
        ((str=? word "FRE")
          (do (unless (pair? a) (%bx-string a))
              (mbf-int (%bx-signed (int& (mem-free (%bx-mem m)) 65535)))))
        ((str=? word "PEEK") (mbf-int (mem-peek (%bx-mem m) (%bx-address a))))
        ((str=? word "SQR") (mbf-sqr (%bx-number a)))
        ((str=? word "LOG") (mbf-log (%bx-number a)))
        ((str=? word "EXP") (mbf-exp (%bx-number a)))
        ((str=? word "SIN") (mbf-sin (%bx-number a)))
        ((str=? word "COS") (mbf-cos (%bx-number a)))
        ((str=? word "TAN") (mbf-tan (%bx-number a)))
        ((str=? word "ATN") (mbf-atn (%bx-number a)))
        ((str=? word "RND")
          (let ((got (mbf-rnd (%bx-number a) (m get (lit rnd)))))
            (do (m set! (lit rnd) (rest got)) (first got))))
        (#t (%bx-todo word))))))

; FN NAME of the argument E (FNDOER): the argument taken, ?UF when NAME has
; no DEF, then the formula read with its argument's variable set to it,
; and the variable's value put back
(def %bx-fn
  (fn (_ m name e)
    (when (%bx-string-name? name) (%bx-fail "TM"))
    ; GETFNM finds the function's entry, or makes one, before the argument
    (%bx-fn-at! m name)
    (let ((x (%bx-number (%bx-eval m e))) (d ((m get (lit fns)) get-or () name)))
      (when (null? d) (%bx-fail "UF"))
      (let ((var (first d)))
        (let ((old (%bx-number-of m var)))
          (%bx-set! m (list (lit var) var) x)
          (let ((v (if (eq? (List second d) (lit bad)) (%bx-fail "SN")
                     (let ((here (m get (lit index))))
                       ; the formula's string constants are in the DEF's line
                       (m set! (lit index) (List third d))
                       (let ((v (%bx-number (%bx-eval m (List second d)))))
                         (m set! (lit index) here)
                         v)))))
            (%bx-number-set! m var old)
            v))))))

; Where the function NAME's entry is, made when it has none: NAME1 has its
; top bit on (GETFNM)
(def %bx-fn-at!
  (fn (_ m name)
    (let ((nb (%bx-name-bytes name)))
      (mem-var! (%bx-mem m) (int| (first nb) 128) (rest nb)))))

; A string constant: in a line of the program, where it is in the line's
; text; typed at the prompt, text that STRLIT copies when it is used
(def %bx-constant
  (fn (_ m e)
    (let ((index (m get (lit index))) (ord (List third e)))
      (if (or (null? index) (int< index 0) (null? ord)) (List second e)
        (let ((strs (List second (List ref 3 (%bx-line-ref m index)))))
          (%bx-placed (List second e) (int+ (%bx-line-text m index) (List ref ord strs)) #f))))))

(def %bx-eval
  (fn (_ m e)
    (let ((tag (first e)))
      (match
        ((eq? tag (lit num)) (List second e))
        ((eq? tag (lit str)) (%bx-constant m e))
        ((eq? tag (lit var)) (%bx-get m e))
        ((eq? tag (lit elem)) (%bx-get m e))
        ((eq? tag (lit op))
          (%bx-op m (List second e) (%bx-eval m (List third e)) (%bx-eval m (List ref 3 e))))
        ((eq? tag (lit rel))
          (%bx-rel (List second e) (%bx-eval m (List third e)) (%bx-eval m (List ref 3 e))))
        ((eq? tag (lit neg)) (mbf-neg (%bx-number (%bx-eval m (List second e)))))
        ((eq? tag (lit not)) (mbf-int (int- -1 (%bx-word (%bx-eval m (List second e))))))
        ((eq? tag (lit call))
          (%bx-call m (List second e) (List map (fn (_ a) (%bx-eval m a)) (List third e))))
        ((eq? tag (lit fn)) (%bx-fn m (List second e) (List third e)))
        (#t (%bx-fail "SN"))))))

; --- PRINT ----------------------------------------------------------------

(def %bx-print
  (fn (_ m items)
    (List for-each
      (fn (_ item)
        (let ((tag (first item)))
          (match
            ((eq? tag (lit semi)) ())
            ((eq? tag (lit comma))
              (let ((zone ((m get (lit dialect)) get (lit zone)))
                    (col (m get (lit col))))
                (if (not (int< col (m get (lit last-comma)))) (%bx-newline m)
                  (%bx-spaces m (int- zone (int% col zone))))))
            ((eq? tag (lit tab))
              (%bx-spaces m (int- (%bx-byte (%bx-eval m (List second item))) (m get (lit col)))))
            ((eq? tag (lit spc)) (%bx-spaces m (%bx-byte (%bx-eval m (List second item)))))
            (#t
              (let ((v (%bx-eval m (List second item))))
                (if (pair? v) (%bx-out m (Str8 append (mbf->str v) " ")) (%bx-out m (%bx-string v))))))))
      items)
    (when (or (null? items)
              (not (List includes? (first (List last items)) (list (lit semi) (lit comma)))))
      (%bx-newline m))))

; --- DATA, READ and INPUT -------------------------------------------------

; Every DATA item of the program, in order: (LINE-NUMBER ITEM . ADDRESS),
; ADDRESS where READ finds the item in the line's text
(def %bx-restore!
  (fn (_ m)
    (m set! (lit data)
      (List flat-map
        (fn (_ i)
          (let ((line (%bx-line-ref m i)))
            (let ((items (List flat-map
                           (fn (_ st) (if (eq? (first st) (lit data)) (List second st) ()))
                           (List third line)))
                  (at (%bx-line-text m i)))
              (List map
                (fn (_ pr) (pair (first line) (pair (first pr) (int+ at (rest pr)))))
                (List zip items (List third (List ref 3 line)))))))
        (List range 0 (Vector length (m get (lit prog))))))))

; ITEM as a value for NAME: answers nil when a number was wanted and ITEM
; is not one.  A string read from the program's DATA at AT is pointed at
; there; one typed in answer, AT nil, has no place yet.
(def %bx-item
  (fn (_ m name item at)
    (if (%bx-string-name? name)
      (if (null? at) (List second item) (%bx-placed (List second item) at #f))
      (if (eq? (first item) (lit quoted)) ()
        (let ((text (Str8 trim (List second item))))
          (if (= (Str8 length text) 0) mbf-zero
            (let ((got (%bx-value m text)))
              (if (or (null? got) (not (null? (rest got)))) () (first got)))))))))

(def %bx-read
  (fn (_ m targets)
    (List for-each
      (fn (_ target)
        (let ((left (m get (lit data))))
          (when (null? left) (%bx-fail "OD"))
          (m set! (lit data) (rest left))
          (let ((v (%bx-item m (List second target) (List second (first left)) (rest (rest (first left))))))
            (when (null? v)
              (m set! (lit line) (first (first left)))
              (%bx-fail "SN"))
            (%bx-set! m target v))))
      targets)))

; A line typed in answer, which the terminal shows with its newline
(def %bx-reply
  (fn (_ m prompt)
    (%bx-out m prompt)
    (let ((line ((m get (lit in)))))
      (%bx-nulls m)
      line)))

; INPUT: answers end when the reply is empty, so the program stops
(def %bx-input
  (fn (_ m prompt targets)
    (let ((first-reply (%bx-reply m (Str8 append (if (null? prompt) "" prompt) "? "))))
      (let ((go (fn (self targets items)
                  (match
                    ((null? targets)
                      (do (unless (null? items) (do (%bx-out m "?EXTRA IGNORED") (%bx-newline m)))
                          ()))
                    ((null? items)
                      (let ((more (%bx-reply m "?? ")))
                        (if (or (null? more) (= (Str8 length more) 0)) (lit end)
                          (self targets (basic-items more)))))
                    (#t
                      (let ((v (%bx-item m (List second (first targets)) (first items) ())))
                        (if (null? v) (lit redo)
                          (do (%bx-set! m (first targets) v)
                              (self (rest targets) (rest items))))))))))
        (if (or (null? first-reply) (= (Str8 length first-reply) 0)) (lit end)
          (let ((r (go targets (basic-items first-reply))))
            (if (eq? r (lit redo))
              (do (%bx-out m "?REDO FROM START") (%bx-newline m)
                  (%bx-input m prompt targets))
              r)))))))

; --- LIST -----------------------------------------------------------------

(def %bx-list
  (fn (_ m from to)
    (List for-each
      (fn (_ line)
        (when (and (or (null? from) (not (int< (first line) from)))
                   (or (null? to) (not (int< to (first line)))))
          (%bx-newline m)
          (%bx-out m (Str8 append (mbf->str (mbf-int (first line))) " " (List second line)))))
      (m get (lit lines)))))

; --- statements -----------------------------------------------------------

; Where line INDEX begins
(def %bx-at-line
  (fn (_ m i) (pair i (List third (%bx-line-ref m i)))))

(def %bx-goto
  (fn (_ m n) (%bx-at-line m (%bx-find m n))))

; The stack without the FOR entry for NAME and the entries above it
(def %bx-drop-for
  (fn (_ stack name)
    (let ((go (fn (self s)
                (match
                  ((null? s) stack)
                  ((and (eq? (first (first s)) (lit for)) (str=? (List second (first s)) name)) (rest s))
                  (#t (self (rest s)))))))
      (go stack))))

; NEXT for NAME, nil for the innermost FOR: a position to loop to, or nil
; when the loop is done
(def %bx-next-one
  (fn (_ m name)
    (let ((go (fn (self s)
                (match
                  ((or (null? s) (not (eq? (first (first s)) (lit for)))) (%bx-fail "NF"))
                  ((or (null? name) (str=? (List second (first s)) name)) s)
                  (#t (self (rest s)))))))
      (let ((s (go (m get (lit stack)))))
        (let ((frame (first s)))
          (let ((var (List second frame)) (limit (List third frame)) (step (List ref 3 frame)))
            (let ((v (mbf-round (mbf-add (%bx-number-of m var) step))))
              (%bx-number-set! m var v)
              (if (int= (mbf-cmp v limit) (mbf-sgn step))
                (do (m set! (lit stack) (rest s)) ())
                (do (m set! (lit stack) s) (List ref 4 frame))))))))))

(def %bx-next
  (fn (_ m names)
    (if (null? names) (%bx-next-one m ())
      (let ((go (fn (self names)
                  (if (null? names) ()
                    (let ((to (%bx-next-one m (first names))))
                      (if (null? to) (self (rest names)) to))))))
        (go names)))))

(def %bx-return
  (fn (_ m)
    (let ((go (fn (self s)
                (match
                  ((null? s) (%bx-fail "RG"))
                  ((eq? (first (first s)) (lit gosub)) (do (m set! (lit stack) (rest s)) (List second (first s))))
                  (#t (self (rest s)))))))
      (go (m get (lit stack))))))

(def %bx-dim
  (fn (_ m decls)
    (List for-each
      (fn (_ d)
        (let ((arrays (m get (lit arrays))))
          (when (arrays has? (first d)) (%bx-fail "DD"))
          (arrays set! (first d)
            (%bx-array-make m (first d)
              (List map (fn (_ e) (%bx-int-in (%bx-eval m e) 0 32767)) (rest d))))))
      decls)))

; DEF FN NAME(ARG)=FORMULA: ?TM for a string name or argument, ?ID typed
; at the prompt
; at the prompt.  As DEF does: the function's entry found or made, then the
; argument's, and the function's value bytes the formula's place in the
; text (here the line's text) and the argument's value; the fifth, a byte DEF
; pushes, is left zero.
(def %bx-def
  (fn (_ m st)
    (let ((name (List second st)) (arg (List third st)))
      (let ((e (%bx-fn-at! m name)))
        (when (%bx-string-name? name) (%bx-fail "TM"))
        (when (null? (m get (lit line))) (%bx-fail "ID"))
        (let ((a (%bx-var-at! m arg)))
          (when (%bx-string-name? arg) (%bx-fail "TM"))
          (mem-word! (%bx-mem m) (int+ e 2) (%bx-line-text m (m get (lit index))))
          (mem-word! (%bx-mem m) (int+ e 4) a)
          ((m get (lit fns)) set! name (list arg (List ref 3 st) (m get (lit index)))))))))

; NULL N: N zero bytes after each new line from now on.  GETBYT takes 0 to
; 255, and NULL refuses 239 and above as unreasonable.
(def %bx-null
  (fn (_ m e)
    (let ((n (%bx-byte (%bx-eval m e))))
      (if (int< 238 n) (%bx-fail "FC") (m set! (lit nulls) n)))))

; POKE A,B: the address taken and checked before the byte (GETNUM)
(def %bx-poke
  (fn (_ m a b)
    (let ((at (%bx-address (%bx-eval m a))))
      (mem-poke! (%bx-mem m) at (%bx-byte (%bx-eval m b))))))

; WAIT A,M1[,M2]: until the byte at A, with M2's bits flipped, has one of
; M1's bits on (FNWAIT).  Only the program writes this memory, so a WAIT
; that does not hold at once waits for ever, as a KIM's does on an address
; nothing drives.
(def %bx-wait
  (fn (_ m a m1 m2)
    (let ((at (%bx-address (%bx-eval m a))))
      (let ((and-mask (%bx-byte (%bx-eval m m1))))
        (let ((eor-mask (if (null? m2) 0 (%bx-byte (%bx-eval m m2)))))
          (let ((go (fn (self)
                      (let ((b (mem-peek (%bx-mem m) at)))
                        (when (int= 0 (int& (int- (int| b eor-mask) (int& b eor-mask)) and-mask))
                          (self))))))
            (go)))))))

; The number a key GET takes reads as, as FIN reads it: a digit is its
; value; a blank, . + - E , or : is zero; any other key is ?SN, reported
; as at the prompt, since TRMNOK makes the line look typed there
(def %bx-key-number
  (fn (_ m k)
    (match
      ((and (not (int< k 48)) (int< k 58)) (mbf-int (int- k 48)))
      ((List includes? k (list 32 43 44 45 46 58 69)) mbf-zero)
      (#t (do (m set! (lit line) ()) (%bx-fail "SN"))))))

; GET V, ...: a key for each variable, waited for.  A string takes the key
; as it is; a number reads it (%bx-key-number), and a , or : left by the
; last one is ?EXTRA IGNORED, as VAREND finds it.  End of input ends the
; run, as an empty reply to INPUT does.
(def %bx-get-keys
  (fn (_ m targets)
    (let ((go (fn (self ts extra)
                (if (null? ts)
                  (do (when extra (%bx-out m "?EXTRA IGNORED") (%bx-newline m)) ())
                  (let ((k ((m get (lit key)))))
                    (if (null? k) (lit end)
                      (if (%bx-string-name? (List second (first ts)))
                        (do (%bx-set! m (first ts) (bytes->str (list k)))
                            (self (rest ts) #f))
                        (do (%bx-set! m (first ts) (%bx-key-number m k))
                            (self (rest ts) (or (int= k 44) (int= k 58)))))))))))
      (go targets #f))))

; TARGET = E, as LET runs it: a simple variable's entry is found or made
; before E is read
(def %bx-let!
  (fn (_ m target e)
    (when (eq? (first target) (lit var)) (%bx-var-at! m (List second target)))
    (%bx-set! m target (%bx-eval m e))))

; A statement run for its effect, which goes on to the next
(def %bx-effect
  (fn (_ m st tag)
    (match
      ((eq? tag (lit print)) (%bx-print m (List second st)))
      ((eq? tag (lit let)) (%bx-let! m (List second st) (List third st)))
      ((eq? tag (lit rem)) ())
      ((eq? tag (lit data)) ())
      ((eq? tag (lit dim)) (%bx-dim m (List second st)))
      ((eq? tag (lit read)) (%bx-read m (List second st)))
      ((eq? tag (lit restore)) (%bx-restore! m))
      ((eq? tag (lit list)) (%bx-list m (List second st) (List third st)))
      ((eq? tag (lit clear)) (%bx-clear! m))
      ((eq? tag (lit def)) (%bx-def m st))
      ((eq? tag (lit null)) (%bx-null m (List second st)))
      ((eq? tag (lit poke)) (%bx-poke m (List second st) (List third st)))
      ((eq? tag (lit wait)) (%bx-wait m (List second st) (List third st) (List ref 3 st)))
      ((eq? tag (lit bad)) (%bx-fail (List second st)))
      (#t (%bx-todo (List second st))))))

; A GOSUB's return, to the statements AFTER it on line INDEX, pushed
(def %bx-push-return!
  (fn (_ m index after)
    (m set! (lit stack) (pair (list (lit gosub) (pair index after)) (m get (lit stack))))))

(def %bx-for
  (fn (_ m st index after)
    (let ((name (List second st)))
      (do
        (%bx-let! m (list (lit var) name) (List third st))
        (let ((limit (mbf-round (%bx-number (%bx-eval m (List ref 3 st)))))
              (step (if (null? (List ref 4 st)) (mbf-int 1)
                      (mbf-round (%bx-number (%bx-eval m (List ref 4 st)))))))
          (m set! (lit stack)
            (pair (list (lit for) name limit step (pair index after))
                  (%bx-drop-for (m get (lit stack)) name))))
        ()))))

(def %bx-on
  (fn (_ m st index after)
    (let ((k (%bx-byte (%bx-eval m (List second st)))) (ns (List ref 3 st)))
      (if (or (int= k 0) (int< (List length ns) k)) ()
        (let ((to (%bx-goto m (List ref (int- k 1) ns))))
          (do (when (eq? (List third st) (lit gosub)) (%bx-push-return! m index after))
              to))))))

(def %bx-run-statement
  (fn (_ m st)
    (do (%bx-clear! m)
        (match
          ((not (null? (List second st))) (%bx-goto m (List second st)))
          ((int= (Vector length (m get (lit prog))) 0) (lit end))
          (#t (%bx-at-line m 0))))))

(def %bx-new
  (fn (_ m)
    (do (%bx-program! m ())
        (lit end))))

(def %bx-cont
  (fn (_ m index)
    (let ((at (m get (lit cont))))
      (if (or (int< -1 index) (null? at)) (%bx-fail "CN") at))))

; Statement ST, run with the statements AFTER it on line INDEX
(def %bx-statement
  (fn (_ m st index after)
    (let ((tag (first st)))
      (match
        ((eq? tag (lit goto)) (%bx-goto m (List second st)))
        ((eq? tag (lit gosub))
          (let ((to (%bx-goto m (List second st))))
            (do (%bx-push-return! m index after) to)))
        ((eq? tag (lit return)) (%bx-return m))
        ((eq? tag (lit if))
          (if (mbf-zero? (%bx-number (%bx-eval m (List second st)))) (lit next-line) ()))
        ((eq? tag (lit for)) (%bx-for m st index after))
        ((eq? tag (lit next)) (%bx-next m (List second st)))
        ((eq? tag (lit end)) (lit end))
        ((eq? tag (lit stop)) (lit stop))
        ((eq? tag (lit on)) (%bx-on m st index after))
        ((eq? tag (lit input))
          (if (int< index 0) (%bx-fail "ID") (%bx-input m (List second st) (List third st))))
        ((eq? tag (lit get))
          (if (int< index 0) (%bx-fail "ID") (%bx-get-keys m (List second st))))
        ((eq? tag (lit run)) (%bx-run-statement m st))
        ((eq? tag (lit new)) (%bx-new m))
        ((eq? tag (lit cont)) (%bx-cont m index))
        (#t (do (%bx-effect m st tag) ()))))))

; The statements of line INDEX, -1 the line typed
(def %bx-statements
  (fn (_ m index)
    (if (int< index 0) (m get (lit direct)) (List third (%bx-line-ref m index)))))

; The position after the end of line INDEX, or nil at the program's end
(def %bx-after-line
  (fn (_ m index)
    (let ((i (int+ index 1)))
      (if (or (int< index 0) (not (int< i (Vector length (m get (lit prog)))))) ()
        (%bx-at-line m i)))))

; How many statements run between collects
(def %bx-sweep-every 4096)

; A collect once every %bx-sweep-every statements
(def %bx-sweep
  (fn (_ m)
    (let ((n (int+ (m get-or 0 (lit steps)) 1)))
      (if (int< n %bx-sweep-every) (m set! (lit steps) n)
        (do (m set! (lit steps) 0) (Heap collect))))))

; Run from POS to an END, a STOP or the program's end: answers end or stop
(def %bx-run
  (fn (_ m pos)
    (let ((go (fn (self pos)
                (if (null? pos) (lit end)
                  (let ((index (first pos)) (sts (rest pos)))
                    (if (null? sts) (self (%bx-after-line m index))
                      (do
                        (%bx-sweep m)
                        (m set! (lit index) index)
                        (m set! (lit line) (if (int< index 0) () (first (%bx-line-ref m index))))
                        (let ((r (%bx-statement m (first sts) index (rest sts))))
                          (match
                            ((null? r) (self (pair index (rest sts))))
                            ((eq? r (lit next-line)) (self (%bx-after-line m index)))
                            ((or (eq? r (lit end)) (eq? r (lit stop)))
                              (do (m set! (lit cont) (pair index (rest sts))) r))
                            (#t (self r)))))))))))
      (go pos))))

; --- a line typed ---------------------------------------------------------

; " IN  N" for a line of the program, nothing for the line typed
(def %bx-where
  (fn (_ m)
    (let ((n (m get (lit line))))
      (if (null? n) "" (Str8 append " IN " (mbf->str (mbf-int n)))))))

(def %bx-ready
  (fn (_ m)
    (%bx-newline m)
    (%bx-out m ((m get (lit dialect)) get (lit ready)))
    (%bx-newline m)))

; The statements of TEXT run as the line typed
(def %bx-direct
  (fn (_ m text)
    (m set! (lit direct) (basic-parse-line (basic-lex (m get (lit dialect)) text)))
    (m set! (lit line) ())
    (let ((r (%bx-guarded (fn (_) (%bx-run m (pair -1 (m get (lit direct))))))))
      (match
        ((eq? r (lit stop))
          (do (%bx-newline m)
              (%bx-out m (Str8 append "BREAK" (%bx-where m)))))
        ((eq? r (lit end)) ())
        (#t (%bx-report m r))))
    (%bx-ready m)))

; What THUNK answers, or the BASIC error it raises
(def %bx-guarded
  (fn (_ thunk)
    (guard (e (if (or (eq? (Err label e) (lit basic)) (eq? (Err label e) (lit basic-todo)))
                e (error e)))
      (thunk))))

; The error R printed, the stack emptied
(def %bx-report
  (fn (_ m r)
    (m set! (lit stack) ())
    (m set! (lit cont) ())
    (%bx-newline m)
    (%bx-out m
      (if (eq? (Err label r) (lit basic))
        (Str8 append "?" (Err text r) " ERROR" (%bx-where m))
        (Str8 append "?" (Err text r) " IS NOT IN X-BASIC YET" (%bx-where m))))))

; Line N stored; ?OM when it does not fit, and the ready prompt after it
(def %bx-stored
  (fn (_ m n text)
    (m set! (lit line) ())
    (let ((r (%bx-guarded (fn (_) (do (%bx-store! m n text) ())))))
      (unless (null? r)
        (%bx-report m r)
        (%bx-ready m)))))

; A line stored when it starts with a line number, else run.  The digits
; and the blanks after them are the number, as LINGET reads them.
(def %bx-typed
  (fn (_ m text)
    (let ((n (Str8 length text)))
      (let ((skip (fn (self i) (if (and (int< i n) (int= (str-byte-ref text i) 32)) (self (int+ i 1)) i))))
        (let ((start (skip 0)))
          (if (and (int< start n)
                   (not (int< (str-byte-ref text start) 48)) (not (int< 57 (str-byte-ref text start))))
            (let ((go (fn (self i k)
                        (match
                          ((not (int< i n)) (pair k i))
                          ((int= (str-byte-ref text i) 32) (self (int+ i 1) k))
                          ((and (not (int< (str-byte-ref text i) 48)) (not (int< 57 (str-byte-ref text i))))
                            (self (int+ i 1) (int+ (int* k 10) (int- (str-byte-ref text i) 48))))
                          (#t (pair k i))))))
              (let ((got (go start 0)))
                (if (int< (first got) 64000)
                  (%bx-stored m (first got) (Str8 sub (rest got) (int- n (rest got)) text))
                  (%bx-direct m text))))
            (%bx-direct m text)))))))

; --- starting up ----------------------------------------------------------

; The number LINGET reads from TEXT, blanks anywhere, with nothing after it:
; nil when TEXT is not one or it passes 63999
(def %bx-linget
  (fn (_ text)
    (let ((n (Str8 length text)))
      (let ((go (fn (self i k digits)
                  (match
                    ((not (int< i n)) (if digits k ()))
                    ((int= (str-byte-ref text i) 32) (self (int+ i 1) k digits))
                    ((and (not (int< (str-byte-ref text i) 48)) (not (int< 57 (str-byte-ref text i))))
                      (let ((k (int+ (int* k 10) (int- (str-byte-ref text i) 48))))
                        (if (int< 63999 k) () (self (int+ i 1) k #t))))
                    (#t ())))))
        (go 0 0 #f)))))

; Whether TEXT is blank, as the first CHRGET finds it
(def %bx-blank? (fn (_ text) (or (null? text) (= (Str8 length (Str8 trim text)) 0))))

; The machine started as the dialect's does (INIT): MEMORY SIZE? (blank
; for all the RAM the dialect has) and WIDTH? (blank for its width), each
; asked again until it is answered with a number it takes, then the bytes
; free and the dialect's banner.  basic-boot-prompt is the question the
; machine is waiting on, nil once it has started; basic-boot-answer! takes
; the line typed in answer.
(def basic-boot-prompt
  (fn (_ m)
    (let ((dialect (m get (lit dialect))))
      (match
        ((eq? (m get (lit boot)) (lit memory)) (Str8 append (dialect get (lit memory-prompt)) "? "))
        ((eq? (m get (lit boot)) (lit width)) (Str8 append (dialect get (lit width-prompt)) "? "))
        (#t ())))))

(def basic-boot-answer!
  (fn (_ m reply)
    (%bx-nulls m)
    (let ((dialect (m get (lit dialect))) (start ((m get (lit dialect)) get (lit txttab))))
      (if (eq? (m get (lit boot)) (lit memory))
        (let ((k (if (%bx-blank? reply) (dialect get (lit ram-top)) (%bx-linget reply))))
          (unless (or (null? k) (not (int< (int+ start 2) k)))
            (m set! (lit mem) (mem-make start k))
            (m set! (lit boot) (lit width))))
        (let ((k (if (%bx-blank? reply) (m get (lit width)) (%bx-linget reply))))
          (unless (or (null? k) (int< k 16) (int< 255 k))
            (unless (%bx-blank? reply) (%bx-width! m k (int- k (int% k (dialect get (lit zone))))))
            (m set! (lit boot) ())
            (%bx-clear! m)
            (%bx-newline m)
            (%bx-out m (Str8 append (mbf->str (mbf-int (int- (mem-at (%bx-mem m) (lit memsiz)) start)))
                                    " BYTES FREE"))
            (%bx-newline m)
            (%bx-newline m)
            (List for-each (fn (_ line) (%bx-out m line) (%bx-newline m)) (dialect get (lit banner)))
            (%bx-ready m)))))))

; The machine started, its questions asked and answered with IN's lines
(def basic-boot
  (fn (_ m)
    (m set! (lit boot) (lit memory))
    (%bx-newline m)
    (let ((go (fn (self)
                (let ((prompt (basic-boot-prompt m)))
                  (unless (null? prompt)
                    (%bx-out m prompt)
                    (basic-boot-answer! m ((m get (lit in))))
                    (self))))))
      (go))))

; The machine made to wait on its start-up questions: the lines typed
; until it has started answer basic-boot-prompt
(def basic-boot-begin!
  (fn (_ m) (do (m set! (lit boot) (lit memory)) ())))

; A line typed, upper-cased outside its strings, REM and DATA when the
; machine folds case.  The terminal has shown its new line; the zero bytes
; after it are the machine's, as INLIN ends with CRDO.
(def basic-type
  (fn (_ m text)
    (%bx-nulls m)
    (%bx-typed m (if (m get (lit fold-case)) (basic-fold (m get (lit dialect)) text) text))))

(provide basic/exec basic-machine basic-boot basic-boot-begin! basic-boot-prompt basic-boot-answer!
  basic-type)
