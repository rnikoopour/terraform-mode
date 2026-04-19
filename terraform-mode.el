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

;; Keyword groups shared across propertizing and highlighting
(rx-define terraform-mode--block-with-type-only   (or "backend" "provider_meta" "resource" "data" "provider"))
(rx-define terraform-mode--block-with-name-only   (or "variable" "module" "output"))
(rx-define terraform-mode--block-with-type-and-name (or "resource" "data"))

;; Text Propertizing
(defun terraform-mode--text-propertize-block (regexp property start end depth &optional required-property)
  "Mark contents of blocks matched by REGEXP with PROPERTY as a text property.
Only marks the portion of each block that overlaps with [START, END).
Only marks blocks at brace nesting DEPTH.
When REQUIRED-PROPERTY is non-nil, only mark blocks where that property is set
at the match."
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
              (if (= relative-depth 0)
                  (let ((content-end (1- (point))))
                    (when (and (> content-end content-start)
                               (> content-end start)
                               (< content-start end))
                      (put-text-property
                       (max content-start start)
                       (min content-end end)
                       property t)))
                ;; Block is incomplete (unbalanced braces during typing).
                ;; Mark what we can so the edited line keeps its property.
                (when (and (< content-start end) (> end start))
                  (put-text-property
                   (max content-start start)
                   end
                   property t))))))))))

(defconst terraform-mode--terraform-block-propertize
  (rx line-start (zero-or-more space) "terraform" (zero-or-more space) "{"))

(defconst terraform-mode--locals-block-propertize
  (rx line-start (zero-or-more space) "locals" (zero-or-more space) "{"))

(defconst terraform-mode--required-providers-block-propertize
  (rx line-start (zero-or-more space) "required_providers" (zero-or-more space) "{"))

(defconst terraform-mode--variable-block-propertize
  (rx line-start (zero-or-more space) terraform-mode--block-with-name-only (one-or-more space)
      "\"" (one-or-more (not (any "\""))) "\""
      (zero-or-more space) "{"))

(defconst terraform-mode--resource-block-propertize
  (rx line-start (zero-or-more space) terraform-mode--block-with-type-and-name (one-or-more space)
      "\"" (one-or-more (not (any "\""))) "\""
      (one-or-more space)
      "\"" (one-or-more (not (any "\""))) "\""
      (zero-or-more space) "{"))

(defconst terraform-mode--module-block-propertize
  (rx line-start (zero-or-more space) "module" (one-or-more space)
      "\"" (one-or-more (not (any "\""))) "\""
      (zero-or-more space) "{"))

(defconst terraform-mode--output-block-propertize
  (rx line-start (zero-or-more space) "output" (one-or-more space)
      "\"" (one-or-more (not (any "\""))) "\""
      (zero-or-more space) "{"))

(defconst terraform-mode--label-bearing-keywords-propertize
  (rx line-start (zero-or-more space)
      (group (or terraform-mode--block-with-type-only terraform-mode--block-with-name-only))
      (one-or-more space)))

