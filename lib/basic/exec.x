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
; One machine runs every dialect.  What differs is the dialect's: its
; numbers are a kit of operations (zero, int, add, cmp, fit, ->bytes ...),
; its variables lie in memory as its layout says, and it names the texts
; it prints.  A value is a number when it is a pair (each kit's numbers
; are), else a string.
;
; A position is (INDEX . STATEMENTS): the line's place in the program, -1
; for the line typed, and the statements still to run on it.  A statement
; answers nil to go on, a position to go to, next-line to skip the rest of
; its line, or end or stop.
;
; An error is (Err raise 'basic CODE), CODE the 6502's two letters, which
; the dialect prints its way.  A statement this bundle does not run yet
; raises 'basic-todo with its word.  A kit may raise 'basic-overflow or
; 'basic-div0 where its BASIC prints the error and goes on, the number it
; goes on with the raise's value.

(module basic/exec)
(import x/type/list)
(import x/type/str)
(import x/type/dict)
(import x/type/vector)
(import x/type/err)
(import x/type/assoc)
(import x/core/doors int+ int- int* int/ int% int< int= int<< int>> int& int| str-byte-ref)
(import basic/mbf mbf-zero mbf-int mbf-sgn mbf-cmp mbf-floor mbf->int mbf-exponent mbf-mantissa mbf-fac)
(import basic/lex basic-lex basic-fold basic-crunch basic-detokenize)
(import basic/tape tape-save tape-load)
(import basic/cpu cpu-make cpu-call!)
(import basic/parse basic-parse-line basic-parse-value basic-items)
(import basic/mem
  mem-peek mem-poke! mem-word mem-word! mem-write! mem-read mem-make mem-at mem-clear! mem-string!
  mem-free mem-program! mem-var mem-var! mem-array-new! mem-array-erase! mem-element)

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
      (m set! (lit numbers) (dialect get (lit numbers)))
      (m set! (lit layout) (dialect get (lit layout)))
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
      (m set! (lit mem) (mem-make (m get (lit layout)) (dialect get (lit txttab)) (dialect get (lit ram-top))))
      (m set! (lit lines) ())
      ; RND's last value; CLEAR and RUN leave it unless the kit says they
      ; put the seed back
      (m set! (lit rnd) ((m get (lit numbers)) get-or () (lit rnd-seed)))
      ; the file SAVE writes a cassette record to and LOAD reads one from
      (m set! (lit tape) "basic.tape")
      ; ERR, the last error's number (ERRFLG)
      (m set! (lit err) 0)
      (%bx-index! m ())
      (%bx-clear! m)
      (when (dialect has? (lit fac)) (%bx-page-zero! m))
      m)))

; The kit's operation KEY
(def %bx-kit (fn (_ m key) ((m get (lit numbers)) get key)))

; The layout's door KEY
(def %bx-layout (fn (_ m key) ((m get (lit layout)) get key)))

(def %bx-dialect (fn (_ m key) ((m get (lit dialect)) get key)))

; What INIT leaves in page zero for USR: ADRAYI and ADRGAY, and USRPOK a
; JMP to FCERR
(def %bx-page-zero!
  (fn (_ m)
    (let ((mem (%bx-mem m)) (d (m get (lit dialect))))
      (mem-word! mem (d get (lit adrayi)) (d get (lit ayint)))
      (mem-word! mem (d get (lit adrgay)) (d get (lit givayf)))
      (mem-poke! mem (d get (lit usrpok)) 76)
      (mem-word! mem (int+ (d get (lit usrpok)) 1) (d get (lit fcerr))))))

(def %bx-width!
  (fn (_ m width last-comma)
    (m set! (lit width) width)
    (m set! (lit last-comma) last-comma)))

(def %bx-mem (fn (_ m) (m get (lit mem))))

