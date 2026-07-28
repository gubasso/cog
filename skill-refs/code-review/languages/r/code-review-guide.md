# R — Review Guide

## When to load

Any `.R`/`.r` file, R Markdown (`.Rmd`), or Quarto (`.qmd`) document with R code.

## Top review heuristics

### Functional / vectorization

- For loop over a vector that could be vectorized → `[important]` "`x * 2` beats `for (i in seq_along(x)) x[i] <- x[i] * 2`."
- `apply` family vs `purrr::map_*` mixed inconsistently → `[suggestion]` "Pick one style."
- Growing a vector in a loop (`x <- c(x, new)`) → `[blocking]` "O(N²); preallocate or use a list and `unlist` at the end."

### Tidy vs base

- Tidyverse functions used without explicit imports (`library(dplyr)` missing in a script) → `[important]`.
- Mixing base R `$`/`[[` and tidyverse `pull`/`select` in the same pipeline → `[suggestion]`.

### NSE / metaprogramming

- `eval(parse(text=...))` → `[blocking]` "Code injection in any user-input context."
- `match.arg` not used when an enum-like argument is expected → `[suggestion]`.
- Quasi-quotation (`{{ }}`, `!!`) used in code that doesn't need it → `[suggestion]` "Adds complexity without payoff."

### Missing data

- `==` comparison with `NA` (returns `NA`, often surprising) → `[important]` "Use `is.na()` or `%in%`."
- `if (na_value)` (errors at runtime when `na_value` is NA) → `[blocking]`.
- Aggregation that doesn't pass `na.rm=TRUE` and the data may have NAs → `[important]`.

### Statistical hygiene

- p-value extraction from `summary()` without using `broom::tidy` → `[suggestion]`.
- Multiple-testing without adjustment when comparing many features → `[important]`.
- `set.seed()` missing for randomized procedures → `[blocking]` "Reproducibility."

### Performance

- `data.frame` for very wide/tall data instead of `data.table` or `tibble` → `[suggestion]`.
- `read.csv` instead of `data.table::fread` / `readr::read_csv` for large files → `[important]` "10×+ speedup."
- `<-` and `=` inconsistent assignment → `[nit]` (style; pick one).

### Output / reporting

- Print-to-console from inside a function (no `message`/`warning` distinction) → `[important]` "Use `message` for status, `warning` for non-fatal issues."
- Hard-coded plot dimensions → `[suggestion]`.
- `print(df)` used to debug, left in shipping code → `[important]`.

### Common bugs

- 1-indexing of vectors but borrowing 0-indexing assumptions from another language → `[blocking]`.
- `length()` vs `nrow()` confusion on data frames → `[important]`.
- Implicit factor conversion in `data.frame()` (less common in modern R but check `stringsAsFactors=FALSE` if older code) → `[important]`.

## CLI specifics

R is rarely a CLI host. If reviewing an Rscript-based CLI:

- Use `optparse` or `docopt` for argument parsing; flag hand-rolled arg-vector slicing.
- Logging via `futile.logger` or `logger`; not `cat`.
- `stop("...")` for errors; non-zero exit follows.

## See also

- General: [../common-bugs.md](../../common-bugs.md).
- Statistical reproducibility: project-specific.
