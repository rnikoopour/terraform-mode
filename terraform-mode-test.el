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

(defun terraform-test-text-property (description content checks)
  "Assert text properties in a terraform-mode buffer with CONTENT.
DESCRIPTION is used in failure messages.
CHECKS is a list of alists, each with pos, property, and value keys."
  (with-temp-buffer
    (terraform-mode)
    (insert content)
    (font-lock-ensure)
    (dolist (check checks)
      (let ((pos      (alist-get 'pos check))
            (property (alist-get 'property check))
            (expected (alist-get 'value check)))
        (unless (eq (get-text-property pos property) expected)
          (ert-fail (format "%s: expected %S=%S at pos %d, got %S"
                            description property expected pos
                            (get-text-property pos property))))))))

(defun terraform-test-face (description content checks)
  "Assert face properties in a terraform-mode buffer with CONTENT.
DESCRIPTION is used in failure messages.
CHECKS is a list of alists, each with pos and face keys."
  (with-temp-buffer
    (terraform-mode)
    (insert content)
    (font-lock-ensure)
    (dolist (check checks)
      (let ((pos (alist-get 'pos check))
            (expected (alist-get 'face check)))
        (unless (eq (get-text-property pos 'face) expected)
          (ert-fail (format "%s: expected face %S at pos %d, got %S"
                            description expected pos
                            (get-text-property pos 'face))))))))

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

;;; String interpolation syntax

(ert-deftest terraform-mode-string-interpolation ()
  "Content inside ${...} is not parsed as a string."
  ;; "${var.foo}" - positions: "(1)$(2){(3)v(4)a(5)r(6).(7)f(8)o(9)o(10)}(11)"(12)
  (terraform-test-with-buffer "\"${var.foo}\""
    (should-not (terraform-test-string-p 4))))

(ert-deftest terraform-mode-string-interpolation-literal-part ()
  "Content outside ${...} in a string is still parsed as a string."
  ;; "prefix-${var.foo}" - 'p' at pos 2 is in the literal part
  (terraform-test-with-buffer "\"prefix-${var.foo}\""
    (should (terraform-test-string-p 2))
    (should-not (terraform-test-string-p 11))))

(ert-deftest terraform-mode-string-interpolation-escaped ()
  "$\\${ is not treated as an interpolation."
  ;; "$${literal}" - the $$ escapes the interpolation
  (terraform-test-with-buffer "\"$${literal}\""
    (should (terraform-test-string-p 5))))

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

;;; Font-lock

(ert-deftest test-terraform-mode--match-depth-0-builtin ()
  (dolist (case '(((description . "terraform at depth 0")
                   (content     . "terraform {}")
                   (check       . (((pos . 1) (face . font-lock-builtin-face)))))
                  ((description . "terraform indented at depth 0")
                   (content     . "  terraform {}")
                   (check       . (((pos . 3) (face . font-lock-builtin-face)))))
                  ((description . "terraform at depth 1 gets no builtin face")
                   (content     . "resource \"foo\" \"bar\" {\nterraform {}\n}")
                   (check       . (((pos . 23) (face . nil)))))))
    (terraform-test-face (alist-get 'description case)
                         (alist-get 'content case)
                         (alist-get 'check case))))

(ert-deftest test-terraform-mode--match-inside-terraform-block ()
  (dolist (case '(((description . "required_providers inside terraform block")
                   (content     . "terraform {\nrequired_providers {}\n}")
                   (check       . (((pos . 13) (face . font-lock-builtin-face)))))
                  ((description . "cloud inside terraform block")
                   (content     . "terraform {\ncloud {}\n}")
                   (check       . (((pos . 13) (face . font-lock-builtin-face)))))
                  ((description . "workspaces inside terraform block")
                   (content     . "terraform {\ncloud {\nworkspaces {}\n}\n}")
                   (check       . (((pos . 21) (face . font-lock-builtin-face)))))
                  ((description . "required_providers outside terraform block gets no builtin face")
                   (content     . "required_providers {}")
                   (check       . (((pos . 1) (face . nil)))))
                  ((description . "cloud outside terraform block gets no builtin face")
                   (content     . "cloud {}")
                   (check       . (((pos . 1) (face . nil)))))))
    (terraform-test-face (alist-get 'description case)
                         (alist-get 'content case)
                         (alist-get 'check case))))

(ert-deftest test-terraform-mode--assignment ()
  (dolist (case '(((description . "assignment target")
                   (content     . "this_is_a_variable = \"some value\"")
                   (check       . (((pos . 1) (face . font-lock-variable-name-face)))))
                  ((description . "indented assignment target")
                   (content     . "  this_is_a_variable = \"some value\"")
                   (check       . (((pos . 3) (face . font-lock-variable-name-face)))))))
    (terraform-test-face (alist-get 'description case)
                         (alist-get 'content case)
                         (alist-get 'check case))))

(ert-deftest test-terraform-mode--match-provider ()
  (dolist (case '(((description . "single provider inside required_providers")
                   (content     . "terraform {\nrequired_providers {\naws {\n}\n}\n}")
                   (check       . (((pos . 34) (face . font-lock-type-face)))))
                  ((description . "multiple providers inside required_providers")
                   (content     . "terraform {\nrequired_providers {\naws {\n}\nazure {\n}\n}\n}")
                   (check       . (((pos . 34) (face . font-lock-type-face))
                                   ((pos . 42) (face . font-lock-type-face)))))
                  ((description . "provider outside required_providers gets no type face")
                   (content     . "aws {}")
                   (check       . (((pos . 1) (face . nil)))))))
    (terraform-test-face (alist-get 'description case)
                         (alist-get 'content case)
                         (alist-get 'check case))))

(ert-deftest test-terraform-mode--block-builtins-with-type ()
  (dolist (case '(((description . "backend keyword and type")
                   (content     . "backend \"s3\" {}")
                   (check       . (((pos . 1) (face . font-lock-builtin-face))
                                   ((pos . 9) (face . font-lock-type-face)))))
                  ((description . "provider_meta keyword and type")
                   (content     . "provider_meta \"foo\" {}")
                   (check       . (((pos . 1)  (face . font-lock-builtin-face))
                                   ((pos . 15) (face . font-lock-type-face)))))
                  ((description . "variable keyword and name")
                   (content     . "variable \"foo\" {}")
                   (check       . (((pos . 1)  (face . font-lock-builtin-face))
                                   ((pos . 10) (face . font-lock-variable-name-face)))))
                  ((description . "builtin-with-type in block comment gets comment face")
                   (content     . "/* backend \"s3\" {} */")
                   (check       . (((pos . 4) (face . font-lock-comment-face)))))))
    (terraform-test-face (alist-get 'description case)
                         (alist-get 'content case)
                         (alist-get 'check case))))

(ert-deftest test-terraform-mode--terraform-block ()
  (dolist (case '(((description . "content inside terraform block has property")
                   (content     . "terraform {\nrequired_version = \"1.0\"\n}")
                   (check       . (((pos . 13) (property . terraform-mode-terraform-block) (value . t)))))
                  ((description . "content outside terraform block has no property")
                   (content     . "required_version = \"1.0\"")
                   (check       . (((pos . 1) (property . terraform-mode-terraform-block) (value . nil)))))))
    (terraform-test-text-property (alist-get 'description case)
                                  (alist-get 'content case)
                                  (alist-get 'check case))))

(ert-deftest test-terraform-mode--locals-block ()
  (dolist (case '(((description . "content inside locals block has property")
                   (content     . "locals {\nfoo = 1\n}")
                   (check       . (((pos . 10) (property . terraform-mode-locals-block) (value . t)))))
                  ((description . "content outside locals block has no property")
                   (content     . "foo = 1")
                   (check       . (((pos . 1) (property . terraform-mode-locals-block) (value . nil)))))))
    (terraform-test-text-property (alist-get 'description case)
                                  (alist-get 'content case)
                                  (alist-get 'check case))))

(ert-deftest test-terraform-mode--locals-keyword ()
  (dolist (case '(((description . "locals keyword gets builtin face")
                   (content     . "locals {}")
                   (check       . (((pos . 1) (face . font-lock-builtin-face)))))))
    (terraform-test-face (alist-get 'description case)
                         (alist-get 'content case)
                         (alist-get 'check case))))

(ert-deftest test-terraform-mode--variable-block ()
  (dolist (case '(((description . "content inside variable block has property")
                   (content     . "variable \"foo\" {\ndefault = 1\n}")
                   (check       . (((pos . 18) (property . terraform-mode-variable-block) (value . t)))))
                  ((description . "content outside variable block has no property")
                   (content     . "default = 1")
                   (check       . (((pos . 1) (property . terraform-mode-variable-block) (value . nil)))))
                  ((description . "variable block nested at depth 1 has no property")
                   (content     . "resource \"aws_instance\" \"foo\" {\nvariable \"bar\" {\ndefault = 1\n}\n}")
                   (check       . (((pos . 48) (property . terraform-mode-variable-block) (value . nil)))))))
    (terraform-test-text-property (alist-get 'description case)
                                  (alist-get 'content case)
                                  (alist-get 'check case))))

(ert-deftest test-terraform-mode--required-providers-block ()
  (dolist (case '(((description . "content inside required_providers block has property")
                   (content     . "terraform {\nrequired_providers {\naws = {}\n}\n}")
                   (check       . (((pos . 33) (property . terraform-mode-required-providers) (value . t)))))
                  ((description . "required_providers outside terraform block has no property")
                   (content     . "required_providers {\naws = {}\n}")
                   (check       . (((pos . 21) (property . terraform-mode-required-providers) (value . nil)))))))
    (terraform-test-text-property (alist-get 'description case)
                                  (alist-get 'content case)
                                  (alist-get 'check case))))

(ert-deftest test-terraform-mode--match-variable-type ()
  (dolist (case '(((description . "string type inside variable block")
                   (content     . "variable \"foo\" {\ntype = string\n}")
                   (check       . (((pos . 25) (face . font-lock-type-face)))))
                  ((description . "number type inside variable block")
                   (content     . "variable \"foo\" {\ntype = number\n}")
                   (check       . (((pos . 25) (face . font-lock-type-face)))))
                  ((description . "bool type inside variable block")
                   (content     . "variable \"foo\" {\ntype = bool\n}")
                   (check       . (((pos . 25) (face . font-lock-type-face)))))
                  ((description . "list type inside variable block")
                   (content     . "variable \"foo\" {\ntype = list(string)\n}")
                   (check       . (((pos . 25) (face . font-lock-type-face)))))
                  ((description . "bare list inside variable block gets variable face not type face")
                   (content     . "variable \"foo\" {\nlist = 1\n}")
                   (check       . (((pos . 18) (face . font-lock-variable-name-face)))))
                  ((description . "set type inside variable block")
                   (content     . "variable \"foo\" {\ntype = set(number)\n}")
                   (check       . (((pos . 25) (face . font-lock-type-face)))))
                  ((description . "map type inside variable block")
                   (content     . "variable \"foo\" {\ntype = map(string)\n}")
                   (check       . (((pos . 25) (face . font-lock-type-face)))))
                  ((description . "object type inside variable block")
                   (content     . "variable \"foo\" {\ntype = object({ name = string })\n}")
                   (check       . (((pos . 25) (face . font-lock-type-face)))))
                  ((description . "list( partial type inside variable block")
                   (content     . "variable \"foo\" {\ntype = list(\n}")
                   (check       . (((pos . 25) (face . font-lock-type-face)))))
                  ((description . "set( partial type inside variable block")
                   (content     . "variable \"foo\" {\ntype = set(\n}")
                   (check       . (((pos . 25) (face . font-lock-type-face)))))
                  ((description . "map( partial type inside variable block")
                   (content     . "variable \"foo\" {\ntype = map(\n}")
                   (check       . (((pos . 25) (face . font-lock-type-face)))))
                  ((description . "object( partial type inside variable block")
                   (content     . "variable \"foo\" {\ntype = object(\n}")
                   (check       . (((pos . 25) (face . font-lock-type-face)))))
                  ((description . "type keyword outside variable block gets no type face")
                   (content     . "string")
                   (check       . (((pos . 1) (face . nil)))))))
    (terraform-test-face (alist-get 'description case)
                         (alist-get 'content case)
                         (alist-get 'check case))))

(ert-deftest test-terraform-mode--match-variable-type-builtins ()
  (dolist (case '(((description . "true inside variable block")
                   (content     . "variable \"foo\" {\ndefault = true\n}")
                   (check       . (((pos . 28) (face . font-lock-builtin-face)))))
                  ((description . "false inside variable block")
                   (content     . "variable \"foo\" {\ndefault = false\n}")
                   (check       . (((pos . 28) (face . font-lock-builtin-face)))))
                  ((description . "optional inside variable block")
                   (content     . "variable \"foo\" {\ntype = object({ name = optional(string) })\n}")
                   (check       . (((pos . 41) (face . font-lock-builtin-face)))))
                  ((description . "true outside variable block gets no builtin face")
                   (content     . "true")
                   (check       . (((pos . 1) (face . nil)))))))
    (terraform-test-face (alist-get 'description case)
                         (alist-get 'content case)
                         (alist-get 'check case))))

(ert-deftest test-terraform-mode--resource-block ()
  (dolist (case '(((description . "content inside resource block has property")
                   (content     . "resource \"aws_instance\" \"foo\" {\nami = \"abc\"\n}")
                   (check       . (((pos . 33) (property . terraform-mode-resource-block) (value . t)))))
                  ((description . "content inside data block has property")
                   (content     . "data \"aws_ami\" \"foo\" {\nowners = [\"self\"]\n}")
                   (check       . (((pos . 24) (property . terraform-mode-resource-block) (value . t)))))
                  ((description . "content outside resource block has no property")
                   (content     . "ami = \"abc\"")
                   (check       . (((pos . 1) (property . terraform-mode-resource-block) (value . nil)))))))
    (terraform-test-text-property (alist-get 'description case)
                                  (alist-get 'content case)
                                  (alist-get 'check case))))

(ert-deftest test-terraform-mode--block-builtins-with-type-and-name ()
  (dolist (case '(((description . "resource keyword gets builtin face")
                   (content     . "resource \"aws_instance\" \"foo\" {}")
                   (check       . (((pos . 1) (face . font-lock-builtin-face)))))
                  ((description . "resource type gets type face")
                   (content     . "resource \"aws_instance\" \"foo\" {}")
                   (check       . (((pos . 10) (face . font-lock-type-face)))))
                  ((description . "resource name gets variable-name face")
                   (content     . "resource \"aws_instance\" \"foo\" {}")
                   (check       . (((pos . 25) (face . font-lock-variable-name-face)))))
                  ((description . "data keyword gets builtin face")
                   (content     . "data \"aws_ami\" \"foo\" {}")
                   (check       . (((pos . 1) (face . font-lock-builtin-face)))))
                  ((description . "data type gets type face")
                   (content     . "data \"aws_ami\" \"foo\" {}")
                   (check       . (((pos . 6) (face . font-lock-type-face)))))
                  ((description . "data name gets variable-name face")
                   (content     . "data \"aws_ami\" \"foo\" {}")
                   (check       . (((pos . 16) (face . font-lock-variable-name-face)))))))
    (terraform-test-face (alist-get 'description case)
                         (alist-get 'content case)
                         (alist-get 'check case))))

(ert-deftest test-terraform-mode--block-keywords-progressive ()
  (dolist (case '(((description . "terraform keyword alone gets builtin face")
                   (content     . "terraform")
                   (check       . (((pos . 1) (face . font-lock-builtin-face)))))
                  ((description . "resource keyword alone gets builtin face")
                   (content     . "resource")
                   (check       . (((pos . 1) (face . font-lock-builtin-face)))))
                  ((description . "data keyword alone gets builtin face")
                   (content     . "data")
                   (check       . (((pos . 1) (face . font-lock-builtin-face)))))
                  ((description . "variable keyword alone gets builtin face")
                   (content     . "variable")
                   (check       . (((pos . 1) (face . font-lock-builtin-face)))))
                  ((description . "resource with type label but no name or brace gets type face")
                   (content     . "resource \"aws_instance\"")
                   (check       . (((pos . 10) (face . font-lock-type-face)))))
                  ((description . "variable with name but no brace gets variable-name face")
                   (content     . "variable \"my_var\"")
                   (check       . (((pos . 10) (face . font-lock-variable-name-face)))))
                  ((description . "resource with both labels but no brace gets variable-name face on name")
                   (content     . "resource \"aws_instance\" \"my_ec2\"")
                   (check       . (((pos . 25) (face . font-lock-variable-name-face)))))))
    (terraform-test-face (alist-get 'description case)
                         (alist-get 'content case)
                         (alist-get 'check case))))

(ert-deftest test-terraform-mode--lifecycle ()
  (dolist (case '(((description . "lifecycle inside resource block gets builtin face")
                   (content     . "resource \"aws_instance\" \"foo\" {\nlifecycle {\n}\n}")
                   (check       . (((pos . 33) (face . font-lock-builtin-face)))))
                  ((description . "lifecycle outside resource block gets no builtin face")
                   (content     . "lifecycle {}")
                   (check       . (((pos . 1) (face . nil)))))))
    (terraform-test-face (alist-get 'description case)
                         (alist-get 'content case)
                         (alist-get 'check case))))

(ert-deftest test-terraform-mode--each ()
  (dolist (case '(((description . "each.key inside resource block gets builtin face on each")
                   (content     . "resource \"aws_instance\" \"foo\" {\neach.key\n}")
                   (check       . (((pos . 33) (face . font-lock-builtin-face)))))
                  ((description . "each.key inside resource block gets builtin face on key")
                   (content     . "resource \"aws_instance\" \"foo\" {\neach.key\n}")
                   (check       . (((pos . 38) (face . font-lock-builtin-face)))))
                  ((description . "each.value inside resource block gets builtin face on value")
                   (content     . "resource \"aws_instance\" \"foo\" {\neach.value\n}")
                   (check       . (((pos . 38) (face . font-lock-builtin-face)))))
                  ((description . "each alone inside resource block gets builtin face")
                   (content     . "resource \"aws_instance\" \"foo\" {\neach\n}")
                   (check       . (((pos . 33) (face . font-lock-builtin-face)))))
                  ((description . "each.key outside resource block gets no builtin face")
                   (content     . "each.key")
                   (check       . (((pos . 1) (face . nil)))))))
    (terraform-test-face (alist-get 'description case)
                         (alist-get 'content case)
                         (alist-get 'check case))))

(ert-deftest test-terraform-mode--module-block ()
  (dolist (case '(((description . "content inside module block has property")
                   (content     . "module \"vpc\" {\nsource = \"terraform-aws-vpc\"\n}")
                   (check       . (((pos . 16) (property . terraform-mode-module-block) (value . t)))))
                  ((description . "content outside module block has no property")
                   (content     . "source = \"terraform-aws-vpc\"")
                   (check       . (((pos . 1) (property . terraform-mode-module-block) (value . nil)))))
                  ((description . "module block nested at depth 1 has no property")
                   (content     . "resource \"aws_instance\" \"foo\" {\nmodule \"vpc\" {\nsource = \"x\"\n}\n}")
                   (check       . (((pos . 48) (property . terraform-mode-module-block) (value . nil)))))))
    (terraform-test-text-property (alist-get 'description case)
                                  (alist-get 'content case)
                                  (alist-get 'check case))))

(ert-deftest test-terraform-mode--module-builtins ()
  (dolist (case '(((description . "source inside module block gets builtin face")
                   (content     . "module \"vpc\" {\nsource = \"terraform-aws-vpc\"\n}")
                   (check       . (((pos . 16) (face . font-lock-builtin-face)))))
                  ((description . "providers inside module block gets builtin face")
                   (content     . "module \"vpc\" {\nproviders = {}\n}")
                   (check       . (((pos . 16) (face . font-lock-builtin-face)))))))
    (terraform-test-face (alist-get 'description case)
                         (alist-get 'content case)
                         (alist-get 'check case))))

(ert-deftest test-terraform-mode--reference-keywords ()
  (dolist (case '(((description . "var gets builtin face")
                   (content     . "var.instance_type")
                   (check       . (((pos . 1) (face . font-lock-builtin-face)))))
                  ((description . "local gets builtin face")
                   (content     . "local.common_tags")
                   (check       . (((pos . 1) (face . font-lock-builtin-face)))))
                  ((description . "module reference gets builtin face")
                   (content     . "module.vpc.vpc_id")
                   (check       . (((pos . 1) (face . font-lock-builtin-face)))))))
    (terraform-test-face (alist-get 'description case)
                         (alist-get 'content case)
                         (alist-get 'check case))))

(provide 'terraform-mode-test)
;;; terraform-mode-test.el ends here
