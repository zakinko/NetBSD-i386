;; Emacs 20 用。princ は batch で端末に届かないので send-string-to-terminal。
;; dolist も無いので while で回す。
(defun say (s) (send-string-to-terminal s))
(defun kick (buf str)
  (set-buffer buf)
  (let ((l (append str nil)))
    (while l (setq last-command-event (car l)) (anthy-insert) (setq l (cdr l)))))
(condition-case e
    (progn
      (load "anthy-unicode.el") (load "leim-list.el")
      (say (format "  underline : %S\n" (face-underline-p 'anthy-highlight-face)))
      (let ((a (get-buffer-create "*A*")) (b (get-buffer-create "*B*")) va1 va2)
        (set-buffer a) (activate-input-method "japanese-anthy-unicode")
        (say (format "  imexit    : %S\n"
                     (if (boundp 'inactivate-current-input-method-function)
                         inactivate-current-input-method-function
                       'no-var)))
        (buffer-enable-undo a) (insert "AAA") (undo-boundary)
        (set-buffer b) (activate-input-method "japanese-anthy-unicode")
        (buffer-enable-undo b) (insert (make-string 40 ?B)) (undo-boundary)
        (kick a "nihongo")
        (setq va1 (save-excursion (set-buffer a) anthy-buffer-undo-list))
        (kick b "kanji")
        (setq va2 (save-excursion (set-buffer a) anthy-buffer-undo-list))
        (say (format "  undo      : %s\n" (if (equal va1 va2) "OK" "NG")))))
  (error (say (format "  ERR %S\n" e))))
