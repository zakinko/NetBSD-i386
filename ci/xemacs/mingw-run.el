;; Run by the MinGW probe in the xemacs.exe it built.  The executable is
;; linked -mwindows, so nothing it prints reaches the console; write the
;; facts to the file MINGW_LOG instead.

(defun mingw-run-say (fmt &rest args)
  (let ((line (concat (apply #'format fmt args) "\n")))
    (with-temp-buffer
      (insert line)
      (write-region (point-min) (point-max) (getenv "MINGW_LOG") t 'silent))))

(mingw-run-say "emacs-version=%s" emacs-version)
(mingw-run-say "system-configuration=%s" system-configuration)
(mingw-run-say "dumped=%S" (and (boundp 'purify-flag) (not purify-flag)))
(mingw-run-say "mule=%S modules=%S" (featurep 'mule) (featurep 'modules))
(mingw-run-say "arith=%S" (+ 1 2))
(mingw-run-say "string=%S" (upcase "xemacs on mingw"))
(mingw-run-say "done")
(kill-emacs 0)