(defun terraform-mode--propertize-quote-as-punct (pos)
  "Mark the double-quote character at POS as punctuation."
  (put-text-property pos (1+ pos) 'syntax-table (string-to-syntax ".")))

(defun terraform-mode--propertize-next-label ()
  "Propertize the label starting at point.
Point must be on an opening double-quote.  Marks it as punctuation, then
scans forward to mark the closing quote as punctuation if present.
Leaves point after the closing quote (if found) or before the terminator.
Returns non-nil if an opening quote was found."
  (when (= (char-after) ?\")
    (terraform-mode--propertize-quote-as-punct (point))
    (forward-char 1)
    (when (re-search-forward (rx (or "\"" space "\n")) nil t)
      (if (= (char-before) ?\")
          (terraform-mode--propertize-quote-as-punct (1- (point)))
        (goto-char (1- (point)))))
    t))

(defun terraform-mode--builtins-with-type-propertize-match (start end)
  "Progressively propertize label quotes in [START, END].
Marks opening and closing quotes of block labels as punctuation to
suppress `font-lock-string-face' on their contents."
  (goto-char start)
  (while (re-search-forward terraform-mode--label-bearing-keywords-propertize end t)
    (let ((keyword (match-string 1)))
      (when (terraform-mode--propertize-next-label)
        (when (member keyword '("resource" "data"))
          (when (looking-at (rx (one-or-more space)))
            (goto-char (match-end 0))
            (terraform-mode--propertize-next-label)))))))

(defun terraform-mode--string-interpolation-propertize ()
  "Mark ${...} in strings so interpolation content is parsed as code.
Marks the enclosing quotes and the interpolation braces with generic-string
delimiter syntax, splitting the string at each ${...} boundary."
  (save-excursion
    (goto-char (point-min))
    (while (< (point) (point-max))
      (cond
       ((or (eq (char-after) ?#)
            (and (eq (char-after) ?/)
                 (eq (char-after (1+ (point))) ?/)))
        (end-of-line)
        (when (< (point) (point-max)) (forward-char 1)))
       ((and (eq (char-after) ?/)
             (eq (char-after (1+ (point))) ?*))
        (or (search-forward "*/" nil t) (goto-char (point-max))))
       ((eq (char-after) ?\")
        (let ((open-pos (point))
              (brace-pairs nil)
              (close-pos nil))
          (forward-char 1)
          (catch 'done
            (while (< (point) (point-max))
              (cond
               ((eq (char-after) ?\\)
                (forward-char 2))
               ((eq (char-after) ?\")
                (setq close-pos (point))
                (forward-char 1)
                (throw 'done nil))
               ((and (eq (char-after) ?$)
                     (eq (char-after (1+ (point))) ?{)
                     (not (eq (char-before) ?$)))
                (let ((brace-open (1+ (point))))
                  (forward-char 2)
                  (let ((depth 1))
                    (while (and (> depth 0) (< (point) (point-max)))
                      (cond
                       ((eq (char-after) ?{)
                        (setq depth (1+ depth))
                        (forward-char 1))
                       ((eq (char-after) ?})
                        (setq depth (1- depth))
                        (when (= depth 0)
                          (push (cons brace-open (point)) brace-pairs))
                        (forward-char 1))
                       (t (forward-char 1)))))))
               (t (forward-char 1)))))
          (when brace-pairs
            (put-text-property open-pos (1+ open-pos)
                               'syntax-table (string-to-syntax "|"))
            (when close-pos
              (put-text-property close-pos (1+ close-pos)
                                 'syntax-table (string-to-syntax "|")))
            (dolist (pair brace-pairs)
              (put-text-property (car pair) (1+ (car pair))
                                 'syntax-table (string-to-syntax "|"))
              (put-text-property (cdr pair) (1+ (cdr pair))
                                 'syntax-table (string-to-syntax "|"))))))
       (t (forward-char 1))))))

(defun terraform-mode--syntax-propertize-extend-region (start end)
  "Extend [START, END) to cover the enclosing top-level block.
Ensures syntax-propertize and font-lock both run on the full block
when any part of it changes."
  (let ((new-start start)
        (new-end end))
    (save-excursion
      (goto-char start)
      (when (re-search-backward
             (rx line-start (or "resource" "data" "module" "variable" "output"
                                "terraform" "provider" "locals")
             word-end) nil t)
        (setq new-start (min new-start (line-beginning-position))))
      (goto-char end)
      (when (re-search-forward (rx line-start "}") nil t)
        (setq new-end (max new-end (point)))))
    (unless (and (= new-start start) (= new-end end))
      (cons new-start new-end))))

(defun terraform-mode--syntax-propertize (start end)
  "Propertize region from START to END.
Order of functions is important."
  (terraform-mode--string-interpolation-propertize)
  (terraform-mode--builtins-with-type-propertize-match start end)
  (terraform-mode--text-propertize-block terraform-mode--terraform-block-propertize 'terraform-mode-terraform-block start end 0)
  (terraform-mode--text-propertize-block terraform-mode--locals-block-propertize 'terraform-mode-locals-block start end 0)
  (terraform-mode--text-propertize-block terraform-mode--required-providers-block-propertize 'terraform-mode-required-providers start end 1 'terraform-mode-terraform-block)
  (terraform-mode--text-propertize-block terraform-mode--variable-block-propertize 'terraform-mode-variable-block start end 0)
  (terraform-mode--text-propertize-block terraform-mode--resource-block-propertize 'terraform-mode-resource-block start end 0)
  (terraform-mode--text-propertize-block terraform-mode--module-block-propertize 'terraform-mode-module-block start end 0)
  (terraform-mode--text-propertize-block terraform-mode--output-block-propertize 'terraform-mode-output-block start end 0))

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

(defconst terraform-mode--block-keywords-highlight
  (rx line-start (zero-or-more space)
      (group (or "terraform"
                 "locals"
                 terraform-mode--block-with-type-only
                 terraform-mode--block-with-name-only))))

(defun terraform-mode--block-keywords-highlight-match (limit)
  "Match block-opening keywords at depth 0 up to LIMIT."
  (terraform-mode--builtin-at-depth-highlight-match terraform-mode--block-keywords-highlight 0 limit))

(defconst terraform-mode--block-builtins-inside-terraform-highlight
  (rx line-start (zero-or-more space) (group (or "required_providers" "cloud" "workspaces"))))

(defun terraform-mode--inside-terraform-block-highlight-match (limit)
  (terraform-mode--builtin-with-property-highlight-match terraform-mode--block-builtins-inside-terraform-highlight 'terraform-mode-terraform-block limit))

(defconst terraform-mode--resource-sub-block-highlight
  (rx line-start (zero-or-more space) (group (one-or-more word)) (zero-or-more space) "{"))

(defun terraform-mode--resource-sub-block-highlight-match (limit)
  "Match sub-block labels inside resource blocks up to LIMIT."
  (terraform-mode--builtin-with-property-highlight-match terraform-mode--resource-sub-block-highlight 'terraform-mode-resource-block limit))

(defconst terraform-mode--lifecycle-highlight
  (rx line-start (zero-or-more space) (group "lifecycle")))

(defun terraform-mode--lifecycle-highlight-match (limit)
  "Match lifecycle keyword inside resource blocks up to LIMIT."
  (terraform-mode--builtin-with-property-highlight-match terraform-mode--lifecycle-highlight 'terraform-mode-resource-block limit))

(defconst terraform-mode--each-highlight
  (rx word-start (group "each") (optional "." (group (or "key" "value"))) word-end))

(defun terraform-mode--each-highlight-match (limit)
  "Match each and each.key/each.value inside resource blocks up to LIMIT."
  (terraform-mode--builtin-with-property-highlight-match terraform-mode--each-highlight 'terraform-mode-resource-block limit))

(defconst terraform-mode--provider-highlight
  (rx line-start (zero-or-more space) (group (one-or-more word)) (one-or-more space) "{"))

(defun terraform-mode--provider-highlight-match (limit)
  "Match provider names inside required_providers blocks up to LIMIT."
  (terraform-mode--builtin-with-property-highlight-match terraform-mode--provider-highlight 'terraform-mode-required-providers limit))

(defconst terraform-mode--assignment-highlight
  (rx line-start (zero-or-more space) (group (one-or-more word)) (zero-or-more space) "="))

(defconst terraform-mode--module-builtins-highlight
  (rx line-start
      (zero-or-more space)
      (group (or "source" "providers"))
      (zero-or-more space)
      "="))

(defun terraform-mode--module-builtin-highlight-match (limit)
  "Match type keywords inside module blocks up to LIMIT."
  (terraform-mode--builtin-with-property-highlight-match terraform-mode--module-builtins-highlight 'terraform-mode-module-block limit))

(defconst terraform-mode--variable-types-highlight
  (rx word-start
      (group (or "string" "number" "bool" "list" "set" "map" "object" "any"))
      word-end))

(defun terraform-mode--variable-type-highlight-match (limit)
  "Match type keywords inside variable blocks up to LIMIT."
  (terraform-mode--builtin-with-property-highlight-match terraform-mode--variable-types-highlight 'terraform-mode-variable-block limit))

(defconst terraform-mode--literal-keywords-highlight
  (rx word-start (group (or "true" "false" "null")) word-end))

(defconst terraform-mode--variable-type-builtins-highlight
  (rx word-start (group "optional") word-end))

(defun terraform-mode--variable-type-builtins-highlight-match (limit)
  "Match builtin values inside variable blocks up to LIMIT."
  (terraform-mode--builtin-with-property-highlight-match terraform-mode--variable-type-builtins-highlight 'terraform-mode-variable-block limit))

(defconst terraform-mode--reference-keywords-highlight
  (rx word-start (group (or "var" "local" "module" "data")) word-end))

(defconst terraform-mode--ternary-highlight
  (rx (group (or "?" ":"))))

(defconst terraform-mode--builtin-functions-highlight
  (rx word-start
      (group (or "abspath" "alltrue" "anytrue" "base64decode" "base64encode"
                 "base64gzip" "base64sha256" "base64sha512" "basename" "bcrypt"
                 "can" "ceil" "chomp" "chunklist" "cidrhost" "cidrnetmask"
                 "cidrsubnet" "cidrsubnets" "coalesce" "coalescelist" "compact"
                 "concat" "contains" "csvdecode" "dirname" "distinct" "element"
                 "endswith" "ephemeralasnull" "file" "filebase64"
                 "filebase64sha256" "filebase64sha512" "fileexists" "filemd5"
                 "fileset" "filesha1" "filesha256" "filesha512" "flatten"
                 "floor" "format" "formatdate" "formatlist" "indent" "index"
                 "issensitive" "join" "jsondecode" "jsonencode" "keys" "length"
                 "log" "lookup" "lower" "matchkeys" "max" "md5" "merge" "min"
                 "nonsensitive" "one" "parseint" "pathexpand" "plantimestamp"
                 "pow" "range" "regex" "regexall" "replace" "reverse"
                 "rsadecrypt" "sensitive" "setintersection" "setproduct"
                 "setsubtract" "setunion" "sha1" "sha256" "sha512" "signum"
                 "slice" "sort" "split" "startswith" "strcontains" "strrev"
                 "substr" "sum" "templatefile" "templatestring"
                 "textdecodebase64" "textencodebase64" "timeadd" "timecmp"
                 "timestamp" "title" "tobool" "tolist" "tomap" "tonumber"
                 "toset" "tostring" "transpose" "trim" "trimprefix" "trimspace"
                 "trimsuffix" "try" "type" "upper" "urlencode" "uuid" "uuidv5"
                 "values" "yamldecode" "yamlencode" "zipmap"))
      "("))

(defconst terraform-mode--block-builtins-with-type-highlight
  (rx line-start (zero-or-more space)
      (group terraform-mode--block-with-type-only)
      (one-or-more space)
      (group "\"" (one-or-more (not (any "\"" space "\n"))) (optional "\""))))

(defconst terraform-mode--block-builtins-with-name-highlight
  (rx line-start (zero-or-more space)
      (group terraform-mode--block-with-name-only)
      (one-or-more space)
      (group "\"" (one-or-more (not (any "\"" space "\n"))) (optional "\""))))

(defconst terraform-mode--block-builtins-with-type-and-name-highlight
  (rx line-start (zero-or-more space)
      (group terraform-mode--block-with-type-and-name)
      (one-or-more space)
      (group "\"" (one-or-more (not (any "\"" space "\n"))) (optional "\""))
      (one-or-more space)
      (group "\"" (one-or-more (not (any "\"" space "\n"))) (optional "\""))))

(defconst terraform-mode--font-lock-keywords
  `((terraform-mode--block-keywords-highlight-match 1 font-lock-builtin-face)
    (terraform-mode--inside-terraform-block-highlight-match 1 font-lock-builtin-face)
    (terraform-mode--module-builtin-highlight-match 1 font-lock-builtin-face)
    (,terraform-mode--assignment-highlight 1 font-lock-variable-name-face)
    (,terraform-mode--literal-keywords-highlight 1 font-lock-builtin-face)
    (,terraform-mode--builtin-functions-highlight 1 font-lock-builtin-face)
    (,terraform-mode--ternary-highlight 1 font-lock-builtin-face)
    (,terraform-mode--reference-keywords-highlight 1 font-lock-builtin-face)
    (terraform-mode--lifecycle-highlight-match 1 font-lock-builtin-face)
    (terraform-mode--resource-sub-block-highlight-match 1 font-lock-variable-name-face)
    (terraform-mode--each-highlight-match
     (1 font-lock-builtin-face)
     (2 font-lock-builtin-face nil t))
    (terraform-mode--provider-highlight-match 1 font-lock-type-face)
    (terraform-mode--variable-type-highlight-match 1 font-lock-type-face)
    (terraform-mode--variable-type-builtins-highlight-match 1 font-lock-builtin-face)
    (,terraform-mode--block-builtins-with-type-highlight
     (1 font-lock-builtin-face)
     (2 font-lock-type-face))
    (,terraform-mode--block-builtins-with-name-highlight
     (1 font-lock-builtin-face)
     (2 font-lock-variable-name-face))
    (,terraform-mode--block-builtins-with-type-and-name-highlight
     (1 font-lock-builtin-face)
     (2 font-lock-type-face)
     (3 font-lock-variable-name-face))))


;; Development utilities

(defun terraform-mode--reload ()
  "Unload and reload terraform-mode."
  (interactive)
  (unload-feature 'terraform-mode t)
  (require 'terraform-mode))

;; Mode Configuration

;;;###autoload
(define-derived-mode terraform-mode prog-mode "Terraform"
  "Major mode for editing Terraform files."
  :syntax-table terraform-mode-syntax-table
  (setq-local comment-start "#")
  (setq-local comment-end "")
  (setq-local font-lock-defaults '(terraform-mode--font-lock-keywords nil nil))
  (setq-local syntax-propertize-function #'terraform-mode--syntax-propertize)
  (add-hook 'syntax-propertize-extend-region-functions
            #'terraform-mode--syntax-propertize-extend-region nil t))

;;;###autoload
(add-to-list 'auto-mode-alist '("\\.tf\\'" . terraform-mode))
;;;###autoload
(add-to-list 'auto-mode-alist '("\\.tfvars\\'" . terraform-mode))

(provide 'terraform-mode)

;;; terraform-mode.el ends here
