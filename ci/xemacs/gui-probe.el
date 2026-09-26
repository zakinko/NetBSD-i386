;; Run inside a GUI XEmacs on Windows (no -batch).  Record what the
;; frame looks like to Lisp, load the sample module if SAMPLE_ELL names
;; one, give the runner time to type into the window and take a
;; screenshot, then write what arrived in the buffer and exit.
;;
;; Output goes to the file GUI_LOG: a GUI process has no console.

(defun gui-probe-say (fmt &rest args)
  (let ((line (concat (apply #'format fmt args) "\n")))
    (with-temp-buffer
      (insert line)
      (write-region (point-min) (point-max) (getenv "GUI_LOG") t 'silent))))

(gui-probe-say "device-type=%S" (device-type))
(gui-probe-say "console-type=%S" (console-type))
(gui-probe-say "frames=%d" (length (frame-list)))
(gui-probe-say "frame-size=%dx%d" (frame-width) (frame-height))
(gui-probe-say "menubar=%S" (and (boundp 'current-menubar) (consp current-menubar)))

(switch-to-buffer (get-buffer-create "*gui-probe*"))
(erase-buffer)
(insert "XEmacs GUI probe\n")
(let ((ell (getenv "SAMPLE_ELL")))
  (if (not (and ell (> (length ell) 0)))
      (gui-probe-say "module=skipped")
    (condition-case err
	(progn
	  (load-module ell)
	  (insert (format "sample-function => %S\n" (sample-function)))
	  (gui-probe-say "module=loaded sample-function=t"))
      (error (gui-probe-say "module-error=%S" err)))))
(insert "typed: ")
(gui-probe-say "ready")

;; The runner types into the window while this waits, then screenshots.
;; start-itimer, not run-at-time: the latter is GNU Emacs's, and under
;; -vanilla it is not defined here.  The first GUI run stopped with
;; "Symbol's function definition is void: run-at-time" in the echo area
;; and never exited.
(require 'itimer)
(start-itimer "gui-probe-exit"
	      (lambda ()
		(gui-probe-say "buffer=%S"
			       (with-current-buffer "*gui-probe*" (buffer-string)))
		(gui-probe-say "exiting")
		(kill-emacs 0))
	      25)
