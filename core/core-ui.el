;;; core-ui.el -- User interface layout & behavior

(when (fboundp 'fringe-mode) (fringe-mode '(2 . 8)))

;; theme and GUI elements are loaded in init.el early
(setq show-paren-delay 0)

(global-hl-line-mode  1)    ; do highlight line
(blink-cursor-mode    1)    ; do blink cursor
(line-number-mode     1)    ; do show line no in modeline
(column-number-mode   1)    ; do show col no in modeline
(size-indication-mode 1)    ; do show file size
(tooltip-mode        -1)    ; don't show tooltips

;; Multiple cursors across buffers cause a strange redraw delay for
;; some things, like auto-complete or evil-mode's cursor color
;; switching.
(setq-default
 cursor-in-non-selected-windows  nil
 visible-bell                    nil    ; silence of the bells
 use-dialog-box                  nil  ; avoid GUI
 redisplay-dont-pause            t
 ;; do not soft-wrap lines
 truncate-lines                  t
 truncate-partial-width-windows  nil
 indicate-buffer-boundaries      nil
 indicate-empty-lines            nil
 fringes-outside-margins         t)

(use-package nlinum
  :commands nlinum-mode
  :init
  (progn
    (defface linum                '((t (:inherit default)))
      "Face for line numbers"
      :group 'nlinum-mode)
    (defface linum-highlight-face '((t (:inherit linum)))
      "Face for line highlights"
      :group 'nlinum-mode)

    ;; Preset width nlinum
    (add-hook! 'nlinum-mode-hook
      (setq nlinum--width (length (number-to-string (count-lines (point-min)
                                                                 (point-max))))))

    ;; Highlight line number
    (defvar narf--hl-nlinum-overlay nil)
    (defvar narf--hl-nlinum-line    nil)
    (defun narf/nlinum-unhl-line ()
      (when narf--hl-nlinum-overlay
        (let* ((ov narf--hl-nlinum-overlay)
               (disp (get-text-property 0 'display (overlay-get ov 'before-string)))
               (str (nth 1 disp)))
          (put-text-property 0 (length str) 'face 'linum str)
          (setq narf--hl-nlinum-overlay nil
                narf--hl-nlinum-line    nil))))

    (defun narf/nlinum-hl-line (&optional line)
      (let ((line-no (or line (line-number-at-pos (point)))))
        (when (and nlinum-mode (not (eq line-no narf--hl-nlinum-line)))
          (let* ((pbol (if line (save-excursion (goto-char (point-min))
                                                (forward-line line-no)
                                                (point-at-bol))
                         (point-at-bol)))
                 (peol (1+ pbol)))
            ;; Handle EOF case
            (when (>= peol (point-max))
              (setq peol (point-max)))
            (jit-lock-fontify-now pbol peol)
            (let* ((overlays (overlays-in pbol peol))
                   (ov (-first (lambda (item) (overlay-get item 'nlinum)) overlays)))
              (when ov
                (narf/nlinum-unhl-line)
                (let* ((disp (get-text-property 0 'display (overlay-get ov 'before-string)))
                       (str (nth 1 disp)))
                  (put-text-property 0 (length str) 'face 'linum-highlight-face str)
                  (put-text-property 0 (length str) 'face 'linum-highlight-face str)
                  (setq narf--hl-nlinum-overlay ov
                        narf--hl-nlinum-line    line-no))))))))

    (defun narf:nlinum-toggle ()
      (interactive)
      (if nlinum-mode
          (narf/nlinum-disable)
        (narf/nlinum-enable)))
    (defun narf/nlinum-enable ()
      (nlinum-mode +1)
      (add-hook 'post-command-hook 'narf/nlinum-hl-line))
    (defun narf/nlinum-disable ()
      (nlinum-mode -1)
      (remove-hook 'post-command-hook 'narf/nlinum-hl-line)
      (narf/nlinum-unhl-line))

    (add-hook 'prog-mode-hook 'narf/nlinum-enable)
    (add-hook 'org-mode-hook  'narf/nlinum-disable))
  :config
  (setq-default nlinum-format " %4d  "))

(when window-system
  (setq frame-title-format '(buffer-file-name "%f" ("%b")))
  (if (string-equal (system-name) "io")
      (set-frame-size (selected-frame) 326 119)))

(add-hook! 'after-init-hook
  (defadvice save-buffers-kill-emacs (around no-query-kill-emacs activate)
    "Prevent annoying \"Active processes exist\" query when you quit Emacs."
    (flet ((process-list ())) ad-do-it)))


;;;; Modeline ;;;;;;;;;;;;;;;;;;;;;;;;;;
(use-package smart-mode-line
  :config
  (progn
    (setq sml/no-confirm-load-theme t
          sml/mode-width      'full
          sml/extra-filler    -7
          sml/show-remote     nil
          sml/modified-char   "*"
          sml/encoding-format nil
          sml/replacer-regexp-list '(("^~/Dropbox/Projects/" "PROJECTS:")
                                     ("^~/.emacs.d/" "EMACS.D:")
                                     ("^~/Dropbox/notes/" "NOTES:")
                                     ("^/usr/local/Cellar/" "HOMEBREW:"))
          sml/pre-modes-separator " : "
          sml/pre-minor-modes-separator " "
          sml/pos-minor-modes-separator ": "
          sml/numbers-separator "/"
          sml/line-number-format "%3l"
          sml/col-number-format "%2c")

    ;; Hide evil state indicator
    (after "evil" (setq evil-mode-line-format nil))

    (setq-default mode-line-misc-info
      '((which-func-mode ("" which-func-format ""))
        (global-mode-string ("" global-mode-string ""))))

    (sml/setup)
    (sml/apply-theme 'respectful)

    ;; Hack modeline to be more vim-like, and right-aligned
    (defun sml/generate-minor-modes ()
      (if sml/simplified
          ""
        (let* ((nameList (rm--mode-list-as-string-list))
               (last nil)
               (concatList (mapconcat (lambda (mode)
                                        (setq mode (s-trim mode))
                                        (if (> (length mode) 1)
                                            (prog1 (concat (if last " ") mode " ")
                                              (setq last nil))
                                          (prog1 mode
                                            (setq last t))))
                                      nameList ""))
               (size (sml/fill-width-available))
               (finalNameList concatList)
               needs-removing filling)
          (when (and sml/shorten-modes (> (length finalNameList) size))
            (setq needs-removing
                  (1+ (sml/count-occurrences-starting-at
                       " " finalNameList
                       (- size (string-width sml/full-mode-string))))))
          (when needs-removing
            (setcdr (last nameList (1+ needs-removing))
                    (list t sml/propertized-full-mode-string)))
          (unless sml/shorten-modes
            (add-to-list 'nameList sml/propertized-shorten-mode-string t))

          ;; Padding
          (setq filling (- size (+ (length (format-mode-line concatList)) (length mode-name) (length vc-mode))))
          (setq filling (make-string (max 0 filling) sml/fill-char))

          (list (propertize filling 'face 'sml/modes)
                (propertize (or vc-mode "") 'face 'sml/vc)
                (propertize sml/pre-modes-separator 'face 'font-lock-comment-delimiter-face)
                (propertize mode-name)
                'sml/pre-minor-modes-separator
                concatList
                (propertize sml/pos-minor-modes-separator 'face
                            'font-lock-comment-delimiter-face)))))

    ;; Remove extra spaces in format lists
    (pop mode-line-modes)
    (nbutlast mode-line-modes)

    ;; Remove spacing in mode-line position so we can put it elsewhere
    (setq mode-line-position
          '((sml/position-percentage-format
             (-3 (:propertize (:eval sml/position-percentage-format)
                              face sml/position-percentage help-echo "Buffer Relative Position\nmouse-1: Display Line and Column Mode Menu")))))

    (after "anzu"
      ;; Add small gap for anzu
      (defun narf/anzu-update-mode-line (here total)
        (concat (anzu--update-mode-line-default here total) " "))
      (setq anzu-mode-line-update-function 'narf/anzu-update-mode-line))

    ;; Rearrange and cleanup
    (setq-default mode-line-format
                  '("%e "
                    mode-line-mule-info
                    mode-line-client
                    mode-line-remote
                    mode-line-frame-identification
                    mode-line-buffer-identification
                    mode-line-modified
                    mode-line-misc-info
                    mode-line-modes
                    mode-line-front-space
                    mode-line-end-spaces
                    " "
                    ":" mode-line-position
                    ))))


(provide 'core-ui)
;;; core-ui.el ends here
