# Census (国勢調査) migration by 5-year age x sex, by municipality, from the
# "5年前の常住地" question: residents on 1 October of the census year by where
# they lived five years earlier, and people who lived in the municipality five
# years earlier by where they live now. Covers 岩手・宮城・福島・熊本 and Japan.
#
#   Rscript src/build_census_idou.R      # ESTAT_APPID in the environment or ~/.Renviron
#
# The key is needed only while the API responses are not cached in
# dt/raw/census_idou/ (gitignored, ~150 MB, about 5 min to download). Never
# commit the key.
#
# Census years used: 2010, 2015, 2020 (periods 2005-10, 2010-15, 2015-20).
# 2000 also asked the question but is not used (pre-merger codes; out of the
# analysis window). 2005 did not ask it, and the 2025 migration tables are not
# published yet (Nov 2026).
#
#   census  version  statsDataId  table
#   2010    raw      0003124350   遡及集計: 現住地又は5年前の常住地(10区分)による年齢(5歳階級),
#                                 男女別人口(転入・転出－特掲) 全国, 都道府県, 市区町村
#   2015    raw      0003169840   same table, 2015
#   2015    imputed  0004019720   不詳補完結果 (遡及集計, published with the 2020 census):
#                                 5年前の常住地・現住地別人口, migration status imputed
#   2020    raw      0003447398   男女, 年齢(5歳階級), 5年前の常住地・現住地別人口
#   2020    imputed  0004020973   不詳補完結果 of the same table
#
# Code changes after the 2010 census (藤沢町 -> 一関市, 滝沢村 -> 滝沢市,
# 富谷町 -> 富谷市, 熊本市 43201 -> 43100) are applied with src/merge_map.csv.
# Designated-city wards are dropped; the city row is used.
#
# Output: dt/census_idou_age_sex_5yr_long.qs2, one row per
#   census_year x version x code x sex x age_band x measure:
#   census_year, version (raw / imputed), level (national / prefecture /
#   municipality), code, name, pref_code, sex (計/男/女),
#   age_band (total, 0_4 ... 80_84, 85+, unknown), measure, n
# Measures (persons; "here" = the municipality in the row):
#   resident    常住者 on census day (all, incl. unknown migration status)
#   stay        現住所: same dwelling as five years ago
#   within      moved within the municipality (in a designated city this
#               includes moves between its wards)
#   in_pref     from another municipality in the same prefecture
#   in_other    from another prefecture
#   in_abroad   from abroad
#   unk_origin  moved, but the municipality five years ago is unknown
#   unk_status  migration status unknown (移動状況「不詳」)
#   out_pref    lived here five years ago, now in another municipality of the prefecture
#   out_other   lived here five years ago, now in another prefecture
# The imputed tables have no unknowns (unk_* = 0) and no age 不詳.

suppressPackageStartupMessages({
  library(dplyr)
  library(tidyr)
  library(purrr)
  library(stringr)
  library(readr)
  library(jsonlite)
  library(qs2)
})

root <- if (dir.exists("dt")) "." else ".."
raw_dir <- file.path(root, "dt/raw/census_idou")
dir.create(raw_dir, recursive = TRUE, showWarnings = FALSE)
prefs <- c("03", "04", "07", "43")
api <- "https://api.e-stat.go.jp/rest/3.0/app/json/"

appid <- function() {
  k <- Sys.getenv("ESTAT_APPID")
  if (!nzchar(k)) stop("ESTAT_APPID is not set (needed to fill the cache in ", raw_dir, ")")
  k
}
# Path of a cached API response; downloaded if missing
cached <- function(file, url_fun) {
  path <- file.path(raw_dir, file)
  if (!file.exists(path)) {
    download.file(url_fun(appid()), path, quiet = TRUE, mode = "wb")
    Sys.sleep(0.5)
  }
  path
}

tables <- tribble(
  ~census_year, ~version,  ~id,
  2010,         "raw",     "0003124350",
  2015,         "raw",     "0003169840",
  2015,         "imputed", "0004019720",
  2020,         "raw",     "0003447398",
  2020,         "imputed", "0004020973"
)