; Variables, arrays and the stack emptied, and DATA read from the start
(def %bx-clear!
  (fn (_ m)
    (mem-clear! (%bx-mem m))
    ; where each simple variable's value is in memory, by name and type;
    ; the value itself is only in memory, so a POKE into it is read back
    (m set! (lit var-at) (Dict make))
    ; each array by name and type: (BOUNDS OFFSET), OFFSET its header's
    ; from ARYTAB
    (m set! (lit arrays) (Dict make))
    ; DEF's functions, by name: (ARG FORMULA INDEX), INDEX the DEF's line
    (m set! (lit fns) (Dict make))
    (m set! (lit stack) ())
    (m set! (lit cont) ())
    ; each letter's type for a name with no sign (DEFTBL), and the lowest
    ; subscript (OPTVAL), with whether OPTION BASE has set it (OPTFLG)
    (m set! (lit deftbl) (Vector make 26 (%bx-dialect m (lit default-type))))
    (m set! (lit base) 0)
    (m set! (lit option) #f)
    (when ((m get (lit numbers)) get-or #f (lit rnd-clear))
      (m set! (lit rnd) (%bx-kit m (lit rnd-seed))))
    ; ON ERROR's line (ONELIN), whether its routine is running (ONEFLG),
    ; and the last error's line (ERRLIN); ERR's number is kept
    (m set! (lit on-error) ())
    (m set! (lit in-error) #f)
    (m set! (lit erl) 0)
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

; Line N of TEXT in DIALECT: (NUMBER TEXT STATEMENTS CRUNCHED), CRUNCHED as
; basic-crunch gives it
(def %bx-line
  (fn (_ dialect n text)
    (list n text (basic-parse-line dialect (basic-lex dialect text)) (basic-crunch dialect text))))

; Line N's text stored, or the line removed when TEXT is blank
(def %bx-store!
  (fn (_ m n text)
    ; the error trap cleared first, so ?OM is not trapped
    (m set! (lit on-error) ())
    (let ((kept (List filter (fn (_ l) (not (int= (first l) n))) (m get (lit lines))))
          (dialect (m get (lit dialect))))
      (%bx-program! m
        (if (= (Str8 length (Str8 trim text)) 0) kept
          (let ((line (%bx-line dialect n text)))
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

; The new line the dialect begins before an error and its ready prompt:
; always, or only when the column is not 0 (CRDONZ)
(def %bx-fresh
  (fn (_ m)
    (when (or (eq? (%bx-dialect m (lit fresh-line)) (lit always)) (int< 0 (m get (lit col))))
      (%bx-newline m))))

(def %bx-spaces
  (fn (_ m n) (when (int< 0 n) (%bx-out m (Str8 repeat n " ")))))

; Line number N as LINPRT prints it: with the blank its sign leaves, or
; without it (the 8086's STROUI starts past it)
(def %bx-linprt
  (fn (_ m n)
    (Str8 append (if (eq? (%bx-dialect m (lit linprt)) (lit sign)) " " "") (Str8 str n))))

; --- values ---------------------------------------------------------------

; A string is #(BYTES ADDRESS VAR?): BYTES its bytes, a list, so a zero
; byte is one like any other (an x string ends at its first); ADDRESS
; where it is in memory, in the program's text or in string space, or nil
; when it has no place yet (a function's answer, a constant typed at the
; prompt, a reply to INPUT); VAR? when it was read from a variable.
(def %bx-number
  (fn (_ v) (if (pair? v) v (%bx-fail "TM"))))

(def %bx-placed (fn (_ bytes a var?) (Vector from-list (list bytes a var?))))

; A string of BYTES with no place yet
(def %bx-text (fn (_ bytes) (%bx-placed bytes () #f)))

; The x string S as a string with no place yet
(def %bx-text-of (fn (_ s) (%bx-text (%bx-bytes s))))

; V's bytes, ?TM for a number
(def %bx-string
  (fn (_ v) (if (pair? v) (%bx-fail "TM") (Vector ref 0 v))))

; BYTES up to the first zero, as an x string: what FIN reads, which a zero
; ends
(def %bx-x-string
  (fn (_ bytes)
    (let ((go (fn (self bs acc)
                (if (or (null? bs) (int= (first bs) 0)) (bytes->str (List reverse acc))
                  (self (rest bs) (pair (first bs) acc))))))
      (go bytes ()))))

; BYTES as the x string the terminal is given: a zero byte is not sent
(def %bx-shown
  (fn (_ bytes) (bytes->str (List filter (fn (_ b) (not (int= b 0))) bytes))))

; V checked to be a string, its place kept
(def %bx-string-value
  (fn (_ v) (do (%bx-string v) v)))

; The string at the descriptor D in memory, read from it
(def %bx-string-at
  (fn (_ m d)
    (let ((mem (%bx-mem m)))
      (let ((n (mem-peek mem d)) (a (mem-word mem (int+ d 1))))
        (%bx-placed (if (int= n 0) () (mem-read mem a n)) a #t)))))

; The string V put at the descriptor D (GETSPT and COPY): text with no
; place is given space; a string read from a variable is copied when it is
; in string space; one in the program's text is pointed at where it is
(def %bx-string-to!
  (fn (_ m d v)
    (let ((mem (%bx-mem m)) (bytes (%bx-string v)))
      (let ((n (List length bytes)))
        (let ((a (if (or (null? (Vector ref 1 v))
                         (and (Vector ref 2 v) (not (int< (Vector ref 1 v) (mem-at mem (lit fretop))))))
                   (if (int= n 0) 0 (mem-string! mem bytes))
                   (Vector ref 1 v))))
          (mem-word! mem (int+ d 1) a)
          (%bx-poke-byte! m d n))))))

(def %bx-poke-byte! (fn (_ m a b) (mem-write! (%bx-mem m) a (list b))))

; TEXT's bytes, as a list
(def %bx-bytes
  (fn (_ text)
    (let ((go (fn (self i acc) (if (int< i 0) acc (self (int- i 1) (pair (str-byte-ref text i) acc))))))
      (go (int- (Str8 length text) 1) ()))))

; A number as an integer from LO to HI, as the kit makes one (the 6502's
; INT, the 8086's CINT); ?FC outside
(def %bx-int-in
  (fn (_ m v lo hi)
    (let ((n ((%bx-kit m (lit integer)) (%bx-number v))))
      (if (or (int< n lo) (int< hi n)) (%bx-fail "FC") n))))

(def %bx-byte (fn (_ m v) (%bx-int-in m v 0 255)))
; An address, as GETADR takes one: ?FC below 0 or past 65535
(def %bx-address (fn (_ m v) (%bx-int-in m v 0 65535)))
(def %bx-word (fn (_ m v) (%bx-int-in m v -32768 32767)))

(def %bx-int (fn (_ m n) ((%bx-kit m (lit int)) n)))

(def %bx-truth (fn (_ m b) (%bx-int m (if b -1 0))))

; A string of BYTES no longer than 255
(def %bx-checked
  (fn (_ bytes) (if (int< 255 (List length bytes)) (%bx-fail "LS") (%bx-text bytes))))

; --- names and types ------------------------------------------------------

; NAME without its type sign
(def %bx-base
  (fn (_ name)
    (let ((n (Str8 length name)))
      (if (Str8 includes? (Str8 sub (int- n 1) 1 name) "$%!#") (Str8 sub 0 (int- n 1) name) name))))

; NAME's VALTYP: 3 a string, 2 an integer, 4 a single (the 6502's real), 8
; a double; with no sign, its first letter's in DEFTBL
(def %bx-type
  (fn (_ m name)
    (let ((c (Str8 sub (int- (Str8 length name) 1) 1 name)))
      (match
        ((str=? c "$") 3)
        ((str=? c "%") 2)
        ((str=? c "!") 4)
        ((str=? c "#") 8)
        (#t (Vector ref (int- (str-byte-ref name 0) 65) (m get (lit deftbl))))))))

(def %bx-string-name? (fn (_ m name) (int= (%bx-type m name) 3)))

; NAME's key among the variables: its base and its type, so A and A! are
; one variable where A's letter is single, and A% another
(def %bx-key
  (fn (_ m name) (Str8 append (%bx-base name) (bytes->str (list (int+ 48 (%bx-type m name)))))))

; NAME's header in memory, as the layout writes it
(def %bx-header
  (fn (_ m name) ((%bx-layout m (lit var-header)) (%bx-base name) (%bx-type m name))))

(def %bx-element-size
  (fn (_ m name) ((%bx-layout m (lit element-size)) (%bx-type m name))))

; A number V made fit to be stored in NAME; a string is checked and keeps
; its place
(def %bx-fit
  (fn (_ m name v)
    (if (%bx-string-name? m name) (%bx-string-value v)
      ((%bx-kit m (lit fit)) (%bx-type m name) (%bx-number v)))))

(def %bx-default
  (fn (_ m name)
    (if (%bx-string-name? m name) (%bx-text ()) ((%bx-kit m (lit fit)) (%bx-type m name) (%bx-kit m (lit zero))))))

; --- variables and arrays -------------------------------------------------

; The value bytes of the number V for NAME
(def %bx-number-bytes
  (fn (_ m name v) ((%bx-kit m (lit ->bytes)) (%bx-type m name) v)))

; Where NAME's value is in memory, or nil when it has no entry
(def %bx-var-at
  (fn (_ m name)
    (let ((at (m get (lit var-at))) (key (%bx-key m name)))
      (if (at has? key) (at get key)
        (let ((h (%bx-header m name)))
          (let ((e (mem-var (%bx-mem m) h)))
            (if (null? e) ()
              (let ((a (int+ e (List length h)))) (do (at set! key a) a)))))))))

; Where NAME's value is, its entry made when it has none
(def %bx-var-at!
  (fn (_ m name)
    (let ((a (%bx-var-at m name)))
      (if (not (null? a)) a
        (let ((h (%bx-header m name)))
          (let ((a (int+ (mem-var! (%bx-mem m) h ((%bx-layout m (lit value-size)) (%bx-type m name)))
                         (List length h))))
            ((m get (lit var-at)) set! (%bx-key m name) a)
            a))))))

; The number V stored in the simple variable NAME, its bytes written
(def %bx-number-set!
  (fn (_ m name v)
    (mem-write! (%bx-mem m) (%bx-var-at! m name) (%bx-number-bytes m name v))))

; The number for NAME in the bytes at A
(def %bx-number-at
  (fn (_ m name a)
    ((%bx-kit m (lit from-bytes)) (%bx-type m name) (mem-read (%bx-mem m) a (%bx-element-size m name)))))

; The simple variable NAME's number, zero when it has no entry (ISVAR
; makes none)
(def %bx-number-of
  (fn (_ m name)
    (let ((a (%bx-var-at m name))) (if (null? a) (%bx-default m name) (%bx-number-at m name a)))))

; An array of NAME, each subscript to BOUNDS: (BOUNDS OFFSET), OFFSET its
; header's from ARYTAB, which a new simple variable moves but not that
(def %bx-array-make
  (fn (_ m name bounds)
    (let ((sizes (List map (fn (_ b) (int+ b 1)) bounds)))
      (let ((a (mem-array-new! (%bx-mem m) (%bx-header m name) sizes (%bx-element-size m name))))
        (list bounds (int- a (mem-at (%bx-mem m) (lit arytab))))))))

; Where the element K of NAME's array A is
(def %bx-element-at
  (fn (_ m name a k)
    (let ((mem (%bx-mem m)))
      (mem-element mem (int+ (mem-at mem (lit arytab)) (List second a)) k (%bx-element-size m name)))))

; NAME's array, made with COUNT subscripts of the dialect's size when it
; has not been
(def %bx-array
  (fn (_ m name count)
    (let ((arrays (m get (lit arrays))) (key (%bx-key m name)))
      (unless (arrays has? key)
        (arrays set! key
          (%bx-array-make m name
            (List map (fn (_ i) (int- (int- (%bx-dialect m (lit array-size)) 1) (m get (lit base))))
                      (List range 0 count)))))
      (arrays get key))))

; The subscript V less the lowest, ?BS for one below it (LNGNAM)
(def %bx-subscript
  (fn (_ m v)
    (let ((i (%bx-int-in m v 0 32767)) (base (m get (lit base))))
      (if (int< i base) (%bx-fail "BS") (int- i base)))))

; The element of SUBSCRIPTS in the array A, counted with the first
; subscript fastest (GETDEF)
(def %bx-slot
  (fn (_ m a subscripts)
    (unless (int= (List length subscripts) (List length (first a))) (%bx-fail "BS"))
    (List fold
      (fn (_ at pr)
        (let ((i (%bx-subscript m (rest pr))))
          (when (int< (first pr) i) (%bx-fail "BS"))
          (int+ (int* at (int+ (first pr) 1)) i)))
      0 (List reverse (List zip (first a) subscripts)))))

(def %bx-get
  (fn (_ m target)
    (let ((name (List second target)))
      (if (eq? (first target) (lit var))
        (if (%bx-string-name? m name)
          (let ((a (%bx-var-at m name))) (if (null? a) (%bx-text ()) (%bx-string-at m a)))
          (%bx-number-of m name))
        (let ((args (List map (fn (_ e) (%bx-eval m e)) (List third target))))
          (let ((a (%bx-array m name (List length args))))
            (let ((at (%bx-element-at m name a (%bx-slot m a args))))
              (if (%bx-string-name? m name) (%bx-string-at m at) (%bx-number-at m name at)))))))))

(def %bx-set!
  (fn (_ m target v)
    (let ((name (List second target)))
      (if (eq? (first target) (lit var))
        (if (%bx-string-name? m name)
          (%bx-string-to! m (%bx-var-at! m name) (%bx-fit m name v))
          (%bx-number-set! m name (%bx-fit m name v)))
        (let ((args (List map (fn (_ e) (%bx-eval m e)) (List third target))))
          (let ((a (%bx-array m name (List length args))) (fit (%bx-fit m name v)))
            (let ((at (%bx-element-at m name a (%bx-slot m a args))))
              (if (%bx-string-name? m name) (%bx-string-to! m at fit)
                (mem-write! (%bx-mem m) at (%bx-number-bytes m name fit))))))))))

; MID$(TARGET, N, M) = E (LHSMID): the string's bytes from position N
; replaced by E's, no more than M of them, nor past its end; its length
; kept.  A string in the program's text is copied to string space first.
; N is 1 to 255 and no more than the length, M 0 to 255 (255 when not
; given, nothing done for 0); ?FC else.
(def %bx-mid!
  (fn (_ m target n-e m-e e)
    (let ((name (List second target)) (mem (%bx-mem m)))
      (unless (%bx-string-name? m name) (%bx-fail "TM"))
      (let ((d (if (eq? (first target) (lit var)) (%bx-var-at! m name)
                 (let ((args (List map (fn (_ e) (%bx-eval m e)) (List third target))))
                   (let ((a (%bx-array m name (List length args))))
                     (%bx-element-at m name a (%bx-slot m a args)))))))
        (let ((len (mem-peek mem d)) (at (mem-word mem (int+ d 1))))
          (when (and (int< 0 len) (int< at (mem-at mem (lit fretop))))
            (mem-word! mem (int+ d 1) (mem-string! mem (mem-read mem at len))))
          (let ((n (%bx-byte m (%bx-eval m n-e))))
            (when (int= n 0) (%bx-fail "FC"))
            (let ((most (if (null? m-e) 255 (%bx-byte m (%bx-eval m m-e))))
                  (bytes (%bx-string (%bx-eval m e))))
              (unless (int= most 0)
                (when (int< len n) (%bx-fail "FC"))
                (let ((room (int+ (int- len n) 1)))
                  (let ((k (List fold (fn (_ a b) (if (int< b a) b a)) room
                             (list most (List length bytes)))))
                    (unless (int= k 0)
                      (mem-write! mem (int+ (mem-word mem (int+ d 1)) (int- n 1))
                                  (List take k bytes)))))))))))))

; --- expressions ----------------------------------------------------------

; A 16-bit two's complement word as a signed integer
(def %bx-signed
  (fn (_ w) (if (int< w 32768) w (int- w 65536))))

; What THUNK answers.  Where the kit raises the overflow or the division
; by zero its BASIC goes on from, the error is printed where the cursor
; is, a new line begun, and the answer is the number the raise carries;
; while ON ERROR is set it is an error, which the trap takes (TRAPER).
(def %bx-soft
  (fn (_ m thunk)
    (guard (e (let ((label (Err label e)))
                (if (or (eq? label (lit basic-overflow)) (eq? label (lit basic-div0)))
                  (let ((code (if (eq? label (lit basic-div0)) "/0" "OV")))
                    (if (not (null? (m get-or () (lit on-error)))) (%bx-fail code)
                      (do (%bx-out m ((%bx-dialect m (lit error-text)) code))
                          (%bx-newline m)
                          (Assoc get (lit value) (e data)))))
                  (error e))))
      (thunk))))

; The kit's operation KEY on A and B
(def %bx-arith
  (fn (_ m key a b)
    (let ((op (%bx-kit m key)))
      (when (null? op) (%bx-todo (if (eq? key (lit power)) "^" (Str8 str key))))
      (%bx-soft m (fn (_) (op a b))))))

; A and B as 16-bit words, joined by F, the answer an integer
(def %bx-logic
  (fn (_ m f a b)
    (%bx-int m (%bx-signed (int& (f (int& (%bx-word m a) 65535) (int& (%bx-word m b) 65535)) 65535)))))

(def %bx-op
  (fn (_ m word a b)
    (match
      ((str=? word "+")
        (if (and (not (pair? a)) (not (pair? b))) (%bx-checked (List append (%bx-string a) (%bx-string b)))
          (%bx-arith m (lit add) (%bx-number a) (%bx-number b))))
      ((str=? word "-") (%bx-arith m (lit sub) (%bx-number a) (%bx-number b)))
      ((str=? word "*") (%bx-arith m (lit mul) (%bx-number a) (%bx-number b)))
      ((str=? word "/") (%bx-arith m (lit div) (%bx-number a) (%bx-number b)))
      ((str=? word "^") (%bx-arith m (lit power) (%bx-number a) (%bx-number b)))
      ((str=? word "\\") (%bx-arith m (lit idiv) (%bx-number a) (%bx-number b)))
      ((str=? word "MOD") (%bx-arith m (lit mod) (%bx-number a) (%bx-number b)))
      ((str=? word "AND") (%bx-logic m (fn (_ x y) (int& x y)) a b))
      ((str=? word "OR") (%bx-logic m (fn (_ x y) (int| x y)) a b))
      ((str=? word "XOR") (%bx-logic m (fn (_ x y) (int- (int| x y) (int& x y))) a b))
      ((str=? word "EQV") (%bx-logic m (fn (_ x y) (int- 65535 (int- (int| x y) (int& x y)))) a b))
      (#t (%bx-logic m (fn (_ x y) (int| (int- 65535 x) y)) a b)))))

; -1, 0 or 1 comparing two strings' bytes A and B one by one
(def %bx-str-cmp
  (fn (_ a b)
    (match
      ((null? a) (if (null? b) 0 -1))
      ((null? b) 1)
      ((int< (first a) (first b)) -1)
      ((int< (first b) (first a)) 1)
      (#t (%bx-str-cmp (rest a) (rest b))))))

(def %bx-rel
  (fn (_ m mask a b)
    (let ((c (match
               ((and (pair? a) (pair? b)) ((%bx-kit m (lit cmp)) a b))
               ((or (pair? a) (pair? b)) (%bx-fail "TM"))
               (#t (%bx-str-cmp (%bx-string a) (%bx-string b))))))
      (%bx-truth m (not (int= 0 (int& mask (match ((int< c 0) 1) ((int= c 0) 2) (#t 4)))))))))

; The number at the start of TEXT, as VAL and INPUT read it, or nil
(def %bx-value
  (fn (_ m text)
    (let ((d (m get (lit dialect))))
      (let ((got (basic-parse-value d (basic-lex d text))))
        (if (null? got) () (pair (%bx-eval m (first got)) (rest got)))))))

; --- USR ------------------------------------------------------------------

; Number V put in the FAC as the 6502 holds it unpacked: FACEXP, the four
; mantissa bytes, FACSGN 0 or $FF, and FACOV the guard byte
(def %bx-fac!
  (fn (_ m v)
    (let ((mem (%bx-mem m)) (fac (%bx-dialect m (lit fac))) (mag (mbf-mantissa v)))
      (mem-poke! mem fac (mbf-exponent v))
      (mem-write! mem (int+ fac 1)
        (list (int& (int>> mag 32) 255) (int& (int>> mag 24) 255) (int& (int>> mag 16) 255)
              (int& (int>> mag 8) 255) (if (int< (mbf-sgn v) 0) 255 0)))
      (mem-poke! mem (%bx-dialect m (lit facov)) (int& mag 255)))))

; The number in the FAC, normalised as FADD would leave it
(def %bx-fac
  (fn (_ m)
    (let ((mem (%bx-mem m)) (fac (%bx-dialect m (lit fac))))
      (let ((ex (mem-peek mem fac)) (b (mem-read mem (int+ fac 1) 5)))
        (if (int= ex 0) mbf-zero
          (mbf-fac (not (int< (List ref 4 b) 128))
            (int+ (int<< (int+ (int<< (int+ (int<< (int+ (int<< (first b) 8) (List second b)) 8) (List third b)) 8)
                                  (List ref 3 b)) 8)
                  (mem-peek mem (%bx-dialect m (lit facov))))
            (int- ex 168)))))))

; The ROM routines a USR routine reaches, run here when the 6502 reaches
; their addresses: FCERR; AYINT, the FAC floored to a signed 32-bit integer
; in FACHO..FACLO, ?FC outside -32768..32767; GIVAYF, the signed integer in
; A (high) and Y (low) made the FAC
(def %bx-usr-hooks
  (fn (_ m)
    (let ((d (m get (lit dialect))) (mem (%bx-mem m)) (h (Dict make)))
      (h set! (d get (lit fcerr)) (fn (_ c) (%bx-fail "FC")))
      (h set! (d get (lit ayint))
        (fn (_ c)
          (let ((v (%bx-fac m)))
            (when (and (not (int< (mbf-exponent v) 144)) (not (int= (mbf-cmp v (mbf-int -32768)) 0)))
              (%bx-fail "FC"))
            (let ((n (mbf->int (mbf-floor v) 65536)))
              (mem-write! mem (int+ (d get (lit fac)) 1)
                (list (int& (int>> n 24) 255) (int& (int>> n 16) 255) (int& (int>> n 8) 255) (int& n 255)))))))
      (h set! (d get (lit givayf))
        (fn (_ c)
          (mem-poke! mem (d get (lit valtyp)) 0)
          (%bx-fac! m (mbf-int (%bx-signed (int+ (int<< (c get (lit a)) 8) (c get (lit y))))))))
      h)))

; USR(A): A in the FAC, VALTYP set by its type, the routine USRPOK jumps to
; called, and the FAC its value once VALTYP says it is a number (CHKNUM).
; A dialect with no FAC here has no USR yet.
(def %bx-usr
  (fn (_ m a)
    (let ((d (m get (lit dialect))) (mem (%bx-mem m)))
      (unless (d has? (lit fac)) (%bx-todo "USR"))
      (if (pair? a)
        (do (%bx-fac! m a) (mem-poke! mem (d get (lit valtyp)) 0))
        (mem-poke! mem (d get (lit valtyp)) 255))
      (guard (e (if (eq? (Err label e) (lit cpu)) (Err raise (lit basic-todo) (Err text e)) (error e)))
        (cpu-call! (cpu-make (mem-at mem (lit bytes))) (d get (lit usrpok)) (%bx-usr-hooks m)))
      (if (int= (mem-peek mem (d get (lit valtyp))) 0) (%bx-fac m) (%bx-fail "TM")))))

; The word W's digits, BITS to a digit and the top one taking what is
; left of its 16, the zeros before the first other digit dropped ($FOUTH,
; $FOUTO)
(def %bx-radix
  (fn (_ w bits)
    (let ((go (fn (self w acc)
                (let ((acc (pair (str-byte-ref "0123456789ABCDEF" (int& w (int- (int<< 1 bits) 1))) acc))
                      (left (int>> w bits)))
                  (if (int= left 0) acc (self left acc))))))
      (%bx-text (go w ())))))

; N bytes of B (SPACE2)
(def %bx-repeat
  (fn (_ n b) (%bx-text (List map (fn (_ i) b) (List range 0 n)))))

; Whether the bytes S start with the bytes P
(def %bx-starts?
  (fn (_ p s)
    (match
      ((null? p) #t)
      ((or (null? s) (not (int= (first p) (first s)))) #f)
      (#t (%bx-starts? (rest p) (rest s))))))

; INSTR([I,] S1, S2): where S2 is first found in S1 from position I (1
; when not given); 0 when it is not, or I is past S1's end; I when S2 is
; null.  I is 1 to 255, ?FC else.
(def %bx-instr
  (fn (_ m args)
    (let ((a (first args)))
      (let ((i (if (pair? a) (let ((i (%bx-byte m a))) (if (int= i 0) (%bx-fail "FC") i)) 1))
            (more (if (pair? a) (rest args) args)))
        (unless (int= (List length more) 2) (%bx-fail "SN"))
        (let ((s1 (%bx-string (first more))) (s2 (%bx-string (List second more))))
          (let ((n1 (List length s1)) (n2 (List length s2)))
            (%bx-int m
              (match
                ((not (int< (int- i 1) n1)) 0)
                ((int= n2 0) i)
                (#t
                  (let ((go (fn (self at left)
                              (match
                                ((int< (int- n1 at) n2) 0)
                                ((%bx-starts? s2 left) (int+ at 1))
                                (#t (self (int+ at 1) (rest left)))))))
                    (go (int- i 1) (List drop (int- i 1) s1))))))))))))

; MKI$, MKS$ and MKD$, CVI, CVS and CVD, by the type each makes or reads
(def %bx-packs (list (pair "MKI$" 2) (pair "MKS$" 4) (pair "MKD$" 8)))
(def %bx-unpacks (list (pair "CVI" 2) (pair "CVS" 4) (pair "CVD" 8)))

(def %bx-call
  (fn (_ m word args)
    (let ((a (if (null? args) () (first args))))
      (match
        ((str=? word "SGN") (%bx-int m ((%bx-kit m (lit sign)) (%bx-number a))))
        ((str=? word "INT") ((%bx-kit m (lit floor)) (%bx-number a)))
        ((str=? word "ABS") ((%bx-kit m (lit abs)) (%bx-number a)))
        ((str=? word "LEN") (%bx-int m (List length (%bx-string a))))
        ((str=? word "STR$") (%bx-text-of ((%bx-kit m (lit ->str)) (%bx-number a))))
        ; FIN reads the text to its first zero byte
        ((str=? word "VAL")
          (let ((got (%bx-value m (%bx-x-string (%bx-string a)))))
            (if (null? got) (%bx-kit m (lit zero)) (first got))))
        ((str=? word "ASC")
          (let ((s (%bx-string a))) (if (null? s) (%bx-fail "FC") (%bx-int m (first s)))))
        ((str=? word "CHR$") (%bx-text (list (%bx-byte m a))))
        ((str=? word "LEFT$")
          (let ((s (%bx-string a)) (n (%bx-byte m (List second args))))
            (%bx-text (List take n s))))
        ((str=? word "RIGHT$")
          (let ((s (%bx-string a)) (n (%bx-byte m (List second args))))
            (%bx-text (if (int< (List length s) n) s (List drop (int- (List length s) n) s)))))
        ((str=? word "MID$")
          (let ((s (%bx-string a)) (i (%bx-byte m (List second args)))
                (n (if (null? (rest (rest args))) 255 (%bx-byte m (List third args)))))
            (when (int= i 0) (%bx-fail "FC"))
            (%bx-text (List sub (int- i 1) n s))))
        ((str=? word "POS") (%bx-int m (m get (lit col))))
        ; the strings collected, then FRETOP - STREND as the kit gives it
        ((str=? word "FRE")
          (do (unless (pair? a) (%bx-string a))
              ((%bx-kit m (lit fre)) (mem-free (%bx-mem m)))))
        ((str=? word "PEEK") (%bx-int m (mem-peek (%bx-mem m) (%bx-address m a))))
        ((str=? word "USR") (%bx-usr m a))
        ((str=? word "HEX$") (%bx-radix ((%bx-kit m (lit word-bits)) (%bx-number a)) 4))
        ((str=? word "OCT$") (%bx-radix ((%bx-kit m (lit word-bits)) (%bx-number a)) 3))
        ((str=? word "SPACE$") (%bx-repeat (%bx-byte m a) 32))
        ; STRING$'s character, a string's first or a number's (ASC2, CONINT)
        ((str=? word "STRING$")
          (let ((n (%bx-byte m a)) (c (List second args)))
            (%bx-repeat n
              (if (pair? c) (%bx-byte m c)
                (let ((s (%bx-string c))) (if (null? s) (%bx-fail "FC") (first s)))))))
        ((str=? word "INSTR") (%bx-instr m args))
        ; a number made a string of its bytes as a variable holds them,
        ; forced to the type first (DOCNVF); and back, from the string's
        ; first bytes, ?FC when it is shorter
        ((List find (fn (_ p) (str=? (first p) word)) %bx-packs)
          (let ((k (rest (List find (fn (_ p) (str=? (first p) word)) %bx-packs))))
            (%bx-text ((%bx-kit m (lit ->bytes)) k ((%bx-kit m (lit fit)) k (%bx-number a))))))
        ((List find (fn (_ p) (str=? (first p) word)) %bx-unpacks)
          (let ((k (rest (List find (fn (_ p) (str=? (first p) word)) %bx-unpacks))) (s (%bx-string a)))
            (if (int< (List length s) k) (%bx-fail "FC")
              ((%bx-kit m (lit from-bytes)) k (List take k s)))))
        ((str=? word "ERR") (%bx-int m (m get-or 0 (lit err))))
        ((str=? word "ERL") ((%bx-kit m (lit line-value)) (m get-or 0 (lit erl))))
        ; RND with no argument is RND(1) (RNDMON)
        ((str=? word "RND")
          (let ((rnd (%bx-kit m (lit rnd))))
            (when (null? rnd) (%bx-todo word))
            (let ((got (rnd (if (null? args) (%bx-int m 1) (%bx-number a)) (m get (lit rnd)))))
              (do (m set! (lit rnd) (rest got)) (first got)))))
        (#t
          (let ((f ((%bx-kit m (lit math)) get-or () word)))
            (if (null? f) (%bx-todo word) (%bx-soft m (fn (_) (f (%bx-number a)))))))))))

; FN NAME of the argument E (FNDOER): the argument taken, ?UF when NAME has
; no DEF, then the formula read with its argument's variable set to it,
; and the variable's value put back
(def %bx-fn
  (fn (_ m name e)
    (when (%bx-string-name? m name) (%bx-fail "TM"))
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

; Where the function NAME's entry is, made when it has none (GETFNM), or
; nil where the layout keeps no entry for a function
(def %bx-fn-at!
  (fn (_ m name)
    (let ((header (%bx-layout m (lit fn-header))))
      (if (null? header) ()
        (mem-var! (%bx-mem m) (header (%bx-base name) (%bx-type m name))
                  ((%bx-layout m (lit value-size)) (%bx-type m name)))))))

; A string constant: in a line of the program, where it is in the line's
; text; typed at the prompt, text that STRLIT copies when it is used
(def %bx-constant
  (fn (_ m e)
    (let ((index (m get (lit index))) (ord (List third e)))
      (if (or (null? index) (int< index 0) (null? ord)) (%bx-text-of (List second e))
        (let ((strs (List second (List ref 3 (%bx-line-ref m index)))))
          (%bx-placed (%bx-bytes (List second e)) (int+ (%bx-line-text m index) (List ref ord strs)) #f))))))

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
          (%bx-rel m (List second e) (%bx-eval m (List third e)) (%bx-eval m (List ref 3 e))))
        ((eq? tag (lit neg)) ((%bx-kit m (lit neg)) (%bx-number (%bx-eval m (List second e)))))
        ((eq? tag (lit not)) (%bx-int m (int- -1 (%bx-word m (%bx-eval m (List second e))))))
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
              (let ((zone (%bx-dialect m (lit zone)))
                    (col (m get (lit col))))
                (if (not (int< col (m get (lit last-comma)))) (%bx-newline m)
                  (%bx-spaces m (int- zone (int% col zone))))))
            ((eq? tag (lit tab))
              (%bx-spaces m (int- (%bx-byte m (%bx-eval m (List second item))) (m get (lit col)))))
            ((eq? tag (lit spc)) (%bx-spaces m (%bx-byte m (%bx-eval m (List second item)))))
            (#t
              (let ((v (%bx-eval m (List second item))))
                (if (pair? v) (%bx-out m (Str8 append ((%bx-kit m (lit ->str)) v) " "))
                  (%bx-out m (%bx-shown (%bx-string v)))))))))
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
    (if (%bx-string-name? m name)
      (if (null? at) (%bx-text-of (List second item)) (%bx-placed (%bx-bytes (List second item)) at #f))
      (if (eq? (first item) (lit quoted)) ()
        (let ((text (Str8 trim (List second item))))
          (if (= (Str8 length text) 0) (%bx-kit m (lit zero))
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

; INPUT: answers end when the reply is empty, so the program stops.  Items
; past the variables are ignored with the dialect's text, or are a reason
; to ask again where it has none.
(def %bx-input
  (fn (_ m prompt targets)
    (let ((first-reply (%bx-reply m (Str8 append (if (null? prompt) "" prompt) "? ")))
          (extra (%bx-dialect m (lit extra-text))))
      (let ((go (fn (self targets items)
                  (match
                    ((null? targets)
                      (match
                        ((null? items) ())
                        ((null? extra) (lit redo))
                        (#t (do (%bx-out m extra) (%bx-newline m) ()))))
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
              (do (%bx-out m (%bx-dialect m (lit redo-text))) (%bx-newline m)
                  (%bx-input m prompt targets))
              r)))))))

; LINE INPUT: the prompt, then the line typed, all of it, put in the
; string TARGET (SINLIN, STRLT3); ?TM for a number's; no line at all ends
; the program
(def %bx-line-input
  (fn (_ m prompt target)
    (%bx-out m (if (null? prompt) "" prompt))
    (unless (%bx-string-name? m (List second target)) (%bx-fail "TM"))
    (let ((line (%bx-reply m "")))
      (if (null? line) (lit end)
        (do (%bx-set! m target (%bx-text-of line)) ())))))

; WRITE: each value, a string in quotes and a number as FOUT makes it
; without the blank for its sign, commas between, then a new line
(def %bx-write
  (fn (_ m es)
    (let ((go (fn (self es sep)
                (unless (null? es)
                  (%bx-out m sep)
                  (let ((v (%bx-eval m (first es))))
                    (%bx-out m
                      (if (pair? v)
                        (let ((s ((%bx-kit m (lit ->str)) v)))
                          (if (Str8 starts? " " s) (Str8 sub 1 (int- (Str8 length s) 1) s) s))
                        (Str8 append "\"" (%bx-shown (%bx-string v)) "\""))))
                  (self (rest es) ",")))))
      (go es "")
      (%bx-newline m))))

; RANDOMIZE: the seed from the formula E, or asked for until a number alone
; is typed, made an integer and given to the kit (RANDOM, STRNDS).  An
; empty reply is 0; none at all ends the program.
(def %bx-randomize
  (fn (_ m e)
    (let ((f (%bx-kit m (lit randomize))))
      (when (null? f) (%bx-todo "RANDOMIZE"))
      (let ((ask (fn (self)
                   (let ((reply (%bx-reply m (Str8 append (%bx-dialect m (lit seed-text)) "? "))))
                     (if (null? reply) ()
                       (let ((text (Str8 trim reply)))
                         (if (= (Str8 length text) 0) (%bx-kit m (lit zero))
                           (let ((got (%bx-value m text)))
                             (if (or (null? got) (not (null? (rest got)))) (self) (first got))))))))))
        (let ((n (if (null? e) (ask) (%bx-number (%bx-eval m e)))))
          (if (null? n) (lit end)
            (do (m set! (lit rnd) (f ((%bx-kit m (lit integer)) n) (m get (lit rnd))))
                ())))))))

; --- LIST -----------------------------------------------------------------

(def %bx-list
  (fn (_ m from to)
    (List for-each
      (fn (_ line)
        (when (and (or (null? from) (not (int< (first line) from)))
                   (or (null? to) (not (int< to (first line)))))
          (%bx-fresh m)
          (%bx-out m (Str8 append (%bx-linprt m (first line)) " " (List second line)))))
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
            (let ((v (%bx-fit m var (%bx-arith m (lit add) (%bx-number-of m var) step))))
              (%bx-number-set! m var v)
              (if (int= ((%bx-kit m (lit cmp)) v limit) ((%bx-kit m (lit sign)) step))
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
        (let ((arrays (m get (lit arrays))) (key (%bx-key m (first d))))
          (when (arrays has? key) (%bx-fail "DD"))
          (arrays set! key
            (%bx-array-make m (first d)
              (List map (fn (_ e) (%bx-subscript m (%bx-eval m e))) (rest d))))))
      decls)))

; DEF FN NAME(ARG)=FORMULA: ?TM for a string name or argument, ?ID typed
; at the prompt.  As DEF does: the function's entry found or made, then the
; argument's, and the function's value bytes the formula's place in the
; text (here the line's text) and the argument's value; the fifth, a byte DEF
; pushes, is left zero.  A layout with no function entries keeps the
; definition only.
(def %bx-def
  (fn (_ m st)
    (let ((name (List second st)) (arg (List third st)))
      (let ((e (%bx-fn-at! m name)))
        (when (%bx-string-name? m name) (%bx-fail "TM"))
        (when (null? (m get (lit line))) (%bx-fail "ID"))
        (let ((a (%bx-var-at! m arg)))
          (when (%bx-string-name? m arg) (%bx-fail "TM"))
          (unless (null? e)
            (mem-word! (%bx-mem m) (int+ e 2) (%bx-line-text m (m get (lit index))))
            (mem-word! (%bx-mem m) (int+ e 4) a))
          ((m get (lit fns)) set! name (list arg (List ref 3 st) (m get (lit index)))))))))

; NULL N: N zero bytes after each new line from now on.  GETBYT takes 0 to
; 255, and NULL refuses 239 and above as unreasonable.
(def %bx-null
  (fn (_ m e)
    (let ((n (%bx-byte m (%bx-eval m e))))
      (if (int< 238 n) (%bx-fail "FC") (m set! (lit nulls) n)))))

; POKE A,B: the address taken and checked before the byte (GETNUM)
(def %bx-poke
  (fn (_ m a b)
    (let ((at (%bx-address m (%bx-eval m a))))
      (mem-poke! (%bx-mem m) at (%bx-byte m (%bx-eval m b))))))

; WAIT A,M1[,M2]: until the byte at A, with M2's bits flipped, has one of
; M1's bits on (FNWAIT).  Only the program writes this memory, so a WAIT
; that does not hold at once waits for ever, as a KIM's does on an address
; nothing drives.
(def %bx-wait
  (fn (_ m a m1 m2)
    (let ((at (%bx-address m (%bx-eval m a))))
      (let ((and-mask (%bx-byte m (%bx-eval m m1))))
        (let ((eor-mask (if (null? m2) 0 (%bx-byte m (%bx-eval m m2)))))
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
      ((and (not (int< k 48)) (int< k 58)) (%bx-int m (int- k 48)))
      ((List includes? k (list 32 43 44 45 46 58 69)) (%bx-kit m (lit zero)))
      (#t (do (m set! (lit line) ()) (%bx-fail "SN"))))))

; GET V, ...: a key for each variable, waited for.  A string takes the key
; as it is; a number reads it (%bx-key-number), and a , or : left by the
; last one is ?EXTRA IGNORED, as VAREND finds it.  End of input ends the
; run, as an empty reply to INPUT does.
(def %bx-get-keys
  (fn (_ m targets)
    (let ((go (fn (self ts extra)
                (if (null? ts)
                  (do (when extra (%bx-out m (%bx-dialect m (lit extra-text))) (%bx-newline m)) ())
                  (let ((k ((m get (lit key)))))
                    (if (null? k) (lit end)
                      (if (%bx-string-name? m (List second (first ts)))
                        (do (%bx-set! m (first ts) (%bx-text (list k)))
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
      ((eq? tag (lit deftype)) (%bx-deftype m (List second st) (List third st)))
      ((eq? tag (lit swap)) (%bx-swap m (List second st) (List third st)))
      ((eq? tag (lit erase)) (%bx-erase m (List second st)))
      ((eq? tag (lit option)) (%bx-option m (List second st)))
      ((eq? tag (lit bad)) (%bx-fail (List second st)))
      (#t (%bx-todo (List second st))))))

; A GOSUB's return, to the statements AFTER it on line INDEX, pushed
(def %bx-push-return!
  (fn (_ m index after)
    (m set! (lit stack) (pair (list (lit gosub) (pair index after)) (m get (lit stack))))))

; FOR: the variable set, then its limit and step made its type
(def %bx-for
  (fn (_ m st index after)
    (let ((name (List second st)))
      (do
        (%bx-let! m (list (lit var) name) (List third st))
        (let ((limit (%bx-fit m name (%bx-eval m (List ref 3 st))))
              (step (%bx-fit m name (if (null? (List ref 4 st)) (%bx-int m 1) (%bx-eval m (List ref 4 st))))))
          (m set! (lit stack)
            (pair (list (lit for) name limit step (pair index after))
                  (%bx-drop-for (m get (lit stack)) name))))
        ()))))

(def %bx-on
  (fn (_ m st index after)
    (let ((k (%bx-byte m (%bx-eval m (List second st)))) (ns (List ref 3 st)))
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

; A tape the monitor could not read or write: the KIM's display shows FFFF
; and BASIC is left, so the run ends
(def %bx-tape-error
  (fn (_ m) (do (%bx-out m "FFFF") (lit end))))

; The program, TXTTAB up to VARTAB, written to the tape with ID $FE, as
; KIM BASIC's SAVE has DUMPT do; a running program goes on
(def %bx-save
  (fn (_ m)
    (let ((mem (%bx-mem m)) (start (%bx-dialect m (lit txttab))))
      (if (tape-save (m get (lit tape)) 254 start (mem-read mem start (int- (mem-at mem (lit vartab)) start)))
        (do (%bx-out m "SAVED") (%bx-newline m) ())
        (%bx-tape-error m)))))

; The lines of program BYTES, as LNKPRG walks them to a link whose high
; byte is zero, each line's text its tokens spelled out
(def %bx-tape-lines
  (fn (_ m bytes)
    (let ((dialect (m get (lit dialect))))
      ; (TEXT . AFTER): the bytes up to a zero, and those past it
      (let ((upto (fn (self bs acc)
                    (match
                      ((null? bs) (pair (List reverse acc) ()))
                      ((int= (first bs) 0) (pair (List reverse acc) (rest bs)))
                      (#t (self (rest bs) (pair (first bs) acc)))))))
        (let ((go (fn (self bs acc)
                    (if (or (int< (List length bs) 4) (int= (List second bs) 0)) (List reverse acc)
                      (let ((cut (upto (List drop 4 bs) ())))
                        (let ((text (basic-detokenize dialect (first cut))))
                          (self (rest cut)
                            (pair (%bx-line dialect (int+ (List third bs) (int* 256 (List ref 3 bs))) text)
                                  acc))))))))
          (go bytes ()))))))

; The first record on the tape made the program at TXTTAB, as KIM BASIC's
; LOAD has LOADT do with $FF at ID: "LOADED", then the program relinked and
; its variables cleared, and the next line read with no ready prompt
(def %bx-load
  (fn (_ m)
    (let ((got (tape-load (m get (lit tape)))))
      (if (null? got) (%bx-tape-error m)
        (do (%bx-program! m (%bx-tape-lines m (first got)))
            (%bx-out m "LOADED")
            (lit loaded))))))

(def %bx-cont
  (fn (_ m index)
    (let ((at (m get (lit cont))))
      (if (or (int< -1 index) (null? at)) (%bx-fail "CN") at))))

; --- ELSE, WHILE and WEND -------------------------------------------------

; Where a false IF goes on (FALSIF): past the ELSE that matches it among
; the statements AFTER it on line INDEX, each IF between needing an ELSE
; of its own; the next line when there is none
(def %bx-else-of
  (fn (_ index after)
    (let ((go (fn (self sts k)
                (match
                  ((null? sts) (lit next-line))
                  ((eq? (first (first sts)) (lit if)) (self (rest sts) (int+ k 1)))
                  ((eq? (first (first sts)) (lit else))
                    (if (int= k 1) (pair index (rest sts)) (self (rest sts) (int- k 1))))
                  (#t (self (rest sts) k))))))
      (go after 1))))

; Where the WEND that closes a WHILE is (WNDSCN): the position past it,
; found from the statements AFTER the WHILE on line INDEX through the
; lines after, each WHILE between needing a WEND of its own; ?WH when the
; program ends first
(def %bx-wend-of
  (fn (_ m index after)
    (let ((go (fn (self i sts k)
                (match
                  ((null? sts)
                    (let ((next (%bx-after-line m i)))
                      (if (null? next) (%bx-fail "WH") (self (first next) (rest next) k))))
                  ((eq? (first (first sts)) (lit while)) (self i (rest sts) (int+ k 1)))
                  ((eq? (first (first sts)) (lit wend))
                    (if (int= k 1) (pair i (rest sts)) (self i (rest sts) (int- k 1))))
                  (#t (self i (rest sts) k))))))
      (go index after 1))))

; A WEND by where it is: its line's place and how many statements follow it
(def %bx-wend-key (fn (_ index after) (pair index (List length after))))

; The stack from the WHILE entry for the WEND at KEY (FNDWND), FOR entries
; passed over; nil when a GOSUB's or the stack's end comes first
(def %bx-find-while
  (fn (_ stack key)
    (let ((go (fn (self s)
                (match
                  ((null? s) ())
                  ((eq? (first (first s)) (lit for)) (self (rest s)))
                  ((eq? (first (first s)) (lit while))
                    (let ((k (List second (first s))))
                      (if (and (int= (first k) (first key)) (int= (rest k) (rest key))) s (self (rest s)))))
                  (#t ())))))
      (go stack))))

(def %bx-holds? (fn (_ m e) (not ((%bx-kit m (lit zero?)) (%bx-number (%bx-eval m e))))))

; WHILE E: the stack's entry for this loop, and those above it, dropped;
; then the loop entered when E holds, else gone on past its WEND
(def %bx-while
  (fn (_ m st index after)
    (let ((past (%bx-wend-of m index after)))
      (let ((key (%bx-wend-key (first past) (rest past))))
        (let ((s (%bx-find-while (m get (lit stack)) key)))
          (unless (null? s) (m set! (lit stack) (rest s))))
        (if (not (%bx-holds? m (List second st))) past
          (do (m set! (lit stack) (pair (list (lit while) key (List second st) (pair index after)) (m get (lit stack))))
              ()))))))

; WEND: ?WE with no WHILE for it; else the stack cut to that WHILE's entry
; and its formula read again on the WHILE's line, the loop going round
; when it holds and on past the WEND when it does not
(def %bx-wend
  (fn (_ m index after)
    (let ((s (%bx-find-while (m get (lit stack)) (%bx-wend-key index after))))
      (when (null? s) (%bx-fail "WE"))
      (let ((e (first s)))
        (let ((at (List ref 3 e)))
          (m set! (lit stack) s)
          (m set! (lit index) (first at))
          (m set! (lit line) (if (int< (first at) 0) () (first (%bx-line-ref m (first at)))))
          (if (%bx-holds? m (List third e)) at
            (do (m set! (lit stack) (rest s)) (pair index after))))))))

; --- DEFINT, SWAP, ERASE and OPTION BASE ---------------------------------

; DEFINT and its kin: each letter of RANGES given TYPE in DEFTBL
(def %bx-deftype
  (fn (_ m type ranges)
    (List for-each
      (fn (_ r)
        (List for-each (fn (_ i) (Vector set! i type (m get (lit deftbl))))
          (List range (first r) (int+ (rest r) 1))))
      ranges)))

; Where TARGET's value is, its variable made when it has none (PTRGET)
(def %bx-target-at
  (fn (_ m target)
    (let ((name (List second target)))
      (if (eq? (first target) (lit var)) (%bx-var-at! m name)
        (let ((args (List map (fn (_ e) (%bx-eval m e)) (List third target))))
          (let ((a (%bx-array m name (List length args))))
            (%bx-element-at m name a (%bx-slot m a args))))))))

; SWAP A, B: the two values' bytes traded.  ?TM when their types differ;
; ?FC when finding B made a variable, which moves the arrays A may be in
(def %bx-swap
  (fn (_ m a b)
    (let ((mem (%bx-mem m)) (na (List second a)) (nb (List second b)))
      (let ((at-a (%bx-target-at m a)) (arytab (mem-at mem (lit arytab))))
        (let ((at-b (%bx-target-at m b)))
          (unless (int= (%bx-type m na) (%bx-type m nb)) (%bx-fail "TM"))
          (unless (int= arytab (mem-at mem (lit arytab))) (%bx-fail "FC"))
          (let ((n (%bx-element-size m na)))
            (let ((va (mem-read mem at-a n)) (vb (mem-read mem at-b n)))
              (mem-write! mem at-a vb)
              (mem-write! mem at-b va))))))))

; ERASE NAMES: each array taken out of memory, the arrays past it moved
; down; ?FC for one there is none of
(def %bx-erase
  (fn (_ m names)
    (List for-each
      (fn (_ name)
        (let ((arrays (m get (lit arrays))) (key (%bx-key m name)) (mem (%bx-mem m)))
          (unless (arrays has? key) (%bx-fail "FC"))
          (let ((offset (List second (arrays get key))))
            (let ((n (mem-array-erase! mem (int+ (mem-at mem (lit arytab)) offset))))
              (arrays del! key)
              (List for-each
                (fn (_ k)
                  (let ((e (arrays get k)))
                    (when (int< offset (List second e))
                      (arrays set! k (list (first e) (int- (List second e) n))))))
                (arrays keys))))))
      names)))

; OPTION BASE N: the lowest subscript.  The same base again does nothing;
; another is ?DD once OPTION BASE has set one or an array is made
(def %bx-option
  (fn (_ m n)
    (let ((mem (%bx-mem m)))
      (unless (int= n (m get (lit base)))
        (when (or (m get (lit option)) (not (int= (mem-at mem (lit arytab)) (mem-at mem (lit strend)))))
          (%bx-fail "DD"))
        (m set! (lit base) n)
        (m set! (lit option) #t)))))

; ON ERROR GOTO N: 0 turns the trap off, and inside a handler prints the
; error being handled, in its line; else the trap goes to line N, ?US when
; there is none
(def %bx-on-error
  (fn (_ m n)
    (if (int= n 0)
      (do (m set! (lit on-error) ())
          (when (m get-or #f (lit in-error))
            (let ((at (m get (lit erl))))
              (m set! (lit line) (if (int= at 65535) () at))
              (%bx-fail ((%bx-dialect m (lit error-code)) (m get (lit err))))))
          ())
      (do (%bx-find m n) (m set! (lit on-error) n) ()))))

; RESUME: 0 the erring statement again, next the one after it, a line
; number a GOTO; ?RW with no error being handled
(def %bx-resume
  (fn (_ m to)
    (unless (m get-or #f (lit in-error)) (%bx-fail "RW"))
    (let ((at (m get (lit err-at))))
      (let ((pos (match
                   ((eq? to (lit next)) (pair (first at) (rest (rest at))))
                   ((int= to 0) at)
                   (#t (%bx-goto m to)))))
        (m set! (lit in-error) #f)
        pos))))

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
          (if (%bx-holds? m (List second st)) () (%bx-else-of index after)))
        ((eq? tag (lit else)) (lit next-line))
        ((eq? tag (lit while)) (%bx-while m st index after))
        ((eq? tag (lit wend)) (%bx-wend m index after))
        ((eq? tag (lit for)) (%bx-for m st index after))
        ((eq? tag (lit next)) (%bx-next m (List second st)))
        ((eq? tag (lit end)) (do (m set! (lit in-error) #f) (lit end)))
        ((eq? tag (lit on-error)) (%bx-on-error m (List second st)))
        ((eq? tag (lit error))
          (let ((n (%bx-byte m (%bx-eval m (List second st)))))
            (if (int= n 0) (%bx-fail "FC") (%bx-fail ((%bx-dialect m (lit error-code)) n)))))
        ((eq? tag (lit resume)) (%bx-resume m (List second st)))
        ((eq? tag (lit stop)) (lit stop))
        ((eq? tag (lit on)) (%bx-on m st index after))
        ((eq? tag (lit input))
          (if (int< index 0) (%bx-fail "ID") (%bx-input m (List second st) (List third st))))
        ((eq? tag (lit line-input)) (%bx-line-input m (List second st) (List third st)))
        ((eq? tag (lit write)) (do (%bx-write m (List second st)) ()))
        ((eq? tag (lit mid))
          (do (%bx-mid! m (List second st) (List third st) (List ref 3 st) (List ref 4 st)) ()))
        ((eq? tag (lit get))
          (if (int< index 0) (%bx-fail "ID") (%bx-get-keys m (List second st))))
        ((eq? tag (lit randomize)) (%bx-randomize m (List second st)))
        ((eq? tag (lit run)) (%bx-run-statement m st))
        ((eq? tag (lit new)) (%bx-new m))
        ((eq? tag (lit save)) (%bx-save m))
        ((eq? tag (lit load)) (%bx-load m))
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

; The error E of the statement at AT taken by the ON ERROR line, when one
; is set and no error is being handled: ERR and ERL set, AT kept for
; RESUME, and the line's start answered
(def %bx-trap
  (fn (_ m e at)
    (let ((label (Err label e)))
      (if (or (m get-or #f (lit in-error)) (null? (m get-or () (lit on-error)))
              (not (List includes? label (list (lit basic) (lit basic-overflow) (lit basic-div0)))))
        (error e)
        (let ((code (match
                      ((eq? label (lit basic-overflow)) "OV")
                      ((eq? label (lit basic-div0)) "/0")
                      (#t (Err text e))))
              (n (m get (lit line))))
          (m set! (lit err) ((%bx-dialect m (lit error-number)) code))
          (m set! (lit erl) (if (null? n) 65535 n))
          (m set! (lit err-at) at)
          (m set! (lit in-error) #t)
          (%bx-goto m (m get-or () (lit on-error))))))))

; The position after line INDEX; past the program's last line while an
; error is being handled, ?NR (PRGEND)
(def %bx-next-line
  (fn (_ m index)
    (let ((pos (%bx-after-line m index)))
      (if (and (null? pos) (not (int< index 0)) (m get-or #f (lit in-error))) (%bx-fail "NR") pos))))

; Run from POS to an END, a STOP or the program's end: answers end or stop,
; or loaded after a LOAD.  While ON ERROR is set each statement runs under
; the trap.
(def %bx-run
  (fn (_ m pos)
    (let ((go (fn (self pos)
                (if (null? pos) (lit end)
                  (let ((index (first pos)) (sts (rest pos)))
                    (if (null? sts) (self (%bx-next-line m index))
                      (do
                        (%bx-sweep m)
                        (m set! (lit index) index)
                        (m set! (lit line) (if (int< index 0) () (first (%bx-line-ref m index))))
                        (let ((r (if (null? (m get-or () (lit on-error)))
                                   (%bx-statement m (first sts) index (rest sts))
                                   (guard (e (%bx-trap m e pos))
                                     (%bx-statement m (first sts) index (rest sts))))))
                          (match
                            ((null? r) (self (pair index (rest sts))))
                            ((eq? r (lit next-line)) (self (%bx-next-line m index)))
                            ((eq? r (lit loaded)) r)
                            ((or (eq? r (lit end)) (eq? r (lit stop)))
                              (do (m set! (lit cont) (pair index (rest sts))) r))
                            (#t (self r)))))))))))
      (go pos))))

; --- a line typed ---------------------------------------------------------

; The dialect's " IN N" for a line of the program, nothing for the line
; typed
(def %bx-where
  (fn (_ m)
    (let ((n (m get (lit line))))
      (if (null? n) "" (Str8 append (%bx-dialect m (lit in-text)) (%bx-linprt m n))))))

(def %bx-ready
  (fn (_ m)
    (%bx-fresh m)
    (%bx-out m (%bx-dialect m (lit ready)))
    (%bx-newline m)))

; The statements of TEXT run as the line typed
(def %bx-direct
  (fn (_ m text)
    (m set! (lit direct) (basic-parse-line (m get (lit dialect)) (basic-lex (m get (lit dialect)) text)))
    (m set! (lit line) ())
    (let ((r (%bx-guarded (fn (_) (%bx-run m (pair -1 (m get (lit direct))))))))
      (match
        ((eq? r (lit stop))
          (do (%bx-fresh m)
              (%bx-out m (Str8 append (%bx-dialect m (lit break-text)) (%bx-where m)))))
        ((eq? r (lit end)) ())
        ((eq? r (lit loaded)) ())
        (#t (%bx-report m r)))
      ; LOAD goes on to MAIN, the next line read with no ready prompt
      (unless (eq? r (lit loaded)) (%bx-ready m)))))

; The labels a run stops for: a BASIC error, a statement not here yet, and
; an overflow or a division by zero no kit operation went on from
(def %bx-stops (list (lit basic) (lit basic-todo) (lit basic-overflow) (lit basic-div0)))

; What THUNK answers, or the BASIC error it raises
(def %bx-guarded
  (fn (_ thunk)
    (guard (e (if (List includes? (Err label e) %bx-stops) e (error e)))
      (thunk))))

; The error R printed as the dialect prints it, the stack emptied
(def %bx-report
  (fn (_ m r)
    (m set! (lit stack) ())
    (m set! (lit cont) ())
    (m set! (lit in-error) #f)
    (%bx-fresh m)
    (let ((label (Err label r)))
      (%bx-out m
        (Str8 append
          (if (eq? label (lit basic-todo)) ((%bx-dialect m (lit todo-text)) (Err text r))
            ((%bx-dialect m (lit error-text))
              (match
                ((eq? label (lit basic-overflow)) "OV")
                ((eq? label (lit basic-div0)) "/0")
                (#t (Err text r)))))
          (%bx-where m))))))

; Line N stored; ?OM when it does not fit, and the ready prompt after it
(def %bx-stored
  (fn (_ m n text)
    (m set! (lit line) ())
    (let ((r (%bx-guarded (fn (_) (do (%bx-store! m n text) ())))))
      (unless (null? r)
        (%bx-report m r)
        (%bx-ready m)))))

; A line stored when it starts with a line number no greater than the
; dialect's last, else run.  The digits and the blanks after them are the
; number, as LINGET reads them.
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
                (if (not (int< (%bx-dialect m (lit line-max)) (first got)))
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

; What INIT prints once the machine has started: the bytes free (MEMSIZ
; less TXTTAB, less the dialect's free-less) and the banner, in the
; dialect's order, then the ready prompt
(def %bx-started!
  (fn (_ m)
    (let ((dialect (m get (lit dialect))) (mem (%bx-mem m)))
      (let ((free (fn (_)
                    (%bx-out m (Str8 append
                                 (%bx-linprt m (int- (int- (mem-at mem (lit memsiz)) (mem-at mem (lit txttab)))
                                                     (dialect get-or 0 (lit free-less))))
                                 (dialect get (lit free-text))))
                    (%bx-newline m)))
            (banner (fn (_) (List for-each (fn (_ line) (%bx-out m line) (%bx-newline m)) (dialect get (lit banner))))))
        (m set! (lit boot) ())
        (%bx-clear! m)
        (if (dialect get-or #f (lit banner-first))
          (do (banner) (free))
          (do (%bx-newline m) (free) (%bx-newline m) (banner)))
        (%bx-ready m)))))

; The machine started as the dialect's does (INIT): MEMORY SIZE? (blank
; for all the RAM the dialect has) and WIDTH? (blank for its width), each
; asked again until it is answered with a number it takes, then the bytes
; free and the dialect's banner.  basic-boot-prompt is the question the
; machine is waiting on, nil once it has started; basic-boot-answer! takes
; the line typed in answer.  A dialect that asks nothing starts at once.
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
    (let ((dialect (m get (lit dialect))) (start (%bx-dialect m (lit txttab))))
      (if (eq? (m get (lit boot)) (lit memory))
        (let ((k (if (%bx-blank? reply) (dialect get (lit ram-top)) (%bx-linget reply))))
          (unless (or (null? k) (not (int< (int+ start 2) k)))
            (m set! (lit mem) (mem-make (m get (lit layout)) start k))
            (m set! (lit boot) (lit width))))
        (let ((k (if (%bx-blank? reply) (m get (lit width)) (%bx-linget reply))))
          (unless (or (null? k) (int< k 16) (int< 255 k))
            (unless (%bx-blank? reply) (%bx-width! m k (int- k (int% k (dialect get (lit zone))))))
            (%bx-started! m)))))))

; The machine started, its questions asked and answered with IN's lines
(def basic-boot
  (fn (_ m)
    (basic-boot-begin! m)
    (let ((go (fn (self)
                (let ((prompt (basic-boot-prompt m)))
                  (unless (null? prompt)
                    (%bx-out m prompt)
                    (basic-boot-answer! m ((m get (lit in))))
                    (self))))))
      (go))))

; The machine made to wait on its start-up questions, the lines typed until
; it has started answering basic-boot-prompt; started at once by a
; dialect that asks none
(def basic-boot-begin!
  (fn (_ m)
    (if ((m get (lit dialect)) has? (lit memory-prompt))
      (do (m set! (lit boot) (lit memory)) (%bx-newline m))
      (%bx-started! m))
    ()))

; A line typed, upper-cased outside its strings, REM and DATA when the
; machine folds case.  The terminal has shown its new line; the zero bytes
; after it are the machine's, as INLIN ends with CRDO.
(def basic-type
  (fn (_ m text)
    (%bx-nulls m)
    (%bx-typed m (if (m get (lit fold-case)) (basic-fold (m get (lit dialect)) text) text))))

(provide basic/exec basic-machine basic-boot basic-boot-begin! basic-boot-prompt basic-boot-answer!
  basic-type)
