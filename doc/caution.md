# Caution points

Things to keep in mind when using the population data in `dt/` and when reading results. Sections 1–3 come from building and checking `dt/jumin_age_sex_5yr_*` (`src/build_jumin_age.R`) and `src/1r_preliminary.ipynb`. Section 4 summarises the limitations in 解析手順書 §12.

## 1. Population basis

- **The existing panel switches basis in 2013.** `3_人口パネル` in `analysis_original_data.xlsx` counts Japanese residents only through 2012. From 2013 it uses the 総計 table, which includes foreign residents. The protocol (§2) says 日本人住民 throughout.
  - Rebuilding the panel from e-Stat matches all 28,902 code-years exactly only under this mixed basis.
  - Growth rates across 2012→2013 therefore also pick up foreign residents being added to the count. Affected and control municipalities are hit to different degrees.
- **Use `basis` in the new data on purpose.** `japanese` is continuous over 1995–2026. `total` exists only from 2013. Foreign residents were not on the register before July 2012, so no `total` series exists before 2013.
- **The reference date changes in 2013.** Counts are as of 3/31 through 2012 and 1/1 from 2013, so the 2012→2013 interval is 0.75 years. Annualise rates as `(P2/P1)^(1/years) − 1` (protocol §3).

## 2. Timing relative to each disaster

| Disaster | Date | Last count before | First count after |
|---|---|---|---|
| 東日本 | 2011-03-11 | 2010-03-31 | 2011-03-31 (20 days after) |
| 熊本 | 2016-04-14/16 | 2016-01-01 | 2017-01-01 |
| 能登 | 2024-01-01 16:10 | 2024-01-01 (same day, before the quake) | 2025-01-01 |

- Taking the "disaster year" count as the baseline means different things in each disaster. For 熊本 and 能登 it is the last count before the earthquake. For 東日本 it comes 20 days after.
- The protocol's pre-disaster base for 東日本 is 2010. `src/1r_preliminary.ipynb` uses the disaster year as requested; change `base_year` there to use 2010.

## 3. Age bands and municipality codes

- **Bands don't always sum to the total.** In the source, the age bands sometimes add up to less than 総数.
  - Japanese-resident tables: by 1–3 people in a few rows.
  - 総計 tables: by a median of 12 and at most 161 people, in about 10,500 rows. The source often marks these municipalities with `*`, without a footnote.
  - The remainder is kept as `age_unspecified` in the wide file, and the affected rows are listed in `dt/jumin_age_bandsum_mismatch.csv`.
  - Sums of age bands (e.g. 20–39) can therefore be slightly smaller than an age-unrestricted figure.
- **The top band changes.** It is `80+` through 2014. From 2015 the source splits 80–84 … 100+. The harmonised `80+` exists for all years; the finer bands are missing before 2015.
- **計 vs 男 + 女:** these differ by 1 person in 12 rows of the 2025–2026 総計 tables, as in the source.
- **Mergers.** Former municipalities are summed into the surviving code only for the protocol §3 list (`src/merge_map.csv`).
  - Municipalities created in the 2005–06 Heisei mergers have no rows before they existed. Coverage rises from 1,105 codes in 1995 to 1,365 in 2006.
  - This does not affect the analysis period (2006+), but any longer pre-period would need a full merger map.
- **Codes are 5-digit text.** Read them as strings (e.g. `03201`); numeric reads drop the leading zero.

### Maps (`src/1r_preliminary.ipynb`; figures 4–6 population, 7–9 全壊棟数, 10–12 trends)

- **Summing the national table.** `dt/jumin_total_all_municipalities.qs2` mixes municipalities with 郡 and prefecture subtotals and with designated-city wards. Sum only `level == "municipality"`, or populations are double-counted. Tokyo's 23 special wards are municipalities.
- **Trend figures 10–12.** "Non-affected" means every unlisted municipality in the same region as the maps, including 仙台市, which was hit by the same disaster.
  - Municipalities whose code absorbed a merger inside the window would show an artificial jump. Non-affected ones with a year-on-year change above +3% or below −25%, or an incomplete series, are left out. For Tohoku 2006–2016, that is 29 of 256.
  - The windows ending after 2026 (Noto) are truncated to the latest data.

