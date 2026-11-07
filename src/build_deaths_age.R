# Municipal deaths by 5-year age group x sex, for 岩手・宮城・福島 2006-2020 and
# 熊本 2006-2025,
# from 人口動態統計 (確定数, 保管統計表 都道府県編, 死亡第1表; e-Stat toukei 00450011).
#
#   Rscript src/build_deaths_age.R
#
# Inputs : dt/raw/deaths_age/manifest.csv (from make_deaths_manifest.R); files
#          are downloaded into dt/raw/deaths_age/ if missing (no key needed).
# Output : dt/deaths_age_sex_5yr_long.qs2, one row per code x year x sex x
#          age_band: code, pref_code, muni, year, sex (計/男/女),
#          age_band (total, 0_4 ... 95_99, 100+, unknown), n
#
# Deaths are by the deceased's residence (住所地), Japanese nationals in Japan,
# calendar year of death.
# Two layouts:
#   2006-2011  long: a "CCCCC名前,総数,計,男,女" row, then one row per age
#              (０歳 … ４歳, 00～04歳 … 95～99歳, 100歳～, 不詳)
#   2012-      wide: one row per municipality x sex (総数/男/女), age columns
#              (000-004歳 / 0～4歳 …, 100歳-, 不詳); 保健所 subtotal rows have
#              4-digit codes and are dropped
# Designated-city wards are summed into the city (熊本市 43100 from 2012, plus
# its 2012 Jan-Mar row under the old code 43201), and the panel-scope merges in
# src/merge_map.csv are applied, as in build_jumin_age.R.

suppressPackageStartupMessages({
  library(dplyr)
  library(tidyr)
  library(purrr)
  library(stringr)
  library(readr)
})

raw_dir <- "dt/raw/deaths_age"
manifest <- read_csv(file.path(raw_dir, "manifest.csv"), col_types = cols(.default = "c")) |>
  mutate(year = as.integer(year),
         file = file.path(raw_dir, sprintf("deaths_%d_%s.csv", year, pref_code)))

for (i in seq_len(nrow(manifest))) {
  if (!file.exists(manifest$file[i]) || file.size(manifest$file[i]) == 0) {
    download.file(manifest$url[i], manifest$file[i], mode = "wb", quiet = TRUE)
    Sys.sleep(0.3)
  }
}

# Full-width digits -> ASCII
zen2han <- function(x) chartr("０１２３４５６７８９", "0123456789", x)
# Age label -> band: "00～04歳" / "000-004歳" / "0～4歳" -> "0_4"; "100歳～" / "100歳-" -> "100+"
norm_band <- function(x) {
  x <- str_remove_all(zen2han(x), "歳|\\s")
  case_when(
    x %in% c("総数") ~ "total",
    x == "不詳" ~ "unknown",
    str_detect(x, "^100") ~ "100+",
    str_detect(x, "^\\d+[～〜-]\\d+$") ~ {
      p <- str_split_fixed(x, "[～〜-]", 2)
      suppressWarnings(paste0(as.integer(p[, 1]), "_", as.integer(p[, 2])))
    },
    TRUE ~ NA_character_   # single years 0..4 (already in 0_4)
  )
}
to_num <- function(x) {
  x <- str_trim(x)
  ifelse(x %in% c("-", "－", ""), 0, suppressWarnings(as.numeric(x)))
}

read_lines_sjis <- function(f) iconv(readLines(f, warn = FALSE, encoding = "bytes"),
                                     from = "CP932", to = "UTF-8", sub = "")

parse_long <- function(f, year) {
  x <- read_lines_sjis(f)
  rows <- str_split(x, ",")
  code <- NA_character_; name <- NA_character_
  out <- vector("list", length(rows))
  for (i in seq_along(rows)) {
    r <- rows[[i]]
    if (length(r) < 5) next
    m <- str_match(r[1], "^(\\d{5})(.*)$")
    if (!is.na(m[1])) { code <- m[2]; name <- str_trim(str_remove_all(m[3], "\\s|\u3000")) }
    else if (str_trim(r[1]) != "") { code <- NA_character_; next }
    if (is.na(code)) next
    b <- norm_band(r[2])
    if (is.na(b)) next
    out[[i]] <- tibble(code = code, muni = name, age_band = b,
                       sex = c("計", "男", "女"), n = to_num(r[3:5]))
  }
  bind_rows(out) |> mutate(year = year)
}

