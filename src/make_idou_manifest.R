# Manifest of 住民基本台帳人口移動報告 (e-Stat toukei 00200523) files with
# municipal in-/out-migrants by 5-year age group x sex, 2014-2025.
#
#   Rscript src/make_idou_manifest.R
#
# No API key needed: the statInfIds are read from e-Stat's public file-listing
# pages. Output: dt/raw/idou_age/manifest.csv
#   year, direction (in/out), table, part, title, statInfId, url
#
# Finest municipal age detail by year (checked on e-Stat, 2026-11):
#   2010-2011, 2013  年齢（3区分）only (詳細集計 table 15)
#   2012-2013        10-year bands (参考表)
#   2014-2019        5-year x sex, 詳細集計 tables 16-1 (転入) / 16-2 (転出),
#                    three regional files each
#   2020-            5-year x sex, 年報（実数） tables 11-1 / 11-2, one file each,
#                    with 移動者 / 日本人移動者 / 外国人移動者

suppressPackageStartupMessages({
  library(dplyr)
  library(purrr)
  library(stringr)
  library(readr)
})

root <- if (dir.exists("dt")) "." else ".."
out_dir <- file.path(root, "dt/raw/idou_age")
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

listing_url <- function(tclass1, year) {
  sprintf(paste0("https://www.e-stat.go.jp/stat-search/files?page=1&layout=datalist&cycle=7",
                 "&toukei=00200523&tstat=000000070001&tclass1=%s&tclass2val=0",
                 "&year=%d0&month=0&result_back=1"), tclass1, year)
}

# One row per listed file: table number, title, part (region), statInfId
parse_listing <- function(url) {
  html <- paste(readLines(url, warn = FALSE, encoding = "UTF-8"), collapse = "\n")
  arts <- str_split(html, "<article class=\"stat-dataset_list-item\">")[[1]][-1]
  map_dfr(arts, function(a) {
    id <- str_match(a, "file-download\\?statInfId=(\\d+)")[, 2]
    if (is.na(id)) return(NULL)
    tab <- str_match(a, "表番号&nbsp;(?:</span>)?(?:<span[^>]*>)?([0-9-]+)")[, 2]
    # The title is a <span> when the table is split into regional files (the
    # link text is then the region), and the link text itself otherwise.
    spans <- str_trim(str_match_all(a, "<span>\\s*([^<]+?)\\s*</span>")[[1]][, 2])
    link <- str_trim(str_match(a, "data-key=\"uid\"[^>]*>\\s*([^<]+?)\\s*</a>")[, 2])
    title <- c(spans[str_detect(spans, "転入|転出")], link)[1]
    part <- if (identical(title, link)) "all" else link
    tibble(table = tab, title = as.character(title), part = as.character(part), statInfId = id)
  })
}

specs <- bind_rows(
  tibble(year = 2014:2019, tclass1 = "000001011680", tables = list(c("16-1", "16-2"))),
  tibble(year = 2020:2025, tclass1 = "000001148746", tables = list(c("11-1", "11-2")))
)

manifest <- pmap_dfr(specs, function(year, tclass1, tables) {
  Sys.sleep(1)
  parse_listing(listing_url(tclass1, year)) |>
    filter(table %in% tables, str_detect(title, "5歳階級"), str_detect(title, "市区町村")) |>
    distinct(statInfId, .keep_all = TRUE) |>
    mutate(year = year,
           direction = ifelse(str_detect(title, "転入者数"), "in", "out"),
           part = as.character(part))
}) |>
  mutate(url = paste0("https://www.e-stat.go.jp/stat-search/file-download?statInfId=",
                      statInfId, "&fileKind=0")) |>
  select(year, direction, table, part, title, statInfId, url) |>
  arrange(year, direction, statInfId)

write_csv(manifest, file.path(out_dir, "manifest.csv"))
print(count(manifest, year, direction) |> as.data.frame())