- **Damage maps (7–9) show 全壊棟数, the count, not 全壊率.** Large municipalities rank high partly because of their size; for example 仙台市 (30,034) is the largest value of all. The study's exposure variable is 全壊率 (per 100 residents), so these maps are not the exposure.
  - Damage data exist only for the affected prefectures (sheet `8_被害データ`), so the surrounding prefectures are grey.
  - Unlisted municipalities with a damage row (仙台市, 浪江町, 飯舘村, 檜枝岐村) are coloured too.
  - The sources have different reference dates (消防白書 H26; 熊本県 第289報; 石川県 第204報, 2025-05-13).

- **"Affected" means listed in the analysis workbook.** Orange marks the municipalities listed in `1_市町村一覧` for the map's 災害 groups (2011: 東日本 + 福島). Unlisted municipalities inside the affected prefectures (仙台市, 檜枝岐村, 浪江町, 飯舘村) are blue, like the surrounding prefectures, even though they were hit by the same disaster.
- **Boundaries are current, populations are not.** The boundaries are the 2025-01-01 N03 vintage, while each map's population is from its disaster year (2011, 2016 or 2024).
  - Codes that changed in between are joined via `src/merge_map.csv`: 滝沢, 富谷 and 熊本市 from the protocol list, plus 那珂川町 → 那珂川市 (40305 → 40231, 2018), which only the maps need.
  - Other boundary changes after the disaster year would show as grey.
- **Wards are merged into their city.** 仙台, 新潟, 北九州, 福岡 and 熊本 are each coloured by city population, not by ward.
- **Grey areas.** On the Kyushu map, the polygons coded 40000 and 46000 are land not assigned to any municipality (所属未定地), so they have no population.
- **Simplified shapes.** Holes are dropped and long boundaries keep every 4th vertex. This is fine for colouring municipalities but not for measuring area or distance.
- **Cropping.** Far-off islands are cropped: Tsushima and the Satsunan islands on the Kyushu map, and 舳倉島 and 七ツ島 on the Ishikawa map. The Tohoku map is uncropped.
- **Japanese residents only.** As in the heatmaps, the `japanese` basis is used, so foreign residents are not counted.

### Year-on-year change rates (`src/2r_age_groups.ipynb`, figures 5–8)

- **The 2012→2013 step is annualised.** It covers 9 months (3/31 → 1/1), so it is computed as `(P_t/P_t−1)^(1/0.75) − 1`. Without this, every series would dip artificially in 2013.
- **Merger steps are blanked.** A one-year total change above +5%, or a missing previous count, is treated as a merger. In Tohoku this hits the 2005→2006 step for 27 listed municipalities (Heisei mergers before the 2006-03-31 count, e.g. 一関市 +90%). The notebooks list them.
- **The 2011 disaster shows in the 2012 point.** The 2011 count is from 2011-03-31, 20 days after the earthquake, so most of the loss appears in the 2011→2012 change.
- **The 65+ jump around 2012–2014 is a cohort effect.** The baby-boom cohort born 1947–49 turned 65 then, so the jump appears in almost every municipality. Do not read it as a disaster effect.
- **Small groups are noisy.** In villages an age group can be a few hundred people, so single-year swings of ±10% can come from a few dozen people.

### Migration by age and cohort rates (`src/3r_migration_kumamoto.ipynb`)

- **Age detail differs by year.** Municipal migration by 5-year age × sex exists only from 2014; 2012–13 has 10-year bands and 2010–11 only three broad groups (see `doc/data.md` §4). Tohoku 2011 cannot be analysed the same way.
- **Japanese movers only.** The 2014–2017 tables publish only 日本人移動者, so all years use Japanese movers and the `japanese` population basis. Foreign residents' moves are left out.
- **Moves between municipalities only.** Moves within a municipality, births and deaths are not migration. Out-migrants are counted by the municipality they left.
- **The calendar year includes the quake.** Migration is counted over calendar years and population on 1 January. The 2016 quake (April) falls inside the 2016 migration year, so 2016 mixes about 3½ months before it with 8½ months after.
- **Single years are modelled, not observed.** `ungroup::pclm` keeps each band's total but invents a smooth shape inside it. For small municipalities and for migrants (a few dozen per year in villages), λ hits its upper bound and the shape is essentially a smooth guess. Read broad patterns only.
  - Migrant fits add back to the published totals within about 2 movers.
  - Zero bands are replaced by 1e-4 before fitting, as pclm advises.
