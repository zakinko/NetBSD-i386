;; -*- coding: utf-8 -*-
;; Does the leim teardown get hooked up?
;;
;; Decide WHICH variable this Emacs reads BEFORE loading anthy.  upstream
;; assigns to deactivate-current-input-method-function with setq, and on an
;; Emacs that has no such variable that simply creates one -- so asking
;; boundp afterwards always says yes and the test passes for the wrong
;; reason.  This is what the first version of this test got wrong.
(setq want (cond ((boundp 'deactivate-current-input-method-function)
                  'deactivate-current-input-method-function)
                 ((boundp 'inactivate-current-input-method-function)
                  'inactivate-current-input-method-function)
                 (t nil)))
(load-library "anthy-unicode")
(load "leim-list")
(set-buffer (get-buffer-create "*t*"))
(activate-input-method "japanese-anthy-unicode")
(princ (format "  this Emacs reads : %s\n" want))
(princ (format "  anthy set it to  : %S\n" (and want (symbol-value want))))
(princ (format "  verdict          : %s\n"
               (if (and want (eq (symbol-value want) 'anthy-unicode-leim-inactivate))
                   "OK (teardown is wired up)"
                 "NG (leaving the input method will not run anthy's teardown)")))
