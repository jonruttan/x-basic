; # x-basic -- BASIC on x-lang
;
; ## basic/term.x -- the terminal a machine writes to
;
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)
;
; Text and zero bytes, both written to descriptor 1 with File write.  NULL
; prints zero bytes, which display cannot, and display reaches descriptor 1
; by another road, so the two would not keep their order.

(module basic/term)
(import x/sys/file)
(import x/core/doors int< int- str-make str-byte-len)

; TEXT written
(def basic-term-out
  (fn (_ text) (File write 1 text (str-byte-len text))))

; Zero bytes, read from /dev/zero when first needed: str-make's bytes are
; spaces
(def %term-zeros (list ()))

(def %term-zero-size 256)

; /dev/zero opened read-only, mode 0
(def %term-zero-buffer
  (fn (_)
    (when (null? (first %term-zeros))
      (let ((fd (File open "/dev/zero" 0)) (buf (str-make %term-zero-size)))
        (File read fd buf %term-zero-size)
        (File close fd)
        (%set-first! %term-zeros buf)))
    (first %term-zeros)))

; N zero bytes written
(def basic-term-zeros
  (fn (_ n)
    (let ((b (%term-zero-buffer)))
      (let ((go (fn (self left)
                  (when (int< 0 left)
                    (let ((k (if (int< %term-zero-size left) %term-zero-size left)))
                      (File write 1 b k)
                      (self (int- left k)))))))
        (go n)))))

(provide basic/term basic-term-out basic-term-zeros)
