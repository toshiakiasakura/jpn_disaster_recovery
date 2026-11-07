# Municipal boundaries for the affected and surrounding prefectures, from
# 国土数値情報 行政区域 (N03), 2025-01-01 vintage.
#
#   Rscript src/fetch_n03.R
#
# Downloads the N03 zip for each prefecture, reads its GeoJSON (EPSG:6668 =
# JGD2011 lon/lat), and caches one flat polygon table as
# dt/raw/n03/n03_2025_polygons.qs2 with columns
#   code (5-digit, wards dissolved to the city code), pref_code, n03_code,
#   part (one id per polygon outer ring), x (lon), y (lat).
# - Holes are dropped and rings with many vertices are thinned to every 4th
#   vertex: fine for colouring whole municipalities at prefecture scale.
# - The downloaded zip and GeoJSON are deleted once parsed; delete the cache to
#   rebuild.
# No sf needed (conda's r-sf would downgrade the R 4.5 packages).

suppressPackageStartupMessages({
  library(jsonlite)
  library(dplyr)
  library(purrr)
})

local({
  root <- if (dir.exists("dt")) "." else ".."
  n03_dir <- file.path(root, "dt/raw/n03")
  dir.create(n03_dir, recursive = TRUE, showWarnings = FALSE)
  vintage <- "20250101"

  # Affected prefectures and every prefecture bordering them:
  #   2011: 03 岩手, 04 宮城, 07 福島 + 02 青森, 05 秋田, 06 山形, 08 茨城,
  #         09 栃木, 10 群馬, 15 新潟
  #   2016: 43 熊本 + the rest of Kyushu (40 福岡, 41 佐賀, 42 長崎, 44 大分,
  #         45 宮崎, 46 鹿児島)
  #   2024: 17 石川 + 16 富山, 18 福井, 21 岐阜
  prefs <- c("02", "03", "04", "05", "06", "07", "08", "09", "10", "15",
             "16", "17", "18", "21",
             "40", "41", "42", "43", "44", "45", "46")

  # Wards of designated cities -> the city code used for population.
  designated <- c("^0410[1-9]$" = "04100",  # 仙台市
                  "^1510[1-9]$" = "15100",  # 新潟市
                  "^4010[1-9]$" = "40100",  # 北九州市
                  "^4013[1-9]$" = "40130",  # 福岡市
                  "^4310[1-9]$" = "43100")  # 熊本市
  ward_to_city <- function(code) {
    out <- code
    for (pat in names(designated)) out[grepl(pat, code)] <- designated[[pat]]
    out
  }

  thin <- function(m, every = 4, min_n = 40) {
    if (nrow(m) <= min_n) return(m)
    m[unique(c(seq(1, nrow(m), by = every), nrow(m))), , drop = FALSE]
  }

  read_pref <- function(p) {
    gj <- file.path(n03_dir, sprintf("N03-%s_%s.geojson", vintage, p))
    if (!file.exists(gj)) {
      zip <- file.path(n03_dir, sprintf("N03-%s_%s_GML.zip", vintage, p))
      url <- sprintf("https://nlftp.mlit.go.jp/ksj/gml/data/N03/N03-%s/N03-%s_%s_GML.zip",
                     substr(vintage, 1, 4), vintage, p)
      download.file(url, zip, mode = "wb", quiet = TRUE)
      unzip(zip, files = basename(gj), exdir = n03_dir)
      unlink(zip)
    }
    g <- read_json(gj, simplifyVector = FALSE)
    out <- imap_dfr(g$features, function(f, i) {
      code <- f$properties$N03_007 %||% NA_character_
      geom <- f$geometry
      polys <- if (geom$type == "Polygon") list(geom$coordinates) else geom$coordinates
      map_dfr(seq_along(polys), function(j) {
        m <- thin(matrix(unlist(polys[[j]][[1]]), ncol = 2, byrow = TRUE))
        tibble(n03_code = code, part = sprintf("%s-%d-%d", p, i, j),
               x = m[, 1], y = m[, 2])
      })
    }) |>
      mutate(pref_code = p, code = ward_to_city(n03_code))
    unlink(gj)
    out
  }

  polys <- map_dfr(prefs, read_pref) |>
    select(code, pref_code, n03_code, part, x, y)
  qs2::qs_save(polys, file.path(n03_dir, "n03_2025_polygons.qs2"))
  cat("N03 polygons:", n_distinct(polys$part), " vertices:", nrow(polys),
      " codes:", n_distinct(polys$code), "\n")
})
