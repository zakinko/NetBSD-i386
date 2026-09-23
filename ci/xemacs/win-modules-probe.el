;; Windows で建てた XEmacs に動的ロード(モジュール)が入っているかを見る。
;;
;; src/sysdll.c には WIN32_NATIVE 用の LoadLibrary/GetProcAddress 実装が
;; 既に在るが、その全体が #ifdef HAVE_SHLIB の中で、nt/xemacs.mak の
;; OPT_DEFINES に -DHAVE_SHLIB が無い。emodules.c は (provide 'modules) を
;; するので、Lisp から見えるかどうかがそのまま答になる。
;;
;; -eval を shell から渡すと引用が入れ子になって壊れる。file に置いて
;; -load する。
(princ (format "modules=%s load-module=%s unload-module=%s\n"
               (featurep 'modules)
               (fboundp 'load-module)
               (fboundp 'unload-module)))
(princ (format "configuration=%s\n" system-configuration))
