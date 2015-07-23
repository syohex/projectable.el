;;; emacs --- Lightweight project cacheing and navigation framework

;; Copyright © 2015  Dominic Charlesworth <dgc336@gmail.com>

;; Author: Dominic Charlesworth <dgc336@gmail.com>
;; URL: https://github.com/domtronn/projectable
;; Version: 0.0.2
;; Keywords: project, convenience

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

;; This package works on creating an associative list of files
;; based on project keys

;; This is perhaps not the best data strucutre for projects but
;; works well for require.js with name setups

;;; Code:

;; (defclass dir ()
;; ((dir :initarg :dir
;;         :documentation "The base path of the directory")
;;    (tags :initarg :create-tags
;;          :documentation "Whether to create tags from them")))

;; (defclass project ()
;;   ((id
;;     :initarg :id
;;     :documentation "The ID of the project")
;;    (project
;;     :initarg :project
;;     :documentation "A List of projects to include")
;;    )
;;   "A definition of a project")

(require 'json)
(require 'ido)

(defconst projectable-dir (file-name-directory load-file-name))

;;; Group Definitions
(defgroup projectable nil
  "Manage how to read and create project caches."
  :group 'tools
  :group 'convenience)

;;; Customisation Option Definitions
(defcustom projectable-alist-cmd (concat projectable-dir "create-file-alist.py")
  "Specify the command that to produce an associative list.

The SHELL-COMMAND, when run with a directory and a list of filter regexps,
should return an associative list in the following form as json for now.

\((file1 (dir1 dir2 dir3)) (file2 (dir1 dir2)))

By default, it uses the python script provided with this package."
  :group 'projectable
  :type 'string
  )

(defcustom projectable-verbose nil
  "Toggle verbose printing.
Mainly for debugging of the package."
  :group 'projectable
  :type 'boolean)

(defcustom projectable-filter-regexps
  (quote
   ("~$" "\\.o$" "\\.exe$" "\\.a$" "\\.elc$" "\\.output$" "\\.$" "#$" "\\.class$"
    "\\/test.*\\.js$" "\\.png$" "\\.svn*" "\\/node_modules\\/*" "\\.gif$" "\\.gem$"
    "\\.pdf$" "\\.swp$" "\\.iml$" "\\.jar$" "\\/build\\/" "Spec\\.js$"
    "\\/script-tests\\/specs" "\\/jsdoc\\/" "\\.min\\.js$" "\\.tags$" "\\.filecache"
    "\\.cache$" "\\/.git\\/" "report" "\\.gcov\\.html$" "\\.func.*\\.html$"))
  "Specify a list of regexps to filter."
  :group 'projectable
  :type '(repeat regexp))

(defcustom projectable-project-directory (expand-file-name "~/Documents/Projects")
  "The directory where project.json files are kept.

By default it looks in your Documents folder"
  :group 'projectable
  :type 'string)

(defcustom projectable-keymap-prefix (kbd "C-c p")
  "Projectable keymap prefix."
  :group 'projectable
  :type 'string)

(defcustom projectable-use-gitignore t
  "Whether to use gitignore for your regexp filters."
  :group 'projectable
  :type 'boolean)

;;; Variable Definitions
(defvar projectable-current-project-path nil)
(defvar projectable-project-alist nil)
(defvar projectable-project-hash nil)
(defvar projectable-file-alist nil)
(defvar projectable-id)

(defvar projectable-indent-level
  2 "The level of indentation to be used.")
(defvar projectable-indent-type
  (list :tabs "	") "The indentation type with the indent character.")
(defvar projectable-reformat-string
  "	" "The level of indentation to be used.")

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
  (setq projectable-current-project-path arg)
  (setq projectable-project-alist (make-hash-table :test 'equal))
  (setq projectable-file-alist (make-hash-table :test 'equal))
  (projectable-refresh)
  (when projectable-use-vertical-flx
    (projectable-disable-vertical))
  (projectable-message (format "New project is %s" arg) t))

(defun projectable-refresh ()
  "Parse a json project file to create a cache for that project.

If the supplied file is not a file but a directory, it just adds
this directory to the file cache"
  (interactive)
  (when projectable-current-project-path
    (if (projectable-is-file projectable-current-project-path)
        ;; Json file so load from json
        (projectable-load-from-json)
      ;; A directory so load form directory
      (progn
        (projectable-message
         (format "%s is not a file - Interpreting as directory" projectable-current-project-path))
        (projectable-load-from-path)))))

(defun projectable-is-file (dir)
  "Check whether DIR is a directory using shell."
	(string-equal "0\n" (shell-command-to-string (format "if [ -d %s ]; then echo 1; else echo 0; fi" dir))))

(defun projectable-load-from-json ()
  "Set the project based on a path.
This will just cache all of the files contained in that directory."
  (let* ((json-object-type 'hash-table)
         (json-contents
          (shell-command-to-string (concat "cat " projectable-current-project-path)))
         (json-hash (json-read-from-string json-contents))
         (gitignore-filter-regexp (list)))

    (setq projectable-project-hash json-hash)
    
    ;; Set project ID
    (let ((id (gethash "projectId" json-hash)))
      (setq projectable-id id)
      (projectable-message (format "Project ID: [%s]" id)))
    
    ;; Set up the gitignore properties
    (let ((project-list (gethash "project" json-hash)))
      (mapc (lambda (x)
              (let ((location (find-file-upwards ".gitignore" (concat (gethash "dir" x) "/"))))
                (when location
                  (setq gitignore-filter-regexp
                        (-distinct
                         (append gitignore-filter-regexp (projectable-get-gitignore-filter location)))))))
            project-list))
    
    ;; Set the indent level
    (when (gethash "indent" json-hash)
      (projectable-set-indent-level (gethash "indent" json-hash)))

    ;; Set the tabs/spaces indent type
    (when (gethash "tabs" json-hash)
      (projectable-set-indent-type (eq :json-false (gethash "tabs" json-hash))))

    (when (gethash "testing" json-hash)
      (let ((test-hash (gethash "testing" json-hash)))
        (when (gethash "sourcePath" test-hash)
          (setq projectable-src-path (gethash "sourcePath" test-hash)))
        (setq projectable-test-path (gethash "path" test-hash))
        (setq projectable-test-extension (gethash "extension" test-hash))))

    (projectable-set-project-alist gitignore-filter-regexp)
    (setq projectable-file-alist (cdr (assoc projectable-id projectable-project-alist))))
  t)

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
  (let ((id (file-name-base projectable-current-project-path)))
    (setq projectable-id id)
    (projectable-message (format "Project ID: [%s]" id)))
  
  (let ((gitignore-filter-regexps (projectable-get-gitignore-filter
                                   (find-file-upwards ".gitignore" (concat projectable-current-project-path "/") ))))
    (projectable-set-project-alist gitignore-filter-regexps))
  (setq projectable-file-alist projectable-project-alist)
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
               " \"")))
    (setq projectable-project-alist
          (json-read-from-string
           (shell-command-to-string cmd)))
    t))

(defun projectable-get-gitignore-filter (dir)
  "Produce regexps filters by based on a .gitignore files found in DIR."
  (with-temp-buffer
    (insert-file-contents dir)
    (goto-char (point-min))
    (flush-lines "^[#]")
    (flush-lines "^$")
    (while (search-forward "*" nil t)
      (replace-match ""))
    (goto-char (point-min))
    (while (search-forward "." nil t)
      (replace-match "\\." nil t))
    (split-string (buffer-string) "\n" t)))

(defun projectable-set-indent-type (bool)
  "Set the indent type based on BOOL.
t => spaces nil => tabs"
  (if bool
      (progn
        (projectable-message (format "Using spaces for project [%s]" projectable-id))
        (setq projectable-indent-type (list :spaces (projectable-build-space-string)))
        (setq projectable-reformat-string "	")
        (setq-default indent-tabs-mode nil))
    (progn
      (projectable-message (format "Using tabs for project [%s]" projectable-id))
      (setq projectable-indent-type (list :tabs "	"))
      (setq projectable-reformat-string (projectable-build-space-string))
      (setq-default indent-tabs-mode t)))
  t)

(defun projectable-set-indent-level (level)
  "Set the indent level based on LEVEL."
  (when (require 'js2-mode nil 'noerror)
    (projectable-message "JS2 mode found")
    (setq-default js2-basic-offset level))
  
  (when (require 'web-mode nil 'noerror)
    (projectable-message "Web mode found")
    (setq-default web-mode-markup-indent-offset level)
    (setq-default web-mode-css-indent-offset level)
    (setq-default web-mode-code-indent-offset level))

  (setq-default c-basic-offset level)
  (setq-default css-indent-offset level)
  (setq-default js-basic-offset level)
  (setq-default basic-offset level)
  (setq tab-width level)
  (projectable-message (format "Setting indent level to %s" level))
  t)

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

(defun find-file-upwards (file-to-find &optional starting-path)
  "Recursively search parent directories for FILE-TO-FIND from STARTING-PATH.
looking for a file with name file-to-find.  Returns the path to it
or nil if not found.

By default, it uses the `default-directory` as a starting point unless stated
otherwise through the use of STARTING-PATH.

This function is taken from
http://www.emacswiki.org/emacs/EmacsTags#tags"
  (cl-labels
      ((find-file-r (path)
                    (let* ((parent (file-name-directory path))
                           (possible-file (concat parent file-to-find)))
                      (cond
                       ((file-exists-p possible-file) possible-file) ; Found
                       ;; The parent of ~ is nil and the parent of / is itself.
                       ;; Thus the terminating condition for not finding the file
                       ;; accounts for both.
                       ((or (null parent) (equal parent (directory-file-name parent))) nil) ; Not found
                       (t (find-file-r (directory-file-name parent))))))) ; Continue
    (find-file-r (if starting-path starting-path default-directory))))


(defun projectable-ido-find-file (file)
  "Using ido, interactively open FILE from projectable alist.
Select a file matched using `ido-switch-buffer` against the contents
of `projectable-file-alist`.  If the file exists in more than one
directory, select directory.  Lastly the file is opened.

This code snippet is borrowed and adapted from
http://emacswiki.org/emacs/FileNameCache"
  (interactive (progn
                 (when projectable-use-vertical-flx
                   (projectable-enable-vertical))
                 (list (ido-completing-read
                        "File: " (mapcar (lambda (x) (car x))
                                         projectable-file-alist)))))
  (let* ((record (assoc file projectable-file-alist)))
    (find-file
     (expand-file-name
      file
      (if (= (length record) 2)
          (car (cdr record))
        (ido-completing-read
         (format "Find %s in dir:" file) (cdr record)))))
    (when projectable-use-vertical-flx
      (projectable-disable-vertical))))


;;; Utility Functions
;;  A bunch of functions to help with project navigation and set up.

(defun projectable-toggle-open-test ()
  "Open associated test class if it exists."
  (interactive)
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
        
        (message (format "Could not find test file for [%s]" buffer-file-name))))))

(defun projectable-guess-source-path ()
  "Guess what the source path for files is."
  (let ((result nil)
        (projects (gethash "project" projectable-project-hash)))
    (mapc #'(lambda (p) (let ((project-dir (expand-file-name (gethash "dir" p))))
                     (when (string-match project-dir (file-truename (buffer-file-name)))
                       (setq result project-dir)))) projects)
    result))

(defun projectable-reformat-file ()
  "Reformat tabs/spaces into correct format for current file."
  (interactive)
  (save-excursion
    (goto-char (point-min))
    (while (search-forward projectable-reformat-string (point-max) t)
			(replace-match "	"))
		(projectable-message
		 (format "Reformatted file to use [%s]" (car projectable-indent-type)) t)))

(defun projectable-build-space-string ()
  "Build the indent string of spaces.
i.e.  If indent level was 4, the indent string would be '    '."
  (make-string projectable-indent-level ? ))

(defun projectable-visit-project-file ()
	"Open the project file currently being used."
  (interactive)
	(when projectable-current-project-path
		(if (projectable-is-file projectable-current-project-path)
				(find-file projectable-current-project-path)
			(projectable-message
			 (format "Current project is an anonymous path, not a project file [%s]" projectable-current-project-path) t))))

;;; Projectable Mode
;;  Set up for the projectable minor-mode.

(when (and (require 'flx-ido nil t)
           (require 'ido-vertical-mode nil t))
  
  (projectable-message "Found FLX-IDO and IDO-VERTICAL")
  (projectable-message "Adding advice to use these features")
  
  (defcustom projectable-use-vertical-flx t
    "Whether to take advantange of FLX and VERTICAL features."
    :group 'projectable
    :type 'boolean)
  (setq projectable-use-vertical-flx t))

(defvar projectable-command-map
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "c") #'projectable-change)
    (define-key map (kbd "r") #'projectable-refresh)
    (define-key map (kbd "f") #'projectable-ido-find-file)
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

(define-minor-mode projectable-mode
  "Minor mode to assist project management and navigation.

When called interactively, toggle `projectable-mode'.  With prefix
ARG, enable `projectable-mode' if ARG is positive, otherwise disable
it.

When called from Lisp, enable `projectable-mode' if ARG is omitted,
nil or positive.  If ARG is `toggle', toggle `projectable-mode'.
Otherwise behave as if called interactively.

\\{projectile-mode-map}"
  :lighter (format "[P>%s]" (upcase projectable-id))
  :keymap projectable-mode-map
  :group 'projectable
  :require 'projectable)

(define-globalized-minor-mode projectable-global-mode
  projectable-mode
  projectable-mode)

(provide 'projectable)
;;; projectable.el ends here
