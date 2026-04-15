# Taxonomy Validation Document — Kairos v1.0
## Historical Examples, Edge Cases & Confusion Matrix

---

## CAT-01 — MONETARY_POLICY

### 3 Historical Examples (Correctly Classified)

| Date | Event | Subtype | Reasoning |
|------|-------|---------|-----------|
| 2022-07-27 | Fed raises rates by 75bps for second consecutive meeting, Powell says "another unusually large increase could be appropriate" | rate_decision_hike | Actual rate change occurred; hawkish guidance is secondary to the action |
| 2023-12-13 | Fed holds rates unchanged, dot plot shows 3 cuts in 2024; Powell says "the question of when to begin reducing rates is coming into view" | forward_guidance_dovish | Rate held steady (not a cut), but forward guidance is explicitly dovish; dot plot pivot is the market-moving signal |
| 2020-03-15 | Fed cuts rates by 100bps in emergency unscheduled meeting, launches $700bn QE programme | emergency_action_easing | Unscheduled (Sunday evening), double action (cut + QE), extreme emergency context |

### 2 Edge Cases

**Edge Case 1: Hold + hawkish statement**
> "ECB holds rates unchanged. Lagarde: 'We are not considering rate cuts at all' — press conference Dec 2023"
- **Classified as**: `forward_guidance_hawkish` (not `rate_decision_hold`)
- **Justification**: The market-moving information is the hawkish signal, not the hold. The hold itself was fully priced. The explicit rejection of cuts is new information that shifts anticipations. Rule: when hold + guidance, classify by the guidance direction.

**Edge Case 2: QE announcement in context of emergency**
> "Bank of Japan unexpectedly expands YCC band to ±1%, seen as de facto rate hike — July 2023"
- **Classified as**: `forward_guidance_hawkish` (not `emergency_action_tightening` or `rate_decision_hike`)
- **Justification**: YCC expansion is not a formal rate hike but a guided tightening signal. No emergency context (scheduled meeting). Primary market signal is hawkish re-calibration of long-end rates. The `emergency_action_tightening` subtype requires unscheduled intervention.

### Common Confusions: CAT-01
- **rate_decision_hike vs forward_guidance_hawkish**: If there is an actual rate change, always use `rate_decision_hike`. Guidance only without action = guidance subtype.
- **qe_announcement vs tapering**: QE announcement = new programme starts or resumes. Tapering = slowing existing programme. Key signal: is the net flow increasing or decreasing?
- **emergency_action_easing vs rate_decision_cut**: Emergency requires unscheduled meeting or extraordinary communication channel.

---

## CAT-02 — MACRO_DATA_RELEASE

### 3 Historical Examples (Correctly Classified)

| Date | Event | Subtype | Reasoning |
|------|-------|---------|-----------|
| 2023-01-06 | US NFP +517k jobs in January vs +187k consensus — massive upside surprise | nfp_above | Official BLS release, deviation >100% vs consensus, clear above classification |
| 2022-10-13 | US CPI 8.2% YoY vs 8.1% expected, core CPI 6.6% highest since 1982 | inflation_cpi_above | BLS official release, +0.1pp headline surprise, +0.3pp core surprise; severe market reaction (S&P -2.4% then recovered) |
| 2023-01-27 | US Q4 GDP +2.9% QoQ annualized vs +2.6% consensus | gdp_above | BEA official advance estimate, +0.3pp beat, clear above classification |

### 2 Edge Cases

**Edge Case 1: Mixed inflation data (headline above, core below)**
> "US CPI 3.7% vs 3.6% expected (+0.1pp) but core CPI 4.1% vs 4.3% expected (-0.2pp) — Sep 2023"
- **Classified as**: `inflation_cpi_inline` (not `inflation_cpi_above`)
- **Justification**: When headline and core point in different directions, the dominant market signal determines classification. Core CPI missed by 0.2pp (a larger surprise magnitude). The market reaction was bullish (bond yields fell). Net classification: inline/slightly below. Note: consider splitting into two events if a pipeline allows it.

