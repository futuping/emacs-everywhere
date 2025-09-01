;;; emacs-everywhere.el --- System-wide popup windows for quick edits -*- lexical-binding: t; -*-

;; Copyright (C) 2021 TEC

;; Author: TEC <https://github.com/tecosaur>
;; Maintainer: TEC <contact@tecosaur.net>
;; Created: February 06, 2021
;; Modified: February 06, 2021
;; Version: 0.1.0
;; Keywords: convenience, frames
;; Homepage: https://github.com/tecosaur/emacs-everywhere
;; Package-Requires: ((emacs "26.3"))

;;; License:

;; This file is part of org-pandoc-import, which is not part of GNU Emacs.
;; SPDX-License-Identifier: GPL-3.0-or-later

;;; Commentary:

;;  System-wide popup Emacs windows for quick edits

;;; Code:

(require 'cl-lib)
(require 'server)
(require 'subr-x)

(defgroup emacs-everywhere ()
  "Customise group for Emacs-everywhere."
  :group 'convenience)

(define-obsolete-variable-alias
  'emacs-everywhere-paste-p 'emacs-everywhere-paste-command "0.1.0")
(defalias 'emacs-everywhere-call 'emacs-everywhere--call)
(make-obsolete 'emacs-everywhere-call "Now private API" "0.2.0")
(define-obsolete-variable-alias
  'emacs-everywhere-return-converted-org-to-gfm
  'emacs-everywhere-convert-org-to-gfm "0.2.0")
(defvaralias 'emacs-everywhere-mode-initial-map 'emacs-everywhere--initial-mode-map)
(make-obsolete-variable 'emacs-everywhere-mode-initial-map "Now private API" "0.2.0")
(defalias 'emacs-everywhere-erase-buffer 'emacs-everywhere--erase-buffer)
(make-obsolete 'emacs-everywhere-erase-buffer "Now private API" "0.2.0")
(defalias 'emacs-everywhere-finish-or-ctrl-c-ctrl-c 'emacs-everywhere--finish-or-ctrl-c-ctrl-c)
(make-obsolete 'emacs-everywhere-finish-or-ctrl-c-ctrl-c "Now private API" "0.2.0")
(defalias 'emacs-everywhere-app-info-osx 'emacs-everywhere--app-info-osx)
(make-obsolete 'emacs-everywhere-app-info-osx "Now private API" "0.2.0")
(defalias 'emacs-everywhere-ensure-oscascript-compiled 'emacs-everywhere--ensure-oscascript-compiled)
(make-obsolete 'emacs-everywhere-ensure-oscascript-compiled "Now private API" "0.2.0")

(defvar emacs-everywhere--display-server
  '(quartz . nil)
  "The detected display server.")

(defcustom emacs-everywhere-paste-command
  (list "osascript" "-e" "tell application \"System Events\" to keystroke \"v\" using command down")
  "Command to trigger a system paste from the clipboard.
This is given as a list in the form (CMD ARGS...).

To not run any command, set to nil."
  :type '(set (repeat string) (const nil))
  :group 'emacs-everywhere)

(defcustom emacs-everywhere-copy-command
  nil
  "Command to write to the system clipboard from a file (%f).
This is given as a list in the form (CMD ARGS...).
In the arguments, \"%f\" is treated as a placeholder for the path
to the file.

When nil, nothing is executed.

`gui-select-text' is always called on the buffer content, however experience
suggests that this can be somewhat flakey, and so an extra step to make sure
it worked can be a good idea."
  :type '(set (repeat string) (const nil))
  :group 'emacs-everywhere)

(defcustom emacs-everywhere-window-focus-command
  (list "osascript" "-e" "tell application id \"%w\" to activate")
  "Command to refocus the active window when emacs-everywhere was triggered.
This is given as a list in the form (CMD ARGS...).
In the arguments, \"%w\" is treated as a placeholder for the window ID,
as returned by `emacs-everywhere-app-id'.

When nil, nothing is executed, and pasting is not attempted."
  :type '(set (repeat string) (const nil))
  :group 'emacs-everywhere)

(defcustom emacs-everywhere-markdown-windows
  '("Reddit" "Stack Exchange" "Stack Overflow" ; Sites
    "Discord" "Element" "Slack" "HedgeDoc" "HackMD" "Zulip" ; Web Apps
    "Pull Request" "Issue" "Comparing .*\\.\\.\\.") ; Github
  "For use with `emacs-everywhere-markdown-p'.
Patterns which are matched against the window title."
  :type '(rep string)
  :group 'emacs-everywhere)

(defcustom emacs-everywhere-markdown-apps
  '("Discord" "Element" "Fractal" "NeoChat" "Slack")
  "For use with `emacs-everywhere-markdown-p'.
Patterns which are matched against the app name."
  :type '(rep string)
  :group 'emacs-everywhere)

(defcustom emacs-everywhere-frame-name-format "Emacs Everywhere :: %s — %s"
  "Format string used to produce the frame name.
Formatted with the app name, and truncated window name."
  :type 'string
  :group 'emacs-everywhere)

(defcustom emacs-everywhere-major-mode-function
  (cond
   ((executable-find "pandoc") #'org-mode)
   ((fboundp 'markdown-mode) #'emacs-everywhere-major-mode-org-or-markdown)
   (t #'text-mode))
  "Function which sets the major mode for the Emacs Everywhere buffer.

When set to `org-mode', pandoc is used to convert from markdown to Org
when applicable."
  :type 'function
  :options '(org-mode
             emacs-everywhere-major-mode-org-or-markdown
             text-mode)
  :group 'emacs-everywhere)

(defcustom emacs-everywhere-init-hooks
  '(emacs-everywhere-set-frame-name
    emacs-everywhere-set-frame-position
    emacs-everywhere-apply-major-mode
    emacs-everywhere-insert-selection
    emacs-everywhere-remove-trailing-whitespace
    emacs-everywhere-init-spell-check)
  "Hooks to be run before function `emacs-everywhere-mode'."
  :type 'hook
  :group 'emacs-everywhere)

(defcustom emacs-everywhere-final-hooks
  '(emacs-everywhere-convert-org-to-gfm
    emacs-everywhere-remove-trailing-whitespace)
  "Hooks to be run just before content is copied."
  :type 'hook
  :group 'emacs-everywhere)

(defcustom emacs-everywhere-frame-parameters
  `((name . "emacs-everywhere")
    (fullscreen . nil) ; Helps on GNOME at least
    (width . 80)
    (height . 12))
  "Parameters `make-frame' recognises to apply to the emacs-everywhere frame."
  :type 'list
  :group 'emacs-everywhere)

(defcustom emacs-everywhere-top-padding 0.2
  "Use the header-line to introduce this fraction of a line as padding.
Set to nil to disable."
  :type '(choice (const nil :tag "No padding") number)
  :group 'emacs-everywhere)

(defcustom emacs-everywhere-file-dir
  temporary-file-directory
  "The default dir for`emacs-everywhere-filename-function'-generated temp files."
  :type 'string
  :group 'emacs-everywhere)

(defcustom emacs-everywhere-file-patterns
  (let ((default-directory emacs-everywhere-file-dir))
    (list (concat "^" (regexp-quote (file-truename "emacs-everywhere-")))
          ;; For qutebrowser 'editor.command' support
          (concat "^" (regexp-quote (file-truename "qutebrowser-editor-")))))
  "A list of file regexps to activate `emacs-everywhere-mode' for."
  :type '(repeat regexp)
  :group 'emacs-everywhere)

(defcustom emacs-everywhere-pandoc-md-args
  '("-f" "markdown-auto_identifiers" "-t" "org")
  "Arguments supplied to pandoc when converting text from Markdown to Org."
  :type '(repeat string)
  :group 'emacs-everywhere)

(defcustom emacs-everywhere-clipboard-sleep-delay
  (cond
   ((eq system-type 'darwin) 0.1) ; MacOS seems to need a little longer
   (t 0.01))
  "Waiting period to wait to propagate clipboard actions."
  :type 'number
  :group 'emacs-everywhere)

(defun emacs-everywhere-temp-filename (app-info)
  "Generate a temp file based on APP-INFO."
  (concat "emacs-everywhere-"
          (format-time-string "%Y%m%d-%H%M%S-" (current-time))
          (emacs-everywhere-app-class app-info)))

(defcustom emacs-everywhere-filename-function
  #'emacs-everywhere-temp-filename
  "A function which generates a file name for the buffer.
The function is passed the result of `emacs-everywhere-app-info'.
Make sure that it will be matched by `emacs-everywhere-file-patterns'."
  :type 'function
  :group 'emacs-everywhere)

(defcustom emacs-everywhere-app-info-function
  #'emacs-everywhere--app-info-osx
  "Function that asks the system for information on the current foreground app.
On most systems, this should be set to a sensible default, but it
may not be set on less common configurations. If unset, a custom
app-info function can be used — see the various
emacs-everywhere--app-info-* functions for reference."
  :type 'function
  :group 'emacs-everywhere)

;; Semi-internal variables

(defconst emacs-everywhere-osascript-accessibility-error-message
  "osascript is not allowed assistive access"
  "String to search for to determine if Emacs does not have accessibility rights.")

(defvar-local emacs-everywhere-current-app nil
  "The current `emacs-everywhere-app'.")
;; Prevents buffer-local variable from being unset by major mode changes
(put 'emacs-everywhere-current-app 'permanent-local t)

(defvar-local emacs-everywhere--contents nil)

;; Make the byte-compiler happier

(declare-function org-in-src-block-p "org")
(declare-function org-ctrl-c-ctrl-c "org")
(declare-function org-export-to-buffer "ox")
(declare-function evil-insert-state "evil-states")
(declare-function spell-fu-buffer "spell-fu")
(declare-function markdown-mode "markdown-mode")

;;; Primary functionality

;;;###autoload
(defun emacs-everywhere (&optional file line column)
  "Launch the emacs-everywhere frame from emacsclient.
This may open FILE at a particular LINE and COLUMN, if specified."
  (let* ((app-info (emacs-everywhere-app-info))
         (param (emacs-everywhere-command-param app-info file line column)))
    (apply #'call-process "emacsclient" nil 0 nil param)))

(defun emacs-everywhere-command-param (app-info &optional file line column)
  "Generate arguments for calling emacsclient.
The arguments are based on a particular APP-INFO. Optionally, a FILE can be
specified, and also a particular LINE and COLUMN."
  (delq
   nil (list
        (when (and (server-running-p) server-use-tcp)
          (concat "--server-file="
                  (shell-quote-argument
                   (expand-file-name server-name server-auth-dir))))
        (when (and (server-running-p) (not server-use-tcp))
          (concat "--socket-name="
                  (shell-quote-argument
                   (expand-file-name server-name server-socket-dir))))
        "-c" "-F"
        (prin1-to-string
         (cons (cons 'emacs-everywhere-app app-info)
               emacs-everywhere-frame-parameters))
        (cond ((and line column) (format "+%d:%d" line column))
              (line              (format "+%d" line)))
        (or file
            (expand-file-name
             (funcall emacs-everywhere-filename-function app-info)
             emacs-everywhere-file-dir)))))

(defun emacs-everywhere-file-p (file)
  "Return non-nil if FILE should be handled by emacs-everywhere.
This matches FILE against `emacs-everywhere-file-patterns'."
  (let ((file (file-truename file)))
    (cl-some (lambda (pattern) (string-match-p pattern file))
             emacs-everywhere-file-patterns)))

;;;###autoload
(defun emacs-everywhere-initialise ()
  "Entry point for the executable.
APP is an `emacs-everywhere-app' struct."
  (let ((file (buffer-file-name (buffer-base-buffer))))
    (when (and file (emacs-everywhere-file-p file))
      (let ((app (or (frame-parameter nil 'emacs-everywhere-app)
                     (emacs-everywhere-app-info))))
        (setq-local emacs-everywhere-current-app app)
        (with-demoted-errors "Emacs Everywhere: error running init hooks, %s"
          (run-hooks 'emacs-everywhere-init-hooks))
        (emacs-everywhere-mode 1)
        (setq emacs-everywhere--contents (buffer-string))))))

;;;###autoload
(add-hook 'server-visit-hook #'emacs-everywhere-initialise)
(add-hook 'server-done-hook #'emacs-everywhere-finish)

(defvar emacs-everywhere--initial-mode-map
  (let ((keymap (make-sparse-keymap)))
    (define-key keymap (kbd "DEL") #'emacs-everywhere--erase-buffer)
    (define-key keymap (kbd "C-SPC") #'emacs-everywhere--erase-buffer)
    keymap)
  "Transient keymap invoked when an emacs-everywhere buffer is first created.
Set to nil to prevent this transient map from activating in emacs-everywhere
buffers.")

(define-minor-mode emacs-everywhere-mode
  "Tweak the current buffer to add some emacs-everywhere considerations."
  :init-value nil
  :lighter " EE"
  :keymap `((,(kbd "C-c C-c") . emacs-everywhere--finish-or-ctrl-c-ctrl-c)
            (,(kbd "C-x 5 0") . emacs-everywhere-finish)
            (,(kbd "C-c C-k") . emacs-everywhere-abort))
  (when emacs-everywhere-mode
    ;; line breaking
    (turn-off-auto-fill)
    (visual-line-mode t)
    ;; DEL/C-SPC to clear (first keystroke only)
    (when (keymapp emacs-everywhere--initial-mode-map)
      (set-transient-map emacs-everywhere--initial-mode-map))
    ;; Header line
    (when emacs-everywhere-top-padding
      (setq-local header-line-format "")
      (face-remap-set-base
       'header-line (list :height emacs-everywhere-top-padding)))
    ;; Replace "When done with a buffer type 'C-x #'" message
    (run-at-time
     nil nil
     (lambda ()
       (message "When done with this buffer type %s (or %s to abort)"
                (propertize "C-c C-c" 'face 'help-key-binding)
                (propertize "C-c C-k" 'face 'help-key-binding))))))

(defun emacs-everywhere-apply-major-mode ()
  "Call `emacs-everywhere-major-mode-function'."
  (funcall emacs-everywhere-major-mode-function))

(defun emacs-everywhere--erase-buffer ()
  "Delete the contents of the current buffer."
  (interactive)
  (delete-region (point-min) (point-max)))

(defun emacs-everywhere--finish-or-ctrl-c-ctrl-c ()
  "Finish emacs-everywhere session or invoke `org-ctrl-c-ctrl-c' in `org-mode'."
  (interactive)
  (if (and (eq major-mode 'org-mode)
           (org-in-src-block-p))
      (org-ctrl-c-ctrl-c)
    (emacs-everywhere-finish)))

(defun emacs-everywhere-finish (&optional abort)
  "Copy buffer content, close emacs-everywhere window, and maybe paste.
Must only be called within a emacs-everywhere buffer.
Never paste content when ABORT is non-nil."
  (interactive)
  (when emacs-everywhere-mode
    (when (equal emacs-everywhere--contents (buffer-string))
      (setq abort t))
    (unless abort
      (run-hooks 'emacs-everywhere-final-hooks)
      ;; First ensure text is in kill-ring and system clipboard
      (let ((text (buffer-string)))
        (kill-new text)
        ;; Use macOS specific clipboard command
        (when (eq system-type 'darwin)
          (call-process "osascript" nil nil nil
                       "-e" (format "set the clipboard to %S" text)))
        ;; Also try GUI selection methods
        (gui-select-text text)
        (gui-backend-set-selection 'PRIMARY text))
      ;; Extra clipboard handling if needed
      (when emacs-everywhere-copy-command ; handle clipboard finicklyness
        (let ((inhibit-message t)
              (require-final-newline nil)
              write-file-functions)
          ;; Add this to your config to exclude tempf file from recent files
          ;; (with-eval-after-load 'recentf
          ;;   (dolist (pattern emacs-everywhere-file-patterns)
          ;;     (add-to-list 'recentf-exclude pattern)))
          (with-file-modes #o600
            (write-file buffer-file-name))
          (apply #'call-process (car emacs-everywhere-copy-command)
                 nil nil nil
                 (mapcar (lambda (arg)
                           (replace-regexp-in-string "%f" buffer-file-name arg))
                         (cdr emacs-everywhere-copy-command))))))
    (sleep-for emacs-everywhere-clipboard-sleep-delay) ; prevents weird multi-second pause, lets clipboard info propagate
    (when emacs-everywhere-window-focus-command
      (let ((window-id (emacs-everywhere-app-id emacs-everywhere-current-app)))
        (apply #'call-process (car emacs-everywhere-window-focus-command)
               nil nil nil
               (mapcar (lambda (arg)
                         (replace-regexp-in-string "%w" window-id arg))
                       (cdr emacs-everywhere-window-focus-command)))
        ;; The frame only has this parameter if this package initialized the temp
        ;; file its displaying. Otherwise, it was created by another program, likely
        ;; a browser with direct EDITOR support, like qutebrowser.
        (when (and (frame-parameter nil 'emacs-everywhere-app)
                   emacs-everywhere-paste-command
                   (not abort))
          ;; Add small delay before paste
          (sleep-for emacs-everywhere-clipboard-sleep-delay)
          (apply #'call-process (car emacs-everywhere-paste-command)
                 nil nil nil
                 (cdr emacs-everywhere-paste-command)))))
    ;; Clean up after ourselves in case the buffer survives `server-buffer-done'
    (set-buffer-modified-p nil)
    (let ((kill-buffer-query-functions nil))
      (emacs-everywhere-mode -1)
      (server-buffer-done (current-buffer)))))

(defun emacs-everywhere-abort ()
  "Abort current emacs-everywhere session."
  (interactive)
  (set-buffer-modified-p nil)
  (emacs-everywhere-finish t))

;;; Window info

(cl-defstruct emacs-everywhere-app
  "Metadata about the last focused window before emacs-everywhere was invoked."
  id class title geometry)

(defun emacs-everywhere-app-info ()
  "Return information on the active window.
This runs `emacs-everywhere-app-info-function' and lightly reformats the app title."
  (if (functionp emacs-everywhere-app-info-function)
      (let ((w (funcall emacs-everywhere-app-info-function)))
        (setf (emacs-everywhere-app-title w)
              (replace-regexp-in-string
               (format " ?-[A-Za-z0-9 ]*%s"
                       (regexp-quote (emacs-everywhere-app-class w)))
               ""
               (replace-regexp-in-string
                "[^[:ascii:]]+" "-" (emacs-everywhere-app-title w))))
        w)
    (user-error "No app-info function is set, see `emacs-everywhere-app-info-function'")))

(defun emacs-everywhere--call (command &rest args)
  "Execute COMMAND with ARGS synchronously."
  (with-temp-buffer
    (apply #'call-process command nil t nil (remq nil args))
    (when (and (eq system-type 'darwin)
               (string-match-p emacs-everywhere-osascript-accessibility-error-message (buffer-string)))
      (call-process "osascript" nil nil nil
                    "-e" (format "display alert \"emacs-everywhere\" message \"Emacs has not been granted accessibility permissions, cannot run emacs-everywhere!
Please go to 'System Preferences > Security & Privacy > Privacy > Accessibility' and allow Emacs.\"" ))
      (error "MacOS accessibility error, aborting"))
    (string-trim (buffer-string))))





(defvar emacs-everywhere--dir (file-name-directory load-file-name))

(defun emacs-everywhere--app-info-osx ()
  "Return information on the active window, on osx."
  (emacs-everywhere--ensure-oscascript-compiled)
  (let ((default-directory emacs-everywhere--dir))
    (let ((app-name (emacs-everywhere--call
                     "osascript" "app-name"))
          (app-bundle-id (emacs-everywhere--call
                          "osascript" "app-bundle-id"))
          (window-title (emacs-everywhere--call
                         "osascript" "window-title"))
          (window-geometry (mapcar #'string-to-number
                                   (split-string
                                    (emacs-everywhere--call
                                     "osascript" "window-geometry") ", "))))
      (make-emacs-everywhere-app
       :id app-bundle-id
       :class app-name
       :title window-title
       :geometry window-geometry))))

(defun emacs-everywhere--ensure-oscascript-compiled (&optional force)
  "Ensure that compiled oscascript files are present.
Will always compile when FORCE is non-nil."
  (unless (and (file-exists-p "app-name")
               (file-exists-p "app-bundle-id")
               (file-exists-p "window-geometry")
               (file-exists-p "window-title")
               (not force))
    (let ((default-directory emacs-everywhere--dir)
          (app-name
           "tell application \"System Events\"
    set frontAppName to name of first application process whose frontmost is true
end tell
return frontAppName")
          (app-bundle-id
           "tell application \"System Events\"\n    set frontAppBundleId to bundle identifier of first application process whose frontmost is true\nend tell\nreturn frontAppBundleId")

          (window-geometry
           "tell application \"System Events\"
     set frontWindow to front window of (first application process whose frontmost is true)
     set windowPosition to (get position of frontWindow)
     set windowSize to (get size of frontWindow)
end tell
return windowPosition & windowSize")
          (window-title
           "set windowTitle to \"\"
tell application \"System Events\"
     set frontAppProcess to first application process whose frontmost is true
end tell
tell frontAppProcess
    if count of windows > 0 then
        set windowTitle to name of front window
    end if
end tell
return windowTitle"))
      (dolist (script `(("app-name" . ,app-name)
                        ("app-bundle-id" . ,app-bundle-id)
                        ("window-geometry" . ,window-geometry)
                        ("window-title" . ,window-title)))
        (write-region (cdr script) nil (concat (car script) ".applescript"))
        (shell-command (format "osacompile -r scpt:128 -t osas -o %s %s"
                               (car script) (concat (car script) ".applescript")))))))


;;; Secondary functionality

(defun emacs-everywhere-set-frame-name ()
  "Set the frame name based on `emacs-everywhere-frame-name-format'."
  (set-frame-name
   (format emacs-everywhere-frame-name-format
           (emacs-everywhere-app-class emacs-everywhere-current-app)
           (truncate-string-to-width
            (emacs-everywhere-app-title emacs-everywhere-current-app)
            45 nil nil "…"))))

(defun emacs-everywhere-remove-trailing-whitespace ()
  "Move point to the end of the buffer, and remove all trailing whitespace."
  (goto-char (max-char))
  (delete-trailing-whitespace)
  (delete-char (- (skip-chars-backward "\n"))))

(defun emacs-everywhere-set-frame-position ()
  "Set the size and position of the emacs-everywhere frame."
  (cl-destructuring-bind (x . y) (mouse-absolute-pixel-position)
    (set-frame-position (selected-frame)
                        (- x 100)
                        (- y 50))))


(defun emacs-everywhere-insert-selection ()
  "Insert the last text selection into the buffer."
  (pcase system-type
    ('darwin (progn
               ;; Try to get selected text directly via AppleScript
               (let ((selection
                      (with-temp-buffer
                        (call-process "osascript" nil t nil
                                    "-e" "tell application \"System Events\"
                                           set frontApp to first application process whose frontmost is true
                                           set frontAppBundleId to bundle identifier of frontApp
                                         end tell
                                         set theSelection to \"\"
                                         tell application id frontAppBundleId
                                           try
                                             set theSelection to selection
                                             if theSelection is not \"\" then
                                               return theSelection
                                             end if
                                           end try
                                         end tell")
                        (buffer-string))))
                 ;; If direct selection fails, fall back to clipboard
                 (if (and selection (not (string-empty-p selection)))
                     (insert selection)
                   (progn
                     (call-process "osascript" nil nil nil
                                  "-e" "tell application \"System Events\" to keystroke \"c\" using command down")
                     (sleep-for emacs-everywhere-clipboard-sleep-delay)
                     (yank))))))
    )
  (when (and (eq major-mode 'org-mode)
             (emacs-everywhere-markdown-p)
             (executable-find "pandoc"))
    (apply #'call-process-region
           (point-min) (point-max) "pandoc"
           t t t
           emacs-everywhere-pandoc-md-args)
    (deactivate-mark) (goto-char (point-max)))
  (cond ((bound-and-true-p evil-local-mode) (evil-insert-state))))

;; macOS-only override of insert-selection to remove non-macOS code paths
(defun emacs-everywhere-insert-selection ()
  "Insert the last text selection into the buffer (macOS only)."
  ;; Try to get selected text directly via AppleScript
  (let ((selection
         (with-temp-buffer
           (call-process "osascript" nil t nil
                         "-e" "tell application \"System Events\"\n                                set frontApp to first application process whose frontmost is true\n                                set frontAppBundleId to bundle identifier of frontApp\n                              end tell\n                              set theSelection to \"\"\n                              tell application id frontAppBundleId\n                                try\n                                  set theSelection to selection\n                                  if theSelection is not \"\" then\n                                    return theSelection\n                                  end if\n                                end try\n                              end tell")
           (buffer-string))))
    ;; If direct selection fails, fall back to clipboard (Cmd+C then yank)
    (if (and selection (not (string-empty-p selection)))
        (insert selection)
      (progn
        (call-process "osascript" nil nil nil
                      "-e" "tell application \"System Events\" to keystroke \"c\" using command down")
        (sleep-for emacs-everywhere-clipboard-sleep-delay)
        (yank))))
  (when (and (eq major-mode 'org-mode)
             (emacs-everywhere-markdown-p)
             (executable-find "pandoc"))
    (apply #'call-process-region
           (point-min) (point-max) "pandoc"
           t t t
           emacs-everywhere-pandoc-md-args)
    (deactivate-mark) (goto-char (point-max)))
  (cond ((bound-and-true-p evil-local-mode) (evil-insert-state))))

(defun emacs-everywhere-init-spell-check ()
  "Run a spell check function on the buffer, using a relevant enabled mode."
  (cond ((bound-and-true-p spell-fu-mode) (spell-fu-buffer))
        ((bound-and-true-p flyspell-mode) (flyspell-buffer))))

(defun emacs-everywhere-markdown-p ()
  "Return t if the original window is recognised as markdown-flavoured."
  (let ((title (emacs-everywhere-app-title emacs-everywhere-current-app))
        (class (emacs-everywhere-app-class emacs-everywhere-current-app)))
    (or (cl-some (lambda (pattern)
                   (string-match-p pattern title))
                 emacs-everywhere-markdown-windows)
        (cl-some (lambda (pattern)
                   (string-match-p pattern class))
                 emacs-everywhere-markdown-apps))))

(defun emacs-everywhere-major-mode-org-or-markdown ()
  "Use markdow-mode, when window is recognised as markdown-flavoured.
Otherwise use `org-mode'."
  (if (emacs-everywhere-markdown-p)
      (markdown-mode)
    (org-mode)))

(defcustom emacs-everywhere-org-export-options
  "#+property: header-args :exports both
#+options: toc:nil\n"
  "A string inserted at the top of the Org buffer prior to export.
This is with the purpose of setting #+property and #+options parameters.

Should end in a newline to avoid interfering with the buffer content."
  :type 'string
  :group 'emacs-everywhere)

(defvar org-export-show-temporary-export-buffer)
(defun emacs-everywhere-convert-org-to-gfm ()
  "When appropriate, convert org buffer to markdown."
  (when (and (eq major-mode 'org-mode)
             (emacs-everywhere-markdown-p))
    (goto-char (point-min))
    (insert emacs-everywhere-org-export-options)
    (let (org-export-show-temporary-export-buffer)
      (require 'ox-md)
      (org-export-to-buffer (if (featurep 'ox-gfm) 'gfm 'md) (current-buffer)))))

(defun emacs-everywhere--required-executables ()
  "Return a list of cons cells, each giving a required executable and its purpose."
  (let* ((feat-cmds
          (list (cons "paste" emacs-everywhere-paste-command)
                (cons "copy" emacs-everywhere-copy-command)
                (cons "focus window" emacs-everywhere-window-focus-command)
                (list "pandoc conversion" "pandoc")))
         executable-list)
    (dolist (feat-cmd (delq nil feat-cmds))
      (when (cdr feat-cmd)
        (when (and (equal (cadr feat-cmd) "sh")
                   (equal (caddr feat-cmd) "-c"))
          (setcdr feat-cmd (split-string (cadddr feat-cmd))))
        (push (cons (cadr feat-cmd) (car feat-cmd))
              executable-list)))
    executable-list))

(defun emacs-everywhere-check-health ()
  "Check whether emacs-everywhere has everything it needs."
  (interactive)
  (switch-to-buffer
   (get-buffer-create "*Emacs Everywhere health check*"))
  (read-only-mode 1)
  (with-silent-modifications
    (erase-buffer)
    (let ((required-cmds
           (emacs-everywhere--required-executables)))
      (insert (propertize "Emacs Everywhere system health check\n" 'face 'outline-1)
              "operating system: " (propertize (symbol-name system-type) 'face 'font-lock-type-face)
              "\n")
      (dolist (req-cmd required-cmds)
        (if (not (cdr req-cmd))
            (insert
             (propertize (format "• %s (unavailible)\n" (cdr req-cmd)) 'face 'font-lock-comment-face))
          (insert
           (propertize (format "• %s " (cdr req-cmd))
                       'face `(:inherit outline-4 :height ,(face-attribute 'default :height)))
           "requires "
           (propertize (car req-cmd) 'face 'font-lock-constant-face)
           (if (executable-find (car req-cmd))
               (propertize " ✓ installed" 'face 'success)
             (propertize " ✗ missing" 'face 'error))
           "\n"))))))

(provide 'emacs-everywhere)
;;; emacs-everywhere.el ends here