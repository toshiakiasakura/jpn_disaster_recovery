# Build the list of e-Stat files: 住民基本台帳 municipal population by
# 5-year age group x sex (statsCode 00200241), 1995-2026.
#
# Only this step needs an e-Stat app ID, and it is read from the environment
# so it never lands in the repo:
#   ESTAT_APPID=xxxx Rscript R/make_jumin_manifest.R
# The manifest it writes is all build_jumin_age.R needs; the file downloads
# themselves do not require a key.

suppressPackageStartupMessages({
  library(jsonlite)
  library(dplyr)
  library(purrr)
  library(stringr)
  library(readr)
})

appid <- Sys.getenv("ESTAT_APPID")
if (appid == "") stop("Set ESTAT_APPID")

url <- paste0(
  "https://api.e-stat.go.jp/rest/3.0/app/json/getDataCatalog?appId=", appid,
  "&statsCode=00200241&searchWord=", URLencode("年齢", reserved = TRUE)
)
res <- fromJSON(url, simplifyVector = FALSE)$GET_DATA_CATALOG
if (res$RESULT$STATUS != 0) stop(res$RESULT$ERROR_MSG)

as_list <- function(x) if (!is.null(names(x))) list(x) else x
cats <- as_list(res$DATA_CATALOG_LIST_INF$DATA_CATALOG_INF)

rows <- map_dfr(cats, function(c) {
  year <- as.integer(str_match(c$DATASET$TITLE$NAME, "年次_(\\d{4})年")[, 2])
  map_dfr(as_list(c$RESOURCES$RESOURCE), function(r) {
    tibble(year = year, name = r$TITLE$NAME, url = r$URL, format = r$FORMAT %||% NA)
  })
})

# 1995-2012: "YY-04_市区町村別年齢別人口" (Japanese residents only; foreign
# residents were not on the register until July 2012).
# 2013+: both the 【日本人住民】 table ("YY-08_") and the 【総計】 table
# ("YY-04_", Japanese + foreign). 3_人口パネル uses 総計 from 2013.
manifest <- rows |>
  filter(str_detect(name, "市区町村別年齢(階級)?別人口")) |>
  filter((year <= 2012 & str_detect(name, "^\\d{2}-04_")) |
           (year >= 2013 & str_detect(name, "【日本人住民】|【総計】"))) |>
  mutate(
    basis = case_when(year <= 2012 ~ "japanese",
                      str_detect(name, "【総計】") ~ "total",
                      TRUE ~ "japanese"),
    statInfId = str_match(url, "statInfId=(\\d+)")[, 2],
    ref_date = if_else(year <= 2012, sprintf("%d-03-31", year), sprintf("%d-01-01", year)),
    url = sprintf("https://www.e-stat.go.jp/stat-search/file-download?statInfId=%s&fileKind=0", statInfId)
  ) |>
  arrange(year, basis) |>
  select(year, basis, ref_date, name, statInfId, url)

stopifnot(!anyDuplicated(manifest[c("year", "basis")]))
dir.create("dt/raw/jumin_age", recursive = TRUE, showWarnings = FALSE)
write_csv(manifest, "dt/raw/jumin_age/manifest.csv")
cat("Years:", paste(range(manifest$year), collapse = "-"), " files:", nrow(manifest), "\n")