**Edge Case 2: GDP advance estimate vs final**
> "UK GDP confirmed at -0.3% for Q3, in line with advance estimate"
- **Classified as**: `gdp_revision_down` (with low confidence) or `gdp_inline`
- **Justification**: This is a confirmation, not a new reading. Primary classification should be at advance estimate publication. Confirmation event has low market impact unless it diverges from advance. If confirming a negative print: use `gdp_revision_down` with coefficient 0.3 (not the full `gdp_below` impact).

### Common Confusions: CAT-02
- **nfp_above vs unemployment_fall**: NFP and unemployment rate are different series. Strong payrolls with unchanged unemployment = `nfp_above`. Unemployment rate drop = `unemployment_fall`. Often co-released; classify primary market-moving release.
- **inflation_cpi_above vs MONETARY_POLICY**: CPI is a data release, not a CB decision. Even if the market prices in CB response, classify as CAT-02. CB response will be classified separately when it occurs.
- **pmi_expansion vs gdp_above**: PMI is a survey/leading indicator. GDP is the actual measure. PMI classifications have lower `authority_floor` (0.7 vs 0.8).

---

## CAT-03 — GEOPOLITICAL_SHOCK

### 3 Historical Examples (Correctly Classified)

| Date | Event | Subtype | Reasoning |
|------|-------|---------|-----------|
| 2022-02-24 | Russia launches full-scale invasion of Ukraine | armed_conflict_start | New armed conflict between nation states; massive market impact (oil +10%, gold +2%, EUR -1.5%) |
| 2022-03-08 | US bans Russian oil imports; Biden signs executive order | sanctions_announcement | Official US government sanctions, verified by White House; geopolitical motivation (Ukraine war); energy component noted in conditions |
| 2023-10-07 | Hamas attacks Israel, killing 1,200 people; Israel declares state of war | armed_conflict_start | New front opened in Middle East conflict; major geopolitical risk repricing; oil +3% on supply risk |

### 2 Edge Cases

**Edge Case 1: Election result (near regime_change boundary)**
> "Javier Milei wins Argentina presidential election with 56% vote, promises dollarization and extreme austerity"
- **Classified as**: `regime_change_stable` (not `regime_change_unstable`)
- **Justification**: Democratic election, not a coup. Milei won with clear majority. Despite radical policies, the transition was constitutional. Markets rallied on expectation of fiscal reform. `regime_change_stable` applies even when policies are disruptive, as long as transition is legitimate.

**Edge Case 2: Ceasefire that quickly breaks down**
> "Israel-Gaza ceasefire announced, expected to last 4 days for hostage exchange — Nov 2023"
- **Classified as**: `armed_conflict_ceasefire` (with confidence 0.75 vs typical 0.80+)
- **Justification**: Technically a ceasefire even if temporary. Confidence reduced due to known short duration. Market impact appropriately muted. If ceasefire is conditional or limited, reduce confidence by 0.1.

### Common Confusions: CAT-03
- **sanctions_announcement (CAT-03) vs export_restriction_commodity (CAT-05)**: Sanctions are geopolitically motivated comprehensive restrictions on a country. Export restrictions are trade policy tools. India banning wheat exports = CAT-05. US banning Russian oil = CAT-03 (geopolitical).
- **armed_conflict_escalation vs armed_conflict_start**: Escalation requires a pre-existing conflict. If no conflict existed before, always start.
- **diplomatic_crisis vs armed_conflict**: Diplomatic crisis = no military action. Any armed engagement (even brief skirmish) = armed_conflict subtype.

---

## CAT-04 — ENERGY_COMMODITY_SHOCK

### 3 Historical Examples (Correctly Classified)

| Date | Event | Subtype | Reasoning |
|------|-------|---------|-----------|
| 2022-10-05 | OPEC+ agrees to reduce output by 2 million barrels per day, largest cut since 2020 | opec_cut | Formal OPEC+ ministerial decision; -2Mb/d is meaningful cut (>2% of global supply); Brent +3% same day |
| 2019-09-14 | Drone attack on Saudi Abqaiq facility cuts Saudi oil output by 5Mb/d (50%) | oil_supply_disruption | Unplanned supply disruption, extreme magnitude; Brent +15% at open; SPR release considered |
| 2022-09-27 | Nord Stream pipelines sabotaged; gas leaks detected in Baltic Sea | gas_supply_disruption | Major gas infrastructure destruction; permanent supply disruption; EUR/gas prices spiked sharply |