parse_wide <- function(f, year, pref_code) {
  x <- read_lines_sjis(f)
  hr <- which(str_detect(x, "^,,総数,"))[1]
  hdr <- str_split(x[hr], ",")[[1]]
  bands <- norm_band(hdr)
  rows <- str_split(x[(hr + 1):length(x)], ",")
  code <- NA_character_; name <- NA_character_
  out <- vector("list", length(rows))
  for (i in seq_along(rows)) {
    r <- rows[[i]]
    if (length(r) < length(hdr)) next
    if (str_trim(r[1]) == "保健所別計") {   # prefecture total in this layout
      code <- paste0(pref_code, "000"); name <- "保健所別計"
    } else if (str_trim(r[1]) != "") {
      m <- str_match(r[1], "^(\\d{5})(.*)$")
      if (is.na(m[1])) { code <- NA_character_; next }   # 保健所 rows: 4-digit code
      code <- m[2]; name <- str_trim(str_remove_all(m[3], "\\s|\u3000"))
    }
    if (is.na(code)) next
    sex <- c("総数" = "計", "男" = "男", "女" = "女")[str_trim(r[2])]
    keep <- which(!is.na(bands))
    out[[i]] <- tibble(code = code, muni = name, sex = unname(sex),
                       age_band = bands[keep], n = to_num(r[keep]))
  }
  bind_rows(out) |> mutate(year = year)
}

parse_file <- function(f, year, pref_code) {
  x <- read_lines_sjis(f)
  if (any(str_detect(x, "^,,総数,男,女"))) parse_long(f, year) else parse_wide(f, year, pref_code)
}

raw <- pmap_dfr(list(manifest$file, manifest$year, manifest$pref_code), parse_file) |>
  filter(!is.na(sex))

# Wards -> designated city; panel merges
merge_map <- read_csv("src/merge_map.csv", col_types = cols(.default = "c")) |>
  filter(scope == "panel")
deaths <- raw |>
  mutate(code = case_when(str_detect(code, "^4310[1-9]$") ~ "43100",
                          str_detect(code, "^0410[1-9]$") ~ "04100",
                          TRUE ~ code)) |>
  left_join(merge_map |> select(former, survivor), by = c("code" = "former")) |>
  mutate(code = coalesce(survivor, code)) |>
  group_by(code, year, sex, age_band) |>
  summarise(muni = last(muni), n = sum(n), .groups = "drop") |>
  mutate(pref_code = substr(code, 1, 2),
         muni = ifelse(code == "43100", "熊本市", ifelse(code == "04100", "仙台市", muni)),
         age_band = factor(age_band, levels = c("total", paste0(seq(0, 95, 5), "_", seq(4, 99, 5)),
                                                "100+", "unknown")),
         sex = factor(sex, levels = c("計", "男", "女"))) |>
  select(code, pref_code, muni, year, sex, age_band, n) |>
  arrange(code, year, sex, age_band)
qs2::qs_save(deaths, "dt/deaths_age_sex_5yr_long.qs2")

# ---- checks ---------------------------------------------------------------
w <- deaths |> mutate(age_band = as.character(age_band)) |>
  pivot_wider(names_from = age_band, values_from = n)
bands <- c(paste0(seq(0, 95, 5), "_", seq(4, 99, 5)), "100+", "unknown")
d <- w$total - rowSums(w[bands])
cat("Rows:", nrow(w), " total != sum of bands (incl. unknown):", sum(d != 0, na.rm = TRUE),
    " NA cells:", sum(is.na(d)), "\n")
sx <- w |> select(code, year, sex, total) |> pivot_wider(names_from = sex, values_from = total)
cat("計 != 男 + 女:", sum(sx$計 != sx$男 + sx$女, na.rm = TRUE), "\n")
pc <- w |> filter(sex == "計") |>
  group_by(pref_code, year) |>
  summarise(pref = sum(total[grepl("000$", code)]),
            munis = sum(total[!grepl("000$", code)]), .groups = "drop")
cat("Prefecture row != sum of municipalities:", sum(pc$pref != pc$munis), "of", nrow(pc), "\n")
if (any(pc$pref != pc$munis)) print(as.data.frame(filter(pc, pref != munis)))

study <- readxl::read_excel("dt/analysis_original_data.xlsx", sheet = "1_市町村一覧",
                            col_types = "text") |>
  filter(災害 %in% c("東日本", "福島", "熊本"))
cov <- expand_grid(code = study$市町村コード, year = 2006:2025) |>
  filter(!(substr(code, 1, 2) == "43" & year < 2010), !(substr(code, 1, 2) != "43" & year > 2020)) |>
  anti_join(w |> filter(sex == "計") |> select(code, year), by = c("code", "year"))
cat("Study municipality-years missing:", nrow(cov), "\n")
if (nrow(cov)) print(head(as.data.frame(cov), 20))
cat("Spot check, 女川町 04581 total deaths:\n")
print(w |> filter(code == "04581", sex == "計", year %in% 2009:2013) |> select(year, total) |> as.data.frame())
