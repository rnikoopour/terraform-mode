;;; terraform-mode.el --- Major mode for Terraform files -*- lexical-binding: t -*-

;; Copyright (C) 2017 by Syohei YOSHIDA

;; Original Author: Syohei YOSHIDA <syohex@gmail.com>
;; Original URL: https://github.com/syohex/emacs-terraform-mode

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
(rx-define terraform-mode--block-with-name-only   (or "variable" "module" "output" "dynamic"))
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

(defconst terraform-mode--terraform-block-propertize-regexp
  (rx line-start (zero-or-more space) "terraform" (zero-or-more space) "{"))

(defconst terraform-mode--locals-block-propertize-regexp
  (rx line-start (zero-or-more space) "locals" (zero-or-more space) "{"))

(defconst terraform-mode--required-providers-block-propertize-regexp
  (rx line-start (zero-or-more space) "required_providers" (zero-or-more space) "{"))

(defconst terraform-mode--variable-block-propertize-regexp
  (rx line-start (zero-or-more space) "variable" (one-or-more space)
      "\"" (one-or-more (not (any "\""))) "\""
      (zero-or-more space) "{"))

(defconst terraform-mode--resource-block-propertize-regexp
  (rx line-start (zero-or-more space) terraform-mode--block-with-type-and-name (one-or-more space)
      "\"" (one-or-more (not (any "\""))) "\""
      (one-or-more space)
      "\"" (one-or-more (not (any "\""))) "\""
      (zero-or-more space) "{"))

(defconst terraform-mode--module-block-propertize-regexp
  (rx line-start (zero-or-more space) "module" (one-or-more space)
      "\"" (one-or-more (not (any "\""))) "\""
      (zero-or-more space) "{"))

(defconst terraform-mode--output-block-propertize-regexp
  (rx line-start (zero-or-more space) "output" (one-or-more space)
      "\"" (one-or-more (not (any "\""))) "\""
      (zero-or-more space) "{"))