### 2 Edge Cases

**Edge Case 1: IEA emergency SPR release**
> "IEA coordinates release of 60 million barrels from strategic reserves in response to Ukraine war"
- **Classified as**: `oil_supply_disruption` (secondary event, mitigating) or standalone event?
- **Classified as**: `opec_increase` (but from non-OPEC source)
- **Best classification**: CAT-04 `oil_demand_revision_down` is wrong. Actually this is a supply-side response. Use `oil_supply_disruption` with direction -1 (disruption being eased). OR: create contextual note that this is a supply-relief event triggered by the prior disruption.
- **Rule**: SPR releases are classified under CAT-04 as secondary events attached to the originating disruption event.

**Edge Case 2: LNG export terminal fire vs gas shortage**
> "Freeport LNG facility fire removes 2bcf/day of US LNG export capacity for 3 months — Jun 2022"
- **Classified as**: `gas_supply_disruption` (not `port_blockage` CAT-08)
- **Justification**: This is an energy infrastructure disruption (CAT-04) not a logistics disruption (CAT-08). The primary driver affected is `prix_gaz` not `balance_commerciale`. Geography: US exports reduced, EU/Asia LNG spot prices impacted.

### Common Confusions: CAT-04
- **opec_cut vs oil_supply_disruption**: OPEC+ decisions are planned/policy actions. Disruptions are unplanned (accidents, attacks, natural events).
- **gas_supply_disruption (CAT-04) vs shipping_disruption (CAT-08)**: If the disruption is to the gas/energy commodity itself = CAT-04. If disruption is to the logistics/transport network = CAT-08.
- **agricultural_drought (CAT-04) vs drought_major (CAT-09)**: Agricultural focus with commodity price impact = CAT-04. Drought as climate event with broad economic damage = CAT-09.

---

## CAT-05 — TRADE_POLICY

### 3 Historical Examples (Correctly Classified)

| Date | Event | Subtype | Reasoning |
|------|-------|---------|-----------|
| 2018-07-06 | US imposes 25% tariff on $34bn of Chinese goods; China retaliates with equivalent tariffs | trade_war_escalation | Bilateral retaliation cycle actively escalating; simultaneous action-reaction; marks formal start of US-China trade war |
| 2022-10-07 | US announces sweeping semiconductor export controls to China, restricting NVIDIA chip sales | export_restriction_tech | Technology-specific export controls (not tariffs); semiconductor focus; national security motivation |
| 2020-01-15 | US and China sign Phase 1 trade deal; US agrees to cut some tariffs in exchange for Chinese purchase commitments | trade_war_deescalation | Formal partial truce; tariff rollbacks agreed; risk sentiment improved |

### 2 Edge Cases

**Edge Case 1: Tariff threat that is later implemented**
> "Trump tweets 'If China doesn't make a deal, I will raise tariffs to 25% on all remaining $300bn' — May 2019"
- **Classified as**: `tariff_threat` at time of tweet
- **When tariffs implemented (May 10)**: reclassified as `tariff_hike`
- **Rule**: Classify at point in time. Threats and implementations are separate events with different impact coefficients.

**Edge Case 2: Bilateral investment treaty vs FTA**
> "US and EU announce launch of negotiations for Transatlantic Trade and Investment Partnership (TTIP)"
- **Classified as**: `trade_agreement_signed` (LOW confidence ~0.65) or separate category?
- **Best classification**: NOT `trade_agreement_signed` (no deal signed yet). This is a diplomatic signal. Use `diplomatic_crisis` complement: there is no subtype for "trade negotiations launched." Closest: CAT-05 with subtype `trade_war_deescalation` if tensions were high, or NO classification (defer to "Other" with reasoning).
- **Rule**: Negotiations launched ≠ agreement signed. Require at minimum a preliminary agreement or framework for `trade_agreement_signed`.

