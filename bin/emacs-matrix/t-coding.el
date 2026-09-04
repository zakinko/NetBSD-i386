;; -*- coding: utf-8 -*-
;; The pipe to the agent.  anthy-agent-unicode speaks UTF-8 only, so the
;; user's locale must not decide what goes over the pipe.
;;
;; Print the buffer as UTF-8 BYTES, not as characters.  Emacs 22 does not
;; hold Japanese as Unicode code points internally, and princ of multibyte
;; text in batch is mangled on the older versions -- both would make a
;; correct result look wrong.  Bytes are the same on every version.
(load-library "anthy-unicode")
(load "leim-list")
(set-buffer (get-buffer-create "*t*"))
(activate-input-method "japanese-anthy-unicode")
(dolist (c (append "nihongo " nil))
  (setq last-command-event (if (featurep (quote xemacs)) (character-to-event c) c)) (anthy-insert))
(setq last-command-event (if (featurep (quote xemacs)) (character-to-event 13) 13)) (anthy-insert)
(let* ((s (buffer-string))
       (b (if (fboundp 'encode-coding-string) (encode-coding-string s 'utf-8) s))
       (h ""))
  (dotimes (i (length b))
    (setq h (concat h (format "%02x " (logand (aref b i) 255)))))
  (princ (format "  pipe coding : %S\n"
                 (if (fboundp 'process-coding-system)
                     (process-coding-system anthy-agent-unicode-process)
                   'n/a)))
  (princ (format "  utf-8 bytes : %s\n" h))
  (princ (format "  verdict     : %s\n"
                 (if (string= h "e6 97 a5 e6 9c ac e8 aa 9e ")
                     "OK (nihongo -> the three kanji)"
                   "NG (not the expected bytes)"))))
