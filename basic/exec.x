; # x-basic -- BASIC on x-lang
;
; ## basic/exec.x -- the machine: the program, its variables, and running it
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
(import x/core/doors int+ int- int* int/ int% int< int= int& int| str-byte-ref)
(import basic/mbf
  mbf-zero mbf-zero? mbf-int mbf-neg mbf-abs mbf-sgn mbf-cmp mbf-round mbf-add mbf-sub
  mbf-mul mbf-div mbf-floor mbf->int mbf->str)
(import basic/mbf-math
  mbf-log mbf-exp mbf-power mbf-sqr mbf-sin mbf-cos mbf-tan mbf-atn mbf-rnd-seed mbf-rnd)
(import basic/lex basic-lex basic-fold)
(import basic/parse basic-parse-line basic-parse-value basic-items)

(def %bx-fail (fn (_ code) (Err raise (lit basic) code)))
(def %bx-todo (fn (_ word) (Err raise (lit basic-todo) word)))

; --- the machine ----------------------------------------------------------

; A machine for DIALECT, writing with OUT and reading lines with IN (a
; function answering the next line, or nil at the end)
(def basic-machine
  (fn (_ dialect out in)
    (let ((m (Dict make)))
      (m set! (lit dialect) dialect)
      (m set! (lit out) out)
      (m set! (lit in) in)
      (m set! (lit col) 0)
      ; whether a typed line is upper-cased outside its strings, REM and DATA
      (m set! (lit fold-case) (dialect get-or #t (lit fold-case)))
      (m set! (lit lines) ())
      ; RND's last value; CLEAR and RUN leave it
      (m set! (lit rnd) mbf-rnd-seed)
      (%bx-index! m)
      (%bx-clear! m)
      m)))

; Variables, arrays and the stack emptied, and DATA read from the start
(def %bx-clear!
  (fn (_ m)
    (m set! (lit vars) (Dict make))
    (m set! (lit arrays) (Dict make))
    ; DEF's functions, by name: (ARG . FORMULA)
    (m set! (lit fns) (Dict make))
    (m set! (lit stack) ())
    (m set! (lit cont) ())
    (%bx-restore! m)))

; The program as a vector, and each line number's place in it
(def %bx-index!
  (fn (_ m)
    (let ((v (Vector from-list (m get (lit lines)))) (at (Dict make)))
      (Vector for-each (fn (_ i) (at set! (first (Vector ref i v)) i))
        (Vector from-list (List range 0 (Vector length v))))
      (m set! (lit prog) v)
      (m set! (lit at) at))))

(def %bx-line-ref (fn (_ m i) (Vector ref i (m get (lit prog)))))

; The place of line number N
(def %bx-find
  (fn (_ m n)
    (let ((i ((m get (lit at)) get n)))
      (if (null? i) (%bx-fail "US") i))))

; Line N's text stored, or the line removed when TEXT is blank
(def %bx-store!
  (fn (_ m n text)
    (let ((kept (List filter (fn (_ l) (not (int= (first l) n))) (m get (lit lines)))))
      (m set! (lit lines)
        (if (= (Str8 length (Str8 trim text)) 0) kept
          (let ((line (list n text (basic-parse-line (basic-lex (m get (lit dialect)) text)))))
            (List append (List filter (fn (_ l) (int< (first l) n)) kept)
                         (pair line (List filter (fn (_ l) (int< n (first l))) kept)))))))
    (%bx-index! m)
    (%bx-clear! m)))

; --- output ---------------------------------------------------------------

; TEXT written, a new line begun wherever the line is full
(def %bx-out
  (fn (_ m text)
    (let ((width ((m get (lit dialect)) get (lit width))) (n (Str8 length text)))
      (let ((room (int- width (m get (lit col)))))
        (if (not (int< room n))
          (do ((m get (lit out)) text)
              (m set! (lit col) (int+ (m get (lit col)) n)))
          (do ((m get (lit out)) (Str8 sub 0 room text))
              ((m get (lit out)) "\n")
              (m set! (lit col) 0)
              (%bx-out m (Str8 sub room (int- n room) text))))))))

(def %bx-newline
  (fn (_ m)
    ((m get (lit out)) "\n")
    (m set! (lit col) 0)))

(def %bx-spaces
  (fn (_ m n) (when (int< 0 n) (%bx-out m (Str8 repeat n " ")))))

; --- values ---------------------------------------------------------------

(def %bx-num? (fn (_ v) (pair? v)))

(def %bx-number
  (fn (_ v) (if (pair? v) v (%bx-fail "TM"))))

(def %bx-string
  (fn (_ v) (if (pair? v) (%bx-fail "TM") v)))

; A number as an integer from LO to HI, by INT; ?FC outside
(def %bx-int-in
  (fn (_ v lo hi)
    (let ((n (mbf->int (mbf-floor (%bx-number v)) 65536)))
      (if (or (int< n lo) (int< hi n)) (%bx-fail "FC") n))))

(def %bx-byte (fn (_ v) (%bx-int-in v 0 255)))
(def %bx-word (fn (_ v) (%bx-int-in v -32768 32767)))

(def %bx-truth (fn (_ b) (if b (mbf-int -1) mbf-zero)))

; A string no longer than 255
(def %bx-checked
  (fn (_ s) (if (int< 255 (Str8 length s)) (%bx-fail "LS") s)))

(def %bx-string-name? (fn (_ name) (Str8 ends? "$" name)))
(def %bx-int-name? (fn (_ name) (Str8 ends? "%" name)))

(def %bx-default
  (fn (_ name) (if (%bx-string-name? name) "" mbf-zero)))

; V made fit to be stored in NAME
(def %bx-fit
  (fn (_ name v)
    (match
      ((%bx-string-name? name) (%bx-string v))
      ((%bx-int-name? name) (mbf-int (%bx-word v)))
      (#t (mbf-round (%bx-number v))))))

; --- variables and arrays -------------------------------------------------

; An array of NAME with the upper bounds BOUNDS: (BOUNDS . VECTOR)
(def %bx-array-make
  (fn (_ name bounds)
    (let ((size (List fold (fn (_ n b) (int* n (int+ b 1))) 1 bounds)))
      (pair bounds (Vector make size (%bx-default name))))))

(def %bx-array
  (fn (_ m name count)
    (let ((arrays (m get (lit arrays))))
      (unless (arrays has? name)
        (arrays set! name
          (%bx-array-make name
            (List map (fn (_ i) (int- ((m get (lit dialect)) get (lit array-size)) 1))
                      (List range 0 count)))))
      (arrays get name))))

; The slot of SUBSCRIPTS in the array A
(def %bx-slot
  (fn (_ a subscripts)
    (unless (int= (List length subscripts) (List length (first a))) (%bx-fail "BS"))
    (List fold
      (fn (_ at pr)
        (let ((i (%bx-int-in (rest pr) 0 32767)))
          (when (int< (first pr) i) (%bx-fail "BS"))
          (int+ (int* at (int+ (first pr) 1)) i)))
      0 (List zip (first a) subscripts))))

(def %bx-get
  (fn (_ m target)
    (let ((name (List second target)))
      (if (eq? (first target) (lit var))
        ((m get (lit vars)) get-or (%bx-default name) name)
        (let ((args (List map (fn (_ e) (%bx-eval m e)) (List third target))))
          (let ((a (%bx-array m name (List length args))))
            (Vector ref (%bx-slot a args) (rest a))))))))

(def %bx-set!
  (fn (_ m target v)
    (let ((name (List second target)))
      (if (eq? (first target) (lit var))
        ((m get (lit vars)) set! name (%bx-fit name v))
        (let ((args (List map (fn (_ e) (%bx-eval m e)) (List third target))))
          (let ((a (%bx-array m name (List length args))))
            (Vector set! (%bx-slot a args) (%bx-fit name v) (rest a))))))))

; --- expressions ----------------------------------------------------------

; A 16-bit two's complement word as a signed integer
(def %bx-signed
  (fn (_ w) (if (int< w 32768) w (int- w 65536))))

(def %bx-op
  (fn (_ m word a b)
    (match
      ((str=? word "+")
        (if (and (not (pair? a)) (not (pair? b))) (%bx-checked (Str8 append a b))
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
               (#t (%bx-str-cmp a b)))))
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
          (if (= (Str8 length (%bx-string a)) 0) (%bx-fail "FC") (mbf-int (str-byte-ref a 0))))
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
    (let ((x (%bx-number (%bx-eval m e))) (d ((m get (lit fns)) get-or () name)))
      (when (null? d) (%bx-fail "UF"))
      (let ((var (first d)) (vars (m get (lit vars))))
        (let ((old (vars get-or (%bx-default var) var)))
          (%bx-set! m (list (lit var) var) x)
          (let ((v (if (eq? (rest d) (lit bad)) (%bx-fail "SN")
                     (%bx-number (%bx-eval m (rest d))))))
            (vars set! var old)
            v))))))

(def %bx-eval
  (fn (_ m e)
    (let ((tag (first e)))
      (match
        ((eq? tag (lit num)) (List second e))
        ((eq? tag (lit str)) (List second e))
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
                    (width ((m get (lit dialect)) get (lit width)))
                    (col (m get (lit col))))
                (if (not (int< col (int* (int- (int/ width zone) 1) zone))) (%bx-newline m)
                  (%bx-spaces m (int- zone (int% col zone))))))
            ((eq? tag (lit tab))
              (%bx-spaces m (int- (%bx-byte (%bx-eval m (List second item))) (m get (lit col)))))
            ((eq? tag (lit spc)) (%bx-spaces m (%bx-byte (%bx-eval m (List second item)))))
            (#t
              (let ((v (%bx-eval m (List second item))))
                (if (pair? v) (%bx-out m (Str8 append (mbf->str v) " ")) (%bx-out m v)))))))
      items)
    (when (or (null? items)
              (not (List includes? (first (List last items)) (list (lit semi) (lit comma)))))
      (%bx-newline m))))

; --- DATA, READ and INPUT -------------------------------------------------

; Every DATA item of the program, in order: (LINE-NUMBER . ITEM)
(def %bx-restore!
  (fn (_ m)
    (m set! (lit data)
      (List flat-map
        (fn (_ line)
          (List flat-map
            (fn (_ st)
              (if (eq? (first st) (lit data))
                (List map (fn (_ item) (pair (first line) item)) (List second st))
                ()))
            (List third line)))
        (m get (lit lines))))))

; ITEM as a value for NAME: answers nil when a number was wanted and ITEM
; is not one
(def %bx-item
  (fn (_ m name item)
    (if (%bx-string-name? name) (List second item)
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
          (let ((v (%bx-item m (List second target) (rest (first left)))))
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
      (m set! (lit col) 0)
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
                      (let ((v (%bx-item m (List second (first targets)) (first items))))
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
            (let ((v (mbf-round (mbf-add ((m get (lit vars)) get-or mbf-zero var) step))))
              ((m get (lit vars)) set! var v)
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
            (%bx-array-make (first d)
              (List map (fn (_ e) (%bx-int-in (%bx-eval m e) 0 32767)) (rest d))))))
      decls)))

; DEF FN NAME(ARG)=FORMULA: ?TM for a string name or argument, ?ID typed
; at the prompt
(def %bx-def
  (fn (_ m st)
    (let ((name (List second st)) (arg (List third st)))
      (when (%bx-string-name? name) (%bx-fail "TM"))
      (when (null? (m get (lit line))) (%bx-fail "ID"))
      (when (%bx-string-name? arg) (%bx-fail "TM"))
      ((m get (lit fns)) set! name (pair arg (List ref 3 st))))))

; A statement run for its effect, which goes on to the next
(def %bx-effect
  (fn (_ m st tag)
    (match
      ((eq? tag (lit print)) (%bx-print m (List second st)))
      ((eq? tag (lit let)) (%bx-set! m (List second st) (%bx-eval m (List third st))))
      ((eq? tag (lit rem)) ())
      ((eq? tag (lit data)) ())
      ((eq? tag (lit dim)) (%bx-dim m (List second st)))
      ((eq? tag (lit read)) (%bx-read m (List second st)))
      ((eq? tag (lit restore)) (%bx-restore! m))
      ((eq? tag (lit list)) (%bx-list m (List second st) (List third st)))
      ((eq? tag (lit clear)) (%bx-clear! m))
      ((eq? tag (lit def)) (%bx-def m st))
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
        (%bx-set! m (list (lit var) name) (%bx-eval m (List third st)))
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
    (do (m set! (lit lines) ())
        (%bx-index! m)
        (%bx-clear! m)
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
    (let ((r (guard (e (if (or (eq? (Err label e) (lit basic)) (eq? (Err label e) (lit basic-todo)))
                         e (error e)))
               (%bx-run m (pair -1 (m get (lit direct)))))))
      (match
        ((eq? r (lit stop))
          (do (%bx-newline m)
              (%bx-out m (Str8 append "BREAK" (%bx-where m)))))
        ((eq? r (lit end)) ())
        (#t
          (do (m set! (lit stack) ())
              (m set! (lit cont) ())
              (%bx-newline m)
              (%bx-out m
                (if (eq? (Err label r) (lit basic))
                  (Str8 append "?" (Err text r) " ERROR" (%bx-where m))
                  (Str8 append "?" (Err text r) " IS NOT IN X-BASIC YET" (%bx-where m))))))))
    (%bx-ready m)))

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
                  (%bx-store! m (first got) (Str8 sub (rest got) (int- n (rest got)) text))
                  (%bx-direct m text))))
            (%bx-direct m text)))))))

; A line typed, upper-cased outside its strings, REM and DATA when the
; machine folds case
(def basic-type
  (fn (_ m text)
    (%bx-typed m (if (m get (lit fold-case)) (basic-fold (m get (lit dialect)) text) text))))

(provide basic/exec basic-machine basic-type)