### Common Confusions: CAT-05
- **tariff_hike (CAT-05) vs sanctions_announcement (CAT-03)**: Tariffs are economic/trade policy tools. Sanctions are geopolitical tools. If motivation is political/security = CAT-03. If motivation is trade imbalance/protection = CAT-05.
- **export_restriction_tech (CAT-05) vs tech_export_ban (CAT-10)**: Both cover tech export controls. Use CAT-05 when the trade policy dimension dominates (bilateral trade dispute). Use CAT-10 when the technology/structural dimension dominates (semiconductor supply chain restructuring with long-term implications).
- **trade_agreement_signed vs trade_war_deescalation**: Full FTA with legal text = `trade_agreement_signed`. Truce/phase deal without comprehensive legal framework = `trade_war_deescalation`.

---

## CAT-06 — FISCAL_REGULATORY_POLICY

### 3 Historical Examples (Correctly Classified)

| Date | Event | Subtype | Reasoning |
|------|-------|---------|-----------|
| 2020-03-27 | US CARES Act signed: $2.2 trillion stimulus package including $1,200 checks, $600/week unemployment, $500bn corporate loans | fiscal_stimulus_major | >1% GDP threshold (>10% actually), emergency context, broad economic impact |
| 2011-08-05 | S&P downgrades US sovereign credit rating from AAA to AA+, first ever US downgrade | sovereign_downgrade | Official credit rating agency action, maximum authority; paradoxically UST yields fell (safe haven demand) |
| 2023-01-12 | Congress reaches debt ceiling; Treasury begins extraordinary measures; X-date estimated June | debt_ceiling_crisis | US hits statutory debt limit; technical default risk; T-bills near X-date trading at premium |

### 2 Edge Cases

**Edge Case 1: Truss Mini-Budget (fiscal_stimulus_minor becoming crisis)**
> "UK Chancellor Kwarteng announces £45bn unfunded tax cuts — 'mini-budget' — Sep 23 2022"
- **Initially classified as**: `fiscal_stimulus_minor` (tax cuts, ~1.8% GDP)
- **After market reaction**: `sovereign_downgrade` risk, `contagion_spread_widening` (CAT-07)
- **Rule**: Classify the event as announced. Subsequent market reactions are separate events. The mini-budget announcement = `fiscal_stimulus_minor` + `tax_cut_corporate`. The gilt crisis that followed = `liquidity_crisis` (CAT-07). Two separate events.

**Edge Case 2: IMF programme conditions**
> "Argentina agrees to $44bn IMF programme with conditions including spending cuts and peso devaluation"
- **Classified as**: `fiscal_austerity` (not `sovereign_downgrade`)
- **Justification**: The event is a fiscal policy commitment (spending cuts required by IMF). The IMF programme itself is a debt restructuring mechanism. Sovereign downgrade would require a rating agency action. This is fiscal_austerity under external pressure.

### Common Confusions: CAT-06
- **fiscal_stimulus_major (CAT-06) vs climate_policy_new (CAT-09)**: IRA has both fiscal (tax credits) and climate dimensions. Classify by primary causal mechanism. If the news frame is green investment/climate = CAT-09. If news frame is economic stimulus = CAT-06. Note: when in doubt, CAT-09 for IRA/Green Deal.
- **financial_regulation_tighten vs sovereign_downgrade**: Regulation = policy change affecting all banks. Downgrade = specific assessment of sovereign creditworthiness. Very different causal pathways.
- **debt_ceiling_crisis vs sovereign_downgrade**: Debt ceiling = political/legislative risk. Sovereign downgrade = credit agency's assessment. Can co-occur but are different events.

---

## CAT-07 — FINANCIAL_STABILITY

### 3 Historical Examples (Correctly Classified)

| Date | Event | Subtype | Reasoning |
|------|-------|---------|-----------|
| 2023-03-10 | Silicon Valley Bank (SVB) seized by FDIC after $42bn bank run in 48 hours | bank_failure | US regulator (FDIC) takes receivership; $209bn assets; 16th largest US bank; systemic contagion fear |
| 2011-07-18 | Italy/Spain sovereign spread vs Bund widens to 400bps; contagion from Greece spreading | contagion_spread_widening | Multiple sovereign spreads widening simultaneously; systemic EZ risk; Draghi speech needed |
| 2019-09-17 | US overnight repo rate spikes to 10% (vs 2% target); Fed emergency $75bn injection | liquidity_crisis | Acute overnight funding stress; unscheduled Fed intervention required; repo market dysfunction |

