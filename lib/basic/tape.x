; # x-basic -- BASIC on x-lang
;
; ## lib/basic/tape.x -- a KIM-1 cassette record in a file
;
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)
;
; The characters the KIM-1 monitor's DUMPT ($1800) writes to tape and its
; LOADT ($1873) reads back: 100 SYN ($16), *, the ID, the start address low
; then high, the data, each byte as two upper-case hex digits, then /, the
; checksum low then high, and two EOT ($04).  The checksum is the 16-bit
; sum of the start address and the data bytes, not the ID.  A load takes
; the first record after ten SYN and a *, whatever its ID, and leaves its
; start address unused, as LOADT does with $FF at ID ($17F9).

(module basic/tape)
(import x/type/list)
(import x/type/str)
(import x/type/dict)
(import x/sys/file)
(import x/core/doors int+ int* int< int= int& int>> str-make str-byte-ref str-byte-len)

(def %tape-digits "0123456789ABCDEF")

; Byte B as two hex digits
(def %tape-hex
  (fn (_ b)
    (Str8 append (Str8 sub (int>> b 4) 1 %tape-digits) (Str8 sub (int& b 15) 1 %tape-digits))))

; The value of hex digit C, -1 for any other byte
(def %tape-digit
  (fn (_ c)
    (match
      ((and (not (int< c 48)) (int< c 58)) (int+ c -48))
      ((and (not (int< c 65)) (int< c 71)) (int+ c -55))
      (#t -1))))

; A record of BYTES from address START, with ID, written to PATH: #t, or
; #f when PATH cannot be opened
(def tape-save
  (fn (_ path id start bytes)
    (let ((fd (File open path (list 'wronly 'creat 'trunc))))
      (if (int< fd 0) #f
        (let ((lo (int& start 255)) (hi (int& (int>> start 8) 255)))
          (let ((sum (int& (List fold (fn (_ s b) (int+ s b)) (int+ lo hi) bytes) 65535)))
            (let ((text (Str8 join ""
                          (List append
                            (list (Str8 repeat 100 (bytes->str (list 22))) "*"
                                  (%tape-hex id) (%tape-hex lo) (%tape-hex hi))
                            (List map %tape-hex bytes)
                            (list "/" (%tape-hex (int& sum 255)) (%tape-hex (int>> sum 8))
                                  (bytes->str (list 4 4)))))))
              (File write fd text (str-byte-len text))
              (File close fd)
              #t)))))))

(def %tape-size 512)

; A reader of descriptor FD, a buffer at a time
(def %tape-reader
  (fn (_ fd)
    (let ((r (Dict make)))
      (r set! (lit fd) fd)
      (r set! (lit buf) (str-make %tape-size))
      (r set! (lit n) 0)
      (r set! (lit i) 0)
      r)))

; The next byte R reads, -1 at the end
(def %tape-char
  (fn (_ r)
    (unless (int< (r get (lit i)) (r get (lit n)))
      (let ((k (File read (r get (lit fd)) (r get (lit buf)) %tape-size)))
        (r set! (lit n) (if (int< k 0) 0 k))
        (r set! (lit i) 0)))
    (if (int< (r get (lit i)) (r get (lit n)))
      (let ((c (str-byte-ref (r get (lit buf)) (r get (lit i)))))
        (r set! (lit i) (int+ (r get (lit i)) 1))
        c)
      -1)))

; The byte of hex digits C and the next, -1 when either is not one
(def %tape-pair
  (fn (_ r c)
    (let ((h (%tape-digit c)))
      (if (int< h 0) -1
        (let ((l (%tape-digit (%tape-char r))))
          (if (int< l 0) -1 (int+ (int* h 16) l)))))))

(def %tape-byte (fn (_ r) (%tape-pair r (%tape-char r))))

; The record past the *: its data bytes in a list, or nil for a byte that
; is not hex, a checksum that does not match, or the end of the tape
(def %tape-body
  (fn (_ r)
    (let ((id (%tape-byte r)) (lo (%tape-byte r)))
      (let ((hi (%tape-byte r)))
        (if (or (int< id 0) (int< lo 0) (int< hi 0)) ()
          (let ((go (fn (self sum acc)
                      (let ((c (%tape-char r)))
                        (if (int= c 47)
                          (let ((cl (%tape-byte r)))
                            (let ((ch (%tape-byte r)))
                              (if (and (int= cl (int& sum 255)) (int= ch (int>> sum 8)))
                                (list (List reverse acc))
                                ())))
                          (let ((b (%tape-pair r c)))
                            (if (int< b 0) ()
                              (self (int& (int+ sum b) 65535) (pair b acc)))))))))
            (go (int+ lo hi) ())))))))

; The data of the first record PATH holds, in a list of one, or nil when PATH
; cannot be opened or holds no good record
(def tape-load
  (fn (_ path)
    (let ((fd (File open path 'rdonly)))
      (if (int< fd 0) ()
        (let ((r (%tape-reader fd)))
          ; HUNT for a SYN, COUNT the ten after it, then skip SYN to the *;
          ; any other byte hunts again
          (let ((go (fn (self state k)
                      (let ((c (%tape-char r)))
                        (match
                          ((int< c 0) ())
                          ((eq? state (lit hunt)) (self (if (int= c 22) (lit count) (lit hunt)) 0))
                          ((eq? state (lit count))
                            (match
                              ((not (int= c 22)) (self (lit hunt) 0))
                              ((int= k 9) (self (lit star) 0))
                              (#t (self (lit count) (int+ k 1)))))
                          (#t
                            (match
                              ((int= c 42) (%tape-body r))
                              ((int= c 22) (self (lit star) 0))
                              (#t (self (lit hunt) 0)))))))))
            (let ((got (go (lit hunt) 0)))
              (File close fd)
              got)))))))

(provide basic/tape tape-save tape-load)
