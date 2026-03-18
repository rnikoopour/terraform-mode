;;; terraform-mode.el --- Major mode for Terraform files -*- lexical-binding: t -*-

;; Copyright (C) 2017 by Syohei YOSHIDA

;; Original Author: Syohei YOSHIDA <syohex@gmail.com>
;; Original URL: https://github.com/syohex/emacs-terraform-mode

;; Rewrite Author: Reza Nikoopour <rnikoopour@gmail.com>
;; Version: 2.0.0
;; Package-Requires: ((emacs "26.1"))
;; Keywords: languages terraform

;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <http://www.gnu.org/licenses/>.

;;; Commentary:

;; A major mode for editing Terraform (.tf and .tfvars) files.
;; Derived from prog-mode.

;;; Code:

(defvar terraform-mode-syntax-table
  (let ((table (make-syntax-table)))
    ;; # and // are line comments (style b); /* */ are block comments (style a)
    (modify-syntax-entry ?# "< b" table)
    (modify-syntax-entry ?\n "> b" table)
    (modify-syntax-entry ?/ ". 124b" table)
    (modify-syntax-entry ?* ". 23" table)
    ;; _ is a word constituent
    (modify-syntax-entry ?_ "w" table)
    ;; strings
    (modify-syntax-entry ?\" "\"" table)
    ;; brackets
    (modify-syntax-entry ?{ "(}" table)
    (modify-syntax-entry ?} "){" table)
    (modify-syntax-entry ?\[ "(]" table)
    (modify-syntax-entry ?\] ")[" table)
    (modify-syntax-entry ?\( "()" table)
    (modify-syntax-entry ?\) ")(" table)
    table)
  "Syntax table for `terraform-mode'.")

(defconst terraform-mode--block-builtins-depth-0
  (rx line-start (zero-or-more space) (group "terraform")))

(defconst terraform-mode--block-builtins-depth-1
  (rx line-start (zero-or-more space) (group (or "required_providers" "cloud"))))

(defconst terraform-mode--block-builtins-depth-2
  (rx line-start (zero-or-more space) (group "workspaces")))

(defconst terraform-mode--block-builtins-with-type
  (rx line-start (zero-or-more space)
      (group (or "backend" "provider_meta"))
      (one-or-more space)
      (group (group "\"") (one-or-more (not (any "\""))) (group "\""))
      (zero-or-more space) "{"))

(defun terraform-mode--syntax-propertize (start end)
  "Mark type argument quotes in builtin-with-type blocks as punctuation.
This prevents them from receiving `font-lock-string-face' during syntactic
fontification, allowing `font-lock-type-face' to be applied without override."
  (goto-char start)
  (funcall
   (syntax-propertize-rules
    (terraform-mode--block-builtins-with-type
     (3 ".")
     (4 ".")))
   start end))

(defconst terraform-mode--provider
  (rx line-start (zero-or-more space) (group (one-or-more word)) (one-or-more space) "{"))

(defconst terraform-mode--variable
  (rx line-start (zero-or-more space) (group (one-or-more word)) (zero-or-more space) "="))

(defun terraform-mode--match-builtin-at-depth (regexp depth limit)
  "Search for REGEXP up to LIMIT and match only at brace nesting DEPTH."
  (and (re-search-forward regexp limit t)
       (= (nth 0 (syntax-ppss (match-beginning 0))) depth)))

(defun terraform-mode--match-depth-0-builtin (limit)
  (terraform-mode--match-builtin-at-depth terraform-mode--block-builtins-depth-0 0 limit))

(defun terraform-mode--match-depth-1-builtin (limit)
  (terraform-mode--match-builtin-at-depth terraform-mode--block-builtins-depth-1 1 limit))

(defun terraform-mode--match-depth-2-builtin (limit)
  (terraform-mode--match-builtin-at-depth terraform-mode--block-builtins-depth-2 2 limit))


(defconst terraform-mode--required-providers-block
  (rx line-start (zero-or-more space) "required_providers" (zero-or-more space) "{"))

(defconst terraform-mode--provider-anchor
  `(,terraform-mode--required-providers-block
    (,terraform-mode--provider
     (save-excursion (backward-char) (condition-case nil (forward-sexp) (error nil)) (point))
     nil
     (1 font-lock-type-face))))

(defconst terraform-mode--font-lock-keywords
  `((terraform-mode--match-depth-0-builtin 1 font-lock-builtin-face)
    (terraform-mode--match-depth-1-builtin 1 font-lock-builtin-face)
    (terraform-mode--match-depth-2-builtin 1 font-lock-builtin-face)
    ,terraform-mode--provider-anchor
    (,terraform-mode--block-builtins-with-type
     (1 font-lock-builtin-face)
     (2 font-lock-type-face))
    (,terraform-mode--variable 1 font-lock-variable-name-face)))

;;;###autoload
(define-derived-mode terraform-mode prog-mode "Terraform"
  "Major mode for editing Terraform files."
  :syntax-table terraform-mode-syntax-table
  (setq-local comment-start "#")
  (setq-local comment-end "")
  (setq-local font-lock-defaults '(terraform-mode--font-lock-keywords nil nil))
  (setq-local syntax-propertize-function #'terraform-mode--syntax-propertize))

;;;###autoload
(add-to-list 'auto-mode-alist '("\\.tf\\'" . terraform-mode))
;;;###autoload
(add-to-list 'auto-mode-alist '("\\.tfvars\\'" . terraform-mode))

(provide 'terraform-mode)

;;; terraform-mode.el ends here