### 2 Edge Cases

**Edge Case 1: Credit Suisse restructuring (not formal failure)**
> "Credit Suisse AT1 bonds written to zero in UBS forced merger; CHF 54bn liquidity backstop from SNB — Mar 2023"
- **Classified as**: `bank_rescue` (not `bank_failure`)
- **Justification**: Credit Suisse was acquired (not allowed to fail); AT1 writedown is part of rescue mechanism; depositors protected. The failure was avoided by government orchestration. However, classifying `bank_failure` for CS would also be defensible for the initial bank run event (March 15-17). Rule: if regulators manage an orderly resolution = `bank_rescue`. If uncontrolled collapse occurs = `bank_failure`.

**Edge Case 2: Flash Crash with lasting impact**
> "Dow drops 1,000 points in minutes on August 24 2015 China growth fears; recovers partially but not fully"
- **Classified as**: `market_crash` (not `flash_crash`)
- **Justification**: Flash crash = full reversal within same session. August 24 saw a -6.6% S&P open that only partially recovered (closed -3.9%). The partial recovery and lasting repricing makes this a `market_crash`. Rule: if end-of-day close is >2% below open high = `market_crash`. If full intraday reversal = `flash_crash`.

### Common Confusions: CAT-07
- **bank_failure vs credit_event_corporate**: Bank failure is specific to depository institutions and has systemic contagion risk. Corporate default can be any non-bank entity (Enron, Lehman is actually bank_failure, Evergrande = credit_event_corporate).
- **market_crash vs flash_crash**: Duration and reversal are the key distinguishers. Flash = intraday full reversal. Crash = multi-day repricing.
- **liquidity_crisis vs bank_failure**: Liquidity crisis = the system runs dry. Bank failure = a specific institution fails. A bank failure can trigger a liquidity crisis (but not vice versa).

---

## CAT-08 — SUPPLY_CHAIN_DISRUPTION

### 3 Historical Examples (Correctly Classified)

| Date | Event | Subtype | Reasoning |
|------|-------|---------|-----------|
| 2021-03-23 | Ever Given container ship runs aground in Suez Canal, blocking all traffic for 6 days | port_blockage | Physical blockage of critical shipping lane; $9bn/day in global trade disrupted |
| 2021-11-01 | Global chip shortage reported affecting auto, consumer electronics, appliances industries; lead times >52 weeks | semiconductor_shortage | Structural shortage across multiple industries; 52-week lead times confirmed; auto production curtailed globally |
| 2024-01-12 | Houthi attacks on Red Sea shipping force major carriers (Maersk, MSC) to reroute around Cape of Good Hope; freight rates +300% | shipping_disruption | Persistent rerouting of global shipping away from critical lane; sustained freight rate spike; inflationary implications |

### 2 Edge Cases

**Edge Case 1: COVID supply shock (supply or demand?)**
> "Chinese factory output collapses in February 2020 as COVID lockdowns shut Wuhan factories"
- **Classified as**: `pandemic_supply_shock` (not `factory_shutdown_major`)
- **Justification**: The pandemic dimension makes this systemic, not company/sector specific. A single major factory shutdown = `factory_shutdown_major`. When a pandemic causes nationwide closures = `pandemic_supply_shock`. Scale and cause determine classification.

**Edge Case 2: US longshoremen strike threatening port closures**
> "US East Coast longshoremen authorize strike vote; ILA threatens to shut 36 ports handling 50% of US trade — Sep 2024"
- **Classified as**: `port_blockage` (prospective, confidence 0.75)
- **Justification**: Strike threat at major US ports qualifies as `port_blockage` even pre-implementation if threat is credible and authorized. Confidence reduced to 0.75 for threat vs 0.85+ for actual shutdown.

