;; Load the sample module built by ellcc and call into it.
;; SAMPLE_ELL names the file; the caller builds it first.
;; Prints one line per fact so the job can match each by name.

(let ((file (getenv "SAMPLE_ELL")))
  (princ (format "file=%s exists=%s\n" file (and file (file-exists-p file))))
  (condition-case err
      (progn
	(load-module file)
	(princ (format "loaded=t\n"))
	(princ (format "sample-function=%S\n" (sample-function)))
	(princ (format "sample-boolean=%S\n" sample-boolean))
	;; sample-string is not printed: vars_of_sample never assigns
	;; Vsample_string, so its value is whatever the zeroed word means.
	(princ (format "list-modules=%S\n" (list-modules))))
    (error
     (princ (format "error=%S\n" err))
     (kill-emacs 1))))
(kill-emacs 0)
