;; Windows で建てた XEmacs に動的ロード(モジュール)が入っているかを見る。
;;
;; 当初「xemacs.mak の OPT_DEFINES に -DHAVE_SHLIB が無いから無効」と読んだが、
;; それは探す場所が違っていた。Windows は configure を走らせず、
;; src/config.h.in をそのまま config.h にコピーして使い (nt/xemacs.mak 937)、
;; その中で後から s/windowsnt.h を読む (config.h.in 903)。s/windowsnt.h は
;; #define HAVE_SHLIB しているので (86)、312 行の #undef はそれに上書きされる。
;; emodules.obj と sysdll.obj も object 一覧に入っている。
;;
;; つまり経路は繋がっていて、modules は t で返るはず。「Windows のモジュール
;; 対応はまだ」が何を指すのかは、ここから先を測らないと分からない。
(princ (format "modules=%s\n" (featurep 'modules)))
(princ (format "load-module=%s unload-module=%s\n"
               (fboundp 'load-module) (fboundp 'unload-module)))
(princ (format "configuration=%s\n" system-configuration))
;; 実際に load-module を呼んで、どこで止まるかを見る。存在しない名前でよい。
;; 「機能が無い」のか「使えるが対象が無い」のかは、返る error で分かれる。
(princ (format "module-load-path=%s\n"
               (if (boundp 'module-load-path) module-load-path "(unbound)")))
(princ (format "module-extensions=%s\n"
               (if (boundp 'module-extensions) module-extensions "(unbound)")))
(condition-case err
    (progn (load-module "no-such-module-here")
           (princ "load-module: 例外なしで返った\n"))
  (error (princ (format "load-module: %S\n" err))))