### Common Confusions: CAT-08
- **shipping_disruption vs port_blockage**: Port blockage = specific port or canal physically blocked (Ever Given). Shipping disruption = broader network disruption (Red Sea threat causing rerouting, Panama Canal drought).
- **semiconductor_shortage (CAT-08) vs tech_export_ban (CAT-10)**: Shortage = supply-demand imbalance. Export ban = political/regulatory restriction. Both affect semiconductor supply but through different mechanisms.
- **pandemic_supply_shock vs factory_shutdown_major**: Scale determines the classification. Single major factory = factory_shutdown. Pandemic affecting entire industrial economy = pandemic_supply_shock.

---

## CAT-09 — CLIMATE_NATURAL_DISASTER

### 3 Historical Examples (Correctly Classified)

| Date | Event | Subtype | Reasoning |
|------|-------|---------|-----------|
| 2022-08-16 | Biden signs Inflation Reduction Act: $369bn in climate and clean energy spending over 10 years | climate_policy_new | Landmark US climate legislation; largest climate investment in US history; direct market impact on clean energy equities |
| 2022-09-28 | Hurricane Ian makes landfall in Florida as Category 4, estimated $100bn+ in damages | hurricane_typhoon | Category 4 hurricane; major economic damage to Florida; insurance sector impact; oil refining at risk |
| 2011-03-11 | Magnitude 9.0 earthquake + tsunami hits Tohoku; Fukushima Daiichi nuclear plant loses power | earthquake_tsunami | Largest Japanese earthquake on record; Fukushima = nuclear energy crisis; markets: Nikkei -6.2%, JPY strengthened paradoxically |

### 2 Edge Cases

**Edge Case 1: European drought affecting hydropower**
> "Rhine River water levels fall to historic lows, disrupting industrial shipping and threatening hydropower in Germany, Switzerland — Aug 2022"
- **Classified as**: `drought_major` (CAT-09, not CAT-04)
- **Justification**: The primary event is a climate/weather phenomenon (drought). The economic impact runs through hydropower, industrial shipping, and agricultural channels. While `prix_gaz` is affected, the root cause is climate. Rule: when the event is a weather phenomenon = CAT-09. When the event is a commodity market decision = CAT-04.

**Edge Case 2: Wildfire causing utility company bankruptcy**
> "PG&E files for bankruptcy citing $30bn in wildfire liabilities from 2017-2018 California fires"
- **Classified as**: `credit_event_corporate` (CAT-07) not `wildfire_major` (CAT-09)
- **Justification**: The bankruptcy filing is the financial event. The original wildfires were CAT-09. These are two separate events months apart. Rule: classify the proximate event. The bankruptcy = CAT-07. The wildfires that caused it = separate historical CAT-09 events.

### Common Confusions: CAT-09
- **climate_policy_new (CAT-09) vs fiscal_stimulus_major (CAT-06)**: IRA = CAT-09 because primary mechanism is climate/energy transition. Pure infrastructure spending without climate dimension = CAT-06. Hybrid: classify by the dominant market narrative at announcement.
- **drought_major (CAT-09) vs agricultural_drought (CAT-04)**: When a drought primarily impacts food commodities/prices = CAT-04. When drought is a broader economic/climate event (affecting hydropower, industry, water supply) = CAT-09.
- **hurricane_typhoon vs flood_major**: Hurricanes/typhoons are the weather system. Floods are the consequence. If the flood is caused by a named hurricane = `hurricane_typhoon`. If flood is standalone (monsoon, river overflow) = `flood_major`.

---

## CAT-10 — TECHNOLOGY_STRUCTURAL

### 3 Historical Examples (Correctly Classified)

| Date | Event | Subtype | Reasoning |
|------|-------|---------|-----------|
| 2022-11-30 | OpenAI launches ChatGPT; reaches 1 million users in 5 days; triggers AI investment race globally | ai_breakthrough_major | Transformative product launch; general purpose AI technology; triggered hundreds of billions in corporate AI investment commitments |
| 2022-10-07 | US Commerce Dept announces sweeping chip export controls to China: bans on advanced GPUs, chip-making equipment, US persons | tech_export_ban | National security-motivated technology controls; semiconductor-specific; NVIDIA stock -3.7%, ASML -7% |
| 2021-05-07 | Colonial Pipeline ransomware attack shuts largest US fuel pipeline; fuel shortages along US East Coast | cyber_attack_critical_infra | Critical infrastructure (energy); ransomware = criminal/state actor; fuel supply disruption; US declares emergency |

