# Municipal 住民基本台帳 population by 5-year age group x sex, 1995-2026,
# for the 1,379 municipalities in dt/analysis_original_data.xlsx (3_人口パネル).
#
#   Rscript R/build_jumin_age.R
#
# Inputs : dt/raw/jumin_age/manifest.csv (from make_jumin_manifest.R); the
#          e-Stat files are downloaded into dt/raw/jumin_age/ if missing.
# Outputs: dt/jumin_age_sex_5yr_long.qs2    long: code x year x basis x sex x age_band
#          dt/jumin_age_sex_5yr_wide.csv   one row per code x year x basis x sex
#          dt/jumin_age_check.csv          comparison with 3_人口パネル
#          dt/jumin_age_bandsum_mismatch.csv  rows where bands != 総数 in the source
#
# basis = "japanese": 日本人住民 (the only table through 2012; 【日本人住民】 from
#         2013). Continuous 1995-2026.
# basis = "total":    【総計】 (Japanese + foreign residents), 2013+ only.
# 3_人口パネル is japanese through 2012 and total from 2013; this script
# reproduces it exactly that way. Reference date is 3/31 through 2012 and 1/1
# from 2013.

suppressPackageStartupMessages({
  library(readxl)
  library(dplyr)
  library(tidyr)
  library(purrr)
  library(stringr)
  library(readr)
})

raw_dir <- "dt/raw/jumin_age"
manifest <- read_csv(file.path(raw_dir, "manifest.csv"), col_types = cols(.default = "c")) |>
  mutate(year = as.integer(year))

# ---- download -------------------------------------------------------------
raw_file <- function(year, basis) file.path(raw_dir, sprintf("jumin_%d_%s.xls", year, basis))
for (i in seq_len(nrow(manifest))) {
  f <- raw_file(manifest$year[i], manifest$basis[i])
  if (!file.exists(f) || file.size(f) == 0) {
    download.file(manifest$url[i], f, mode = "wb", quiet = TRUE)
  }
}

# ---- parse one year -------------------------------------------------------
# "0～4歳" / "0歳～4歳" / "5～9" -> "0_4"; "80歳以上" -> "80+"
norm_band <- function(x) {
  x <- str_remove_all(x, "歳|\\s")
  case_when(
    str_detect(x, "以上$") ~ paste0(str_remove(x, "以上$"), "+"),
    str_detect(x, "～") ~ str_replace(x, "～", "_"),
    TRUE ~ x
  )
}

parse_year <- function(year, basis) {
  f <- raw_file(year, basis)
  # From 2021 e-Stat serves .xlsx content under the same file name; pick the
  # reader from the file signature (ZIP "PK" = xlsx).
  is_xlsx <- identical(readBin(f, "raw", 2), charToRaw("PK"))
  reader <- if (is_xlsx) read_xlsx else read_xls
  v <- reader(f, col_names = FALSE, col_types = "text", .name_repair = "minimal")
  # Header row = the one whose 5th cell is 総数 (from 2021 the 団体コード cell
  # sits on a units row below it).
  hr <- which(v[[5]] == "総数")[1]
  hdr <- as.character(unlist(v[hr, ]))
  age_cols <- which(str_detect(hdr, "^\\d+(歳)?～\\d+(歳)?$|以上$"))
  bands <- norm_band(hdr[age_cols])

  d <- v[(hr + 1):nrow(v), c(1:4, 5, age_cols)]
  names(d) <- c("code6", "pref", "muni", "sex", "total", bands)
  d |>
    filter(str_detect(code6, "^\\d{6}$"), !is.na(muni), sex %in% c("計", "男", "女")) |>
    mutate(
      year = year,
      basis = basis,
      code = substr(code6, 1, 5),
      pref = str_trim(str_replace_all(pref, "　", " ")),
      muni = str_trim(str_replace_all(muni, "　", " "))
    ) |>
    select(-code6) |>
    pivot_longer(c(total, all_of(bands)), names_to = "age_band", values_to = "pop") |>
    mutate(pop = as.numeric(pop))
}

raw <- map2_dfr(manifest$year, manifest$basis, parse_year) |>
  left_join(manifest |> select(year, basis, ref_date), by = c("year", "basis"))

# 80+ is the top band through 2014; later years go to 100+. Add a harmonized
# 80+ for every year so the series is comparable over time.
fine80 <- c("80_84", "85_89", "90_94", "95_99", "100+")
add80 <- raw |>
  filter(age_band %in% fine80) |>
  group_by(code, pref, muni, year, basis, ref_date, sex) |>
  summarise(pop = sum(pop), .groups = "drop") |>
  mutate(age_band = "80+")
raw <- bind_rows(raw, add80)

# ---- mergers: sum former municipalities into the surviving code ------------
# Protocol §3 for the affected municipalities. Each entry: surviving code <-
# former codes; the former codes are added to the survivor in years where they
# are reported separately.
panel <- read_excel("dt/analysis_original_data.xlsx", sheet = "3_人口パネル",
                    col_types = c("text", "text", "text", rep("numeric", 7)))
names(panel) <- c("code", "pref", "muni", "year", "tot", "p0_14", "p20_39", "p65", "f20_39", "births")
panel_codes <- unique(panel$code)

