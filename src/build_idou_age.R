# Municipal in-/out-migrants by 5-year age group x sex, 2014-2025, from
# 住民基本台帳人口移動報告 (総務省統計局; e-Stat toukei 00200523).
#
#   Rscript src/build_idou_age.R
#
# Inputs : dt/raw/idou_age/manifest.csv (from make_idou_manifest.R); the files
#          are downloaded into dt/raw/idou_age/ if missing (no key needed).
# Output : dt/idou_age_sex_5yr_long.qs2, one row per
#          code x year x direction x mover x sex x age_band, columns
#            code, pref, muni, level, year, direction (in/out), mover, sex,
#            age_band, n
#   direction  in  = 他市区町村からの転入者数 (in-migrants from other municipalities)
#              out = 他市区町村への転出者数 (out-migrants to other municipalities)
#   mover      japanese = 日本人移動者 (every year)
#              all      = 移動者, incl. foreign nationals (2018+ only)
#              foreign  = 外国人移動者 (2020+ only)
#   age_band   total, 0_4 ... 85_89, 90+, and origin_unknown (in-migrants only:
#              その他 / 移動前の住所地不詳, see the check below)
#   level      municipality / ward (designated-city ward) / district (郡) /
#              prefecture / aggregate (全国, 市部, 郡部, 特別区部 ...)
#              Sum only level == "municipality".
#
# Three source layouts:
#   2014-2017  詳細集計 table 16, .xls, 3 regional files; sheets 総数/男/女,
#              日本人移動者 only
#   2018-2019  same, sheets "移動者 総数a" ... "日本人 女c"
#   2020-      年報（実数） table 11, xlsx under an .xls name, one long sheet:
#              one row per 国籍 x area, three sex blocks of columns

suppressPackageStartupMessages({
  library(readxl)
  library(dplyr)
  library(tidyr)
  library(purrr)
  library(stringr)
  library(readr)
})

raw_dir <- "dt/raw/idou_age"
manifest <- read_csv(file.path(raw_dir, "manifest.csv"), col_types = cols(.default = "c")) |>
  mutate(year = as.integer(year))
regions <- unique(manifest$part[manifest$part != "all"])
manifest$part_id <- ifelse(manifest$part == "all", "all",
                           as.character(match(manifest$part, regions)))
manifest$file <- file.path(raw_dir, sprintf("idou_%d_%s_%s.xls", manifest$year,
                                            manifest$direction, manifest$part_id))

# ---- download -------------------------------------------------------------
for (i in seq_len(nrow(manifest))) {
  f <- manifest$file[i]
  if (!file.exists(f) || file.size(f) == 0) {
    download.file(manifest$url[i], f, mode = "wb", quiet = TRUE)
    Sys.sleep(0.5)
  }
}

# ---- parse ----------------------------------------------------------------
# "0～4歳" / "0歳～4歳" -> "0_4"; "90歳以上" -> "90+"; 総数 -> total
norm_band <- function(x) {
  x <- str_remove_all(x, "歳|\\s|\\d\\)")
  case_when(
    x %in% c("総数") ~ "total",
    str_detect(x, "以上$") ~ paste0(str_remove(x, "以上$"), "+"),
    str_detect(x, "～") ~ str_replace(x, "～", "_"),
    str_detect(x, "その他|Other|不詳") ~ "origin_unknown",
    TRUE ~ NA_character_
  )
}
keep_bands <- c("total", paste0(seq(0, 85, 5), "_", seq(4, 89, 5)), "90+", "origin_unknown")
# The xls name cells carry the 3-digit local code in front ("423 富 谷 町")
clean_name <- function(x) str_remove(str_remove_all(x, "[\\s\\x{3000}*]"), "^\\d+")