- **Cohort (Lexis) approximation.** Movers in year *t* reported at age *x* are credited half to the cohort aged *x* and half to the cohort aged *x*−1 on 1 January *t*. This assumes the reported age is age at the move and that moves are spread evenly over the year.
- **Back-cast cohorts.** The 2014–15 values trace the 2016 cohorts backwards. For the youngest cohort, members not yet born are simply absent.
- **Later disasters in the follow-up.** The July 2020 Kyushu floods (令和2年7月豪雨) hit the Kuma river basin (球磨村, 人吉市, 芦北町, 八代市). Migration there from 2020 is not an earthquake effect; 球磨村 shows broad losses at almost every age from 2020.
- **Pooled groups.** "High damage" pools 益城町, 西原村, 南阿蘇村, 嘉島町 and 御船町 (全壊率 ≥ 1), so 益城町 (35k) weighs most. 熊本市 is shown separately because it would dominate any pool.

### Residual net migration (`src/4r_residual_migration.ipynb`)

- **Net migration is a residual:** population change + deaths. It also absorbs register corrections (職権記載・消除), moves to and from abroad, and fitting error. Births are outside the cohorts, which are fixed at the baseline count.
- **Validation:** against directly reported migration (Kumamoto, 2014–2020, Japanese movers), the cohort rates correlate at 0.83 (high damage), 0.56 (熊本市) and 0.70 (other). Mean differences are ≤ 0.3 per 1,000, and yearly totals agree closely (e.g. 2014: −2,781 vs −2,779).
- **One-year residuals are noisy where neighbouring birth cohorts differ sharply.** The bands hide single-year cohort sizes, so a single interval can be off by about ±15–30 per 1,000.
  - The national single-year offset halves this, from about ±65, but cannot remove it.
  - The worst case is the 1944–50 births (war-end dip next to the 1947–49 boom): ages 55–74 in the Tohoku window and 60–79 in the Kumamoto window. These ages are shaded or flagged ⚠ and should not be read.
  - The figures show the pre-quake ±2 SD band as a noise yardstick. In Tohoku the target ages 0–14 and 20–39 have pre-quake SDs of about 1–5 per 1,000; Kumamoto 15–29 is noisier (9–15).
- **Single municipalities are noisier than pooled groups.** In the heatmaps, read patterns across rows and intervals, not single cells.
- **2011 death timing.** Tsunami victims stayed on the 2011-03-31 register (20 days after the quake) and were removed later through death notifications and, from June 2011, presumed deaths of the missing.
  - The 2011 excess deaths are therefore placed in the interval 2011-03-31 → 2012-03-31.
  - Placing them in the quake interval instead gives impossible net in-migration of about +70 per 1,000 in 大槌町 and 陸前高田市.
  - The true split differs by town. For tsunami towns, read the quake interval and year 1 together; their sum does not depend on this choice and is tabulated in the notebook.
- **Interval timing.** Counts are on 3/31 up to 2012 and on 1/1 from 2013, while deaths are by calendar year: deaths are prorated 0.75 / 0.25 to each interval. The 2012-03-31 → 2013-01-01 interval is 0.75 years; it is annualised, and its cohort ageing is approximated.
- **Fukushima evacuation areas.** Evacuees who kept their registration are not migrants in the register, so the residual understates the real population loss there.

### 2D ungrouping (`src/5r_ungroup2d.ipynb`)