# Category code -> measure, per table (others dropped: subtotals, ward-level splits)
# 2010/2015: moves between wards of a designated city (00050) are listed apart
# from 自市区町村内 (00040); both are "within" at city level.
mm_old <- c("00010" = "resident", "00020" = "stay", "00040" = "within", "00050" = "within", "00060" = "in_pref",
            "00070" = "in_other", "00080" = "in_abroad", "00090" = "unk_origin",
            "00100" = "unk_status", "00130" = "out_pref", "00140" = "out_other")
mm_new <- c("0" = "resident", "001" = "stay", "00211" = "within", "00212" = "in_pref",
            "00213" = "in_other", "0022" = "in_abroad", "003" = "unk_origin",
            "004" = "unk_status", "1012" = "out_pref", "1013" = "out_other")
measure_map <- list("0003124350" = mm_old, "0003169840" = mm_old, "0004019720" = mm_new,
                    "0003447398" = mm_new, "0004020973" = mm_new)

norm_age <- function(x) {
  x <- str_remove_all(x, "\\s|歳")
  case_when(
    str_detect(x, "^総数") ~ "total",
    str_detect(x, "不詳") ~ "unknown",
    str_detect(x, "再掲") ~ NA_character_,
    x %in% c("85以上", "85～89", "90～94", "95以上") ~ "85+",
    str_detect(x, "^\\d+～\\d+$") ~ str_replace(x, "～", "_"),
    TRUE ~ NA_character_)
}
norm_sex <- function(x) case_when(str_detect(x, "総数") ~ "計", str_detect(x, "男") ~ "男",
                                  str_detect(x, "女") ~ "女", TRUE ~ NA_character_)

# Class objects of a table: list of tibbles (code, name, level), named by id
class_objs <- function(id) {
  meta <- fromJSON(cached(sprintf("meta_%s.json", id), function(k)
    sprintf("%sgetMetaInfo?appId=%s&statsDataId=%s", api, k, id)), simplifyVector = FALSE)
  objs <- meta$GET_META_INFO$METADATA_INF$CLASS_INF$CLASS_OBJ
  map(set_names(objs, map_chr(objs, "@id")), function(o) {
    cl <- if (!is.null(names(o$CLASS))) list(o$CLASS) else o$CLASS
    tibble(code = map_chr(cl, "@code"), name = map_chr(cl, "@name"),
           level = map_chr(cl, ~ .x[["@level"]] %||% NA_character_), obj_name = o[["@name"]])
  })
}

fetch_table <- function(id) {
  cls <- class_objs(id)
  areas <- cls$area |> filter(code == "00000" | (substr(code, 1, 2) %in% prefs & level != "5"))
  chunks <- split(areas$code, ceiling(seq_along(areas$code) / 40))
  vals <- imap_dfr(chunks, function(codes, i) {
    start <- 1; page <- 1; out <- list()
    repeat {
      js <- fromJSON(cached(sprintf("data_%s_%02d_%d.json", id, as.integer(i), page), function(k)
        sprintf("%sgetStatsData?appId=%s&statsDataId=%s&cdArea=%s&metaGetFlg=N&cntGetFlg=N&limit=100000&startPosition=%d",
                api, k, id, paste(codes, collapse = ","), start)))
      if (js$GET_STATS_DATA$RESULT$STATUS != 0) stop(id, ": ", js$GET_STATS_DATA$RESULT$ERROR_MSG)
      sd <- js$GET_STATS_DATA$STATISTICAL_DATA
      out[[page]] <- as_tibble(sd$DATA_INF$VALUE)
      nk <- sd$RESULT_INF$NEXT_KEY
      if (is.null(nk)) break
      start <- as.integer(nk); page <- page + 1
    }
    bind_rows(out)
  })
  # Which class object is sex / age / measure in this table
  dims <- setdiff(names(cls), c("tab", "area", "time"))
  role <- map_chr(dims, function(d) {
    nm <- cls[[d]]$obj_name[1]
    if (str_detect(nm, "男女")) "sex" else if (str_detect(nm, "年齢")) "age" else "measure"
  })
  lab <- function(d) setNames(cls[[d]]$name, cls[[d]]$code)
  col <- function(r) vals[[paste0("@", dims[role == r])]]
  tibble(area_code = vals[["@area"]],
         area_name = setNames(cls$area$name, cls$area$code)[vals[["@area"]]],
         sex = norm_sex(lab(dims[role == "sex"])[col("sex")]),
         age_band = norm_age(lab(dims[role == "age"])[col("age")]),
         measure = unname(measure_map[[id]][col("measure")]),
         n = ifelse(vals[["$"]] == "-", 0, suppressWarnings(as.numeric(vals[["$"]])))) |>
    filter(!is.na(sex), !is.na(age_band), !is.na(measure)) |>
    group_by(area_code, area_name, sex, age_band, measure) |>
    summarise(n = sum(n), .groups = "drop")
}