parse_xls_sheet <- function(f, sheet, year, direction) {
  v <- read_xls(f, sheet = sheet, col_names = FALSE, col_types = "text", .name_repair = "minimal")
  hr <- which(apply(v, 1, function(r) any(grepl("^0～4", r))))[1]
  hdr <- unlist(v[hr, ])
  # The 'Other' column is labelled only in the English header row of some files
  hdr[is.na(hdr) & seq_along(hdr) == ncol(v) & direction == "in"] <- "Other"
  bands <- norm_band(hdr)
  cols <- which(bands %in% keep_bands)
  label <- paste(unlist(v[1:(hr - 1), ]), collapse = " ")
  mover <- if (str_detect(sheet, "^移動者")) "all"
           else if (str_detect(sheet, "^日本人") || str_detect(label, "日本人移動者")) "japanese"
           else stop("mover type not found: ", f, " ", sheet)
  sex <- c("総数" = "計", "男" = "男", "女" = "女")[str_extract(sheet, "総数|男|女")]
  d <- v[(hr + 1):nrow(v), c(2, 8, cols)]
  names(d) <- c("code", "name", bands[cols])
  d |>
    filter(str_detect(code, "^\\d{5}$")) |>
    mutate(name = clean_name(name), year = year, direction = direction,
           mover = mover, sex = unname(sex)) |>
    pivot_longer(any_of(keep_bands), names_to = "age_band", values_to = "n")
}

parse_xlsx <- function(f, year, direction) {
  v <- read_xlsx(f, sheet = 1, col_names = FALSE, col_types = "text", .name_repair = "minimal")
  hr <- which(apply(v, 1, function(r) any(r %in% "0歳～4歳")))[1]
  sex_row <- unlist(v[hr - 1, ])
  bands <- norm_band(unlist(v[hr, ]))
  cols <- which(bands %in% keep_bands & !is.na(sex_row))
  mover_map <- c("移動者" = "all", "日本人移動者" = "japanese", "外国人移動者" = "foreign")
  d <- v[(hr + 2):nrow(v), c(3, 6, 7, cols)]
  names(d) <- c("mover", "code", "name", paste(sex_row[cols], bands[cols], sep = "|"))
  d |>
    filter(str_detect(code, "^\\d{5}$")) |>
    mutate(mover = unname(mover_map[mover]), name = clean_name(name),
           year = year, direction = direction) |>
    pivot_longer(contains("|"), names_to = c("sex", "age_band"), names_sep = "\\|",
                 values_to = "n") |>
    mutate(sex = recode(sex, "総数" = "計"))
}

parse_file <- function(f, year, direction) {
  if (identical(readBin(f, "raw", 2), charToRaw("PK"))) return(parse_xlsx(f, year, direction))
  # excel_sheets() picks the format from the extension, so ask the xls reader
  sheets <- readxl:::xls_sheets(f)
  map_dfr(sheets, function(s) parse_xls_sheet(f, s, year, direction))
}

raw <- pmap_dfr(list(manifest$file, manifest$year, manifest$direction), parse_file) |>
  mutate(n_chr = str_replace_all(n, "[,\\s]", ""),
         # "-" = none -> 0; "..." = not available -> NA
         n = ifelse(n_chr %in% c("-", "－", "―"), 0, suppressWarnings(as.numeric(n_chr)))) |>
  select(-n_chr)
cat("Cells not available ('...'):", sum(is.na(raw$n)), "\n")

# ---- levels and names -----------------------------------------------------
# Codes with 3rd digit 1 are designated cities (NN1x0, name ends 市) and their
# wards (name ends 区), except Tokyo, where 131xx are the special wards
# (municipalities) and 13100 is the 特別区部 total. Hokkaido 振興局 and Tokyo
# 支庁 rows are subtotals (2014-2024 only, as are 市部/郡部 and 郡 rows).
pref_names <- raw |> filter(str_detect(code, "000$")) |> distinct(code, name) |>
  transmute(pc = substr(code, 1, 2), pref = name) |> distinct(pc, .keep_all = TRUE)
