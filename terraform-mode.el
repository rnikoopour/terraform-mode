;;; terraform-mode.el --- Major mode for Terraform files -*- lexical-binding: t -*-

;; Copyright (C) 2017 by Syohei YOSHIDA

;; Original Author: Syohei YOSHIDA <syohex@gmail.com>
;; Original URL: https://github.com/syohex/emacs-terraform-mode

;; Rewrite Author: Reza Nikoopour <rnikoopour@gmail.com>
;; Version: 2.0.0
;; Package-Requires: ((emacs "30.1"))
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

;; A major mode for editing Terraform files (.tf and .tfvars) files.
;; Derived from prog-mode.

;;; Code:

;; Syntax Table
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

;; Text Propertizing
(defun terraform-mode--text-propertize-block (regexp property start end depth &optional required-property)
  "Mark contents of blocks matched by REGEXP with PROPERTY as a text property.
Only marks the portion of each block that overlaps with [START, END).
Only marks blocks at brace nesting DEPTH.
When REQUIRED-PROPERTY is non-nil, only mark blocks where that property is set at the match."
  (remove-text-properties start end (list property nil))
  (save-excursion
    (goto-char (point-min))
    (while (re-search-forward regexp nil t)
      (when (and (= (nth 0 (save-excursion (parse-partial-sexp (point-min) (match-beginning 0)))) depth)
                 (or (null required-property)
                     (get-text-property (match-beginning 0) required-property)))
        (let ((content-start (point)))
          (save-excursion
            (let ((relative-depth 1))
              (while (and (> relative-depth 0)
                          (re-search-forward "[{}]" nil t))
                (pcase (char-before)
                  (?{ (setq relative-depth (1+ relative-depth)))
                  (?} (setq relative-depth (1- relative-depth)))))
              (when (= relative-depth 0)
                (let ((content-end (1- (point))))
                  (when (and (> content-end content-start)
                             (> content-end start)
                             (< content-start end))
                    (put-text-property
                     (max content-start start)
                     (min content-end end)
                     property t)))))))))))

(defconst terraform-mode--terraform-block-propertize
  (rx line-start (zero-or-more space) "terraform" (zero-or-more space) "{"))

(defconst terraform-mode--required-providers-block-propertize
  (rx line-start (zero-or-more space) "required_providers" (zero-or-more space) "{"))

(defconst terraform-mode--variable-block-propertize
  (rx line-start (zero-or-more space) "variable" (one-or-more space)
      "\"" (one-or-more (not (any "\""))) "\""
      (zero-or-more space) "{"))

(eval-and-compile
  (defconst terraform-mode--block-builtins-with-type-propertize
    (rx line-start (zero-or-more space)
	(group (or "backend" "provider_meta"))
	(one-or-more space)
	(group (group "\"") (one-or-more (not (any "\""))) (group "\""))
	(zero-or-more space) "{"))

  (defconst terraform-mode--block-builtins-with-name-propertize
    (rx line-start (zero-or-more space)
	(group "variable")
	(one-or-more space)
	(group (group "\"") (one-or-more (not (any "\""))) (group "\""))
	(zero-or-more space) "{")))

(defun terraform-mode--builtins-with-type-propertize-match (start end)
  "Add text property to Terraform blocks with type.
This prevents `font-lock-string-face' from being applied.
Applies to region [START, END]."
  (goto-char start)
  (funcall
   (syntax-propertize-rules
    (terraform-mode--block-builtins-with-type-propertize
     (3 ".")
     (4 "."))
    (terraform-mode--block-builtins-with-name-propertize
     (3 ".")
     (4 ".")))
   start end))

(defun terraform-mode--syntax-propertize (start end)
  "Propertize region from START to END."
  (terraform-mode--builtins-with-type-propertize-match start end)
  (terraform-mode--text-propertize-block terraform-mode--terraform-block-propertize 'terraform-mode-terraform-block start end 0)
  (terraform-mode--text-propertize-block terraform-mode--variable-block-propertize 'terraform-mode-variable-block start end 0)
  (terraform-mode--text-propertize-block terraform-mode--required-providers-block-propertize 'terraform-mode-required-providers start end 1 'terraform-mode-terraform-block))

;; Syntax highlighting
(defun terraform-mode--builtin-at-depth-highlight-match (regexp depth limit)
  "Search for REGEXP up to LIMIT and match only at brace nesting DEPTH."
  (and (re-search-forward regexp limit t)
       (= (nth 0 (syntax-ppss (match-beginning 0))) depth)))

(defun terraform-mode--builtin-with-property-highlight-match (regexp property limit)
  "Search for REGEXP up to LIMIT and match only where PROPERTY is set."
  (let (found)
    (while (and (not found)
                (re-search-forward regexp limit t))
      (when (get-text-property (match-beginning 0) property)
        (setq found t)))
    found))

(defconst terraform-mode--terraform-keyword-highlight
  (rx line-start (zero-or-more space) (group "terraform")))

(defun terraform-mode--terraform-block-highlight-match (limit)
  (terraform-mode--builtin-at-depth-highlight-match terraform-mode--terraform-keyword-highlight 0 limit))

(defconst terraform-mode--block-builtins-inside-terraform-highlight
  (rx line-start (zero-or-more space) (group (or "required_providers" "cloud" "workspaces"))))

(defun terraform-mode--inside-terraform-block-highlight-match (limit)
  (terraform-mode--builtin-with-property-highlight-match terraform-mode--block-builtins-inside-terraform-highlight 'terraform-mode-terraform-block limit))

(defconst terraform-mode--provider-highlight
  (rx line-start (zero-or-more space) (group (one-or-more word)) (one-or-more space) "{"))

(defun terraform-mode--provider-highlight-match (limit)
  "Match provider names inside required_providers blocks up to LIMIT."
  (terraform-mode--builtin-with-property-highlight-match terraform-mode--provider-highlight 'terraform-mode-required-providers limit))

(defconst terraform-mode--assignment-highlight
  (rx line-start (zero-or-more space) (group (one-or-more word)) (zero-or-more space) "="))

(defconst terraform-mode--variable-types-highlight
  (rx word-start
      (group (or "string" "number" "bool" "list" "set" "map" "object"))
      word-end))

(defun terraform-mode--variable-type-highlight-match (limit)
  "Match type keywords inside variable blocks up to LIMIT."
  (terraform-mode--builtin-with-property-highlight-match terraform-mode--variable-types-highlight 'terraform-mode-variable-block limit))

(defconst terraform-mode--block-builtins-with-type-highlight
  terraform-mode--block-builtins-with-type-propertize)

(defconst terraform-mode--block-builtins-with-name-highlight
  terraform-mode--block-builtins-with-name-propertize)

(defconst terraform-mode--font-lock-keywords
  `((terraform-mode--terraform-block-highlight-match 1 font-lock-builtin-face)
    (terraform-mode--inside-terraform-block-highlight-match 1 font-lock-builtin-face)
    (,terraform-mode--assignment-highlight 1 font-lock-variable-name-face)
    (terraform-mode--provider-highlight-match 1 font-lock-type-face)
    (terraform-mode--variable-type-highlight-match 1 font-lock-type-face)
    (,terraform-mode--block-builtins-with-type-highlight
     (1 font-lock-builtin-face)
     (2 font-lock-type-face))
    (,terraform-mode--block-builtins-with-name-highlight
     (1 font-lock-builtin-face)
     (2 font-lock-variable-name-face))))


;; Mode Configuration

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
