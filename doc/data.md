# Data sources

All data in this project come from public statistics. This page lists where each source comes from, which file in `dt/` holds it, and how to rebuild it. For caveats on using the data, see `doc/caution.md`.

## 1. Sources at a glance

| Data | Source | Years | Where in this repo |
|---|---|---|---|
| Population by 5-year age band × sex, by municipality | 総務省「住民基本台帳に基づく人口、人口動態及び世帯数」市区町村別年齢（階級）別人口 (e-Stat, statsCode 00200241) | 1995–2026 | `dt/jumin_age_sex_5yr_*`, `dt/jumin_total_all_municipalities.qs2` (rebuilt here); also `3_人口パネル` in the workbook |
| In-/out-migrants by 5-year age band × sex, by municipality | 総務省統計局「住民基本台帳人口移動報告」 (e-Stat, toukei 00200523) | 2014–2025 | `dt/idou_age_sex_5yr_long.qs2` (built here; see §4) |
| Deaths by 5-year age band × sex, by municipality (岩手・宮城・福島・熊本) | 厚生労働省「人口動態統計」確定数, 保管統計表 都道府県編 死亡第1表 (e-Stat, toukei 00450011) | 2006–2020 (熊本 to 2025) | `dt/deaths_age_sex_5yr_long.qs2` (built here; see §5) |
| National Japanese population by single year of age | 総務省統計局「人口推計」長期時系列データ 第4表 (e-Stat, toukei 00200524) | 2005–2020 (1 October) | `dt/natpop_japanese_single_year.csv` (built here; see §6) |
| Births by municipality | Same survey, 人口動態 (annual; the year up to 1 January) | as in the workbook | `3_人口パネル` (`出生数`), `5_出生37` |
| 全壊・半壊棟数 (fully / half-destroyed buildings) | 消防白書 H26 附属資料1 (岩手・宮城・福島); 熊本県災害対策本部 第289報; 石川県 第204報 (R7.5.13) | per disaster | `8_被害データ` (column `出典`) |
| Town-office coordinates (for distance to the prefectural capital) | 国土地理院 市区町村役場データ | — | `1_市町村一覧` (`県庁所在地からの距離km`) |
| Socio-economic indicators | 総務省「統計でみる市区町村のすがた」2013・2021・2024 (経済センサス, 国勢調査, 課税状況 etc.) | pre-disaster edition: 東日本 2013, 熊本 2021, 能登 2024 | `6_社会経済37` |
| Municipal boundaries (maps only) | 国土交通省 国土数値情報 行政区域 (N03), 2025-01-01 vintage | 2025 | `dt/raw/n03/n03_2025_polygons.qs2` (cache, not committed) |

The protocol (解析手順書 §2) also lists 復興予算 (復興庁 復興交付金配分表; 市町村決算カード) and 応急仮設 (prefectural lists of construction-type housing; みなし仮設 materials such as BRI 資料 No.216). These are not in the workbook or in `dt/`.

## 2. Analysis workbook: `dt/analysis_original_data.xlsx`

Compiled by the original (Python) analysis, provisional as of October 2026. The `README` sheet gives the sources as:

> 総務省「住民基本台帳に基づく人口、人口動態及び世帯数」（各年1月1日、2012年以前は3月31日）／消防白書H26附属資料1／熊本県災害対策本部 第289報／石川県 第204報／総務省「統計でみる市区町村のすがた」2013・2021・2024／経済センサス基礎調査／国勢調査

| Sheet | Content | Source |
|---|---|---|
| `1_市町村一覧` | 187 affected municipalities: population, damage, 全壊率, evacuation flag, controls, distance, yearly gaps | Derived from sheets 3 and 8 and the 国土地理院 office coordinates |
| `2_対照リスト` | Selected controls per affected municipality | Derived (matching) |
| `3_人口パネル` | Population (総人口, 0–14, 20–39, 65+, 女性20–39) and births, 1,379 municipalities | 住民基本台帳 |
| `4_年次ギャップ37`, `5_出生37` | Gaps for the 37 municipalities with 全壊率 ≥ 1 | Derived |
| `6_社会経済37` | Pre-disaster socio-economic indicators | 統計でみる市区町村のすがた |
| `7_感度分析` | Sensitivity results | Derived |
| `8_被害データ` | 全壊・半壊棟数 extracted from the PDFs and checked against prefecture totals: 消防白書H26附属資料1 (127 rows), 熊本県第289報 (45), 石川県第204報 (19) | Damage reports |

Per the protocol, the analysis can be rebuilt from sheets 3, 8 and 6.

## 3. Age × sex population from e-Stat (rebuilt in this repo)

- **Survey:** 住民基本台帳に基づく人口、人口動態及び世帯数, table 市区町村別年齢別人口 / 年齢階級別人口 (e-Stat statsCode 00200241).
- **Files:** 46 Excel files, one per year and basis. Each is listed with its `statInfId` and download URL in `dt/raw/jumin_age/manifest.csv`, for example:
  - 1995: `95-04_市区町村別年齢別人口`, https://www.e-stat.go.jp/stat-search/file-download?statInfId=000008291543&fileKind=0
  - 2026: `26-08_【日本人住民】市区町村別年齢階級別人口`, https://www.e-stat.go.jp/stat-search/file-download?statInfId=000040479054&fileKind=0
