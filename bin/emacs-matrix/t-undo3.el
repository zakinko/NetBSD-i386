;; -*- coding: utf-8 -*-
;; Does B's saved undo list overwrite A's?
;;
;; A and B must differ in length: with the same length a clobbered list and
;; a correct one look identical.  Read A's value with the current buffer set
;; back to A -- reading it right after kicking B would read B's own value
;; once the variable is buffer local, which is the fix, not the bug.
;;
;; Do not call undo here.  In batch it inserts a Redo boundary and the
;; result stops meaning anything.  Look at buffer-undo-list directly.
(load-library "anthy-unicode")
(load "leim-list")

(defun kick (buf str)
  (set-buffer buf)
  (dolist (c (append str nil))
    (setq last-command-event (if (featurep (quote xemacs)) (character-to-event c) c)) (anthy-insert)))

(let ((a (get-buffer-create "*A*")) (b (get-buffer-create "*B*")))
  (set-buffer a) (activate-input-method "japanese-anthy-unicode")
  (buffer-enable-undo a) (insert "AAA") (undo-boundary)
  (set-buffer b) (activate-input-method "japanese-anthy-unicode")
  (buffer-enable-undo b) (insert (make-string 40 ?B)) (undo-boundary)

  (kick a "nihongo")
  (setq va1 (with-current-buffer a anthy-buffer-undo-list))
  (kick b "kanji")
  (setq va2 (with-current-buffer a anthy-buffer-undo-list))

  (princ (format "  buffer local?    : %s\n"
                 (with-current-buffer a
                   (if (if (featurep 'xemacs) (local-variable-p 'anthy-buffer-undo-list (current-buffer)) (local-variable-p 'anthy-buffer-undo-list)) "yes" "NO (global)"))))
  (princ (format "  A saved, A's val : %S\n" va1))
  (princ (format "  B saved, A's val : %S\n" va2))
  (set-buffer a)
  (setq last-command-event (if (featurep (quote xemacs)) (character-to-event 13) 13)) (anthy-insert)
  (princ (format "  A after commit   : %S\n" buffer-undo-list))
  (princ (format "  verdict          : %s\n"
                 (if (equal va1 va2)
                     "OK (A keeps its own history)"
                   "NG (B's history landed in A)"))))