### 2 Edge Cases

**Edge Case 1: DeepSeek releases open-source AI model disrupting Nvidia**
> "DeepSeek R1 release Jan 2025: matches GPT-4 performance at fraction of compute cost; Nvidia stock -17% in one day"
- **Classified as**: `ai_breakthrough_major` (not `productivity_shock_positive`)
- **Justification**: This is a capability breakthrough announcement, not a measured productivity gain. `ai_breakthrough_major` covers all major AI capability events regardless of who benefits. The market reaction (Nvidia selloff) is a secondary effect of the primary AI breakthrough.

**Edge Case 2: EU DMA enforcement action vs US DOJ lawsuit**
> "EU regulators fine Apple €1.8bn for App Store anti-steering rules violation under DMA — Mar 2024"
- **Classified as**: `tech_antitrust_action` (confidence 0.85)
- **Justification**: DMA enforcement is the EU's technology antitrust/competition mechanism. Classified as `tech_antitrust_action` regardless of whether it's EU or US action. Note: EU DMA actions have faster enforcement timelines than US DOJ cases, so confidence should be higher for EU actions that have already resulted in fines.

### Common Confusions: CAT-10
- **ai_breakthrough_major vs productivity_shock_positive**: AI breakthrough = specific product/capability announcement. Productivity shock = measured aggregate economic productivity gain (observed, not speculated). Use `ai_breakthrough_major` for all near-term AI announcements; `productivity_shock_positive` only when productivity gains are confirmed in data.
- **tech_export_ban (CAT-10) vs export_restriction_tech (CAT-05)**: Both cover technology export controls. CAT-10 = structural/strategic dimension dominant (long-term supply chain impact, AI/semiconductor race). CAT-05 = trade policy dimension dominant (bilateral dispute, tariff context).
- **cyber_attack_critical_infra vs cyber_attack_financial**: Critical infrastructure = power grid, water, transport, hospitals. Financial = banks, exchanges, payment systems. Some attacks span both (e.g., attack on clearing house = financial).

---

## GLOBAL CONFUSION MATRIX SUMMARY

| Confusion pair | Decision rule |
|---|---|
| CAT-01 vs CAT-02 | Data release vs CB decision: always classify what HAPPENED |
| CAT-03 vs CAT-05 | Geopolitical motivation vs trade policy motivation |
| CAT-04 vs CAT-09 | Commodity/energy mechanism vs climate/natural disaster mechanism |
| CAT-05 vs CAT-10 | Trade policy frame vs technology/structural frame |
| CAT-06 vs CAT-09 | Fiscal mechanism vs climate/energy transition mechanism |
| CAT-07 vs CAT-01 | Institution-specific event vs system-wide CB action |
| CAT-08 vs CAT-04 | Logistics/supply chain mechanism vs energy/commodity mechanism |
| Flash crash vs market crash | Full intraday reversal vs lasting repricing |
| Threat vs implementation | Always classify at time of event; threats and implementations are separate |

---

## EXPECTED CLASSIFICATION DISTRIBUTION

Based on global financial news flow analysis:

| Category | Expected % of classified events |
|---|---|
| CAT-02 MACRO_DATA_RELEASE | 28% |
| CAT-01 MONETARY_POLICY | 18% |
| CAT-06 FISCAL_REGULATORY | 12% |
| CAT-05 TRADE_POLICY | 10% |
| CAT-03 GEOPOLITICAL_SHOCK | 9% |
| CAT-04 ENERGY_COMMODITY | 8% |
| CAT-07 FINANCIAL_STABILITY | 6% |
| CAT-09 CLIMATE_NATURAL | 4% |
| CAT-08 SUPPLY_CHAIN | 3% |
| CAT-10 TECHNOLOGY | 2% |
| OTHER | <2% |
