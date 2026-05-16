# terraform-mode

A from-scratch rewrite of emacs-terraform-mode using text properties for contextual font-lock.

## Key files

- `terraform-mode.el` — the mode itself
- `terraform-mode-test.el` — ERT tests

## Running tests

```bash
emacs --batch -l terraform-mode.el -l terraform-mode-test.el -f ert-run-tests-batch-and-exit
```

## Architecture

Font-lock is contextual: instead of using brace-depth counters at highlight time, regions are first marked with text properties during `syntax-propertize`, then highlight matchers filter on those properties.

### Text property propertizing

`terraform-mode--text-propertize-block` marks block interiors with a named text property. Call it from `terraform-mode--syntax-propertize`. The `depth` parameter guards top-level blocks (depth 0); use `required-property` for blocks that must be nested inside another marked block (e.g. `required_providers` inside `terraform`).

Current block properties:
- `terraform-mode-terraform-block` — inside `terraform {}`
- `terraform-mode-required-providers` — inside `required_providers {}` (requires terraform-block)
- `terraform-mode-variable-block` — inside `variable "name" {}`
- `terraform-mode-resource-block` — inside `resource "type" "name" {}` or `data "type" "name" {}`
- `terraform-mode-locals-block` — inside `locals {}`
- `terraform-mode-module-block` — inside `module "name" {}`
- `terraform-mode-output-block` — inside `output "name" {}`
- `terraform-mode-provider-block` — inside `provider "name" {}`
- `terraform-mode-for-expression` — inside a `[for ...]` or `{for ...}` expression
- `terraform-mode-tfvars-file` — entire buffer when visiting a `.tfvars` file

### Syntax propertize rules

Quote characters in builtin labels must be marked as punctuation (`.`) so `font-lock-string-face` is not applied. This is done in `terraform-mode--builtins-with-type-propertize-match` via `syntax-propertize-rules`.

Block patterns are grouped by label count: one quoted label (`block-builtins-with-type-propertize`, `block-builtins-with-name-propertize`) and two quoted labels (`block-builtins-with-type-and-name-propertize`). These three constants must be in `eval-and-compile` because `syntax-propertize-rules` is a macro.

### Naming conventions

- `*-propertize` — `defconst` regexp used for syntax propertizing
- `*-propertize-match` — `defun` called by `syntax-propertize-function`
- `*-highlight` — `defconst` regexp used for font-lock (usually aliases the propertize const)
- `*-highlight-match` — `defun` used as a font-lock matcher

### Highlight matchers

Two helpers:
- `terraform-mode--builtin-at-depth-highlight-match` — match at a specific brace depth (used only for the top-level `terraform` keyword)
- `terraform-mode--builtin-with-property-highlight-match` — match only where a text property is set (preferred for everything else)

## Test conventions

Tests use `terraform-test-face` and `terraform-test-text-property` helpers. Each test is a `dolist` over a list of cases, each case being an alist with `description`, `content`, and `check` keys. Pass an optional `file-name` to `terraform-test-face` when the test requires a specific buffer file name (e.g. `.tfvars` tests).
