# Manifest of 人口動態統計 (e-Stat toukei 00450011) files with municipal deaths
# by 5-year age group x sex, for the prefectures and years needed by
# src/4r_residual_migration.ipynb and src/5r_ungroup2d.ipynb.
#
#   Rscript src/make_deaths_manifest.R
#
# No API key needed: candidates come from e-Stat's public search pages, and each
# candidate's header is downloaded and checked, because the file titles are
# ambiguous before 2014 ("1-2 03 岩手県" in 2006-2011, "1 03 岩手県" in
# 2012-2013, shared with other tables of the same number).
#
# Table: 確定数 / 保管統計表 都道府県編（報告書非掲載表）/ 死亡・乳児死亡,
#   死亡第1表 (1-2 before 2012) 死亡数，性・年齢（５歳階級）・都道府県
#   （・保健所）・市区町村別, one CSV (Shift-JIS) per prefecture and year.
# Output: dt/raw/deaths_age/manifest.csv
#   year, pref_code, pref, statInfId, header, url

suppressPackageStartupMessages({
  library(dplyr)
  library(purrr)
  library(stringr)
  library(readr)
})

root <- if (dir.exists("dt")) "." else ".."
out_dir <- file.path(root, "dt/raw/deaths_age")
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

prefs <- c("03" = "岩手県", "04" = "宮城県", "07" = "福島県", "43" = "熊本県")
# Years per prefecture: Tohoku counts 2006-2016 (4r/5r); Kumamoto to 2025 so
# 5r can cover the same periods as 3r (migration 2014-2025)
years_of <- list("03" = 2006:2020, "04" = 2006:2020, "07" = 2006:2020, "43" = 2006:2025)
years <- sort(unique(unlist(years_of)))

dl_url <- function(id) paste0("https://www.e-stat.go.jp/stat-search/file-download?statInfId=", id, "&fileKind=1")

# Candidate statInfIds from the search page (death tables of the given year)
candidates <- function(year, pref) {
  queries <- c(paste("死亡数 年齢（５歳階級） 市区町村", pref), paste("死亡 1-2", pref))
  ids <- map(queries, function(q) {
    url <- sprintf("https://www.e-stat.go.jp/stat-search/files?page=1&query=%s&layout=dataset&toukei=00450011&year=%d0",
                   URLencode(q, reserved = TRUE), year)
    html <- paste(readLines(url, warn = FALSE, encoding = "UTF-8"), collapse = "\n")
    arts <- str_split(html, "<article class=\"stat-resource_list-item stat-resource_list-item-dataset\">")[[1]][-1]
    arts <- arts[str_detect(arts, "死亡・") & str_detect(arts, str_sub(pref, 1, 2))]
    unique(unlist(str_match_all(arts, "statInfId=(\\d+)") |> map(~ .x[, 2])))
  })
  Sys.sleep(0.5)
  unique(unlist(ids))
}

# The file's own title line (2nd line), or NA
header_of <- function(id) {
  tf <- tempfile(fileext = ".csv")
  on.exit(unlink(tf))
  ok <- tryCatch({ download.file(dl_url(id), tf, mode = "wb", quiet = TRUE); TRUE }, error = function(e) FALSE)
  if (!ok) return(NA_character_)
  x <- readLines(tf, n = 3, warn = FALSE, encoding = "bytes")
  x <- iconv(x, from = "CP932", to = "UTF-8", sub = "")
  paste(x[1:2], collapse = " ")
}
is_target <- function(h, pref) {
  !is.na(h) && str_detect(h, "死亡数") && str_detect(h, "年齢（５歳階級）|年齢\\(5歳階級\\)") &&
    str_detect(h, "市区町村") && !str_detect(h, "死因|死産|乳児") && str_detect(h, str_sub(pref, 1, 2))
}

manifest <- map_dfr(years, function(y) {
  map_dfr(names(prefs), function(pc) {
    if (!y %in% years_of[[pc]]) return(NULL)
    for (id in candidates(y, prefs[[pc]])) {
      h <- header_of(id)
      if (is_target(h, prefs[[pc]])) {
        return(tibble(year = y, pref_code = pc, pref = prefs[[pc]], statInfId = id,
                      header = str_squish(str_remove_all(h, ",")), url = dl_url(id)))
      }
    }
    warning("no file found for ", y, " ", prefs[[pc]])
    NULL
  })
})

write_csv(manifest, file.path(out_dir, "manifest.csv"))
print(count(manifest, year) |> as.data.frame())