- **Coverage:**
  - `japanese` (日本人住民): 32 files, 1995–2026.
  - `total` (総計, including foreign residents): 14 files, 2013–2026.
- **Reference date:** 3/31 through 2012, 1/1 from 2013.
- **Downloaded:** 2026-11-06. The raw files are in `dt/raw/jumin_age/` and are not committed; only `manifest.csv` is.

| Output file | Content |
|---|---|
| `dt/jumin_age_sex_5yr_long.qs2` | Long: code × year × basis × sex × age band, for the 1,379 panel municipalities. Read with `qs2::qs_read()`. |
| `dt/jumin_age_sex_5yr_wide.csv` | The same, one row per code × year × basis × sex, with `age_unspecified` |
| `dt/jumin_total_all_municipalities.qs2` | Total population for every row of the source (all municipalities, plus wards, 郡 and prefecture subtotals; see `level`) |
| `dt/jumin_age_check.csv` | Comparison with `3_人口パネル`: all 28,902 code-years match exactly |
| `dt/jumin_age_bandsum_mismatch.csv` | Rows where the source's age bands do not sum to 総数 |

Rebuild:

```sh
Rscript src/build_jumin_age.R                          # downloads missing files; no key needed
ESTAT_APPID=<your app id> Rscript src/make_jumin_manifest.R   # only to refresh the manifest
```

Mergers are summed into the surviving code using `src/merge_map.csv` (protocol §3 list).

## 4. Migration by age from e-Stat: 住民基本台帳人口移動報告

- **Survey:** 住民基本台帳人口移動報告, 総務省統計局 (e-Stat toukei 00200523).
- **What it counts:** 転入 = in-migrants from other municipalities; 転出 = out-migrants to other municipalities. Moves within a municipality are not counted.
- **Period:** calendar years (1 January – 31 December).

**Finest municipal age detail by year** (checked on e-Stat, November 2026):

| Years | Municipal age detail | Table | Basis |
|---|---|---|---|
| 2010–2011 | 3 groups only (0–14 / 15–64 / 65+) | 詳細集計 table 15-1/15-2 | Japanese movers |
| 2012–2013 | 10-year bands (参考表); 3 groups in 詳細集計 | 参考表, table 15 | Japanese movers |
| 2014–2017 | **5-year × sex** | 詳細集計 table 16-1 (転入) / 16-2 (転出), 3 regional files per year | Japanese movers only |
| 2018–2019 | **5-year × sex** | 詳細集計 table 16-1 / 16-2, 3 regional files | 移動者 (incl. foreign) and 日本人移動者 |
| 2020–2025 | **5-year × sex** | 年報（実数） table 11-1 / 11-2, one file per year | 移動者, 日本人移動者, 外国人移動者 |

- **5-year detail starts in 2014.** Municipal migration by 5-year age × sex is published only from 2014; 2012–13 has only 10-year bands and 2010–11 only three broad groups.
  - The 2011 Great East Japan Earthquake therefore has no 5-year municipal migration data before it or in its first years. That is why the cohort analysis (`src/3r_migration_kumamoto.ipynb`) covers Kumamoto only.
  - Kumamoto 2016 has 5-year data from two years before the quake to nine years after.
- **Noto.** The 2025 tables are published (statInfId 000040428748 / 000040428749), so Noto 2024 has one year of follow-up.
- **Age bands:** 0–4 … 85–89 and 90+. In-migrant tables also have その他 / 移動前の住所地不詳 (previous address unknown). This is **not** part of 総数; it is stored as `age_band == "origin_unknown"`.
- **Files:** 48, listed with `statInfId` and URL in `dt/raw/idou_age/manifest.csv`. Downloaded 2026-11-06; raw files are in `dt/raw/idou_age/` (not committed). Examples:
  - 2014 table 16-1, 30和歌山県～47沖縄県: https://www.e-stat.go.jp/stat-search/file-download?statInfId=000028096965&fileKind=0
  - 2025 table 11-2: https://www.e-stat.go.jp/stat-search/file-download?statInfId=000040428749&fileKind=0

| Output file | Content |
|---|---|
| `dt/idou_age_sex_5yr_long.qs2` | code × year × direction (in/out) × mover (japanese/all/foreign) × sex × age band, every row of the source. `level` = municipality / ward / district / prefecture / aggregate; sum only `level == "municipality"` (1,741 per year). |

Checks printed by the build:
- 計 = 男 + 女 everywhere.
- Each prefecture row equals the sum of its municipalities.
- 総数 equals the sum of the age bands, except for 1–5 movers of unknown age in about 1,000 rows.
- 60 cells are `...` (not available) and are stored as NA.
- 富谷町 04423 is recoded to 富谷市 04216 (src/merge_map.csv).

Rebuild (no API key needed; the manifest is scraped from the public file-listing pages):

