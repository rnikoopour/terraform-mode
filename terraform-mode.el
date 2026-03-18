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

(defconst terraform-mode--block-builtins-no-type-or-name
  (rx line-start (zero-or-more space) (group "terraform")))

(defconst terraform-mode--variable
  (rx line-start (zero-or-more space) (group (one-or-more word)) (zero-or-more space) "="))

(defconst terraform-mode--font-lock-keywords
  `((,terraform-mode--block-builtins-no-type-or-name 1 font-lock-builtin-face)
    (,terraform-mode--variable 1 font-lock-variable-name-face)))

;;;###autoload
(define-derived-mode terraform-mode prog-mode "Terraform"
  "Major mode for editing Terraform files."
  :syntax-table terraform-mode-syntax-table
  (setq-local comment-start "#")
  (setq-local comment-end "")
  (setq-local font-lock-defaults '(terraform-mode--font-lock-keywords nil nil)))

;;;###autoload
(add-to-list 'auto-mode-alist '("\\.tf\\'" . terraform-mode))
;;;###autoload
(add-to-list 'auto-mode-alist '("\\.tfvars\\'" . terraform-mode))

(provide 'terraform-mode)

;;; terraform-mode.el ends here
