;; Every key nt/xemacs.mak writes to config.values must come back through
;; config-value, the old ones as well as the ones added for ellcc.
;; config.el expands ${...} and $(...) across every value when it loads
;; the file, so one bad value would take all the keys with it, including
;; blddir, which build-report.el reads.

(require 'config)
(let ((nonempty '(blddir srcdir CC CFLAGS LISPDIR
		  XEMACS_CC XE_CFLAGS c_switch_all dll_ld dll_ldflags
		  dll_ldo dll_post configuration version))
      ;; Empty on purpose under MSVC: no PIC switch, no extra link flags.
      (empty '(dll_cflags LDFLAGS))
      (bad nil))
  (dolist (k nonempty)
    (let ((v (config-value k)))
      (princ (format "%s = %S\n" k v) 'external-debugging-output)
      (unless (and (stringp v) (> (length v) 0)) (push k bad))))
  (dolist (k empty)
    (let ((v (config-value k)))
      (princ (format "%s = %S\n" k v) 'external-debugging-output)
      (unless (equal v "") (push k bad))))
  (princ (format "keys in config-value-hash-table: %d\n"
		 (hash-table-count (config-value-hash-table)))
	 'external-debugging-output)
  (if bad
      (progn (princ (format "bad: %S\n" (nreverse bad)) 'external-debugging-output)
	     (kill-emacs 1))
    (princ "config.values: all keys present\n" 'external-debugging-output)
    (kill-emacs 0)))
