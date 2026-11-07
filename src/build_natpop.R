# National Japanese population by single year of age, 1 October 2000-2020,
# from 人口推計 長期時系列データ (総務省統計局; e-Stat toukei 00200524),
# 第4表 "年齢（各歳）、男女別人口（各年10月1日現在）－総人口、日本人人口".
#
#   Rscript src/build_natpop.R
#
# Used as the single-year age shape (pclm offset) in
# src/4r_residual_migration.ipynb, so that cohort-size cliffs that 5-year bands
# hide (the small 1945-46 births next to the 1947-49 baby boom, the 1966 丙午
# dip) are kept when municipal bands are split into single years.
# Output: dt/natpop_japanese_single_year.csv  year (2005-2020), age (0-99, 100 = 100+), pop
#         (thousands, both sexes, Japanese population)

suppressPackageStartupMessages({
  library(readxl)
  library(dplyr)
  library(purrr)
  library(stringr)
  library(readr)
})

f <- "dt/raw/natpop/jinko_suikei_kakusai_2000_2020.xlsx"
if (!file.exists(f)) {
  dir.create(dirname(f), recursive = TRUE, showWarnings = FALSE)
  download.file("https://www.e-stat.go.jp/stat-search/file-download?statInfId=000013168604&fileKind=4",
                f, mode = "wb", quiet = TRUE)
}

parse_sheet <- function(sheet) {
  v <- read_excel(f, sheet = sheet, col_names = FALSE, col_types = "text", .name_repair = "minimal")
  yr_row <- which(apply(v, 1, function(r) any(str_detect(str_remove_all(r, "\\s"), "^(平成\\d+年)?20\\d\\d"), na.rm = TRUE)))[1]
  sx_row <- which(apply(v, 1, function(r) any(str_remove_all(r, "\\s") == "男女計", na.rm = TRUE)))[1]
  cols <- which(str_remove_all(unlist(v[sx_row, ]), "\\s") == "男女計")
  years <- as.integer(str_match(str_remove_all(unlist(v[yr_row, cols]), "\\s"), "(20\\d\\d)")[, 2])
  first_age <- which(str_detect(str_remove_all(v[[1]], "\\s"), "^0歳"))[1]
  rows <- first_age:(first_age + 100)   # 0 ... 99, 100歳以上
  map2_dfr(cols, years, function(cl, yr) {
    tibble(year = yr, age = 0:100, pop = as.numeric(unlist(v[rows, cl])))
  })
}

# Sheets 2 and 4 are the 日本人人口 tables (2000-2015, 2015-2020)
nat <- bind_rows(parse_sheet(2), parse_sheet(4)) |>
  distinct(year, age, .keep_all = TRUE) |>
  filter(year >= 2005) |>   # 2000-2004 group the oldest ages; not needed
  arrange(year, age)
stopifnot(!anyNA(nat$pop), all(table(nat$year) == 101))
write_csv(nat, "dt/natpop_japanese_single_year.csv")
cat("Years:", paste(range(nat$year), collapse = "-"), " rows:", nrow(nat), "\n")
print(nat |> filter(year == 2010, age %in% 60:68) |> as.data.frame())
