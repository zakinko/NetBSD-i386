;; Load the sample module built by ellcc and call into it.
;; SAMPLE_ELL names the file; the caller builds it first.
;; Prints one line per fact so the job can match each by name.
;;
;; Each line is also appended to SAMPLE_LOG as it is produced.  stdout
;; is buffered, and a process that dies inside load-module takes the
;; buffer with it; the first run on Windows came back with exit 1 and
;; not even the line printed before the load.

(setq load-modules-quietly nil)

(defun module-load-say (fmt &rest args)
  (let ((line (concat (apply #'format fmt args) "\n"))
	(log (getenv "SAMPLE_LOG")))
    (princ line)
    (when log
      (write-region line nil log t 'silent))))

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