(defconst terraform-mode--label-bearing-keywords-propertize-regexp
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
  (while (re-search-forward terraform-mode--label-bearing-keywords-propertize-regexp end t)
    (let ((keyword (match-string 1)))
      (when (terraform-mode--propertize-next-label)
        (when (member keyword '("resource" "data"))
          (when (looking-at (rx (one-or-more space)))
            (goto-char (match-end 0))
            (terraform-mode--propertize-next-label)))))))

(defun terraform-mode--mark-interpolation-braces (start end)
  "Scan [START, END) and apply '|' syntax to each ${...} brace pair boundary."
  (save-excursion
    (goto-char start)
    (while (< (point) end)
      (cond
       ((eq (char-after) ?\\)
        (forward-char 2))
       ((and (eq (char-after) ?$)
             (eq (char-after (1+ (point))) ?{)
             (not (eq (char-before) ?$)))
        (let ((brace-open (1+ (point))))
          (forward-char 2)
          (let ((depth 1))
            (while (and (> depth 0) (< (point) end))
              (cond
               ((eq (char-after) ?{) (setq depth (1+ depth)) (forward-char 1))
               ((eq (char-after) ?})
                (setq depth (1- depth))
                (when (= depth 0)
                  (put-text-property brace-open (1+ brace-open)
                                     'syntax-table (string-to-syntax "|"))
                  (put-text-property (point) (1+ (point))
                                     'syntax-table (string-to-syntax "|")))
                (forward-char 1))
               (t (forward-char 1)))))))
       (t (forward-char 1))))))

(defun terraform-mode--propertize-heredoc ()
  "Propertize the heredoc starting at point.
Expects point to be at the first '<' of '<<TERM' or '<<-TERM'.
Advances point past the heredoc (or to point-max if incomplete)."
  (let ((open-pos (point)))
    (forward-char 2)
    (let ((strip (eq (char-after) ?-)))
      (when strip (forward-char 1))
      (if (looking-at (rx (group (one-or-more (any "A-Za-z0-9_")))))
          (let* ((term (match-string 1))
                 (close-re (if strip
                               (concat "^[ \t]*" (regexp-quote term) "[ \t]*$")
                             (concat "^" (regexp-quote term) "[ \t]*$"))))
            (goto-char (match-end 0))
            (end-of-line)
            (when (< (point) (point-max)) (forward-char 1))
            (let* ((content-start (point))
                   (complete (re-search-forward close-re nil t))
                   (content-end (if complete (line-end-position) (point-max))))
              (put-text-property open-pos (1+ open-pos)
                                 'syntax-table (string-to-syntax "|"))
              (when complete
                (put-text-property content-end (1+ content-end)
                                   'syntax-table (string-to-syntax "|")))
              (terraform-mode--mark-interpolation-braces content-start content-end)
              (goto-char (min (1+ content-end) (point-max)))))
        ;; << but not a valid heredoc term: back up and let the loop advance
        (forward-char -1)))))

(defun terraform-mode--propertize-interpolated-string ()
  "Propertize the double-quoted string starting at point.
When the string contains '${...}' interpolations, applies generic-string
delimiter syntax to the quote and brace boundaries so interpolation content
is parsed as code rather than as part of the string.
Advances point past the closing quote (or to point-max if unclosed)."
  (let ((open-pos (point))
        (close-pos nil)
        (found-interpolation nil))
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
                 ((eq (char-after) ?{) (setq depth (1+ depth)) (forward-char 1))
                 ((eq (char-after) ?})
                  (setq depth (1- depth))
                  (when (= depth 0)
                    (put-text-property brace-open (1+ brace-open)
                                       'syntax-table (string-to-syntax "|"))
                    (put-text-property (point) (1+ (point))
                                       'syntax-table (string-to-syntax "|"))
                    (setq found-interpolation t))
                  (forward-char 1))
                 (t (forward-char 1)))))))
         (t (forward-char 1)))))
    (when found-interpolation
      (put-text-property open-pos (1+ open-pos)
                         'syntax-table (string-to-syntax "|"))
      (when close-pos
        (put-text-property close-pos (1+ close-pos)
                           'syntax-table (string-to-syntax "|"))))))

(defun terraform-mode--propertize-string-literals ()
  "Scan the buffer and apply syntax-table properties to strings and heredocs.
Skips comments so their contents are not mistakenly propertized."
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
       ((and (eq (char-after) ?<)
             (eq (char-after (1+ (point))) ?<))
        (terraform-mode--propertize-heredoc))
       ((eq (char-after) ?\")
        (terraform-mode--propertize-interpolated-string))
       (t (forward-char 1))))))

(defun terraform-mode--syntax-propertize-extend-region (start end)
  "Extend [START, END) to cover the enclosing top-level block.
Ensures 'syntax-propertize' and font-lock both run on the full block
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

(defun terraform-mode--for-expression-text-propertize-regexp (start end)
  "Mark for expressions with text properties.
Clears terraform-mode-for-expression and terraform-mode-for-var in [START, END)
then rescans from point-min to re-apply across the buffer."
  (remove-text-properties start end
                           '(terraform-mode-for-expression nil
                             terraform-mode-for-var nil))
  (save-excursion
    (goto-char (point-min))
    (while (re-search-forward
            (rx (or "[" "{") (zero-or-more (any " \t\n")) "for" word-end)
            nil t)
      (let* ((expr-start (match-beginning 0))
             (close-char  (if (= (char-after expr-start) ?\[) ?\] ?\})))
        (skip-chars-forward " \t\n")
        (let ((var-regions '())
              (var-names '()))
          (let (body-start
                expr-end)
            ;; Parse first var name (skip if it is "in", meaning no vars)
            (when (and (looking-at (rx (group (one-or-more word))))
                       (not (string= (match-string 1) "in")))
              (push (cons (match-beginning 1) (match-end 1)) var-regions)
              (push (match-string 1) var-names)
              (goto-char (match-end 1))
              (skip-chars-forward " \t")
              ;; Optional second var after comma: `for key, val in`
              (when (looking-at (rx "," (zero-or-more space)
                                    (group (one-or-more word))))
                (push (cons (match-beginning 1) (match-end 1)) var-regions)
                (push (match-string 1) var-names)
                (goto-char (match-end 0)))
              (skip-chars-forward " \t\n"))
            ;; If "in" is present, scan the body for the closing bracket
            (when (looking-at (rx "in" word-end))
              (goto-char (match-end 0))
              ;; Scan forward tracking bracket depth.
              ;; depth=1: we are directly inside the outer [ or {.
              ;; A bare `:` at depth=1 starts the body.
              ;; Depth reaching 0 on the matching close char ends the expression.
              (let ((depth 1))
                (while (and (not expr-end) (< (point) (point-max)))
                  (let ((ch (char-after)))
                    (cond
                     ((null ch) (setq expr-end (point)))
                     ((memq ch '(?\[ ?\{ ?\())
                      (setq depth (1+ depth))
                      (forward-char 1))
                     ((memq ch '(?\] ?\} ?\)))
                      (setq depth (1- depth))
                      (cond
                       ((< depth 0) (setq expr-end (point)))
                       ((and (= depth 0) (= ch close-char))
                        (forward-char 1)
                        (setq expr-end (point)))
                       (t (forward-char 1))))
                     ((and (= ch ?:) (= depth 1) (not body-start))
                      (setq body-start (1+ (point)))
                      (forward-char 1))
                     (t (forward-char 1)))))))
            (cond
             (expr-end
              (put-text-property expr-start expr-end
                                 'terraform-mode-for-expression t)
              (dolist (vr var-regions)
                (put-text-property (car vr) (cdr vr)
                                   'terraform-mode-for-var t))
              (when body-start
                (save-excursion
                  (goto-char body-start)
                  (while (re-search-forward
                          (rx word-start (group (one-or-more word)) word-end)
                          expr-end t)
                    (when (member (match-string 1) var-names)
                      (put-text-property (match-beginning 1) (match-end 1)
                                         'terraform-mode-for-var t))))))
             ;; Incomplete expression (no "in" yet or no closing bracket):
             ;; mark what we can so highlights appear while the user is typing.
             ((< expr-start end)
              (put-text-property expr-start end
                                 'terraform-mode-for-expression t)
              (dolist (vr var-regions)
                (put-text-property (car vr) (cdr vr)
                                   'terraform-mode-for-var t))
              (when body-start
                (save-excursion
                  (goto-char body-start)
                  (while (re-search-forward
                          (rx word-start (group (one-or-more word)) word-end)
                          end t)
                    (when (member (match-string 1) var-names)
                      (put-text-property (match-beginning 1) (match-end 1)
                                         'terraform-mode-for-var t)))))))))))))

(defun terraform-mode--syntax-propertize-regexp (start end)
  "Propertize region from START to END.
Order of functions is important."
  (terraform-mode--propertize-string-literals)
  (terraform-mode--builtins-with-type-propertize-match start end)
  (terraform-mode--text-propertize-block terraform-mode--terraform-block-propertize-regexp 'terraform-mode-terraform-block start end 0)
  (terraform-mode--text-propertize-block terraform-mode--locals-block-propertize-regexp 'terraform-mode-locals-block start end 0)
  (terraform-mode--text-propertize-block terraform-mode--required-providers-block-propertize-regexp 'terraform-mode-required-providers start end 1 'terraform-mode-terraform-block)
  (terraform-mode--text-propertize-block terraform-mode--variable-block-propertize-regexp 'terraform-mode-variable-block start end 0)
  (terraform-mode--text-propertize-block terraform-mode--resource-block-propertize-regexp 'terraform-mode-resource-block start end 0)
  (terraform-mode--text-propertize-block terraform-mode--module-block-propertize-regexp 'terraform-mode-module-block start end 0)
  (terraform-mode--text-propertize-block terraform-mode--output-block-propertize-regexp 'terraform-mode-output-block start end 0)
  (terraform-mode--for-expression-text-propertize-regexp start end))

;; Syntax highlighting
(defun terraform-mode--builtin-at-depth-highlight-match (regexp depth limit)
  "Search for REGEXP up to LIMIT and match only at brace nesting DEPTH."
  (and (re-search-forward regexp limit t)
       (= (nth 0 (syntax-ppss (match-beginning 0))) depth)))

(defun terraform-mode--builtin-with-property-highlight-match (regexp properties limit)
  "Search for REGEXP up to LIMIT and match only where at least one of PROPERTIES is set."
  (let (found)
    (while (and (not found)
                (re-search-forward regexp limit t))
      (when (seq-some (lambda (p) (get-text-property (match-beginning 0) p)) properties)
        (setq found t)))
    found))

(defconst terraform-mode--block-keywords-highlight-regexp
  (rx line-start (zero-or-more space)
      (group (or "terraform"
                 "locals"
                 terraform-mode--block-with-type-only
                 terraform-mode--block-with-name-only))))

(defun terraform-mode--block-keywords-highlight-match (limit)
  "Match block-opening keywords at depth 0 up to LIMIT."
  (terraform-mode--builtin-at-depth-highlight-match terraform-mode--block-keywords-highlight-regexp 0 limit))

(defconst terraform-mode--block-builtins-inside-terraform-highlight-regexp
  (rx line-start (zero-or-more space) (group (or "required_providers" "cloud" "workspaces"))))

(defun terraform-mode--inside-terraform-block-highlight-match (limit)
  (terraform-mode--builtin-with-property-highlight-match terraform-mode--block-builtins-inside-terraform-highlight-regexp '(terraform-mode-terraform-block) limit))

(defconst terraform-mode--resource-sub-block-highlight-regexp
  (rx line-start (zero-or-more space) (group (one-or-more word)) (zero-or-more space) "{"))

(defun terraform-mode--resource-sub-block-highlight-match (limit)
  "Match sub-block labels inside resource blocks up to LIMIT."
  (terraform-mode--builtin-with-property-highlight-match terraform-mode--resource-sub-block-highlight-regexp '(terraform-mode-resource-block) limit))

(defconst terraform-mode--lifecycle-highlight-regexp
  (rx line-start (zero-or-more space) (group "lifecycle")))

(defun terraform-mode--lifecycle-highlight-match (limit)
  "Match lifecycle keyword inside resource blocks up to LIMIT."
  (terraform-mode--builtin-with-property-highlight-match terraform-mode--lifecycle-highlight-regexp '(terraform-mode-resource-block) limit))

(defconst terraform-mode--resource-builtins-highlight-regexp
  (rx line-start (zero-or-more space) (group (or "for_each" "count" "content"))))

(defun terraform-mode--resource-builtins-highlight-match (limit)
  "Match for_each, count, and content builtins inside resource blocks up to LIMIT."
  (terraform-mode--builtin-with-property-highlight-match terraform-mode--resource-builtins-highlight-regexp '(terraform-mode-resource-block) limit))

(defconst terraform-mode--each-highlight-regexp
  (rx word-start (group "each") (optional "." (group (or "key" "value"))) word-end))

(defun terraform-mode--each-highlight-match (limit)
  "Match each and each.key/each.value inside resource blocks up to LIMIT."
  (terraform-mode--builtin-with-property-highlight-match terraform-mode--each-highlight-regexp '(terraform-mode-resource-block) limit))

(defconst terraform-mode--provider-highlight-regexp
  (rx line-start (zero-or-more space) (group (one-or-more word)) (one-or-more space) "{"))

(defun terraform-mode--provider-highlight-match (limit)
  "Match provider names inside required_providers blocks up to LIMIT."
  (terraform-mode--builtin-with-property-highlight-match terraform-mode--provider-highlight-regexp '(terraform-mode-required-providers) limit))

(defconst terraform-mode--assignment-highlight-regexp
  (rx (or line-start (any "{,"))
      (zero-or-more space) (group (one-or-more word)) (zero-or-more space) "="))

(defconst terraform-mode--module-builtins-highlight-regexp
  (rx line-start
      (zero-or-more space)
      (group (or "source" "providers"))
      (zero-or-more space)
      "="))

(defun terraform-mode--module-builtin-highlight-match (limit)
  "Match type keywords inside module blocks up to LIMIT."
  (terraform-mode--builtin-with-property-highlight-match terraform-mode--module-builtins-highlight-regexp '(terraform-mode-module-block) limit))

(defconst terraform-mode--variable-types-highlight-regexp
  (rx word-start
      (group (or "string" "number" "bool" "list" "set" "map" "object" "any"))
      word-end))

(defun terraform-mode--variable-type-highlight-match (limit)
  "Match type keywords inside variable blocks up to LIMIT."
  (terraform-mode--builtin-with-property-highlight-match terraform-mode--variable-types-highlight-regexp '(terraform-mode-variable-block) limit))

(defconst terraform-mode--literal-keywords-highlight-regexp
  (rx word-start (group (or "true" "false" "null")) word-end))

(defconst terraform-mode--variable-type-builtins-highlight-regexp
  (rx word-start (group "optional") word-end))

(defun terraform-mode--variable-type-builtins-highlight-match (limit)
  "Match builtin values inside variable blocks up to LIMIT."
  (terraform-mode--builtin-with-property-highlight-match terraform-mode--variable-type-builtins-highlight-regexp '(terraform-mode-variable-block) limit))

(defconst terraform-mode--reference-keywords-highlight-regexp
  (rx word-start (group (or "var" "local" "module" "data")) word-end))

(defconst terraform-mode--negation-highlight-regexp
  (rx (group "!") (or (syntax word) "(")))


(defconst terraform-mode--builtin-functions-highlight-regexp
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

(defconst terraform-mode--all-block-properties
  '(terraform-mode-terraform-block
    terraform-mode-locals-block
    terraform-mode-required-providers
    terraform-mode-variable-block
    terraform-mode-resource-block
    terraform-mode-module-block
    terraform-mode-output-block
    terraform-mode-for-expression))

(defconst terraform-mode--for-expression-keywords-highlight-regexp
  (rx word-start (group (or "for" "in")) word-end))

(defun terraform-mode--for-expression-keywords-highlight-match (limit)
  "Match for and in keywords inside for expressions up to LIMIT."
  (terraform-mode--builtin-with-property-highlight-match
   terraform-mode--for-expression-keywords-highlight-regexp
   '(terraform-mode-for-expression) limit))

(defun terraform-mode--for-var-highlight-match (limit)
  "Match regions marked with terraform-mode-for-var property up to LIMIT."
  (let (found)
    (while (and (not found) (< (point) limit))
      (cond
       ((get-text-property (point) 'terraform-mode-for-var)
        (let ((end (next-single-property-change (point) 'terraform-mode-for-var nil limit)))
          (set-match-data (list (point) end))
          (goto-char end)
          (setq found t)))
       (t
        (let ((next (next-single-property-change (point) 'terraform-mode-for-var nil limit)))
          (goto-char next)))))
    found))

(defconst terraform-mode--block-builtins-with-type-highlight-regexp
  (rx line-start (zero-or-more space)
      (group terraform-mode--block-with-type-only)
      (one-or-more space)
      (group "\"" (one-or-more (not (any "\"" space "\n"))) (optional "\""))))

(defconst terraform-mode--block-builtins-with-name-highlight-regexp
  (rx line-start (zero-or-more space)
      (group terraform-mode--block-with-name-only)
      (one-or-more space)
      (group "\"" (one-or-more (not (any "\"" space "\n"))) (optional "\""))))

(defconst terraform-mode--block-builtins-with-type-and-name-highlight-regexp
  (rx line-start (zero-or-more space)
      (group terraform-mode--block-with-type-and-name)
      (one-or-more space)
      (group "\"" (one-or-more (not (any "\"" space "\n"))) (optional "\""))
      (one-or-more space)
      (group "\"" (one-or-more (not (any "\"" space "\n"))) (optional "\""))))

(defun terraform-mode--assignment-highlight-match (limit)
  "Match assignment targets inside any block up to LIMIT."
  (terraform-mode--builtin-with-property-highlight-match
   terraform-mode--assignment-highlight-regexp
   terraform-mode--all-block-properties limit))

(defun terraform-mode--literal-keywords-highlight-match (limit)
  "Match true/false/null inside any block up to LIMIT."
  (terraform-mode--builtin-with-property-highlight-match
   terraform-mode--literal-keywords-highlight-regexp
   terraform-mode--all-block-properties limit))

(defun terraform-mode--negation-highlight-match (limit)
  "Match negation operator inside any block up to LIMIT."
  (terraform-mode--builtin-with-property-highlight-match
   terraform-mode--negation-highlight-regexp
   terraform-mode--all-block-properties limit))

(defun terraform-mode--builtin-functions-highlight-match (limit)
  "Match builtin function calls inside any block up to LIMIT."
  (terraform-mode--builtin-with-property-highlight-match
   terraform-mode--builtin-functions-highlight-regexp
   terraform-mode--all-block-properties limit))

(defun terraform-mode--reference-keywords-highlight-match (limit)
  "Match reference keywords inside any block up to LIMIT."
  (terraform-mode--builtin-with-property-highlight-match
   terraform-mode--reference-keywords-highlight-regexp
   terraform-mode--all-block-properties limit))

(defconst terraform-mode--font-lock-keywords
  `((terraform-mode--block-keywords-highlight-match 1 font-lock-builtin-face)
    (terraform-mode--inside-terraform-block-highlight-match 1 font-lock-builtin-face)
    (terraform-mode--module-builtin-highlight-match 1 font-lock-builtin-face)
    (terraform-mode--for-expression-keywords-highlight-match 1 font-lock-builtin-face)
    (terraform-mode--for-var-highlight-match 0 font-lock-variable-name-face)
    (terraform-mode--resource-builtins-highlight-match 1 font-lock-builtin-face)
    (terraform-mode--assignment-highlight-match 1 font-lock-variable-name-face)
    (terraform-mode--literal-keywords-highlight-match 1 font-lock-constant-face)
    (terraform-mode--negation-highlight-match 1 font-lock-builtin-face)
    (terraform-mode--builtin-functions-highlight-match 1 font-lock-builtin-face)
    (terraform-mode--reference-keywords-highlight-match 1 font-lock-builtin-face)
    (terraform-mode--lifecycle-highlight-match 1 font-lock-builtin-face)
    (terraform-mode--resource-sub-block-highlight-match 1 font-lock-variable-name-face)
    (terraform-mode--each-highlight-match
     (1 font-lock-builtin-face)
     (2 font-lock-builtin-face nil t))
    (terraform-mode--provider-highlight-match 1 font-lock-type-face)
    (terraform-mode--variable-type-highlight-match 1 font-lock-type-face)
    (terraform-mode--variable-type-builtins-highlight-match 1 font-lock-builtin-face)
    (,terraform-mode--block-builtins-with-type-highlight-regexp
     (1 font-lock-builtin-face)
     (2 font-lock-type-face))
    (,terraform-mode--block-builtins-with-name-highlight-regexp
     (1 font-lock-builtin-face)
     (2 font-lock-variable-name-face))
    (,terraform-mode--block-builtins-with-type-and-name-highlight-regexp
     (1 font-lock-builtin-face)
     (2 font-lock-type-face)
     (3 font-lock-variable-name-face))))


;; Development utilities

(defun terraform-mode--reload ()
  "Unload and reload terraform-mode."
  (interactive)
  (unload-feature 'terraform-mode t)
  (require 'terraform-mode))

;; Customization

(defgroup terraform nil
  "Major mode for Terraform configuration files."
  :group 'languages)

(defcustom terraform-mode-command "terraform"
  "Command to run terraform."
  :type 'string
  :group 'terraform)

(defcustom terraform-mode-format-on-save nil
  "When non-nil, run `terraform-mode-format-buffer' before saving."
  :type 'boolean
  :group 'terraform)

;; Provider docs

(defun terraform-mode--extract-provider (resource-name)
  "Return the provider prefix of RESOURCE-NAME (the part before the first underscore)."
  (car (split-string resource-name "_")))

(defun terraform-mode--extract-resource (resource-name)
  "Return the resource suffix of RESOURCE-NAME (everything after the first underscore)."
  (mapconcat #'identity (cdr (split-string resource-name "_")) "_"))

(defun terraform-mode--provider-source-in-buffer (provider)
  "Search the current buffer for the source of PROVIDER in required_providers.
Return the source string (e.g. \"hashicorp/aws\") or nil if not found."
  (save-excursion
    (goto-char (point-min))
    (when (and (re-search-forward (rx line-start "terraform" (zero-or-more blank) "{") nil t)
               (re-search-forward (rx line-start (zero-or-more blank) "required_providers" (zero-or-more blank) "{") nil t)
               (re-search-forward (rx line-start (zero-or-more blank)
                                      (literal provider) (zero-or-more blank) "=" (zero-or-more blank) "{") nil t)
               (re-search-forward (rx line-start (zero-or-more blank)
                                      "source" (zero-or-more blank) "=" (zero-or-more blank)
                                      "\"" (group (one-or-more (any "a-z/"))) "\"") nil t))
      (match-string 1))))

(defun terraform-mode--provider-source (provider)
  "Return the registry source for PROVIDER by scanning .tf files.
Checks the current buffer first, then other .tf files in the same directory.
Returns an empty string if not found."
  (let* ((dir (when buffer-file-name (file-name-directory buffer-file-name)))
         (source (terraform-mode--provider-source-in-buffer provider)))
    (when (and (not source) dir)
      (let ((tf-files (directory-files dir nil (rx line-start (one-or-more (any alnum blank "_.-")) ".tf" line-end))))
        (while (and (not source) tf-files)
          (with-temp-buffer
            (insert-file-contents (expand-file-name (pop tf-files) dir))
            (setq source (terraform-mode--provider-source-in-buffer provider))))))
    (or source "")))

(defun terraform-mode--provider-namespace-from-cli (provider)
  "Return the namespace for PROVIDER by running `terraform providers'."
  (let ((output (shell-command-to-string (concat terraform-mode-command " providers"))))
    (with-temp-buffer
      (insert output)
      (goto-char (point-min))
      (when (re-search-forward (concat "/\\(.*?\\)/" provider "\\]") nil t)
        (match-string 1)))))

(defun terraform-mode--resource-doc-url (resource doc-dir)
  "Return the Terraform registry URL for RESOURCE under DOC-DIR (\"resources\" or \"data-sources\")."
  (let* ((provider (terraform-mode--extract-provider resource))
         (resource-name (terraform-mode--extract-resource resource))
         (source (terraform-mode--provider-source provider)))
    (when (string-empty-p source)
      (let ((ns (terraform-mode--provider-namespace-from-cli provider)))
        (setq source (if ns (concat ns "/" provider) ""))))
    (if (not (string-empty-p source))
        (format "https://registry.terraform.io/providers/%s/latest/docs/%s/%s"
                source doc-dir resource-name)
      (user-error "Cannot determine provider source for %s" provider))))

(defun terraform-mode--doc-url-at-point ()
  "Return the registry documentation URL for the resource or data block at point."
  (save-excursion
    (goto-char (line-beginning-position))
    (unless (looking-at-p (rx line-start (or "resource" "data")))
      (re-search-backward (rx line-start (or "resource" "data")) nil t))
    (let ((doc-dir (if (equal (word-at-point) "data") "data-sources" "resources")))
      (forward-symbol 2)
      (terraform-mode--resource-doc-url (thing-at-point 'symbol) doc-dir))))

(defun terraform-mode-open-doc ()
  "Open browser at the Terraform registry page for the resource at point."
  (interactive)
  (browse-url (terraform-mode--doc-url-at-point)))

(defun terraform-mode-kill-doc-url ()
  "Copy the Terraform registry URL for the resource at point to the kill ring."
  (interactive)
  (let ((url (substring-no-properties (terraform-mode--doc-url-at-point))))
    (kill-new url)
    (message "Copied URL: %s" url)))

(defun terraform-mode-insert-doc-comment ()
  "Insert a comment with the Terraform registry URL above the resource block at point."
  (interactive)
  (let ((url (terraform-mode--doc-url-at-point)))
    (save-excursion
      (unless (looking-at-p (rx line-start (or "resource" "data")))
        (re-search-backward (rx line-start (or "resource" "data")) nil t))
      (insert (format "# %s\n" url)))))

;; Formatting

(defun terraform-mode-format-region (beg end)
  "Rewrite region BEG to END in canonical format using terraform fmt."
  (interactive "r")
  (let ((buf (get-buffer-create "*terraform-fmt*")))
    (unwind-protect
        (if (zerop (call-process-region beg end terraform-mode-command nil buf nil
                                        "fmt" "-no-color" "-"))
            (save-restriction
              (narrow-to-region beg end)
              (replace-buffer-contents buf))
          (message "terraform fmt: %s"
                   (with-current-buffer buf (buffer-string))))
      (kill-buffer buf))))

(defun terraform-mode-format-buffer ()
  "Rewrite current buffer in canonical format using terraform fmt."
  (interactive)
  (terraform-mode-format-region (point-min) (point-max)))

;; imenu

(defun terraform-mode--imenu-index ()
  "Build imenu index for Terraform buffers."
  (let ((index (make-hash-table :test #'equal)))
    (save-excursion
      (save-match-data
        (goto-char (point-min))
        (while (re-search-forward
                (rx line-start (zero-or-more space)
                    (group (or "resource" "data")) (one-or-more space)
                    "\"" (group (one-or-more (not (any "\"")))) "\""
                    (one-or-more space)
                    "\"" (group (one-or-more (not (any "\"")))) "\"")
                nil t)
          (let ((keyword (match-string-no-properties 1))
                (type    (match-string-no-properties 2))
                (name    (match-string-no-properties 3))
                (pos     (match-beginning 0)))
            (push (cons (concat type "/" name) pos)
                  (gethash keyword index))))
        (goto-char (point-min))
        (while (re-search-forward
                (rx line-start (zero-or-more space)
                    (group (or "variable" "module" "output")) (one-or-more space)
                    "\"" (group (one-or-more (not (any "\"")))) "\"")
                nil t)
          (let ((keyword (match-string-no-properties 1))
                (name    (match-string-no-properties 2))
                (pos     (match-beginning 0)))
            (push (cons name pos) (gethash keyword index))))
        (goto-char (point-min))
        (while (re-search-forward
                (rx line-start (zero-or-more space)
                    (group "provider") (one-or-more space)
                    "\"" (group (one-or-more (not (any "\"")))) "\"")
                nil t)
          (let ((keyword (match-string-no-properties 1))
                (name    (match-string-no-properties 2))
                (pos     (match-beginning 0)))
            (push (cons name pos) (gethash keyword index))))))
    (let ((result '()))
      (maphash (lambda (k v) (push (cons k (nreverse v)) result)) index)
      (sort result (lambda (a b) (string< (car a) (car b)))))))

;; Mode Configuration

(defun terraform-mode--indent-line ()
  "Indent current line based on Terraform style (2-space indentation).
A line can be at most one indent level deeper than the previous non-blank
line, regardless of how many brackets opened on that line."
  (let ((indent
         (save-excursion
           (back-to-indentation)
           (cond
            ;; Closing bracket: use the indentation of the line that opened it
            ((looking-at (rx (any "}])")))
             (let ((opener (nth 1 (syntax-ppss))))
               (if opener
                   (save-excursion (goto-char opener) (current-indentation))
                 0)))
            ;; Regular line: previous non-blank line's indent, plus one
            ;; tab-width if that line increased nesting depth at all
            (t
             (forward-line -1)
             (while (and (not (bobp))
                         (looking-at (rx line-start (zero-or-more space) line-end)))
               (forward-line -1))
             (if (looking-at (rx line-start (zero-or-more space) line-end))
                 0
               (let* ((bol (line-beginning-position))
                      (eol (line-end-position))
                      (prev-indent (current-indentation))
                      (depth-delta (- (nth 0 (syntax-ppss eol))
                                      (nth 0 (syntax-ppss bol)))))
                 (if (> depth-delta 0)
                     (+ prev-indent tab-width)
                   prev-indent))))))))
    (save-excursion (indent-line-to indent))
    (when (< (current-column) (current-indentation))
      (back-to-indentation))))

(defun terraform-mode--unindent ()
  "Unindent the current line or active region by one indent level."
  (interactive)
  (if (use-region-p)
      (indent-rigidly (region-beginning) (region-end) (- tab-width))
    (indent-rigidly (line-beginning-position) (line-end-position) (- tab-width))))

;; hideshow

(add-to-list 'hs-special-modes-alist
             '(terraform-mode "{" "}" "#" nil nil))


;;;###autoload
(define-derived-mode terraform-mode prog-mode "Terraform"
  "Major mode for editing Terraform files."
  :syntax-table terraform-mode-syntax-table
  (setq-local comment-start "#")
  (setq-local comment-end "")
  (setq-local tab-width 2)
  (setq-local indent-tabs-mode nil)
  (setq-local indent-line-function #'terraform-mode--indent-line)
  (setq-local font-lock-defaults '(terraform-mode--font-lock-keywords nil nil))
  (setq-local syntax-propertize-function #'terraform-mode--syntax-propertize-regexp)
  (add-hook 'syntax-propertize-extend-region-functions
            #'terraform-mode--syntax-propertize-extend-region nil t)
  (setq-local imenu-create-index-function #'terraform-mode--imenu-index)
  (setq-local imenu-sort-function #'imenu--sort-by-name)
  (when terraform-mode-format-on-save
    (add-hook 'before-save-hook #'terraform-mode-format-buffer nil t)))

(define-key terraform-mode-map (kbd "<backtab>") #'terraform-mode--unindent)
(define-key terraform-mode-map (kbd "C-c C-t C-w") #'terraform-mode-open-doc)
(define-key terraform-mode-map (kbd "C-c C-t C-c") #'terraform-mode-kill-doc-url)
(define-key terraform-mode-map (kbd "C-c C-t C-r") #'terraform-mode-insert-doc-comment)

;;;###autoload
(add-to-list 'auto-mode-alist '("\\.tf\\'" . terraform-mode))
;;;###autoload
(add-to-list 'auto-mode-alist '("\\.tfvars\\'" . terraform-mode))

(provide 'terraform-mode)

;;; terraform-mode.el ends here