lev <- raw |>
  distinct(code, year, name) |>
  mutate(level = case_when(
    str_detect(code, "000$") ~ "prefecture",
    str_detect(code, "^0000") | name %in% c("市部", "郡部", "全国") |
      str_detect(name, "振興局$|支庁$|特別区部$") ~ "aggregate",
    str_detect(name, "郡$") ~ "district",
    !str_detect(code, "^13") & substr(code, 3, 3) == "1" & str_detect(name, "区$") ~ "ward",
    TRUE ~ "municipality"))

idou <- raw |>
  left_join(lev, by = c("code", "year", "name")) |>
  mutate(pc = substr(code, 1, 2)) |>
  left_join(pref_names, by = "pc") |>
  rename(muni = name) |>
  select(code, pref, muni, level, year, direction, mover, sex, age_band, n)

# Code changes in the panel's merge list: only 富谷町 04423 -> 富谷市 04216
# (became a city in 2016-10) falls inside 2014-2025. Recode to the survivor
# and sum, as in build_jumin_age.R.
merge_map <- read_csv("src/merge_map.csv", col_types = cols(.default = "c")) |>
  filter(scope == "panel")
idou <- idou |>
  left_join(merge_map |> select(former, survivor), by = c("code" = "former")) |>
  mutate(code = coalesce(survivor, code)) |>
  group_by(code, pref, level, year, direction, mover, sex, age_band) |>
  summarise(muni = last(muni), n = sum(n), .groups = "drop")

band_order <- keep_bands
idou <- idou |>
  mutate(age_band = factor(age_band, levels = band_order),
         sex = factor(sex, levels = c("計", "男", "女"))) |>
  arrange(code, year, direction, mover, sex, age_band)
qs2::qs_save(idou, "dt/idou_age_sex_5yr_long.qs2")

# ---- checks ---------------------------------------------------------------
w <- idou |>
  filter(level == "municipality") |>
  mutate(age_band = as.character(age_band)) |>
  pivot_wider(names_from = age_band, values_from = n)
s5 <- setdiff(keep_bands, c("total", "origin_unknown"))
w$band_sum <- rowSums(w[s5])
# 総数 is the sum of the age bands, except for a few movers of unknown age
# (1-5 people in ~1,000 rows). origin_unknown (その他 / 移動前の住所地不詳)
# is NOT part of 総数.
diff <- w$total - w$band_sum
cat("Municipality rows:", nrow(w), "\n")
cat("total == sum of age bands:", sum(diff == 0, na.rm = TRUE),
    "; total - band sum, when not 0:", paste(range(diff[diff != 0], na.rm = TRUE), collapse = " to "),
    "in", sum(diff != 0, na.rm = TRUE), "rows; rows with a '...' cell:", sum(is.na(diff)), "\n")

sx <- w |> select(code, year, direction, mover, sex, total) |>
  pivot_wider(names_from = sex, values_from = total)
cat("計 != 男 + 女:", sum(sx$計 != sx$男 + sx$女, na.rm = TRUE), "\n")

pref_chk <- idou |>
  filter(age_band == "total", sex == "計", level %in% c("municipality", "prefecture"),
         !str_detect(code, "^00")) |>   # 00000 = 全国
  group_by(pc = substr(code, 1, 2), year, direction, mover) |>
  summarise(pref_row = sum(n[level == "prefecture"]),
            munis = sum(n[level == "municipality"]), .groups = "drop")
cat("Prefecture row != sum of its municipalities:",
    sum(pref_chk$pref_row != pref_chk$munis, na.rm = TRUE), "of", nrow(pref_chk), "\n")

cat("Rows per year x mover (計, total, municipalities):\n")
print(idou |> filter(level == "municipality", sex == "計", age_band == "total") |>
        count(year, mover, direction) |>
        pivot_wider(names_from = c(mover, direction), values_from = n) |> as.data.frame())
