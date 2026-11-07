# Lasius niger: demography, large-colony behaviour and sexual reproduction

Tags: [Ln] measured in L. niger; [relative] other species; [inference] my own reasoning or arithmetic.
Access: **FT** = I read the full text (or the accepted manuscript) myself; **FT-x** = open full text read through an automated extraction step, so check numbers before relying on them; **ABS** = abstract only; **SEC** = another paper's citation or a search snippet; the original was not read.

Papers read in full by me: Kramer et al. 2016, Hart et al. 2018, Stukalyuk 2025 (parts), Stukalyuk & Czaczkes 2024 preprint (parts), Detrain et al. 2010 preprint (parts). Everything else is weaker. Paywalled classics (Sommer & Hölldobler 1995, Rasse & Deneubourg 2001, Mailleux et al. 2003, Boomsma & Leusink 1981, van der Have et al. 1988) were NOT read, so they are represented only through abstracts or citing papers.

## Lifespan: queen longevity, worker lifespan, ageing and gene expression

### Takeaway
The 28.75-year queen is a single captive record. The best measured worker data give a mean of 309-434 days and a maximum of about 3 years at 22 C in the lab. Workers born in larger colonies live shorter lives. I found no field measurement of worker lifespan.

### Cited Findings
- [Ln] Queen held 28.75 years in captivity by Hermann Appel, reported by Kutter & Stumper 1969. One individual, conditions not retrieved. SEC — [UF Book of Insect Records ch. 34](https://entnemdept.ufl.edu/walker/ufbir/chapters/chapter_34.shtml/index_order.shtml)
- [Ln] Kramer et al. round the same record to a 28-year maximum. FT — [Kramer et al. 2016](https://doi.org/10.1016/j.exger.2016.09.008)
- [Ln] Worker lifespan by birth colony. Lab, constant 22 C, no hibernation, no queen, no foraging risk, weekly honey-water and crickets; 17 founding queens from Rostock, Germany, collected 13 July 2009. FT — [Kramer et al. 2016](https://doi.org/10.1016/j.exger.2016.09.008):
  - Early-stage colonies (about 8 months old, 18 +/- 8 workers): 6 cohorts, 217 workers, mean lifespan 434.35 +/- 43.58 d (95% CI), maximum 1,129 d.
  - Intermediate-stage colonies (20 months old, 250 +/- 79 workers, range 122-392): 3 cohorts of 58 +/- 18 workers, mean lifespan 309.23 +/- 36.24 d, maximum 1,094 d.
  - The difference arises before about 400 days of age. After that the mortality rates are indistinguishable.
  - Gompertz fits: early stage a = 0.000416, b = 0.003287; intermediate stage a = 0.001719, b = 0.002387 (per day).
- **Conflict on worker lifespan, same original source:** Kramer et al. cite Kutter & Stumper 1969 for an average of one to two years ([Kramer et al. 2016](https://doi.org/10.1016/j.exger.2016.09.008), FT), while the UF chapter credits the same paper with workers living 7-8 years ([UF ch. 34](https://entnemdept.ufl.edu/walker/ufbir/chapters/chapter_34.shtml/index_order.shtml), SEC). Possibly mean versus maximum. I did not read the 1969 original. Kramer's measured maximum (about 3.1 y) does not support 7-8 y.
- **Paper's internal inconsistency:** the survival test reports n = 310 in the text and n = 3104 in the Figure 3 caption, while cohort sizes and Table 1 subsets sum to about 390. FT — [Kramer et al. 2016](https://doi.org/10.1016/j.exger.2016.09.008)
- [Ln] Age shapes gene expression more than caste does: RNA-seq of brains and legs. ABS — [Lucas, Romiguier & Keller 2017](https://zendy.io/title/10.1111/mec.14256)
- [Ln] Queen-biased genes in legs are enriched for ageing genes and for immune genes (immune only in 1-day-old individuals); SOD3 was the most differentially expressed gene between 1-day-old queen and worker brains. SEC — [Lucas & Keller 2018 record](https://serval.unil.ch/notice/serval:BIB_74528A39B802) (mapping of this record to the letter not confirmed)
- [Ln] DNA and protein repair genes do not differ at 1 day old, rise with age, and rise more in queens. SEC — [Lucas, Privman & Keller 2016](https://pmc.ncbi.nlm.nih.gov/articles/PMC5076446)
- [Ln] Mating induces egg-laying, followed by up-regulation of vitellogenin and defensin; mating frequency did not change expression of the tested genes. SEC — [Chérasse et al. 2019](https://link.springer.com/article/10.1007/s00359-019-01362-0)
- [Ln] Sperm stored for more than 20 years is cited as a literature value, not measured there. ABS — [McAfee et al. 2025](https://doi.org/10.1038/s41598-025-22689-6)
- [Ln] 93 queen-brain transcriptomes, 123 differentially expressed genes, 4 candidate genes. The trait tested was not captured in what I read. ABS — [Le Lay et al. 2026](https://doi.org/10.1111/mec.70614)
- [relative, species list unverified] Across two termites, two bees and two ants, downstream targets of the insulin/TOR/JH network, including vitellogenins, matter more for ageing than upstream parts. SEC — [Korb et al. 2021](https://pred.uni-regensburg.de/id/eprint/47964/)

### Inferences
- [inference] The Kramer formula prints as "a + exp(bt)" in the extracted PDF. That would give hazards above 1 per day, so I read it as a lost multiplication sign, a * exp(bt). By hand this gives median ages of about 568 d (early stage) and 282 d (intermediate), against observed means of 434 and 309 d. The intermediate fit is close and the early-stage fit is loose. Check the PDF figure before coding it.
- [inference] Kramer's lab lifespans probably overstate field lifespans for foragers, because cohorts had no predation or foraging risk. They also had no winter, so the calendar effect of hibernation is unknown.
- [inference] A game could model worker lifespan as dependent on colony stage at birth, roughly 430 d mean in a young colony and 310 d once above a few hundred workers. The study only covers colonies up to about 400 workers, so anything for 1,000 is an extrapolation.

### Gaps
- No field worker lifespan found.
- No L. niger vitellogenin-by-age series found. The Kohlmeier paper you named did not surface in any L. niger search. From memory, not verified, Kohlmeier's ageing work is on Temnothorax, so it may be [relative].
- Conditions of the Appel queen (temperature, hibernation, colony size) not retrieved.

## Fecundity and growth: eggs per day, queen weight, population by colony age, maximum size

### Takeaway
I found no measured eggs-per-day figure for a mature L. niger colony, and no measured growth curve past 20 months. Solid points are 18 workers at 8 months and 250 at 20 months in the lab. Maximum colony size is quoted between about 40,000 and 70,000, and those figures are mostly estimates.

### Cited Findings
- [Ln] Lab population by age: about 18 +/- 8 workers at 8 months after one winter; 250 +/- 79 (range 122-392) at 20 months after two winters. 17 colonies founded; 22 C with hibernation 15 Oct-15 Mar at ambient Rostock temperature; housed in 12 x 17 x 4 cm boxes. FT — [Kramer et al. 2016](https://doi.org/10.1016/j.exger.2016.09.008)
- [Ln] In winter, queens stopped laying and all brood became larvae. Same conditions. FT — [Kramer et al. 2016](https://doi.org/10.1016/j.exger.2016.09.008)
- [Ln] Field census, Kyiv region: 41 mounds in a hyper-dense nest complex, 132-11,995 workers, mean 4,164 +/- 446, median 3,719; 8 mounds under 1,000, 23 at 1,000-5,000, 9 at 5,000-10,000, 1 above 10,000. Mound diameter correlates with population r = 0.887, height r = 0.654. This population is atypical (little aggression between nests). FT (parts) — [Stukalyuk 2025](https://ojs.akademperiodyka.org.ua/index.php/Zoodiversity/article/view/673)
- **Conflict within Stukalyuk 2025:** a 35 cm mound is "estimated" at 14,000 workers, yet the measured mean is 4,164 in a sample whose mean mound is about 34 cm across (mean quoted for the complex survey; the 41 censused mounds may differ). FT — [Stukalyuk 2025](https://ojs.akademperiodyka.org.ua/index.php/Zoodiversity/article/view/673)
- **Conflict on maximum size:**
  - about 60,000 in a monogynous nest, credited to Boomsma et al. 1982, and said to be limited by one queen's laying capacity. SEC — [Stukalyuk 2025](https://ojs.akademperiodyka.org.ua/index.php/Zoodiversity/article/view/673)
  - usually at most about 10,000 per mound, about 70,000 in favourable habitat. SEC — [Zoodiversity paper](https://ojs.akademperiodyka.org.ua/index.php/Zoodiversity/article/download/502/241)
  - 4,000-7,000 typical, rarely 40,000 (tertiary, not peer reviewed). SEC — [Wikipedia](https://en.wikipedia.org/wiki/Lasius_niger)
  - a hundred to more than ten thousand, stated in a pollution-gradient study. SEC — [Grześ et al. 2019](https://www.ncbi.nlm.nih.gov/pmc/articles/PMC6546855/)
- [Ln] Heavier queens at the flight had more brood at first worker eclosion and higher colony productivity at hibernation. Two study years; weights and n not retrieved. ABS — [Fjerdingstad & Keller 2004](https://doi.org/10.1554/03-535)
- [Ln] Egg-laying data exist only for special cases: virgin queens with wings removed laid a four-day average of 6.1 +/- 3.9 eggs in weeks 3-4, far fewer than mated queens. SEC — [Jemielity, Gräff & Keller 2006](https://link.springer.com/article/10.1007/s00040-006-0875-8)
- [Ln] A methoprene study counted eggs of 60 queens over two weeks; rates not retrieved. SEC — [Pamminger et al. 2016](https://pmc.ncbi.nlm.nih.gov/articles/PMC4721097)
- [Ln] 100 lab colonies: honey water was the best of 4 carbohydrate diets; crickets the best of 4 protein diets, improving development and winter survival. No percentages in abstract. ABS — [Szabó, Nagy & Tartally 2025](https://doi.org/10.1038/s41598-025-06406-x)
- [Ln] Co-founded colonies are said to grow faster than single-queen ones. SEC — [Stukalyuk & Czaczkes 2024 preprint](https://doi.org/10.1101/2024.07.16.603683), citing Sommer & Hölldobler 1992, 1995
- [not peer reviewed] Retailer claim of up to 10,000 workers within 3 years — [Antstore](https://www.antstore.net/shop/en/ants/Ants-from-Central-Europe/Lasius-niger--Black-Garden-Ant-.html); forum anecdote of about 2,000 at two years — [Formiculture](https://www.formiculture.com/topic/9020-species-colony-growth-rates/). Both exceed Kramer's measured 250 at 20 months, although Kramer's small box and weekly feeding may have limited growth.

### Inferences
- [inference] 18 to 250 workers in 12 months is about 14-fold. It cannot continue at that rate: 250 x 14 = 3,500 at about 32 months is plausible, but a further 14-fold would pass the quoted maximum.
- [inference] A rough upper limit on sustained egg-laying can be derived, not measured. With 60,000 workers living about 310 days, replacement alone needs about 190 workers per day. Winter lowers the laying season, so summer rates would have to be higher. Treat this as an order of magnitude only, since it combines figures from different populations and a lab lifespan.
- [inference] For a game capped at 1,000 workers, about 310 d mean life means about 3 replacement workers per day, before any growth or brood loss.

### Gaps
- No eggs-per-day by colony size or season for mature colonies. Absence of evidence in my search, not proof that it does not exist.
- Queen weight in mg not retrieved. Fjerdingstad & Keller's full text hit a human verification page and I did not go past it.
- Sommer & Hölldobler 1995 itself: I only have bibliographic details ([DOI](https://doi.org/10.1006/anbe.1995.0244)) and citing statements. Its founding and growth tables need a library copy.
- No measured population at years 3-10, and no time to maturity.

## Nanitics and worker size

### Takeaway
L. niger is monomorphic. Workers grow only slightly with colony stage: head width 1.08 mm versus 1.15 mm, with overlapping distributions. I found no direct measurement of the true first brood against later workers.

### Cited Findings
- [Ln] Head width: 1.08 +/- 0.07 mm (N = 57, colonies about 8 months) versus 1.15 +/- 0.06 mm (N = 50, colonies 20 months), p < 0.001; distributions overlap considerably. Lab, measured on pooled dead workers. FT — [Kramer et al. 2016](https://doi.org/10.1016/j.exger.2016.09.008)
- [Ln] Switch to regular-sized workers is linked to a threshold of 75 workers. SEC — [Kramer et al. 2016](https://doi.org/10.1016/j.exger.2016.09.008) citing [Mailleux et al. 2003](https://doi.org/10.1007/s000400300004)
- [Ln, as asserted] Small workers from new colonies are better at brood care and larger ones at foraging. Kramer's supporting citation (Porter & Tschinkel 1986) is, from memory, on Solenopsis, so this may be [relative] in origin. FT — [Kramer et al. 2016](https://doi.org/10.1016/j.exger.2016.09.008)
- [Ln] 44 young nests were sampled to test whether small workers are over-represented, as in mature colonies. I did not retrieve the result. SEC — [Grześ et al. 2015](https://dx.doi.org/10.1155/2015/873415)
- [Ln] Colonies raised by founding queens fast until first brood matures, living on their own reserves. FT — [Kramer et al. 2016](https://doi.org/10.1016/j.exger.2016.09.008)

### Inferences
- [inference] Kramer's "early stage" workers hatched in the summer after the first winter, so they are not the very first nanitics. True nanitics are probably smaller than 1.08 mm, by an unknown margin.
- [inference] Head width differs by about 6.5%. Rendering such a difference in the game would be nearly invisible unless deliberately exaggerated.

### Gaps
- True nanitic head width. Larval-diet effects on worker size. Size at colonies above about 400 workers.

## Density and space: workers per volume, what stops digging, how nests scale

### Takeaway
Nest volume tracks worker number and digging slows on its own, but I found no measured workers-per-chamber figures for colonies of 100, 500 or 1,000. Any such number in the game will be inferred from lab housing. The figures below are not natural density measurements.

### Cited Findings
- [Ln] Number of ants correlates strongly with final nest volume and digging rate. Digging is limited directly by nest volume and by a change in ants after digging. Adding ants prompts further excavation. Standardised artificial setup; group sizes and volumes per ant not retrieved. ABS/SEC — [Rasse & Deneubourg 2001](https://doi.org/10.1023/A:1011163804217)
- [Ln] Nest volume is restated as growing almost proportionally with colony size. SEC — [Grześ et al. 2019](https://www.ncbi.nlm.nih.gov/pmc/articles/PMC6546855/)
- [Ln] Building: pheromone-driven deposition amplification plus a body-size template sets the height at which ants start a roof on pillars; a 3D model reproduces regular pillars and merging caps. SEC — [Khuong et al. 2016](https://doi.org/10.1073/pnas.1509829113)
- [relative] Messor sancta excavation is logistic-shaped, suggesting double feedback. SEC — [Buhl et al. 2005](https://doi.org/10.1007/s00114-004-0577-x)
- [Ln] Nest density: mean 17.6 and maximum 108 nests per 100 m2 on 68 Central European test plots (Seifert 2017, as cited); 11.7-12.4 mounds per 100 m2 in Kyiv nest complexes, likely under-counted. SEC/FT — [Stukalyuk 2025](https://ojs.akademperiodyka.org.ua/index.php/Zoodiversity/article/view/673)
- [Ln] Mound size: mean diameter 34.1 cm, height 22.9 cm (Kyiv complex). FT — [Stukalyuk & Czaczkes 2024 preprint](https://doi.org/10.1101/2024.07.16.603683)
- [Ln] Lab housing: 53.4 ants in a 56 x 41 x 2 mm chamber. FT-x — [Planckaert et al. 2019](https://doi.org/10.1038/s41598-019-52019-6). Colonies of up to 392 workers in 12 x 17 x 4 cm boxes. FT — [Kramer et al. 2016](https://doi.org/10.1016/j.exger.2016.09.008)

### Inferences
- [inference] Floor area per ant: Planckaert chamber 43 mm2 per ant (86 mm3 per ant, brood absent). Kramer's box at 392 workers about 0.52 cm2 per ant, but that box is also the foraging arena.
- [inference] Scaling those to a game, at 0.43-0.52 cm2 per ant: 100 ants about 43-52 cm2, 500 ants about 215-260 cm2, 1,000 ants about 430-520 cm2 of floor. These are tolerated lab densities, not preferred ones, and they ignore brood.
- [inference] Field cross-check: a 34 cm by 23 cm dome is about 13,900 cm3. With 4,164 workers that is about 3.3 cm3 of mound per worker, ignoring the underground part and treating soil as space. It is only an order of magnitude.
- [inference] For digging, a proportional rule with a self-limiting brake matches Rasse & Deneubourg qualitatively: target volume proportional to population, with digging slowing as the target is reached and resuming when ants are added.

### Gaps
- Volume per ant in Rasse & Deneubourg. Full text paywalled.
- Toffin and García Ibarra: neither surfaced as a readable source. From memory, not verified, Toffin et al. 2009 used Messor sancta, not L. niger, so treat it as likely [relative]. PMC blocked automated access behind a CAPTCHA check, and I did not try to pass it.
- Whether soil across the whole tank would change digging. No source found.

## Behaviour that changes with colony size

### Takeaway
The roughly 75-worker switch to cooperative foraging is attributed to Mailleux et al. 2003 for L. niger, not to Beckers et al. 1989. I could not confirm a 75 figure in Beckers. Published figures for the inactive share and the share of workers outside the nest at 100-1,000 workers were not found.

### Cited Findings
- [Ln] Threshold of 75 workers for the shift to cooperative foraging, and cohorts kept below it to avoid the effect. FT citing SEC — [Kramer et al. 2016](https://doi.org/10.1016/j.exger.2016.09.008) citing [Mailleux et al. 2003](https://doi.org/10.1007/s000400300004)
- [Ln] As colonies grow from incipient to mature, foraging shifts from individual exploitation to mass recruitment; the proportion of patrollers falls significantly and that of conveyors stays about constant. Numbers not retrieved. SEC (search snippet) — [Mailleux et al. 2003](https://doi.org/10.1007/s000400300004)
- **Attribution correction:** Beckers et al. 1989 is a cross-species table of 98 species with colony sizes described as first-order approximations. The text I could read gave no numeric cutoff; Figure 1 percentiles were not extractable and L. niger appears only as a table row. ABS/SEC — [Beckers et al. 1989](https://doi.org/10.1155/1989/94279), [MIT Psyche copy](https://groups.csail.mit.edu/mac/projects/psyche/96/96-239.html)
- [relative, model] Failure rates in recruitment depend on colony size differently per strategy; a colony of a given size should use one method only. A mathematical model, not L. niger data. ABS — [Planqué et al. 2010](https://doi.org/10.1371/journal.pone.0011664)
- [Ln] Trophallaxis: 5 subcolonies of 53.4 +/- 5.2 workers, queenless and broodless, 22 +/- 3 C, 90 min. Foragers 12.2 +/- 1.9 ants; non-foragers 41.2 +/- 5.9. Events per subcolony 99.0 +/- 17.4; per forager 6.3 +/- 2.9, per non-forager 2.9 +/- 2.7. Naive ants declined exponentially with a mean time of 35 min. Network not different from random (1,000 randomised networks). FT-x — [Planckaert et al. 2019](https://doi.org/10.1038/s41598-019-52019-6)
- [Ln] 22 colonies with automated tracking: colonies separate foragers from nurses and the queen; pathogen exposure strengthens this segregation. Per-colony counts not retrieved. ABS/SEC — [Stroeymeyt et al. 2018](https://doi.org/10.1126/science.aat4793)
- [Ln, as listed] Activity periodicity of about 20-120 minutes in groups of 1, 6 and 10 ants over one week. Preprint. ABS — [Oh & Cremer 2025](https://doi.org/10.1101/2025.08.11.669637)

### Inferences
- [inference] Planckaert's forager share is 12.2 / 53.4 = about 23% of ants that visited food in 90 min, or about 20% as the extraction summary worded it. It does not measure the share of workers outside the nest in an intact colony with brood.
- [inference] For the game, 75 workers is the only colony-size threshold here with L. niger attribution. It comes through a citation, and the Mailleux text itself should be checked.

### Gaps
- Inactive-worker share in L. niger: not found. An automated summary inferred about 17% from Planckaert, but its arithmetic had no support in the reported counts, so I rejected it.
- Share of workers outside the nest at 100, 500, 1,000: not found.
- Division of labour by colony size beyond the patroller/conveyor statement: not found.

## Foraging science on L. niger

### Takeaway
Route memory overrides pheromone after a single visit, and the two together speed ants up. Trail width changes the traffic pattern more than the amount of traffic. These are short lab experiments, and I found no reliable 24-hour activity pattern.

### Cited Findings
- [Ln] Route memory overrides trail pheromone after one previous visit, when the two conflict at a fork. Lab. ABS/SEC — [Grüter, Czaczkes & Ratnieks 2011](https://doi.org/10.1007/s00265-010-1020-2)
- [Ln] When pheromone and memory agree, walking speed rises by 25% and straightness by 30%, and trail deposition is maintained, only when used together. Lab. ABS — [Czaczkes et al. 2011](https://doi.org/10.1098/rsbl.2011.0067)
- [Ln] Bottlenecks did not change traffic volume or food return; ants instead formed alternating inbound and outbound clusters. ABS — [Dussutour, Deneubourg & Fourcassié 2005](https://doi.org/10.1242/jeb.01711)
- [Ln] Branches narrowed from 10 mm to 1.5 mm: recruitment dynamics not significantly changed, traffic shifted from asymmetric to symmetric use between 10 and 6 mm, and pushing appeared on narrow branches. SEC — [Optimal traffic organisation (arXiv)](https://arxiv.org/pdf/cond-mat/0403142)
- [Ln] Repeated contacts with nestmates, or with beads coated in cuticular hydrocarbons, reduce pheromone deposition. Authors not confirmed from the snippet. SEC — [PMC4685442](https://pmc.ncbi.nlm.nih.gov/articles/PMC4685442)
- [Ln] Scouts lay a trail only if they can ingest a desired volume, an all-or-none threshold; multiple small feeders count too, and trail marks are equally intense whatever the number of sources. Colony response follows the distribution of thresholds among workers. SEC — [Mailleux et al., foraging-rule paper, year unconfirmed](https://pmc.ncbi.nlm.nih.gov/articles/PMC1691411), [Mailleux et al. 2009](https://doi.org/10.1016/j.crvi.2008.10.005)
- [Ln] Night warming and light affect activity, brood development and worker mortality, with no figures in the abstract. ABS — [Trigos-Peral et al. 2024](https://doi.org/10.1016/j.scitotenv.2024.170157)

### Inferences
- [inference] Simple game rules are supported: a forager with one successful visit follows memory; a trail above the desired-volume threshold gets reinforced; crowding reduces deposition and turns narrow tunnels into alternating clusters rather than lowering throughput.

### Gaps
- Daily activity curve for L. niger in the field: not found.

## Sexual reproduction: alates, weather, mating, founding

### Takeaway
The flight data are strong: above 13 C, wind below 6.3 m/s, 97% in July/August in the UK, no single national flying-ant day. Colony age or size at first alates and alate numbers were not found. Founding-success figures are thin, and the often-quoted Madsen & Offenberg 2017 is about pleometrosis and colony growth, not predation.

### Cited Findings

**Flight timing and weather.** Citizen science, UK, 2012-2014, 13,394 analysable records of 16,139; 124 weather stations. FT — [Hart et al. 2018](https://doi.org/10.1111/ecog.03140):
- [Ln mostly] Of 436 ants returned in 2013, 386 (88.5%) were L. niger, then L. flavus 8.5%. Records were not individually identified.
- June 2.1%, July 64.6%, August 32.6%, September 0.7% (2014 only).
- Peak days: 24 July 2012 (1,067 records), 1 August 2013 (935), 17 July 2014 (1,095). Reports on 68/97 days in 2012 and 2013, and on 93/97 days in 2014.
- Temperature positive, wind negative, rising temperature and falling wind relative to the day before both positive; pressure not significant (range 1004-1028 mbar). Final model R2 = 0.51. All days with mean above 25 C had reports.
- Urban records about 3 days earlier (day 55.5 v 58.5); warm microhabitats about 3 days earlier; Exeter about 9 days ahead of more northerly stations in 2013. Geography explains only about 1% of variance.
- No significant spatial clustering at national or Greater London scale.
- Caveats: effort not quantified, and rainfall could not be tested. A record of winged ants is not necessarily a flight.
- **Internal conflict:** the abstract and discussion say ants were only observed above 13 C and below 6.3 m/s, while the results say most were. Treat these as soft thresholds on daily means, not hard limits.

**Earlier and other flight work:**
- [Ln] Schiermonnikoog and Amsterdam, 1977-1979: time of day, relative humidity and global radiation significant for flight days. No flights above 1.7 m/s at 2 m height until part-way through the season, then at higher speeds. SEC — [Boomsma & Leusink 1981](https://doi.org/10.1007/BF00348045) via [Hart et al. 2018](https://doi.org/10.1111/ecog.03140)
- **Conflict:** the 1.7 m/s Dutch limit is far below the 6.3 m/s UK figure. Measured differently (at 2 m on site versus nearest-station daily means), so these may not truly disagree. Boomsma & Leusink stressed humidity and radiation, while Hart did not test them.
- [relative] Barcelona swifts killed in aircraft strikes: 31 of 72 birds with ant remains, 16 species, weather did not differ between detection and non-detection days, activity peaks early morning and evening. Mediterranean; no L. niger data in abstract. ABS — [Garcia-Garin et al. 2026](https://doi.org/10.1038/s41598-026-48191-1)
- [Ln] Thousands of sexuals from many colonies gather for a few hours. SEC — [Aron & Deneubourg 2020](https://www.ncbi.nlm.nih.gov/pmc/articles/PMC7419493/)
- [Ln] Colonies may produce multiple batches, with a major flight followed by minor ones. Attributed by the authors to a general text, so it is not measured here. FT — [Hart et al. 2018](https://doi.org/10.1111/ecog.03140)

**Mating:**
- [Ln] 535 queens and 4,825 workers from seven NW European populations: most queens mated once, double mating occurred in every population, one triple mating; effective mating frequency 1.16 (range 1.04-1.42). Electrophoresis. ABS/SEC — [Boomsma & Van der Have 1998](https://acnpsearch.tweb-dev.unibo.it/singlejournalindex/46863245)
- [Ln] Heavier queens mated with more males and stored more sperm; queens of intermediate weight survived flights best; little evidence that mate number itself helps colony performance. ABS — [Fjerdingstad & Keller 2004](https://doi.org/10.1554/03-535)
- [Ln] Swiss and Swedish populations: queen mating frequency and sex allocation vary substantially, but workers do not adjust allocation to mating frequency. ABS — [Fjerdingstad, Gertsch & Keller 2002](https://scilit.com/publications/49053e71f6003ac1240dcaa1c92a1ea5)

**Dealation and founding:**
- [Ln] Removing wings alone triggers egg-laying in virgin queens. SEC — [Jemielity, Gräff & Keller 2006](https://link.springer.com/article/10.1007/s00040-006-0875-8)
- [Ln] Pleometrotic founding reported in 18% of cases (Sommer & Hölldobler 1995), ending in one queen. SEC — [Stukalyuk & Czaczkes 2024 preprint](https://doi.org/10.1101/2024.07.16.603683)
- [Ln] Queens in groups of 5-7, 20-21 C, no hibernation, 58 queens in 11 tubes, Kyiv, July 2019. Normal population: under 20% survived by 130 days, down to one queen per tube in three of four tubes, within 23 days of first workers. Hyper-dense population: 75% to 227 days. A third of deaths came before first workers; the rest when 10-30 workers were present. Preprint, small n. FT — [Stukalyuk & Czaczkes 2024](https://doi.org/10.1101/2024.07.16.603683)
- **Citation correction:** the title of Madsen & Offenberg 2017 (Asian Myrmecology 9, e009003) concerns pleometrosis and brood transplantation for colony growth. It is cited for death in fights in 60% of pleometrotic groups, not for predation. I could not read the original. SEC — [Stukalyuk 2025](https://ojs.akademperiodyka.org.ua/index.php/Zoodiversity/article/view/673)
- [Ln] Incipient-colony mortality is stated as up to 95%. The derivation was not read, so don't treat it as a measured L. niger rate. SEC — [Brütsch, Avril & Chapuisat 2017](https://pmc.ncbi.nlm.nih.gov/articles/PMC5701228)
- [Ln] Brief heat stress right after flight raises queen mortality and reduces the chance of producing workers. No numbers in abstract. ABS — [Roux et al. 2026](https://doi.org/10.1098/rsbl.2026.0016)
- [Ln] First-year: worker activity and aggregation before hibernation predict overwinter survival; early infection slows growth, with compensatory growth after. Summary blog, primary paper not read. SEC — [Myrmecological News blog](https://blog.myrmecologicalnews.org/2022/03/09/long-term-consequences-of-early-queen-infection-for-ant-colonies/)
- [Unknown species, possibly relative] One queen producing three times more workers and egg-to-worker 4 days (8%) faster in pleometrosis (Offenberg et al. 2012). The preprint does not name the species; from memory this may be Oecophylla. SEC — [Stukalyuk & Czaczkes 2024](https://doi.org/10.1101/2024.07.16.603683)

### Inferences
- [inference] A game flight rule could be: from late June to early September, each warm still day has a chance of a flight that rises with temperature above 13 C and falls toward 6 m/s, boosted if the day is warmer and calmer than yesterday. Local flights rather than one national day would match Hart.
- [inference] Four days being 8% implies egg-to-worker about 50 days in the unnamed species. It should not be used as an L. niger number without checking.

### Gaps
- Colony size or age at first alates: not found.
- Alates per colony and numerical male/female ratio: not found. [van der Have et al. 1988](https://dare.uva.nl/id/53d6c4b5-390b-4d00-9bf5-1efadcea58e7) should have this, but I only saw its metadata.
- Season when alates develop and whether they overwinter: not found. Hart et al. only say colonies can be flight-ready by July.
- Time of day for L. niger flights in numbers, and humidity values: Boomsma & Leusink full text needed.
- Predation on queens by species, and measured nature founding success: not found.

## Aphid mutualism in measured terms

### Takeaway
I found no measured share of the L. niger diet from honeydew and no colony-level honeydew volume. Per-aphid output is about 110-133 micrograms per hour on tansy, which supports only a rough estimate per aphid group.

### Cited Findings
- [relative partner, Aphis fabae] About 110 micrograms per aphid per hour on Tanacetum vulgare, twice the output on Vicia faba or Chenopodium album (so about 55 on those hosts). Attribution from a snippet. SEC — [Fischer et al. 2005 record](https://doaj.org/article/70d1c01b1da9464ea12917605d4e5ec7)
- [Ln partner] 133 micrograms per aphid per hour on tansy; honeydew output corresponded with L. niger attendance across aphid species. Attribution from a snippet. SEC — [Völkl et al. 1999](https://link.springer.com/doi/10.1007/s004420050751)
- [Ln] A. fabae honeydew: sucrose, fructose and glucose nearly 90% of identified sugars; melezitose 2.2 g/L, under 2%. About 50 unattended aphids. Ants at 23 +/- 2 C and 65 +/- 5% RH. Scout preference: melezitose = sucrose = raffinose above other sugars. FT (parts) — [Detrain et al. 2010 preprint](https://orbi.uliege.be/bitstream/2268/63162/1/Detrainetal2010_preprint.pdf)
- [Ln] Sugar-fed ants prey more and tend less, collecting less honeydew. ABS/SEC — [Offenberg 2001](https://link.springer.com/doi/10.1007/s002650000303)
- [Ln] Small A. fabae populations are protected by L. niger, which drives most predators away; unprotected colonies are eliminated or restricted (Banks 1962). SEC — [C. J. Banks author record](https://scite.ai/authors/c-j-banks-4JRkMa)
- **Conflict:** Nixon 1951 argued protection is merely incidental, and later authors see a more complicated relationship. A. fabae can also colonise hosts without ants. SEC — same search; primary sources not read.

### Inferences
- [inference] 100 aphids at 110-133 micrograms per hour is about 11-13 mg per hour, or about 260-320 mg per day if output were constant. This is wet mass on one host, and collection efficiency is unknown.

### Gaps
- Share of diet from honeydew in L. niger, whether by isotopes or by gut content. Not found.
- Honeydew volume per colony per day, and aphid numbers tended per colony. Not found.
- Protection effect size in numbers. Not found.
