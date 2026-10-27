# Resolve concat-axis values (shared by both paths)

Prefers
[`stringr::str_match()`](https://stringr.tidyverse.org/reference/str_match.html)
over
[`regmatches()`](https://rdrr.io/r/base/regmatches.html)/[`regexec()`](https://rdrr.io/r/base/grep.html):
the latter silently drops non-matches and misaligns rows.

## Usage

``` r
resolve_concat(
  files,
  concat,
  parse_format = NULL,
  origin = NULL,
  unit = "days"
)
```
