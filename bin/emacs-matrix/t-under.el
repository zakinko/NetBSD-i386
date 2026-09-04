;; Does anthy-highlight-face actually get an underline here?
(load-library "anthy-unicode")
(princ (format "  underline: %S\n" (face-underline-p 'anthy-highlight-face)))