t0 <- Sys.time()
raw <- tables |> mutate(data = map(id, fetch_table)) |> unnest(data)
cat("Read", nrow(raw), "cells in", round(as.numeric(difftime(Sys.time(), t0, units = "secs"))), "s\n")

merge_map <- read_csv(file.path(root, "src/merge_map.csv"), col_types = cols(.default = "c")) |>
  filter(scope == "panel")
out <- raw |>
  left_join(merge_map |> select(former, survivor, survivor_name), by = c(area_code = "former")) |>
  mutate(code = coalesce(survivor, area_code),
         name = coalesce(survivor_name, area_name),
         level = case_when(code == "00000" ~ "national", substr(code, 3, 5) == "000" ~ "prefecture",
                           TRUE ~ "municipality"),
         pref_code = substr(code, 1, 2)) |>
  group_by(census_year, version, level, code, pref_code, sex, age_band, measure) |>
  summarise(name = last(name), n = sum(n), .groups = "drop") |>
  relocate(name, .after = code)

# ---- Checks ---------------------------------------------------------------
wide <- out |> pivot_wider(names_from = measure, values_from = n, values_fill = 0)
chk_add <- wide |>
  mutate(gap = resident - (stay + within + in_pref + in_other + in_abroad + unk_origin + unk_status)) |>
  filter(abs(gap) > 0)
keys <- c("census_year", "version", "code", "age_band", "measure")
chk_sex <- out |> filter(sex != "計") |> group_by(across(all_of(keys))) |>
  summarise(mf = sum(n), .groups = "drop") |>
  inner_join(out |> filter(sex == "計"), by = keys) |> filter(mf != n)
keys <- c("census_year", "version", "code", "sex", "measure")
chk_age <- out |> filter(age_band != "total") |> group_by(across(all_of(keys))) |>
  summarise(s = sum(n), .groups = "drop") |>
  inner_join(out |> filter(age_band == "total"), by = keys) |> filter(s != n)
chk_pref <- out |> filter(measure == "resident", age_band == "total", sex == "計", level != "national") |>
  group_by(census_year, version, pref_code) |>
  summarise(munis = sum(n[level == "municipality"]), pref = sum(n[level == "prefecture"]), .groups = "drop") |>
  mutate(diff = munis - pref)
cat("Rows where resident != stay + within + in + unknown:", nrow(chk_add), "\n")
cat("Rows where 計 != 男 + 女:", nrow(chk_sex), "\n")
cat("Rows where age bands do not sum to total:", nrow(chk_age), "\n")
cat("Prefecture residents vs sum of municipalities:\n")
print(as.data.frame(chk_pref))

qs_save(out, file.path(root, "dt/census_idou_age_sex_5yr_long.qs2"))
cat("Saved", nrow(out), "rows\n")
print(out |> filter(level == "municipality") |> group_by(census_year, version) |>
        summarise(codes = n_distinct(code), rows = n(), .groups = "drop") |> as.data.frame())
