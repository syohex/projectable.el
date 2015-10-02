;;; projectable.el --- Lightweight project cacheing and navigation framework -*- lexical-binding: t -*-

;; Copyright © 2015  Dominic Charlesworth <dgc336@gmail.com>

;; Author: Dominic Charlesworth <dgc336@gmail.com>
;; URL: https://github.com/domtronn/projectable
;; Version: 1.0.0
;; Package-Version: 20150724-1604
;; Keywords: project, convenience
;; Package-Requires: ((dash "2.11.0"))

;; This file is NOT part of GNU Emacs.

;; This program is free software; you can redistribute it and/or
;; modify it under the terms of the GNU General Public License
;; as published by the Free Software Foundation; either version 3
;; of the License, or (at your option) any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this program. If not, see <http://www.gnu.org/licenses/>.

;;; Commentary:

;; This package creates an associative list of files
;; based on project keys for easier navigation.

;; Packages are defined by json files which can be loaded in.

;; This is perhaps not the best data strucutre for projects but
;; works well for require.js with name setups

;;; Code:

(require 'json)
(require 'ido)
(require 'dash)

(defconst projectable-dir (file-name-directory load-file-name))

;;; Group Definitions
(defgroup projectable nil
  "Manage how to read and create project caches."
  :group 'tools
  :group 'convenience)

(defcustom projectable-project-directory (expand-file-name "~/Documents/Projects")
  "The directory where project json files are kept.

By default it looks in the ~/Documents/Projects folder"
  :group 'projectable
  :type 'string)

(defcustom projectable-keymap-prefix (kbd "C-c p")
  "Projectable keymap prefix."
  :group 'projectable
  :type 'key-sequence)

(defcustom projectable-use-gitignore t
  "Whether to use gitignore for your regexp filters."
  :group 'projectable
  :type 'boolean)

(defcustom projectable-constrain-reformat t
  "Whether to constraint `projectable-reformat-file` to project files.

If nil, you can call `projectable-reformat-file` on any file which will
reformat that file to use the projects format settings."
  :group 'projectable
  :type 'boolean)

;;; Customisation Option Definitions
(defcustom projectable-alist-cmd (concat projectable-dir "create-file-alist.py")
  "Specify the command that to produce an associative list.

The SHELL-COMMAND, when run with a directory and a list of filter regexps,
should return an associative list in the following form as json for now.

\((file1 (dir1 dir2 dir3)) (file2 (dir1 dir2)))

By default, it uses the python script provided with this package."
  :group 'projectable
  :type 'string)

(defvar projectable-find-cmd-format
  "find %s -type f | grep -E \"%s\" | grep -vE \"%s\" | xargs %s"
  "Command format of find command used to pass to tags cmd.

The formats should be replaced, in order, by
- directory
- string of regexp language extensions e.g.  \\.cpp
  see `projectable-ctags-supported-languages`
  and `projectable-get-ctags-supported-languages`
- string of regexp filters
  see `projectable-filter-regexps`
  and `projectable-get-filter-regexps`")

(defcustom projectable-auto-visit-tags t
  "Whether to visit the tags file upon creation of a tags file."
  :group 'projectable
  :type 'boolean)
(defcustom projectable-tags-file ".tags"
  "The name of the tags file to create."
  :group 'projectable
  :type 'string)
(defcustom projectable-ctags-cmd-format
  (format "ctags -f %s/%s -e" "%s" projectable-tags-file)
  "Specify the ctags command to pipe a list of files into.

-e is required to create an Emacs style tags file."
  :group 'projectable
  :type 'string)
(defcustom projectable-ctags-supported-languages
  '((asp . ("\\.asp$"))
    (c .  ("\\.c$"))
    (c++ . ("\\.cpp$" "\\.cc$" "\\.c\\+\\+"))
    (cs . ("\\.cs$"))
    (cobol . ("\\.cbl$" "\\.cob$" "\\.cpy$"))
    (erlang . ("\\.erl$" "\\.hrl$"))
    (fortran . ("\\.f$" "\\.for$" "\\.f90" "\\.f95"))
    (html . ("\\.html$" "\\.htm$"))
    (java . ("\\.java$" "\\.class$"))
    (javascript .  ("\\.js$"))
    (lisp . ("\\.lisp$" "\\.lsp$" "\\.l$" "\\.cl$"))
    (lua .  ("\\.lua$"))
    (matlab . ("\\.m$"))
    (perl . ("\\.pl$" "\\.pm$"))
    (php . ("\\.php$" "\\.php[3-5]$" "\\.phps$"))
    (python . ("\\.py$" "\\.pyc$" "\\.pyd$" "\\.pyo$" "\\.pyw$"))
    (ruby . ("\\.rb$"))
    (coffeescript . ("\\.coffee$")))
  "Select the languages you want to create ctags from."
  :group 'projectable
  :type '(alist :key-type symbol :value-type
                (repeat :tag "Regexp Extensions" regexp)))

(defcustom projectable-filter-tests t
  "Whether to filter out test files.

If t then the `projectable-file-alist` will not contain test files that
match `projectable-test-filter-regexp`, so that you only open directly
to source files.  If nil then `projectable-file-alist` will contain all
files."
  :group 'projectable
  :type 'booelan)
(defcustom projectable-test-filter-regexps
  (quote ("Test\\.[[:alpha:]]+$" "Spec\\.[[:alpha:]]+$"))
  "Specify a list of regexps to filter out test files."
  :group 'projectable
  :type '(repeat regexp))

(defcustom projectable-filter-regexps
  (quote
   ("~$" "\\.o$" "\\.exe$" "\\.a$" "/\\.svn" "\\.elc$" "\\.output$" "\\.$" "#$" "\\.class$"
    "\\.png$" "\\.svn*" "\\/node_modules\\/*" "\\.gif$" "\\.gem$"
    "\\.pdf$" "\\.swp$" "\\.iml$" "\\.jar$" "\\/build\\/" "/\\.git"
    "\\/jsdoc\\/" "\\.min\\.js$" "\\.tags$" "\\.filecache"
    "\\.cache$" "\\/.git\\/" "report" "\\.gcov\\.html$" "\\.func.*\\.html$"))
  "Specify a list of regexps to filter."
  :group 'projectable
  :type '(repeat regexp))

(defcustom projectable-verbose nil
  "Toggle verbose printing.
Mainly for debugging of the package."
  :group 'projectable
  :type 'boolean)



;;; Variable Definitions
(defvar projectable-current-project-path nil)
(defvar projectable-project-alist nil)
(defvar projectable-project-hash nil)
(defvar projectable-file-alist nil)
(defvar projectable-test-alist nil)
(defvar projectable-id)

(defvar projectable-indent-level
  2 "The level of indentation to be used.")
(defvar projectable-indent-object
  (list :tabs "	" "  ") "Definiton of indentation type with the indent character.")

(defvar projectable-test-path
  nil "The root of test files for the project.")
(defvar projectable-src-path
  nil "The src path for tests.")
(defvar projectable-test-extension
  nil "The extension of the test file e.g. ...Test.")

(defvar projectable-use-vertical-flx nil)

;;; Function Definitions
(defun projectable-change (arg)
  "Change project path to ARG and refresh the cache."
  (interactive (progn
                 (when projectable-use-vertical-flx
                   (projectable-enable-vertical))
                 (list (ido-read-file-name "Enter path to Project file: "
                                           projectable-project-directory))))
  ;; Set the current project path to new directory
  (setq projectable-current-project-path arg)
  ;; Reset project specific variables
  (setq tags-table-list nil)
  (setq projectable-src-path nil)
  (setq projectable-test-path nil)
  (setq projectable-test-extension nil)
  (setq projectable-project-alist (make-hash-table :test 'equal))
  (setq projectable-file-alist (make-hash-table :test 'equal))

  (projectable-refresh)
  (when projectable-use-vertical-flx (projectable-disable-vertical)))

(defun projectable-refresh ()
  "Parse a json project file to create a cache for that project.

If the supplied file is not a file but a directory, it just adds
this directory to the file cache"
  (interactive)
  (when projectable-current-project-path
    (if (not (file-directory-p projectable-current-project-path))
        ;; Json file so load from json
        (progn (projectable-load-from-json)
               (projectable-message (format "New project is [%s]" projectable-current-project-path) t))
      ;; A directory so load form directory
      (progn
        (projectable-message
         (format "Interpreting as directory - [%s] is not a file" projectable-current-project-path))
        (projectable-load-from-path)))))

(defun projectable-load-from-json ()
  "Set the project based on a path.
This will just cache all of the files contained in that directory."
  (let* ((json-object-type 'hash-table)
         (json-contents (with-temp-buffer
                          (insert-file-contents projectable-current-project-path)
                          (buffer-string)))
         (json-hash (json-read-from-string json-contents)))

    (setq projectable-project-hash json-hash)

    ;; Set project ID
    (let ((id (gethash "id" json-hash)))
      (setq projectable-id id)
      (projectable-message (format "Project ID: [%s]" id)))

    ;; Create tags
    (projectable-create-tags
     (list (gethash "dirs" json-hash) (when (gethash "libs" json-hash) (gethash "libs" json-hash))))

    (when (gethash "style" json-hash)
      (projectable-set-styling (gethash "style" json-hash)))

    (when (gethash "testing" json-hash)
      (projectable-set-testing (gethash "testing" json-hash)))
    
    (let* ((gitignore-from-hash (gethash "gitignore" json-hash))
           (use-gitignore (if gitignore-from-hash
                              (not (eq :json-false gitignore-from-hash))
                            projectable-use-gitignore)))
      (projectable-set-project-alist
       (when (and use-gitignore projectable-use-gitignore)
         (projectable-get-all-gitignore-filter (gethash "dirs" json-hash))))))
  t)

(defun projectable-get-all-gitignore-filter (project-list)
  "Get a distinct list of regexps to gitignore in the PROJECT-LIST files."
  (let ((gitignore-filter-regexp (list)))
    (mapc (lambda (x)
            (let ((location (locate-dominating-file (concat (gethash "dir" x) "/") ".gitignore")))
              (when location
                (setq gitignore-filter-regexp
                      (-distinct
                       (append gitignore-filter-regexp (projectable-get-gitignore-filter location)))))))
          project-list)
    gitignore-filter-regexp))

(defun projectable-create-tags (hash-list)
  "Create tags in the root projects based on a HASH-LIST of directories and flags."
  (mapc (lambda (hash)
          (mapc (lambda (elt)
                  (let* ((dir (concat (gethash "dir" elt) "/"))
                         (create-tags-p (not (eq :json-false (gethash "create-tags" elt)))))
                    (when create-tags-p
                      (projectable-message (format "Creating tags for [%s]" dir))
                      (projectable-create-tags-in-directory dir)
                      (when projectable-auto-visit-tags
                        (let ((tags-file (format "%s%s" (file-truename dir) projectable-tags-file)))
                          (when (not (member tags-file tags-table-list))
                            (setq tags-table-list (append tags-table-list (list tags-file)))))
                        )))
                  ) hash)) hash-list))

(defun projectable-create-tags-in-directory (dir)
  "Build and run the create tags command in DIR."
  (let* ((cmd
          (shell-quote-argument
           (format projectable-find-cmd-format
                  dir
                  (projectable-get-ctags-supported-languages)
                  (projectable-get-filter-regexps)
                  (format projectable-ctags-cmd-format dir))))
         (name (format "[projectable] Creating tags for [%s]" dir))
         (buffer-name (format "*create-tags*<%s>" dir)))
    (projectable-message cmd)
    (start-process-shell-command name buffer-name cmd)))

(defun projectable-set-styling (style-hash)
  "Set up variables associated with the styling from a STYLE-HASH."
  ;; Set the indent level
  (when (gethash "indent" style-hash)
    (projectable-set-indent-level (gethash "indent" style-hash)))
  ;; Set the tabs/spaces indent type
  (when (gethash "tabs" style-hash)
    (projectable-set-indent-object (eq :json-false (gethash "tabs" style-hash)))))

(defun projectable-set-testing (test-hash)
  "Set up variables associated with testing from a TEST-HASH."
  (when (gethash "sourcePath" test-hash)
    (setq projectable-src-path (gethash "sourcePath" test-hash)))
  (setq projectable-test-path (gethash "path" test-hash))
  (setq projectable-test-extension (gethash "extension" test-hash)))

(defun projectable-load-from-path ()
  "Load a project from a given directory."
  ;; Remove trailing slash on directory variable if it exists
  (setq projectable-current-project-path
        (with-temp-buffer
          (insert projectable-current-project-path)
          (goto-char (point-min))
          (while (re-search-forward "/$" nil t)
            (replace-match ""))
          (buffer-string)))

  ;; Set project ID
  (let ((id (file-name-nondirectory projectable-current-project-path)))
    (setq projectable-id id)
    (projectable-message (format "Project ID: [%s]" id)))

  (let ((gitignore-filter-regexps (projectable-get-gitignore-filter
                                   (locate-dominating-file (concat projectable-current-project-path "/") ".gitignore"))))
    (projectable-set-project-alist (when projectable-use-gitignore gitignore-filter-regexps)))
  t)

(defun projectable-set-project-alist (&optional gitignore-filter-regexps)
  "Set `projectable-project-alist` by usings `projectable-alist-cmd`.

Can be passed a list GITIGNORE-FILTER-REGEXPS of regexps to append to
the filter string set in the customisations."
  (let* ((json-object-type 'alist) (json-array-type 'list) (json-key-type 'string)
         (cmd (concat
               projectable-alist-cmd
               " "
               (expand-file-name projectable-current-project-path)
               " \""
               (mapconcat 'identity (append projectable-filter-regexps gitignore-filter-regexps) ",")
               " \""))
         (result (json-read-from-string (shell-command-to-string cmd))))
		(projectable-message cmd)
    (setq projectable-project-alist result)
    (setq projectable-file-alist (cdr (assoc projectable-id result)))
    t))

(defun projectable-get-gitignore-filter (gitignore-dir)
  "Produce regexps filters by based on a .gitignore files found in GITIGNORE-DIR."
  (with-temp-buffer
    (insert-file-contents (concat gitignore-dir ".gitignore"))
    (goto-char (point-min))
    (flush-lines "^[#]")
    (flush-lines "^$")
    (while (search-forward "*" nil t)
      (replace-match ""))
    (goto-char (point-min))
    (while (search-forward "." nil t)
      (replace-match "\\." nil t))
    (split-string (buffer-string) "\n" t)))

(defun projectable-set-indent-object (bool)
  "Set the indent type based on BOOL.
t => spaces nil => tabs"
  (if bool
      (progn
        (projectable-message (format "Using spaces for project [%s]" projectable-id))
        (setq projectable-indent-object (list :spaces (projectable-build-space-string) "	"))
        (setq-default indent-tabs-mode nil))
    (progn
      (projectable-message (format "Using tabs for project [%s]" projectable-id))
      (setq projectable-indent-object (list :tabs "	" (projectable-build-space-string)))
      (setq-default indent-tabs-mode t)))
   t)

(defun projectable-set-indent-level (level)
  "Set the indent level based on LEVEL."
  (setq projectable-indent-level level)
  (setq-default c-basic-offset level)
  (setq-default css-indent-offset level)
  (setq-default js-indent-level level)
  (setq-default basic-offset level)
  (setq tab-width level)
  (projectable-message (format "Setting indent level to %s" level))
  t)

(eval-after-load "js2-mode"
  (setq-default js2-basic-offset projectable-indent-level))
(eval-after-load "web-mode"
  (progn (setq-default web-mode-markup-indent-offset projectable-indent-level)
         (setq-default web-mode-css-indent-offset projectable-indent-level)
         (setq-default web-mode-code-indent-offset projectable-indent-level)))

;; Utility functions
(defun projectable-message (string &optional override)
  "Prints debug message STRING for the package.
If called with boolean OVERRIDE, this will override the verbose setting."
  (when (or projectable-verbose override)
    (message (format "[projectable] %s" string))))

(defun projectable-enable-vertical ()
  "Enable vertical selection with flx matching."
  (setq flx-ido-use-faces t)
  (setq ido-use-faces nil)
  (flx-ido-mode 1)
  (ido-vertical-mode 1))

(defun projectable-disable-vertical ()
  "Disable vertical selection and flx matching."
  (setq flx-ido-use-faces nil)
  (setq ido-use-faces t)
  (flx-ido-mode 0)
  (ido-vertical-mode 0))

;;; Utility Functions
;;  A bunch of functions to help with project navigation and set up.

(defun projectable--switch-buffer (f)
  "Call F as the mechanism for switch to buffer branching."
	(let ((project-buffers (-map #'buffer-name (projectable-get-project-buffers))))
		(funcall f (completing-read
                (format "[%s] Switch to buffer: " projectable-id)
                project-buffers))))

(defun projectable-switch-buffer ()
	"Using `completing-read`, interactively switch buffers contained within the project."
  (interactive)
  (projectable--switch-buffer 'switch-to-buffer))


(defun projectable-switch-buffer-other-window ()
	"Using `completing-read`, interactively switch buffers in other window for project buffers."
  (interactive)
	(projectable--switch-buffer 'switch-to-buffer-other-window))


(defun projectable-find-file (file)
  "Call `projectable--find-file` for FILE with `find-file` as function call."
  (interactive (progn
                 (when projectable-use-vertical-flx
                   (projectable-enable-vertical))
                 (list (completing-read
                        "File: " (mapcar (lambda (x) (car x))
                                         projectable-file-alist)))))
  (projectable--find-file file 'find-file))

(defun projectable-find-file-other-window (file)
  "Call `projectable--find-file` for FILE with `find-file` as function call."
  (interactive (progn
                 (when projectable-use-vertical-flx
                   (projectable-enable-vertical))
                 (list (completing-read
                        "File: " (mapcar (lambda (x) (car x))
                                         projectable-file-alist)))))
  (projectable--find-file file 'find-file-other-window))

(defun projectable--find-file (file f)
  "Using `completing-read`, interactively open FILE using F from project.
Select a file matched using `ido-switch-buffer` against the contents
of `projectable-file-alist`.  If the file exists in more than one
directory, select directory.  Lastly the file is opened.

This code snippet is borrowed and adapted from
http://emacswiki.org/emacs/FileNameCache"
  (let* ((record (assoc file projectable-file-alist)))
    (funcall f
     (expand-file-name
      file
      (if (= (length record) 2)
          (car (cdr record))
        (completing-read
         (format "Find %s in dir:" file) (cdr record)))))
    (when projectable-use-vertical-flx
      (projectable-disable-vertical))))

(defun projectable-toggle-open-test ()
  "Open associated test class if it exists."
  (interactive)
  (unless (and projectable-test-path projectable-test-extension)
    (error "[projectable] You do not have a testing path or extension set, try updating %s.json (C-c p p)" projectable-id))
  (let ((file-ext (file-name-extension (buffer-file-name)))
        (src-path projectable-src-path)
        (test-path projectable-test-path))
    (when (not projectable-src-path)
      (progn
        (setq src-path (projectable-guess-source-path))
        (setq test-path (format "%s/%s" src-path projectable-test-path))
        (if src-path (projectable-message (format  "Guessed the source path as [%s]" src-path)))))

    (if (and src-path (string-match test-path (file-truename (buffer-file-name))))
        ;; In a test class, go to source
        (find-file (replace-regexp-in-string
                    test-path src-path
                    (replace-regexp-in-string
                     (format "%s\\\.%s" projectable-test-extension file-ext)
                     (format "\.%s" file-ext) (buffer-file-name))))

      (if (and src-path (string-match src-path (file-truename (buffer-file-name))))
          ;; In a source class, go to test
          (find-file (replace-regexp-in-string
                      src-path test-path
                      (replace-regexp-in-string
                       (format "\\\.%s" file-ext)
                       (format "%s\.%s" projectable-test-extension file-ext) (buffer-file-name))))

        (projectable-message (format "Could not find test file for [%s]" buffer-file-name) t)))))

(defun projectable-guess-source-path ()
  "Guess what the source path for files is."
  (let ((result nil)
        (projects (gethash "dirs" projectable-project-hash)))
    (mapc #'(lambda (p) (let ((project-dir (expand-file-name (gethash "dir" p))))
                     (when (string-match project-dir (file-truename (buffer-file-name)))
                       (setq result project-dir)))) projects)
    result))

(defun projectable-reformat-file ()
  "Reformat tabs/spaces into correct format for current file."
  (interactive)
  (if (or (projectable-project-contains (buffer-file-name))
          (not  projectable-constrain-reformat))
      (save-excursion
        (indent-region (point-min) (point-max))
        (goto-char (point-min))
        (while (search-forward (caddr projectable-indent-object) (point-max) t)
          (replace-match (cadr projectable-indent-object)))
        (projectable-message
         (format "Reformatted file to use [%s]" (car projectable-indent-object)) t))
    (projectable-message
     (format "Reformat aborted - [%s] is not part of project" (file-name-nondirectory (buffer-file-name))) t)))

(defun projectable-build-space-string ()
  "Build the indent string of spaces.
i.e.  If indent level was 4, the indent string would be '    '."
  (make-string projectable-indent-level ? ))

(defun projectable-kill-project-buffers ()
  "Kill all open buffers in the current project."
  (interactive)
  (mapc (lambda (buf) (kill-buffer buf)) (projectable-get-project-buffers)))

(defun projectable-get-project-buffers ()
  "Get a list of buffers within the current project."
  (-filter (lambda (buffer) (let* ((bufname (buffer-file-name buffer)))
							 (and bufname (projectable-project-contains bufname)))) (buffer-list)))

(defun projectable-project-contains (file)
  "Check to see if project alist contain FILE."
	
  (let* ((result nil)
         (file-name (file-name-nondirectory file))
         (file-dir (file-name-directory file)))
    (mapc #'(lambda (alist)
              (when (and (assoc file-name (cdr alist)) (member file-dir (cdr (assoc file-name (cdr alist)))))
                (setq result t)))
          projectable-project-alist) result))

(defun projectable-visit-project-file ()
  "Open the project file currently being used."
  (interactive)
  (when projectable-current-project-path
    (if (not (file-directory-p projectable-current-project-path))
        (find-file projectable-current-project-path)
      (projectable-message
       (format "Current project is an anonymous path, not a project file [%s]" projectable-current-project-path) t))))

(defun projectable-get-ctags-supported-languages ()
  "Flatten and concatenate all supported languages for find command."
  (mapconcat #'(lambda (a) (format "%s" a))
             (-flatten (mapcar #'(lambda (a) (cdr a)) projectable-ctags-supported-languages)) "|"))

(defun projectable-get-filter-regexps ()
  "Flatten and concatenate all filter regexps for find command."
  (mapconcat #'(lambda (a) (format "%s" a)) projectable-filter-regexps "|"))

;;; Projectable Mode
;;  Set up for the projectable minor-mode.

(when (and (require 'flx-ido nil 'noerror)
           (require 'ido-vertical-mode nil 'noerror))

  (defcustom projectable-use-vertical-flx t
    "Whether to take advantange of FLX and VERTICAL features."
    :group 'projectable
    :type 'boolean)
  (setq projectable-use-vertical-flx t))

(defvar projectable-command-map
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "c") #'projectable-change)
    (define-key map (kbd "r") #'projectable-refresh)
    (define-key map (kbd "f") #'projectable-find-file)
    (define-key map (kbd "t") #'projectable-toggle-open-test)
    (define-key map (kbd "l") #'projectable-reformat-file)
    (define-key map (kbd "p") #'projectable-visit-project-file)
    map)
  "Keymap for Projectable commands after `projectable-keymap-prefix'.")
(fset 'projectable-command-map projectable-command-map)

(defvar projectable-mode-map
  (let ((map (make-sparse-keymap)))
    (define-key map projectable-keymap-prefix 'projectable-command-map)
    map)
  "Keymap for Projectile mode.")

;;;###autoload
(define-minor-mode projectable-mode
  "Minor mode to assist project management and navigation.

When called interactively, toggle `projectable-mode'.  With prefix
ARG, enable `projectable-mode' if ARG is positive, otherwise disable
it.

When called from Lisp, enable `projectable-mode' if ARG is omitted,
nil or positive.  If ARG is `toggle', toggle `projectable-mode'.
Otherwise behave as if called interactively.

\\{projectile-mode-map}"
  :lighter (format " [P>%s]" (upcase projectable-id))
  :keymap projectable-mode-map
  :group 'projectable
  :require 'projectable)

;;;###autoload
(define-globalized-minor-mode projectable-global-mode
  projectable-mode
  projectable-mode)

(provide 'projectable)
;;; projectable.el ends here