```sh
Rscript src/make_idou_manifest.R   # refresh the list of files
Rscript src/build_idou_age.R       # download missing files, parse, check
```

## 5. Deaths by age from e-Stat: 人口動態統計

- **Source:** 人口動態統計 (厚生労働省), 確定数 / 保管統計表 都道府県編（報告書非掲載表）/ 死亡・乳児死亡, 死亡第1表 (titled "1-2" before 2012): 死亡数，性・年齢（５歳階級）・都道府県（・保健所）・市区町村別.
- **Coverage:** one CSV (Shift-JIS) per prefecture and year. Deaths of Japanese nationals in Japan, by residence, calendar year.
- **Scope:** 岩手, 宮城 and 福島 2006–2020, and 熊本 2006–2025, i.e. what `src/4r_residual_migration.ipynb` and `src/5r_ungroup2d.ipynb` (figure 8, which follows Kumamoto to 2025) need. 65 files, listed in `dt/raw/deaths_age/manifest.csv`; downloaded 2026-11-07. From 2021 the files use the same wide layout.
- **Ambiguous titles before 2014:** the files are titled only "1-2 03 岩手県" (2006–11) or "1 03 岩手県" (2012–13), and other tables share those titles. The manifest script therefore downloads each candidate and checks its header.
- **Layouts:**
  - 2006–2011: long, one row per age.
  - 2012+: wide, one row per municipality × sex, with 保健所 subtotal rows (dropped; the 保健所別計 row is the prefecture total).
- **Age bands:** 0–4 … 95–99, 100+, and 不詳 (`unknown`, 7 deaths in the 4r scope).
- **Code handling:**
  - 熊本市 is reported by ward from 2012, and its 2012 January–March deaths are under the old code 43201; both are summed into 43100.
  - The panel merges in `src/merge_map.csv` are applied.
- **Checks (all pass):**
  - bands sum to 総数;
  - 計 = 男 + 女;
  - each prefecture total equals the sum of its municipalities;
  - all 168 study municipalities are present every year.
  - Spot check: 女川町 2011 = 941 deaths, against 86–152 in other years.

```sh
Rscript src/make_deaths_manifest.R   # no key; about 5 minutes (header checks)
Rscript src/build_deaths_age.R
```

## 6. National single-year population: 人口推計

- **Source:** 人口推計 長期時系列データ (総務省統計局), 第4表 "年齢（各歳）、男女別人口（各年10月1日現在）－総人口、日本人人口（2000年～2020年）", statInfId 000013168604 (xlsx).
- **Output:** `dt/natpop_japanese_single_year.csv`: Japanese population, both sexes, thousands, ages 0–99 and 100+, 1 October 2005–2020. 2000–2004 group the oldest ages and are dropped.
- **Use:** the within-band single-year shape (pclm offset) for municipal population in `src/4r_residual_migration.ipynb`. It keeps cohort-size cliffs that 5-year bands hide (1945–46 vs the 1947–49 baby boom, 1966).

```sh
Rscript src/build_natpop.R
```

## 7. Municipal boundaries (maps)

- **Source:** 国土数値情報 行政区域データ (N03), 2025-01-01 vintage, GeoJSON, downloaded per prefecture from `https://nlftp.mlit.go.jp/ksj/gml/data/N03/N03-2025/N03-20250101_<pref>_GML.zip`.
- **Prefectures:** the affected prefectures and their neighbours: 02–10, 15–18, 21, 40–46.
- **Processing:** `src/fetch_n03.R` merges designated-city wards into the city code, drops holes, keeps every 4th vertex on long boundaries, and caches the result as `dt/raw/n03/n03_2025_polygons.qs2` (gitignored; downloaded 2026-11-06). The downloaded zip and GeoJSON are deleted after parsing.
- **Rebuild:** delete the cache and run `Rscript src/fetch_n03.R`, or run `src/1r_preliminary.ipynb`, which calls it when the cache is missing.

## 8. Which notebook uses what

| Notebook | Data used |
|---|---|
| `src/1r_preliminary.ipynb` | `jumin_age_sex_5yr_long.qs2`, `jumin_total_all_municipalities.qs2`, N03 cache, workbook sheets `1_市町村一覧` and `8_被害データ` |
| `src/2r_age_groups.ipynb` | `jumin_age_sex_5yr_long.qs2`, workbook sheet `1_市町村一覧` |
| `src/4r_residual_migration.ipynb` | `jumin_age_sex_5yr_long.qs2` (`japanese`), `deaths_age_sex_5yr_long.qs2`, `natpop_japanese_single_year.csv`, `idou_age_sex_5yr_long.qs2` (validation), workbook sheet `1_市町村一覧` |
| `src/5r_ungroup2d.ipynb` | as 4r (reads its 1D cache `output/4r_pclm_cache.qs2`), plus 2D population fits cached in `output/5r_pclm2d_cache.qs2` |
| `src/3r_migration_kumamoto.ipynb` | `idou_age_sex_5yr_long.qs2` (Japanese movers), `jumin_age_sex_5yr_long.qs2` (`japanese` basis), workbook sheet `1_市町村一覧` |