- **Setup:** population split with `ungroup::pclm2D` over age × time per municipality, with the national single-year offset, bands harmonised to 80+, and BIC-chosen λ (kr = 2). Deaths and movers stay 1D, so the 2011 and 2016 spikes are not smoothed over time.
- **Result:** a small, consistent gain, not a fix.
  - Pre-quake method noise falls by about 5–15% in most groups and age bands (Tohoku "Other listed" is the exception).
  - Kumamoto validation, all municipality × cohort × year cells: SD of the gap 28.2 → 26.6 per 1,000 and correlation 0.72 → 0.73. Small municipalities stay noisy (< 5,000 residents: SD 51 → 49).
  - The wave at the 1944–50 births becomes narrower but is not smaller.
  - Most of the noise is information missing inside the 5-year bands, which smoothing over time cannot restore.
- **Fit settings:** λ for age goes to its upper bound (the national offset carries the shape). λ for time ranges from 530 to 1e5.
- **Figure 8 (Kumamoto, laid out like 3r figure 3):** this extends the window to 2026, beyond the national single-year shape (2020). Its population is therefore split with plain `pclm2D`, without the national shape.
  - Without it, cohort cliffs are smoothed. The residual swings by about ±40–55 per 1,000 at ages 65–79 in every period, and by +28/−35 at ages 45–54 in 2016, where the 1966 丙午 dip sits on a band edge. Read the residual there only up to about age 40.
  - Under 40 it agrees with reported net migration (high damage, 2016, ages 20–24: −90 vs −116).
  - Fitting without the offset is slow: 43 minutes for 45 municipalities (cached).
- **Figures 9–10 (what the fits look like):** with the national shape, the 1947 and 1966 cliffs appear and age along cohort diagonals; without it they are smoothed. In very small municipalities (五木村, about 60 people per band), the single-year values are nearly flat within each band, so they form steps.

### Without the national offset (`src/6r_no_offset.ipynb`)

- **Setup:** reruns 5r figures 1–7 with the population split by plain `pclm` (1D) and plain `pclm2D` (2D), using no national single-year shape. Figures 1–3 compare all four splits (1D/2D × with/without offset).
- **Ages 0–39:** essentially unchanged. The noise SD is 4–11 per 1,000 at ages 20–39 in every variant, and the quake signals are the same.
- **Ages 55–79:** the noise roughly doubles to triples (e.g. 熊本市 6.3 → 21.5 per 1,000). A ±60–90 per 1,000 single-age wave follows the 1944–50 births through the years, and 2D is no better than 1D there. The quake-interval values at these ages are artefacts.
- **Validation (Kumamoto 2014–2020):** cell correlation 0.72/0.73 with the offset vs 0.70/0.73 without (1D/2D). The losses are in the cohorts aged 60–84.
- **Conclusion:** the target-age results do not depend on the offset. For older ages, it is what makes one-year residuals usable.
- **Runtime:** plain `pclm2D` is slow, about 97 minutes on 16 cores for 168 municipalities (cached in `output/6r_pclm_plain_cache.qs2`).

## 4. Study limitations (protocol §12, summarised)

- **Resident-register basis.** Evacuees who did not move their 住民票 still count as living in the municipality, so real losses are underestimated. For 能登, only 2–3 in 10 people in みなし仮設 had moved their registration (金沢大学 DP96).
- **Municipality level.** Differences between districts within a municipality are not visible. Counts include people who moved in for reconstruction work.
- **Controls are matched on four observed conditions only.** Unobserved differences, such as changes in industrial structure, remain. Distance to the prefectural capital is only a rough proxy for urban proximity.
- **Fukushima:** the main exposure is the evacuation order, not 全壊率. Its dose–response is weaker and not significant in the adjusted DID.
- **"Years' worth of decline"** is an estimate from a regression slope, not an observed value. It is undefined for municipalities that were not declining before the disaster.
- **Recovery factors** come from a cross-sectional comparison of 37 municipalities, so they show association, not causation. Jobs and urban proximity can't be separated. Many variables are tested one at a time, so chance hits are likely.
- **Children (0–14) in years 2–5:** the differences between municipalities are as large as before the disaster and are not explained by any factor tested.
- **Noto:** only two years of follow-up so far. Year 3 (published January 2027) is needed to test the patterns.
