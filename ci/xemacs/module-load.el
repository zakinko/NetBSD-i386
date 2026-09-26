;; Load the sample module built by ellcc and call into it.
;; SAMPLE_ELL names the file; the caller builds it first.
;; Prints one line per fact so the job can match each by name.
;;
;; Lines go to external-debugging-output, stderr, which is not buffered,
;; so a process that dies inside load-module still leaves what it had
;; reached.

(setq load-modules-quietly nil)

(defun module-load-say (fmt &rest args)
  (princ (concat (apply #'format fmt args) "\n") 'external-debugging-output))

(let ((file (getenv "SAMPLE_ELL")))
  (module-load-say "file=%s exists=%s" file (and file (file-exists-p file)))
  (condition-case err
      (progn
	(module-load-say "calling load-module")
	(load-module file)
	(module-load-say "loaded=t")
	(module-load-say "sample-function=%S" (sample-function))
	(module-load-say "sample-boolean=%S" sample-boolean)
	;; sample-string is not printed: vars_of_sample never assigns
	;; Vsample_string, so its value is whatever the zeroed word means.
	(module-load-say "list-modules=%S" (list-modules)))
    (error
     (module-load-say "error=%S" err)
     (kill-emacs 1))))
(kill-emacs 0)
