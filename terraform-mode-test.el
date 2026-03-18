;;; terraform-mode-test.el --- Tests for terraform-mode -*- lexical-binding: t -*-

;;; Commentary:
;; ERT tests for terraform-mode.

;;; Code:

(require 'ert)
(require 'terraform-mode)

;;; Helpers

(defmacro terraform-test-with-buffer (content &rest body)
  "Run BODY in a temp buffer with CONTENT in terraform-mode."
  (declare (indent 1))
  `(with-temp-buffer
     (terraform-mode)
     (insert ,content)
     (font-lock-ensure)
     ,@body))

(defun terraform-test-comment-p (pos)
  "Return non-nil if POS is inside a comment."
  (nth 4 (syntax-ppss pos)))

(defun terraform-test-string-p (pos)
  "Return non-nil if POS is inside a string."
  (nth 3 (syntax-ppss pos)))

;;; Mode activation

(ert-deftest terraform-mode-auto-mode-tf ()
  "terraform-mode activates for .tf files."
  (should (equal (cdr (assoc "\\.tf\\'" auto-mode-alist)) 'terraform-mode)))

(ert-deftest terraform-mode-auto-mode-tfvars ()
  "terraform-mode activates for .tfvars files."
  (should (equal (cdr (assoc "\\.tfvars\\'" auto-mode-alist)) 'terraform-mode)))

;;; Comment syntax

(ert-deftest terraform-mode-hash-comment ()
  "# starts a line comment."
  (terraform-test-with-buffer "# comment"
    (should (terraform-test-comment-p 3))))

(ert-deftest terraform-mode-hash-comment-ends-at-newline ()
  "# comment ends at newline."
  (terraform-test-with-buffer "# comment\nnot-a-comment"
    (should (terraform-test-comment-p 3))
    (should-not (terraform-test-comment-p 11))))

(ert-deftest terraform-mode-double-slash-comment ()
  "// starts a line comment."
  (terraform-test-with-buffer "// comment"
    (should (terraform-test-comment-p 4))))

(ert-deftest terraform-mode-double-slash-comment-ends-at-newline ()
  "// comment ends at newline."
  (terraform-test-with-buffer "// comment\nnot-a-comment"
    (should (terraform-test-comment-p 4))
    (should-not (terraform-test-comment-p 12))))

(ert-deftest terraform-mode-block-comment ()
  "/* */ is a block comment."
  (terraform-test-with-buffer "/* comment */"
    (should (terraform-test-comment-p 4))))

(ert-deftest terraform-mode-block-comment-multiline ()
  "/* */ block comment spans multiple lines."
  (terraform-test-with-buffer "/*\ncomment\n*/"
    ;; position 3 is the newline after /*, already inside the comment
    (should (terraform-test-comment-p 3))
    (should (terraform-test-comment-p 5))))

;;; String syntax

(ert-deftest terraform-mode-string ()
  "Double-quoted string is recognized."
  (terraform-test-with-buffer "\"hello\""
    (should (terraform-test-string-p 2))))

(ert-deftest terraform-mode-string-ends ()
  "String ends at closing quote."
  (terraform-test-with-buffer "\"hello\" world"
    (should (terraform-test-string-p 2))
    (should-not (terraform-test-string-p 9))))

;;; Bracket syntax

(ert-deftest terraform-mode-curly-brackets ()
  "Curly braces are matched pairs."
  (terraform-test-with-buffer "{}"
    (goto-char 1)
    (should (equal (char-before (scan-sexps 1 1)) ?}))))

(ert-deftest terraform-mode-square-brackets ()
  "Square brackets are matched pairs."
  (terraform-test-with-buffer "[]"
    (goto-char 1)
    (should (equal (char-before (scan-sexps 1 1)) ?\]))))

(ert-deftest terraform-mode-parens ()
  "Parentheses are matched pairs."
  (terraform-test-with-buffer "()"
    (goto-char 1)
    (should (equal (char-before (scan-sexps 1 1)) ?\)))))

;;; Font-lock variables

(ert-deftest terraform-mode-variable ()
  "Assignment target gets variable face."
  (terraform-test-with-buffer "this_is_a_variable = \"some value\""
    (should (eq (get-text-property 1 'face) 'font-lock-variable-name-face))))

(ert-deftest terraform-mode-variable-indented ()
  "Indented assignment target gets variable face."
  (terraform-test-with-buffer "  this_is_a_variable = \"some value\""
    (should (eq (get-text-property 3 'face) 'font-lock-variable-name-face))))

;;; Font-lock keywords

(ert-deftest terraform-mode-keyword-terraform ()
  "\"terraform\" at the start of a line gets keyword face."
  (terraform-test-with-buffer "terraform {}"
    (should (eq (get-text-property 1 'face) 'font-lock-builtin-face))))

(ert-deftest terraform-mode-keyword-terraform-indented ()
  "\"terraform\" with leading spaces gets keyword face."
  (terraform-test-with-buffer "  terraform {}"
    (should (eq (get-text-property 3 'face) 'font-lock-builtin-face))))

(ert-deftest terraform-mode-keyword-required-providers ()
  "\"required_providers\" at depth 1 gets builtin face."
  ;; terraform {\n = 12 chars, so required_providers starts at 13
  (terraform-test-with-buffer "terraform {\nrequired_providers {}\n}"
    (should (eq (get-text-property 13 'face) 'font-lock-builtin-face))))

(ert-deftest terraform-mode-keyword-cloud ()
  "\"cloud\" at depth 1 gets builtin face."
  ;; terraform {\n = 12 chars, so cloud starts at 13
  (terraform-test-with-buffer "terraform {\ncloud {}\n}"
    (should (eq (get-text-property 13 'face) 'font-lock-builtin-face))))

(ert-deftest terraform-mode-keyword-workspaces ()
  "\"workspaces\" at depth 2 gets builtin face."
  ;; terraform {\ncloud {\n = 20 chars, so workspaces starts at 21
  (terraform-test-with-buffer "terraform {\ncloud {\nworkspaces {}\n}\n}"
    (should (eq (get-text-property 21 'face) 'font-lock-builtin-face))))

(provide 'terraform-mode-test)
;;; terraform-mode-test.el ends here
