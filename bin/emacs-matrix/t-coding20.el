;; t-coding.el の Emacs 20 版。princ が届かないので send-string-to-terminal。
(defun say (s) (send-string-to-terminal s))
(condition-case e
    (progn
      (load "anthy-unicode.el") (load "leim-list.el")
      (set-buffer (get-buffer-create "*t*"))
      (activate-input-method "japanese-anthy-unicode")
      (let ((l (append "nihongo " nil)))
	(while l (setq last-command-event (car l)) (anthy-insert) (setq l (cdr l))))
      (setq last-command-event 13) (anthy-insert)
      (let* ((s (buffer-string)) (b (encode-coding-string s 'utf-8))
	     (i 0) (h ""))
	(while (< i (length b))
	  (setq h (concat h (format "%02x " (logand (aref b i) 255))) i (1+ i)))
	(say (format "  bytes: %s\n" h))
	(say (format "  %s\n" (if (string= h "e6 97 a5 e6 9c ac e8 aa 9e ") "OK" "NG")))))
  (error (say (format "  ERR %S\n" e))))