merge_map <- read_csv(file.path("R", "merge_map.csv"), col_types = cols(.default = "c"))

merged <- raw |>
  left_join(merge_map |> select(former, survivor), by = c("code" = "former")) |>
  mutate(merged_from = if_else(is.na(survivor), NA_character_, code),
         code = coalesce(survivor, code)) |>
  select(-survivor)

out <- merged |>
  filter(code %in% panel_codes) |>
  group_by(code, year, basis, ref_date, sex, age_band) |>
  summarise(
    pop = sum(pop),
    merged_from = paste(sort(unique(na.omit(merged_from))), collapse = ";"),
    .groups = "drop"
  )

# Names and prefecture from the panel, so they match the analysis workbook.
names_tbl <- panel |> distinct(code, pref, muni)
band_order <- c("total", "0_4", "5_9", "10_14", "15_19", "20_24", "25_29",
                "30_34", "35_39", "40_44", "45_49", "50_54", "55_59", "60_64",
                "65_69", "70_74", "75_79", "80+", fine80)
out <- out |>
  left_join(names_tbl, by = "code") |>
  mutate(
    age_band = factor(age_band, levels = band_order),
    sex = factor(sex, levels = c("計", "男", "女")),
    in_original_panel_range = year >= min(panel$year)
  ) |>
  arrange(code, basis, year, sex, age_band) |>
  select(code, pref, muni, year, basis, ref_date, sex, age_band, pop,
         merged_from, in_original_panel_range)

# Long form is ~350 MB as CSV; store it with qs2. Read back with
# qs2::qs_read("dt/jumin_age_sex_5yr_long.qs2").
qs2::qs_save(out, "dt/jumin_age_sex_5yr_long.qs2")

wide <- out |>
  select(-in_original_panel_range) |>
  pivot_wider(names_from = age_band, values_from = pop, names_prefix = "age_") |>
  rename(total = age_total)
# The source's own age bands do not always add up to 総数 (mostly the 総計
# table, many rows marked "*" in the source; up to ~160 people). Keep the
# remainder visible rather than silently dropping it.
s5_cols <- paste0("age_", c("0_4", "5_9", "10_14", "15_19", "20_24", "25_29",
                            "30_34", "35_39", "40_44", "45_49", "50_54",
                            "55_59", "60_64", "65_69", "70_74", "75_79", "80+"))
wide$age_unspecified <- wide$total - rowSums(wide[s5_cols])
write_excel_csv(wide, "dt/jumin_age_sex_5yr_wide.csv")

# ---- checks ---------------------------------------------------------------
w <- out |>
  select(code, muni, year, basis, sex, age_band, pop) |>
  pivot_wider(names_from = age_band, values_from = pop)
s5 <- c("0_4", "5_9", "10_14", "15_19", "20_24", "25_29", "30_34", "35_39",
        "40_44", "45_49", "50_54", "55_59", "60_64", "65_69", "70_74",
        "75_79", "80+")
w$band_sum <- rowSums(w[s5])
bad_sum <- w |> filter(band_sum != total)
write_excel_csv(bad_sum |> select(code, muni, year, basis, sex, total, band_sum),
                "dt/jumin_age_bandsum_mismatch.csv")
cat("Rows where 5-year bands do not sum to total:", nrow(bad_sum), "\n")

sx <- w |>
  select(code, year, basis, sex, total) |>
  pivot_wider(names_from = sex, values_from = total)
cat("Rows where 計 != 男 + 女:", sum(sx$計 != sx$男 + sx$女, na.rm = TRUE), "\n")

both <- w |> filter(sex == "計")
fem  <- w |> filter(sex == "女")
rebuilt <- tibble(
  code = both$code, year = both$year, basis = both$basis,
  tot_new    = both$total,
  p0_14_new  = both$`0_4` + both$`5_9` + both$`10_14`,
  p20_39_new = both$`20_24` + both$`25_29` + both$`30_34` + both$`35_39`,
  p65_new    = both$`65_69` + both$`70_74` + both$`75_79` + both$`80+`
) |>
  left_join(tibble(code = fem$code, year = fem$year, basis = fem$basis,
                   f20_39_new = fem$`20_24` + fem$`25_29` + fem$`30_34` +
                     fem$`35_39`),
            by = c("code", "year", "basis"))

# 3_人口パネル is Japanese residents through 2012 and 総計 from 2013.
chk <- panel |>
  select(code, muni, year, tot, p0_14, p20_39, p65, f20_39) |>
  mutate(basis = if_else(year <= 2012, "japanese", "total")) |>
  left_join(rebuilt, by = c("code", "year", "basis")) |>
  mutate(
    found = !is.na(tot_new),
    match = found & tot == tot_new & p0_14 == p0_14_new &
      p20_39 == p20_39_new & p65 == p65_new & f20_39 == f20_39_new
  )
write_excel_csv(chk, "dt/jumin_age_check.csv")

cat("Panel code-years:", nrow(chk), " found:", sum(chk$found),
    " exact match on all 5 columns:", sum(chk$match), "\n")
cat("Codes per year and basis in output:\n")
print(out |>
        filter(sex == "計", age_band == "total") |>
        count(year, basis) |>
        pivot_wider(names_from = basis, values_from = n) |>
        as.data.frame())
