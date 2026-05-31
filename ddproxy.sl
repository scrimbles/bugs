;;; ddproxy.sl — devdraw keyboard rune filter
;;;
;;; Reads devdraw wire protocol messages from stdin (real devdraw),
;;; rewrites keyboard runes for emacs-style navigation bindings,
;;; writes to stdout (acme). Used as a filter in the ddproxy pipeline.
;;;
;;; Wire format: [4-byte BE length][1-byte tag][1-byte type][payload]
;;; Rrdkbd  (type 11): 8 bytes total, 2-byte rune at offset 6
;;; Rrdkbd4 (type 33): 10 bytes total, 4-byte rune at offset 6

;;; Message types
(def Rrdkbd 11)
(def Rrdkbd4 33)

;;; Plan 9 keyboard runes
(def Kdown  #x80)
(def Khome  #xF00D)
(def Kup    #xF00E)
(def Kleft  #xF011)
(def Kright #xF012)
(def Kend   #xF018)

;;; Keybinding table: control char → action
;;; Actions are either a rune (simple translation) or a function
;;; (9P operation, sends NUL to acme as no-op).
(def *bindings* (table
  #x02 Kleft    ; C-b → left
  #x06 Kright   ; C-f → right
  #x0E 'down    ; C-n → move cursor down (9P)
  #x10 'up))    ; C-p → move cursor up (9P)
;;; C-a, C-e already work natively in acme

;;; 9P command output
;;;
;;; On Plan 9, we could use (file) to access /mnt/acme directly.
;;; On plan9port (macOS/Linux), 9pfuse is unreliable, so we write
;;; commands to stderr. The ddproxy shell script reads these and
;;; dispatches them via the 9p command.
;;;
;;; Command format (one per line on stderr):
;;;   C <id> <cmd>     → write to acme/<id>/ctl
;;;   A <id> <addr>    → write to acme/<id>/addr
;;;   D <id> <data>    → write to acme/<id>/data

(def *focus-file* "/tmp/acme-focus")

(def (read-focus)
  (trycatch
    (let ((f (file *focus-file* :read)))
      (let ((line (io-read-until f #\newline)))
        (io-close f)
        (if (eof-object? line) NIL line)))
    (lambda (e) NIL)))

(def (cmd s)
  (io-write *io-err* (str s "\n"))
  (io-flush *io-err*))

(def (acme-ctl id c)   (cmd (str "C " id " " c)))
(def (acme-addr id a)  (cmd (str "A " id " " a)))
(def (acme-data id d)  (cmd (str "D " id " " d)))

(def (dispatch-action action)
  (let ((id (read-focus)))
    (when id
      (cond
        ((eqv? action 'down) (cmd (str "N " id)))
        ((eqv? action 'up)   (cmd (str "U " id)))))))

(def (translate rune)
  (get *bindings* rune rune))

;;; Big-endian byte helpers

(def (u32be buf off)
  (logior (ash (aref buf off) 24)
          (ash (aref buf (+ off 1)) 16)
          (ash (aref buf (+ off 2)) 8)
          (aref buf (+ off 3))))

(def (u32be! buf off v)
  (aset! buf off       (logand (ash v -24) #xFF))
  (aset! buf (+ off 1) (logand (ash v -16) #xFF))
  (aset! buf (+ off 2) (logand (ash v  -8) #xFF))
  (aset! buf (+ off 3) (logand v #xFF)))

(def (u16be buf off)
  (logior (ash (aref buf off) 8)
          (aref buf (+ off 1))))

(def (u16be! buf off v)
  (aset! buf off       (logand (ash v -8) #xFF))
  (aset! buf (+ off 1) (logand v #xFF)))

;;; Main proxy loop

(def (proxy)
  (let loop ()
    (let ((hdr (io-read *io-in* 'u8 4)))
      (unless (eof-object? hdr)
        (let* ((len (u32be hdr 0))
               (rest (io-read *io-in* 'u8 (- len 4))))
          (unless (eof-object? rest)
            ;; rest[0]=tag, rest[1]=type, rest[2..]=payload
            (let ((action NIL))
              (when (>= (length rest) 2)
                (let ((type (fixnum (aref rest 1))))
                  (cond
                    ;; Rrdkbd4: 4-byte rune at rest[2..5]
                    ((and (= type Rrdkbd4) (= len 10))
                     (let* ((rune (fixnum (u32be rest 2)))
                            (new (translate rune)))
                       (cond
                         ((sym? new)
                          (set! action new)
                          (u32be! rest 2 0))  ; NUL no-op
                         ((not (= rune new))
                          (u32be! rest 2 new)))))
                    ;; Rrdkbd: 2-byte rune at rest[2..3]
                    ((and (= type Rrdkbd) (= len 8))
                     (let* ((rune (fixnum (u16be rest 2)))
                            (new (translate rune)))
                       (cond
                         ((sym? new)
                          (set! action new)
                          (u16be! rest 2 0))  ; NUL no-op
                         ((not (= rune new))
                          (u16be! rest 2 new))))))))
              ;; Forward message (with NUL or translated rune)
              (io-write *io-out* hdr)
              (io-write *io-out* rest)
              (io-flush *io-out*)
              ;; Perform 9P action after unblocking acme
              (when action
                (dispatch-action action)))
            (loop)))))))

(proxy)
