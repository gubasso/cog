---
digest-of: tech/tools/ast-grep
last-synced: 2026-05-27
source-files:
  - README.md
  - rule-reference.md
token-estimate: 700
---

# AGENTS

## Scope

ast-grep structural code search and rewrite: rule syntax reference covering all rule types,
metavariables, and common patterns.

## Key Points

### Rule Categories

- **Atomic**: `pattern` (string or object with selector/context/strictness), `kind` (Tree-sitter
  node kind), `regex` (Rust regex on node text), `nthChild` (positional), `range` (character
  positions).
- **Relational**: `inside` (ancestor), `has` (descendant), `precedes` (before), `follows` (after).
  All support `stopBy` (neighbor/end/rule) and `field` (for inside/has).
- **Composite**: `all` (AND, ordered), `any` (OR), `not` (negation), `matches` (rule reuse by ID).

### Metavariables

- `$VAR`: single named node capture. Reuse enforces same content (`$A == $A`).
- `$$VAR`: single unnamed node (operators, punctuation).
- `$$$VAR`: zero or more nodes (non-greedy). For variable args, statements.
- `$_VAR`: non-capturing (matches different content even if named identically).
- Must be the only text in an AST node; `obj.on$EVENT` does not work.

### Key Patterns

```yaml
# Find functions with await but no try-catch
rule:
  all:
    - kind: function_declaration
    - has:
        pattern: await $EXPR
        stopBy: end
    - not:
        has:
          pattern: try { $$$ } catch ($E) { $$$ }
          stopBy: end
```

### Best Practices

- When unsure, always use `stopBy: end` for deep relational searches.
- Use `all` composite rules to guarantee metavariable execution order.
- Use `dump_syntax_tree` to debug non-matching rules.
- Break complex patterns into simpler sub-rules using `all`.

### Troubleshooting

1. Rule does not match -> check AST structure with `dump_syntax_tree`.
2. Relational rule misses -> add `stopBy: end`.
3. Wrong node kind -> check Tree-sitter grammar for the language.
4. Metavariable not working -> ensure it is the only content in its AST node.

## Source Map

| Topic                                                      | File                |
| ---------------------------------------------------------- | ------------------- |
| Overview and purpose                                       | `README.md`         |
| Full rule syntax, metavariables, patterns, troubleshooting | `rule-reference.md` |

## Maintenance Notes

- Rule syntax is tied to the ast-grep version; re-verify when upgrading.
- The `pattern` object form (selector, context, strictness) is the most powerful but least
  intuitive; examples in `rule-reference.md` are the primary teaching tool.
