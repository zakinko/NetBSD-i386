;; query-coding-tests.el runs two assertions per ASCII-transparent coding
;; system that (coding-system-list nil) returns, so its test count moves
;; with that list.  Print the size of the list.
(princ (format "coding-systems=%d\n" (length (coding-system-list nil))))
