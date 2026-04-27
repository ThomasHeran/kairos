from __future__ import annotations

import json
from pathlib import Path
from uuid import UUID, uuid5


ROOT = Path(__file__).resolve().parents[1]
KB_PATH = ROOT / "config" / "knowledge_base_v1.json"
SQL_PATH = ROOT / "db" / "seed_knowledge_base_v1.sql"
LOOKUP_PATH = ROOT / "docs" / "event_driver_lookup.json"
TAXONOMY_PATH = ROOT / "config" / "taxonomy_v1.json"
NS = UUID("7f7191a1-3d17-4931-a108-df1b226ff5ba")
PROPAGATION_ATTENUATION = 0.6


def stable_uuid(kind: str, key: str) -> str:
    return str(uuid5(NS, f"{kind}:{key}"))


def delay_days(delay: str) -> int:
    return {
        "immediate": 0,
        "1-4w": 14,
        "1-6m": 90,
        "6m+": 270,
    }[delay]


def horizon_label(delay: str) -> str:
    return {
        "immediate": "immediate",
        "1-4w": "weeks",
        "1-6m": "months",
        "6m+": "structural",
    }[delay]


def intensity_label(value: float) -> str:
    score = abs(value)
    if score >= 0.67:
        return "strong"
    if score >= 0.34:
        return "moderate"
    return "low"


def sql_quote(value: str) -> str:
    return "'" + value.replace("'", "''") + "'"


def sql_json(value: object) -> str:
    return sql_quote(json.dumps(value, ensure_ascii=True, separators=(",", ":"))) + "::jsonb"


def sql_array(values: list[str]) -> str:
    if not values:
        return "ARRAY[]::text[]"
    return "ARRAY[" + ", ".join(sql_quote(value) for value in values) + "]"


def scaled_template(
    template: dict[str, tuple[float, str]], factor: float = 1.0
) -> dict[str, tuple[float, str]]:
    scaled: dict[str, tuple[float, str]] = {}
    for asset_id, (score, delay) in template.items():
        adjusted = max(-0.99, min(0.99, round(score * factor, 3)))
        scaled[asset_id] = (adjusted, delay)
    return scaled


def with_overrides(
    template: dict[str, tuple[float, str]],
    overrides: dict[str, tuple[float, str]],
) -> dict[str, tuple[float, str]]:
    result = dict(template)
    result.update(overrides)
    return result


taxonomy = json.loads(TAXONOMY_PATH.read_text())
lookup = json.loads(LOOKUP_PATH.read_text())
taxonomy_cat_counts = {
    category["cat_id"]: len(category["subtypes"]) for category in taxonomy["categories"]
}

drivers = [
    {
        "slug": "taux_directeurs",
        "label_fr": "Taux directeurs",
        "label_en": "Policy rates",
        "name": "Taux directeurs des banques centrales",
        "category": "monetary",
        "description": "Niveau du taux directeur implicite pour la zone ou l'economie de reference.",
        "sources_mesure": ["Fed", "ECB", "BoE", "BoJ", "BIS"],
        "frequence": "event-driven / quotidienne",
        "unite": "%",
    },
    {
        "slug": "liquidite_globale",
        "label_fr": "Liquidite globale",
        "label_en": "Global liquidity",
        "name": "Liquidite globale",
        "category": "financial",
        "description": "Conditions globales de bilan des banques centrales et abondance de liquidite en dollars.",
        "sources_mesure": ["Fed balance sheet", "ECB APP/PEPP", "BIS liquidity indicators"],
        "frequence": "hebdomadaire",
        "unite": "index",
    },
    {
        "slug": "liquidite_bancaire",
        "label_fr": "Liquidite bancaire",
        "label_en": "Bank liquidity",
        "name": "Liquidite du systeme bancaire",
        "category": "financial",
        "description": "Disponibilite de collateraux et de depots dans le systeme bancaire.",
        "sources_mesure": ["Bank reserves", "Funding spreads", "Bank earnings"],
        "frequence": "hebdomadaire",
        "unite": "index",
    },
    {
        "slug": "conditions_credit",
        "label_fr": "Conditions de credit",
        "label_en": "Credit conditions",
        "name": "Conditions de credit",
        "category": "credit",
        "description": "Tightening ou easing de l'offre de credit bancaire et de marche.",
        "sources_mesure": ["SLOOS", "ECB BLS", "Corporate lending surveys"],
        "frequence": "mensuelle / trimestrielle",
        "unite": "index",
    },
    {
        "slug": "spreads_credit",
        "label_fr": "Spreads de credit",
        "label_en": "Credit spreads",
        "name": "Spreads de credit IG/HY",
        "category": "credit",
        "description": "Prime de risque demandee sur la dette corporate investment grade et high yield.",
        "sources_mesure": ["ICE BofA OAS", "CDX", "iTraxx"],
        "frequence": "quotidienne",
        "unite": "bps",
    },
    {
        "slug": "spreads_souverains",
        "label_fr": "Spreads souverains",
        "label_en": "Sovereign spreads",
        "name": "Spreads souverains",
        "category": "sovereign",
        "description": "Prime de risque souveraine versus Bund ou Treasury de reference.",
        "sources_mesure": ["Bloomberg sovereign curves", "CDS sovereign", "ECB"],
        "frequence": "quotidienne",
        "unite": "bps",
    },
    {
        "slug": "inflation_headline",
        "label_fr": "Inflation headline",
        "label_en": "Headline inflation",
        "name": "Inflation headline",
        "category": "prices",
        "description": "Variation annuelle du CPI/IPC, incluant energie et alimentation.",
        "sources_mesure": ["BLS CPI", "Eurostat HICP", "ONS CPI"],
        "frequence": "mensuelle",
        "unite": "% yoy",
    },
    {
        "slug": "inflation_core",
        "label_fr": "Inflation core",
        "label_en": "Core inflation",
        "name": "Inflation core",
        "category": "prices",
        "description": "Inflation sous-jacente hors composantes volatiles, plus utile pour la reaction des banques centrales.",
        "sources_mesure": ["Core CPI", "Core PCE", "Core HICP"],
        "frequence": "mensuelle",
        "unite": "% yoy",
    },
    {
        "slug": "anticipations_inflation",
        "label_fr": "Anticipations d'inflation",
        "label_en": "Inflation expectations",
        "name": "Anticipations d'inflation",
        "category": "expectations",
        "description": "Breakevens 5y5y et surveys de menages/entreprises sur l'inflation future.",
        "sources_mesure": ["5y5y breakevens", "UMich survey", "ECB SPF"],
        "frequence": "quotidienne / mensuelle",
        "unite": "%",
    },
    {
        "slug": "croissance_pib",
        "label_fr": "Croissance PIB",
        "label_en": "GDP growth",
        "name": "Croissance du PIB",
        "category": "growth",
        "description": "Impulsion de croissance reelle, proxifiee par PIB et nowcasts.",
        "sources_mesure": ["GDP releases", "Nowcasts", "OECD CLI"],
        "frequence": "trimestrielle",
        "unite": "% qoq",
    },
    {
        "slug": "emploi_chomage",
        "label_fr": "Emploi / chomage",
        "label_en": "Labor market",
        "name": "Emploi et chomage",
        "category": "growth",
        "description": "Solidite du marche du travail via NFP, taux de chomage et job openings.",
        "sources_mesure": ["BLS jobs report", "Eurostat unemployment", "JOLTS"],
        "frequence": "mensuelle",
        "unite": "%",
    },
    {
        "slug": "investissement",
        "label_fr": "Investissement",
        "label_en": "Investment",
        "name": "Investissement prive",
        "category": "growth",
        "description": "FBCF privee et depenses capex cycliques.",
        "sources_mesure": ["GDP detail", "Capex guidance", "PMI new orders"],
        "frequence": "trimestrielle",
        "unite": "% gdp",
    },
    {
        "slug": "consommation",
        "label_fr": "Consommation",
        "label_en": "Consumption",
        "name": "Consommation des menages",
        "category": "growth",
        "description": "Dynamique de demande finale des menages et resilience du revenu reel.",
        "sources_mesure": ["Retail sales", "Consumption expenditures", "Consumer surveys"],
        "frequence": "mensuelle",
        "unite": "% gdp",
    },
    {
        "slug": "usd_strength",
        "label_fr": "Force du dollar",
        "label_en": "USD strength",
        "name": "Force du dollar",
        "category": "fx",
        "description": "Direction du dollar global, captee via DXY et flux refuges.",
        "sources_mesure": ["DXY", "Broad dollar index", "Cross-asset flows"],
        "frequence": "quotidienne",
        "unite": "index",
    },
    {
        "slug": "prix_petrole",
        "label_fr": "Prix du petrole",
        "label_en": "Oil price",
        "name": "Prix du petrole",
        "category": "commodity",
        "description": "Prix spot et futures du Brent/WTI comme choc energetique global.",
        "sources_mesure": ["WTI", "Brent", "EIA inventories"],
        "frequence": "quotidienne",
        "unite": "USD/bbl",
    },
    {
        "slug": "prix_metaux",
        "label_fr": "Prix des metaux",
        "label_en": "Industrial metals prices",
        "name": "Prix des metaux industriels",
        "category": "commodity",
        "description": "Prix du cuivre, aluminium et panier de metaux cycliques.",
        "sources_mesure": ["LME", "COMEX", "PMI input prices"],
        "frequence": "quotidienne",
        "unite": "index",
    },
    {
        "slug": "sentiment_marche",
        "label_fr": "Sentiment de marche",
        "label_en": "Market sentiment",
        "name": "Sentiment de marche",
        "category": "market",
        "description": "Appetit pour le risque / aversion au risque, via VIX, credit et breadth.",
        "sources_mesure": ["VIX", "MOVE", "Breadth indicators"],
        "frequence": "quotidienne",
        "unite": "index",
    },
    {
        "slug": "risque_geopolitique",
        "label_fr": "Risque geopolitique",
        "label_en": "Geopolitical risk",
        "name": "Risque geopolitique",
        "category": "market",
        "description": "Niveau de tension geopolitique a portee macro, militaire ou diplomatique.",
        "sources_mesure": ["GPR index", "Event tracking", "Commodity shipping stress"],
        "frequence": "event-driven",
        "unite": "index",
    },
    {
        "slug": "dette_publique",
        "label_fr": "Dette publique",
        "label_en": "Public debt",
        "name": "Dette publique",
        "category": "fiscal",
        "description": "Charge et trajectoire de dette souveraine rapportee au PIB.",
        "sources_mesure": ["Treasury statements", "Debt management offices", "IMF WEO"],
        "frequence": "trimestrielle",
        "unite": "% gdp",
    },
    {
        "slug": "balance_commerciale",
        "label_fr": "Balance commerciale",
        "label_en": "Trade balance",
        "name": "Balance commerciale",
        "category": "trade",
        "description": "Solde commercial et deterioration / amelioration des flux exterieurs.",
        "sources_mesure": ["Trade balance releases", "Customs data", "Current account"],
        "frequence": "mensuelle",
        "unite": "USD bn",
    },
]

core_driver_ids = {driver["slug"] for driver in drivers}
non_core_lookup_drivers = ["prix_gaz", "prix_agricoles"]

arcs_raw = [
    ("taux_directeurs", "conditions_credit", -1, "strong", 0.82, "1-4w", [], 0.91, "Rate hikes tighten bank lending standards with a short lag."),
    ("taux_directeurs", "liquidite_globale", -1, "strong", 0.74, "1-4w", [], 0.88, "Balance sheet tightening and higher policy rates drain global dollar liquidity."),
    ("taux_directeurs", "spreads_credit", 1, "moderate", 0.63, "1-4w", [], 0.86, "Higher discount rates lift refinancing stress for corporate issuers."),
    ("taux_directeurs", "usd_strength", 1, "moderate", 0.58, "immediate", [], 0.84, "Rate differentials support USD through carry and safe-rate demand."),
    ("taux_directeurs", "croissance_pib", -1, "moderate", 0.46, "1-6m", [], 0.77, "Tighter policy slows activity with a several-quarter lag."),
    ("taux_directeurs", "inflation_headline", -1, "low", 0.28, "1-6m", [], 0.72, "Disinflation works with a lag via demand destruction and financing costs."),
    ("taux_directeurs", "investissement", -1, "moderate", 0.55, "1-6m", [], 0.81, "Capex is rate-sensitive through hurdle rates and credit availability."),
    ("liquidite_globale", "spreads_souverains", -1, "strong", 0.76, "1-4w", [], 0.89, "QE-style liquidity compresses sovereign term premia and spreads."),
    ("liquidite_globale", "conditions_credit", 1, "strong", 0.78, "1-4w", [], 0.88, "Abundant reserves and funding conditions ease bank credit creation."),
    ("liquidite_globale", "sentiment_marche", 1, "moderate", 0.52, "immediate", [], 0.8, "Liquidity support improves cross-asset risk appetite."),
    ("liquidite_globale", "usd_strength", -1, "moderate", 0.44, "1-4w", [], 0.76, "Dollar liquidity expansion tends to soften the broad USD."),
    ("liquidite_bancaire", "conditions_credit", 1, "strong", 0.81, "immediate", [], 0.87, "Banks with better liquidity buffers lend more readily."),
    ("liquidite_bancaire", "spreads_credit", -1, "moderate", 0.59, "immediate", [], 0.79, "Funding stress relief narrows corporate spread compensation."),
    ("conditions_credit", "investissement", 1, "strong", 0.72, "1-6m", [], 0.88, "Easier bank lending transmits directly into capex."),
    ("conditions_credit", "consommation", 1, "moderate", 0.47, "1-6m", [], 0.76, "Consumer credit availability lifts durable goods demand."),
    ("conditions_credit", "croissance_pib", 1, "strong", 0.68, "1-6m", [], 0.86, "Broad easing in credit conditions supports aggregate demand."),
    ("conditions_credit", "spreads_credit", -1, "moderate", 0.51, "1-4w", [], 0.78, "Looser financing conditions compress IG/HY spreads."),
    ("spreads_credit", "croissance_pib", -1, "moderate", 0.59, "1-6m", [], 0.83, "Wider spreads precede weaker investment and activity."),
    ("spreads_credit", "sentiment_marche", -1, "moderate", 0.53, "immediate", [], 0.82, "Credit stress quickly deteriorates risk sentiment."),
    ("spreads_souverains", "conditions_credit", -1, "moderate", 0.42, "1-4w", [], 0.74, "Sovereign stress bleeds into domestic bank balance sheets and lending."),
    ("spreads_souverains", "dette_publique", 1, "low", 0.34, "1-6m", [], 0.71, "Higher sovereign funding costs worsen debt-service dynamics."),
    ("inflation_headline", "anticipations_inflation", 1, "strong", 0.74, "1-4w", [], 0.87, "Repeated upside CPI prints re-anchor medium-term expectations higher."),
    ("inflation_headline", "taux_directeurs", 1, "strong", 0.69, "1-4w", [{"driver": "inflation_headline", "operator": ">", "threshold": 3.0}], 0.88, "Central banks react faster when headline inflation breaches comfort zones."),
    ("inflation_headline", "consommation", -1, "moderate", 0.36, "1-4w", [], 0.73, "Real income compression weighs on household demand."),
    ("inflation_headline", "usd_strength", 1, "low", 0.27, "immediate", [{"driver": "taux_directeurs", "operator": ">=", "threshold": 3.0}], 0.68, "Inflation surprises can support USD via hawkish repricing."),
    ("inflation_core", "taux_directeurs", 1, "strong", 0.77, "1-4w", [{"driver": "inflation_core", "operator": ">", "threshold": 2.5}], 0.9, "Persistent core inflation is the most reliable trigger for policy tightening."),
    ("inflation_core", "anticipations_inflation", 1, "moderate", 0.61, "1-4w", [], 0.8, "Sticky core services inflation shapes medium-term inflation expectations."),
    ("anticipations_inflation", "taux_directeurs", 1, "moderate", 0.62, "1-4w", [], 0.81, "Breakeven drift higher tightens reaction functions."),
    ("anticipations_inflation", "spreads_souverains", 1, "moderate", 0.49, "immediate", [], 0.76, "Higher inflation expectations raise nominal term premia."),
    ("croissance_pib", "emploi_chomage", -1, "strong", 0.71, "1-6m", [], 0.88, "Stronger real activity reduces unemployment with a lag."),
    ("croissance_pib", "consommation", 1, "strong", 0.66, "1-6m", [], 0.82, "Growth improves income confidence and spending capacity."),
    ("croissance_pib", "investissement", 1, "strong", 0.74, "1-6m", [], 0.87, "Output growth raises capacity utilisation and capex demand."),
    ("croissance_pib", "balance_commerciale", -1, "low", 0.29, "1-6m", [], 0.65, "Domestic-demand booms often widen import-driven trade deficits."),
    ("emploi_chomage", "consommation", -1, "strong", 0.69, "1-4w", [], 0.84, "Rising unemployment weakens household confidence and spending."),
    ("investissement", "croissance_pib", 1, "strong", 0.72, "1-6m", [], 0.84, "Capex feeds directly into GDP through domestic demand and productivity."),
    ("consommation", "inflation_core", 1, "moderate", 0.41, "1-6m", [], 0.74, "Demand resilience sustains services inflation."),
    ("usd_strength", "inflation_headline", -1, "moderate", 0.39, "1-6m", [], 0.73, "A stronger dollar dampens imported inflation."),
    ("usd_strength", "balance_commerciale", -1, "moderate", 0.33, "1-6m", [], 0.69, "Dollar strength reduces export competitiveness and widens trade deficits."),
    ("usd_strength", "prix_metaux", -1, "moderate", 0.45, "immediate", [], 0.77, "Commodity prices often soften when USD funding tightens."),
    ("prix_petrole", "inflation_headline", 1, "strong", 0.83, "1-4w", [], 0.92, "Oil shocks pass rapidly into CPI through fuel and transport."),
    ("prix_petrole", "croissance_pib", -1, "moderate", 0.44, "1-6m", [], 0.8, "Energy taxation on consumers and firms slows growth."),
    ("prix_petrole", "balance_commerciale", -1, "moderate", 0.52, "1-4w", [], 0.78, "Energy-importing economies see trade balances deteriorate when oil rises."),
    ("prix_metaux", "inflation_core", 1, "low", 0.26, "1-4w", [], 0.67, "Input-cost pressure from metals can leak into core goods inflation."),
    ("risque_geopolitique", "prix_petrole", 1, "strong", 0.88, "immediate", [], 0.93, "Conflict near energy routes causes immediate crude risk premia."),
    ("risque_geopolitique", "sentiment_marche", -1, "strong", 0.81, "immediate", [], 0.91, "Geopolitical escalation drives fast risk-off positioning."),
    ("risque_geopolitique", "usd_strength", 1, "strong", 0.73, "immediate", [], 0.86, "Safe-haven flows lift the USD during geopolitical stress."),
    ("risque_geopolitique", "balance_commerciale", -1, "moderate", 0.41, "1-4w", [], 0.74, "Sanctions and route disruptions impair external trade flows."),
    ("sentiment_marche", "spreads_credit", -1, "strong", 0.67, "immediate", [], 0.87, "Improving sentiment narrows corporate risk premia."),
    ("dette_publique", "spreads_souverains", 1, "strong", 0.72, "1-6m", [{"driver": "dette_publique", "operator": ">", "threshold": 90.0}], 0.84, "Debt sustainability concerns widen sovereign spreads once debt ratios become elevated."),
    ("balance_commerciale", "usd_strength", 1, "moderate", 0.36, "1-6m", [], 0.7, "Persistent external surpluses support currency strength over time."),
]

arcs = []
for source, target, direction, intensity, coefficient, delay, conditions, confidence, note in arcs_raw:
    arcs.append(
        {
            "arc_id": stable_uuid("arc", f"{source}->{target}"),
            "source_driver": source,
            "target_driver": target,
            "direction": direction,
            "intensity": intensity,
            "coefficient": coefficient,
            "delay": delay,
            "conditions": conditions,
            "confidence": confidence,
            "empirical_justification": note,
        }
    )

assets = {
    "bonds_sovereign_us": {"asset_class": "bonds_sovereign", "label_fr": "Obligations souveraines US"},
    "bonds_sovereign_ez": {"asset_class": "bonds_sovereign", "label_fr": "Obligations souveraines zone euro"},
    "bonds_ig": {"asset_class": "bonds_corporate", "label_fr": "Credit investment grade"},
    "bonds_hy": {"asset_class": "bonds_corporate", "label_fr": "Credit high yield"},
    "bonds_inflation_linked": {"asset_class": "bonds_sovereign", "label_fr": "Obligations indexees inflation"},
    "equities_us_growth": {"asset_class": "equities", "label_fr": "Actions US growth"},
    "equities_us_value": {"asset_class": "equities", "label_fr": "Actions US value"},
    "equities_banks": {"asset_class": "equities", "label_fr": "Actions bancaires"},
    "equities_energy": {"asset_class": "equities", "label_fr": "Actions energie"},
    "equities_utilities": {"asset_class": "equities", "label_fr": "Actions utilities"},
    "equities_em": {"asset_class": "equities", "label_fr": "Actions emergentes"},
    "usd_dxy": {"asset_class": "fx", "label_fr": "Dollar DXY"},
    "eur_usd": {"asset_class": "fx", "label_fr": "EUR/USD"},
    "jpy_usd": {"asset_class": "fx", "label_fr": "JPY/USD"},
    "em_fx": {"asset_class": "fx", "label_fr": "Devises emergentes"},
    "gold": {"asset_class": "commodities", "label_fr": "Or"},
    "oil_wti": {"asset_class": "commodities", "label_fr": "WTI"},
    "gas_ttf": {"asset_class": "commodities", "label_fr": "Gaz TTF"},
    "metals_industrial": {"asset_class": "commodities", "label_fr": "Metaux industriels"},
    "reits": {"asset_class": "real_estate", "label_fr": "REITs"},
}

TEMPLATE_RATES_UP = {
    "bonds_sovereign_us": (-0.95, "immediate"),
    "bonds_sovereign_ez": (-0.87, "immediate"),
    "bonds_ig": (-0.72, "1-4w"),
    "bonds_hy": (-0.65, "1-4w"),
    "bonds_inflation_linked": (-0.32, "immediate"),
    "equities_us_growth": (-0.86, "immediate"),
    "equities_us_value": (-0.48, "1-4w"),
    "equities_banks": (0.44, "1-4w"),
    "equities_energy": (-0.21, "1-4w"),
    "equities_utilities": (-0.58, "1-4w"),
    "equities_em": (-0.55, "1-4w"),
    "usd_dxy": (0.68, "immediate"),
    "eur_usd": (-0.58, "immediate"),
    "jpy_usd": (-0.41, "immediate"),
    "em_fx": (-0.64, "1-4w"),
    "gold": (-0.52, "immediate"),
    "oil_wti": (-0.17, "1-6m"),
    "gas_ttf": (-0.11, "1-6m"),
    "metals_industrial": (-0.28, "1-6m"),
    "reits": (-0.82, "1-4w"),
}
TEMPLATE_RISK_ON = {
    "bonds_sovereign_us": (-0.38, "1-4w"),
    "bonds_sovereign_ez": (-0.31, "1-4w"),
    "bonds_ig": (0.56, "1-4w"),
    "bonds_hy": (0.74, "1-4w"),
    "bonds_inflation_linked": (0.18, "1-4w"),
    "equities_us_growth": (0.81, "immediate"),
    "equities_us_value": (0.69, "immediate"),
    "equities_banks": (0.72, "1-4w"),
    "equities_energy": (0.46, "1-4w"),
    "equities_utilities": (0.22, "1-4w"),
    "equities_em": (0.78, "1-4w"),
    "usd_dxy": (-0.42, "immediate"),
    "eur_usd": (0.34, "immediate"),
    "jpy_usd": (0.29, "immediate"),
    "em_fx": (0.71, "1-4w"),
    "gold": (-0.24, "immediate"),
    "oil_wti": (0.37, "1-4w"),
    "gas_ttf": (0.16, "1-4w"),
    "metals_industrial": (0.63, "1-4w"),
    "reits": (0.62, "1-4w"),
}
TEMPLATE_CREDIT_STRESS = {
    "bonds_sovereign_us": (0.54, "immediate"),
    "bonds_sovereign_ez": (0.36, "immediate"),
    "bonds_ig": (-0.82, "immediate"),
    "bonds_hy": (-0.93, "immediate"),
    "bonds_inflation_linked": (-0.12, "1-4w"),
    "equities_us_growth": (-0.71, "immediate"),
    "equities_us_value": (-0.63, "immediate"),
    "equities_banks": (-0.86, "immediate"),
    "equities_energy": (-0.41, "1-4w"),
    "equities_utilities": (-0.27, "1-4w"),
    "equities_em": (-0.76, "immediate"),
    "usd_dxy": (0.44, "immediate"),
    "eur_usd": (-0.29, "immediate"),
    "jpy_usd": (-0.36, "immediate"),
    "em_fx": (-0.83, "immediate"),
    "gold": (0.41, "immediate"),
    "oil_wti": (-0.36, "1-4w"),
    "gas_ttf": (-0.14, "1-4w"),
    "metals_industrial": (-0.58, "1-4w"),
    "reits": (-0.74, "1-4w"),
}
TEMPLATE_INFLATION_UP = {
    "bonds_sovereign_us": (-0.82, "immediate"),
    "bonds_sovereign_ez": (-0.71, "immediate"),
    "bonds_ig": (-0.54, "1-4w"),
    "bonds_hy": (-0.34, "1-4w"),
    "bonds_inflation_linked": (0.84, "immediate"),
    "equities_us_growth": (-0.66, "1-4w"),
    "equities_us_value": (0.22, "1-4w"),
    "equities_banks": (0.31, "1-4w"),
    "equities_energy": (0.72, "immediate"),
    "equities_utilities": (-0.24, "1-4w"),
    "equities_em": (-0.28, "1-4w"),
    "usd_dxy": (0.28, "immediate"),
    "eur_usd": (-0.18, "immediate"),
    "jpy_usd": (-0.16, "immediate"),
    "em_fx": (-0.34, "1-4w"),
    "gold": (0.63, "immediate"),
    "oil_wti": (0.81, "immediate"),
    "gas_ttf": (0.72, "immediate"),
    "metals_industrial": (0.46, "1-4w"),
    "reits": (-0.42, "1-4w"),
}
TEMPLATE_GROWTH_UP = {
    "bonds_sovereign_us": (-0.58, "1-4w"),
    "bonds_sovereign_ez": (-0.47, "1-4w"),
    "bonds_ig": (0.31, "1-4w"),
    "bonds_hy": (0.63, "1-4w"),
    "bonds_inflation_linked": (0.37, "1-4w"),
    "equities_us_growth": (0.54, "immediate"),
    "equities_us_value": (0.73, "immediate"),
    "equities_banks": (0.77, "immediate"),
    "equities_energy": (0.59, "1-4w"),
    "equities_utilities": (-0.12, "1-4w"),
    "equities_em": (0.69, "1-4w"),
    "usd_dxy": (0.14, "immediate"),
    "eur_usd": (0.08, "immediate"),
    "jpy_usd": (0.18, "immediate"),
    "em_fx": (0.48, "1-4w"),
    "gold": (-0.19, "1-4w"),
    "oil_wti": (0.62, "1-4w"),
    "gas_ttf": (0.28, "1-4w"),
    "metals_industrial": (0.78, "1-4w"),
    "reits": (0.41, "1-4w"),
}
TEMPLATE_USD_UP = {
    "bonds_sovereign_us": (0.26, "immediate"),
    "bonds_sovereign_ez": (-0.19, "immediate"),
    "bonds_ig": (-0.18, "1-4w"),
    "bonds_hy": (-0.29, "1-4w"),
    "bonds_inflation_linked": (-0.11, "1-4w"),
    "equities_us_growth": (-0.22, "1-4w"),
    "equities_us_value": (-0.09, "1-4w"),
    "equities_banks": (-0.06, "1-4w"),
    "equities_energy": (-0.18, "1-4w"),
    "equities_utilities": (0.04, "1-4w"),
    "equities_em": (-0.66, "immediate"),
    "usd_dxy": (0.95, "immediate"),
    "eur_usd": (-0.87, "immediate"),
    "jpy_usd": (-0.61, "immediate"),
    "em_fx": (-0.82, "immediate"),
    "gold": (-0.52, "immediate"),
    "oil_wti": (-0.33, "1-4w"),
    "gas_ttf": (-0.21, "1-4w"),
    "metals_industrial": (-0.46, "1-4w"),
    "reits": (-0.17, "1-4w"),
}
TEMPLATE_OIL_UP = {
    "bonds_sovereign_us": (-0.43, "1-4w"),
    "bonds_sovereign_ez": (-0.39, "1-4w"),
    "bonds_ig": (-0.24, "1-4w"),
    "bonds_hy": (-0.14, "1-4w"),
    "bonds_inflation_linked": (0.58, "immediate"),
    "equities_us_growth": (-0.31, "1-4w"),
    "equities_us_value": (0.18, "1-4w"),
    "equities_banks": (0.12, "1-4w"),
    "equities_energy": (0.94, "immediate"),
    "equities_utilities": (-0.11, "1-4w"),
    "equities_em": (-0.07, "1-4w"),
    "usd_dxy": (0.12, "immediate"),
    "eur_usd": (-0.06, "immediate"),
    "jpy_usd": (-0.04, "immediate"),
    "em_fx": (-0.19, "1-4w"),
    "gold": (0.29, "immediate"),
    "oil_wti": (0.98, "immediate"),
    "gas_ttf": (0.52, "immediate"),
    "metals_industrial": (0.17, "1-4w"),
    "reits": (-0.23, "1-4w"),
}
TEMPLATE_GEO_RISK_UP = {
    "bonds_sovereign_us": (0.71, "immediate"),
    "bonds_sovereign_ez": (0.34, "immediate"),
    "bonds_ig": (-0.37, "immediate"),
    "bonds_hy": (-0.68, "immediate"),
    "bonds_inflation_linked": (0.12, "1-4w"),
    "equities_us_growth": (-0.55, "immediate"),
    "equities_us_value": (-0.47, "immediate"),
    "equities_banks": (-0.73, "immediate"),
    "equities_energy": (0.64, "immediate"),
    "equities_utilities": (0.08, "1-4w"),
    "equities_em": (-0.82, "immediate"),
    "usd_dxy": (0.74, "immediate"),
    "eur_usd": (-0.44, "immediate"),
    "jpy_usd": (-0.57, "immediate"),
    "em_fx": (-0.87, "immediate"),
    "gold": (0.81, "immediate"),
    "oil_wti": (0.69, "immediate"),
    "gas_ttf": (0.58, "immediate"),
    "metals_industrial": (-0.18, "1-4w"),
    "reits": (-0.38, "1-4w"),
}
TEMPLATE_SOVEREIGN_STRESS = {
    "bonds_sovereign_us": (-0.21, "immediate"),
    "bonds_sovereign_ez": (-0.83, "immediate"),
    "bonds_ig": (-0.56, "immediate"),
    "bonds_hy": (-0.64, "immediate"),
    "bonds_inflation_linked": (-0.22, "immediate"),
    "equities_us_growth": (-0.31, "immediate"),
    "equities_us_value": (-0.41, "immediate"),
    "equities_banks": (-0.72, "immediate"),
    "equities_energy": (-0.17, "1-4w"),
    "equities_utilities": (-0.26, "1-4w"),
    "equities_em": (-0.58, "immediate"),
    "usd_dxy": (0.39, "immediate"),
    "eur_usd": (-0.42, "immediate"),
    "jpy_usd": (-0.31, "immediate"),
    "em_fx": (-0.63, "immediate"),
    "gold": (0.28, "immediate"),
    "oil_wti": (-0.09, "1-4w"),
    "gas_ttf": (-0.04, "1-4w"),
    "metals_industrial": (-0.29, "1-4w"),
    "reits": (-0.46, "1-4w"),
}
TEMPLATE_METALS_UP = {
    "bonds_sovereign_us": (-0.17, "1-4w"),
    "bonds_sovereign_ez": (-0.14, "1-4w"),
    "bonds_ig": (0.09, "1-4w"),
    "bonds_hy": (0.23, "1-4w"),
    "bonds_inflation_linked": (0.24, "1-4w"),
    "equities_us_growth": (0.18, "1-4w"),
    "equities_us_value": (0.37, "1-4w"),
    "equities_banks": (0.14, "1-4w"),
    "equities_energy": (0.11, "1-4w"),
    "equities_utilities": (-0.06, "1-4w"),
    "equities_em": (0.42, "1-4w"),
    "usd_dxy": (-0.18, "immediate"),
    "eur_usd": (0.09, "immediate"),
    "jpy_usd": (0.04, "immediate"),
    "em_fx": (0.21, "1-4w"),
    "gold": (0.16, "1-4w"),
    "oil_wti": (0.12, "1-4w"),
    "gas_ttf": (0.09, "1-4w"),
    "metals_industrial": (0.97, "immediate"),
    "reits": (0.13, "1-4w"),
}

asset_sensitivity_templates = {
    "taux_directeurs": TEMPLATE_RATES_UP,
    "liquidite_globale": with_overrides(
        scaled_template(TEMPLATE_RISK_ON, 0.9),
        {
            "bonds_sovereign_us": (0.43, "1-4w"),
            "bonds_sovereign_ez": (0.36, "1-4w"),
            "usd_dxy": (-0.51, "immediate"),
            "gold": (0.28, "immediate"),
        },
    ),
    "conditions_credit": with_overrides(
        scaled_template(TEMPLATE_RISK_ON, 0.84),
        {
            "bonds_sovereign_us": (-0.24, "1-4w"),
            "bonds_sovereign_ez": (-0.18, "1-4w"),
            "bonds_ig": (0.73, "1-4w"),
            "bonds_hy": (0.87, "1-4w"),
            "reits": (0.71, "1-4w"),
        },
    ),
    "spreads_credit": TEMPLATE_CREDIT_STRESS,
    "spreads_souverains": TEMPLATE_SOVEREIGN_STRESS,
    "inflation_headline": TEMPLATE_INFLATION_UP,
    "inflation_core": with_overrides(
        scaled_template(TEMPLATE_INFLATION_UP, 0.88),
        {
            "equities_us_growth": (-0.74, "1-4w"),
            "equities_banks": (0.37, "1-4w"),
            "oil_wti": (0.52, "1-4w"),
            "gas_ttf": (0.47, "1-4w"),
        },
    ),
    "anticipations_inflation": with_overrides(
        scaled_template(TEMPLATE_INFLATION_UP, 0.78),
        {
            "gold": (0.72, "immediate"),
            "bonds_inflation_linked": (0.79, "immediate"),
            "equities_energy": (0.52, "1-4w"),
        },
    ),
    "croissance_pib": TEMPLATE_GROWTH_UP,
    "usd_strength": TEMPLATE_USD_UP,
    "prix_petrole": TEMPLATE_OIL_UP,
    "prix_metaux": TEMPLATE_METALS_UP,
    "sentiment_marche": TEMPLATE_RISK_ON,
    "risque_geopolitique": TEMPLATE_GEO_RISK_UP,
}

asset_sensitivity_rows = []
for driver_id, effect_map in asset_sensitivity_templates.items():
    for asset_id, (score, delay) in effect_map.items():
        meta = assets[asset_id]
        asset_sensitivity_rows.append(
            {
                "driver_id": driver_id,
                "asset_id": asset_id,
                "asset_class": meta["asset_class"],
                "asset_label_fr": meta["label_fr"],
                "direction": 1 if score > 0 else -1,
                "sensitivity": abs(score),
                "signed_sensitivity": score,
                "intensity": intensity_label(score),
                "horizon": horizon_label(delay),
                "delay": delay,
            }
        )

event_outcome_templates = {
    "hawkish_cb": {
        "bonds_sovereign_us": {"direction": -1, "change_pct": -2.6, "horizon_days": 10},
        "equities_us_growth": {"direction": -1, "change_pct": -4.3, "horizon_days": 20},
        "usd_dxy": {"direction": 1, "change_pct": 1.9, "horizon_days": 10},
        "gold": {"direction": -1, "change_pct": -1.8, "horizon_days": 10},
    },
    "qe": {
        "bonds_sovereign_us": {"direction": 1, "change_pct": 2.1, "horizon_days": 10},
        "equities_us_growth": {"direction": 1, "change_pct": 5.0, "horizon_days": 20},
        "usd_dxy": {"direction": -1, "change_pct": -1.4, "horizon_days": 10},
        "gold": {"direction": 1, "change_pct": 2.7, "horizon_days": 20},
    },
    "emergency_easing": {
        "bonds_sovereign_us": {"direction": 1, "change_pct": 3.4, "horizon_days": 7},
        "equities_us_growth": {"direction": 1, "change_pct": 6.2, "horizon_days": 15},
        "usd_dxy": {"direction": -1, "change_pct": -1.2, "horizon_days": 7},
        "gold": {"direction": 1, "change_pct": 3.1, "horizon_days": 15},
    },
    "inflation_upside": {
        "bonds_sovereign_us": {"direction": -1, "change_pct": -1.8, "horizon_days": 3},
        "bonds_inflation_linked": {"direction": 1, "change_pct": 0.9, "horizon_days": 5},
        "equities_us_growth": {"direction": -1, "change_pct": -3.1, "horizon_days": 5},
        "usd_dxy": {"direction": 1, "change_pct": 0.8, "horizon_days": 3},
    },
    "growth_down": {
        "bonds_sovereign_us": {"direction": 1, "change_pct": 1.6, "horizon_days": 5},
        "equities_us_growth": {"direction": -1, "change_pct": -4.8, "horizon_days": 10},
        "oil_wti": {"direction": -1, "change_pct": -6.5, "horizon_days": 10},
        "metals_industrial": {"direction": -1, "change_pct": -5.2, "horizon_days": 10},
    },
    "war_shock": {
        "gold": {"direction": 1, "change_pct": 3.4, "horizon_days": 5},
        "oil_wti": {"direction": 1, "change_pct": 7.8, "horizon_days": 5},
        "usd_dxy": {"direction": 1, "change_pct": 1.2, "horizon_days": 5},
        "equities_em": {"direction": -1, "change_pct": -5.5, "horizon_days": 10},
    },
    "oil_shock": {
        "oil_wti": {"direction": 1, "change_pct": 12.0, "horizon_days": 20},
        "bonds_inflation_linked": {"direction": 1, "change_pct": 1.7, "horizon_days": 20},
        "equities_energy": {"direction": 1, "change_pct": 6.8, "horizon_days": 20},
        "bonds_sovereign_us": {"direction": -1, "change_pct": -1.1, "horizon_days": 20},
    },
    "trade_war": {
        "equities_em": {"direction": -1, "change_pct": -4.7, "horizon_days": 20},
        "usd_dxy": {"direction": 1, "change_pct": 1.1, "horizon_days": 10},
        "metals_industrial": {"direction": -1, "change_pct": -4.2, "horizon_days": 20},
        "bonds_sovereign_us": {"direction": 1, "change_pct": 1.0, "horizon_days": 10},
    },
    "trade_war_relief": {
        "equities_em": {"direction": 1, "change_pct": 3.8, "horizon_days": 20},
        "usd_dxy": {"direction": -1, "change_pct": -0.7, "horizon_days": 10},
        "metals_industrial": {"direction": 1, "change_pct": 3.0, "horizon_days": 20},
        "bonds_hy": {"direction": 1, "change_pct": 1.2, "horizon_days": 20},
    },
    "fiscal_stimulus": {
        "equities_us_value": {"direction": 1, "change_pct": 4.4, "horizon_days": 20},
        "equities_banks": {"direction": 1, "change_pct": 5.1, "horizon_days": 20},
        "bonds_sovereign_us": {"direction": -1, "change_pct": -1.4, "horizon_days": 20},
        "oil_wti": {"direction": 1, "change_pct": 4.0, "horizon_days": 20},
    },
    "sovereign_stress": {
        "bonds_sovereign_ez": {"direction": -1, "change_pct": -2.7, "horizon_days": 10},
        "equities_banks": {"direction": -1, "change_pct": -6.2, "horizon_days": 10},
        "usd_dxy": {"direction": 1, "change_pct": 1.0, "horizon_days": 10},
        "gold": {"direction": 1, "change_pct": 1.9, "horizon_days": 10},
    },
    "bank_failure": {
        "bonds_sovereign_us": {"direction": 1, "change_pct": 2.4, "horizon_days": 5},
        "equities_banks": {"direction": -1, "change_pct": -12.0, "horizon_days": 5},
        "bonds_hy": {"direction": -1, "change_pct": -3.2, "horizon_days": 10},
        "gold": {"direction": 1, "change_pct": 2.5, "horizon_days": 10},
    },
    "supply_chain": {
        "oil_wti": {"direction": 1, "change_pct": 4.5, "horizon_days": 10},
        "gas_ttf": {"direction": 1, "change_pct": 6.1, "horizon_days": 10},
        "metals_industrial": {"direction": 1, "change_pct": 3.3, "horizon_days": 10},
        "equities_em": {"direction": -1, "change_pct": -2.9, "horizon_days": 10},
    },
    "climate": {
        "gas_ttf": {"direction": 1, "change_pct": 5.7, "horizon_days": 15},
        "metals_industrial": {"direction": 1, "change_pct": 2.1, "horizon_days": 15},
        "equities_utilities": {"direction": 1, "change_pct": 1.6, "horizon_days": 15},
        "bonds_inflation_linked": {"direction": 1, "change_pct": 0.8, "horizon_days": 15},
    },
    "tech_ban": {
        "equities_em": {"direction": -1, "change_pct": -3.4, "horizon_days": 10},
        "usd_dxy": {"direction": 1, "change_pct": 0.6, "horizon_days": 10},
        "metals_industrial": {"direction": -1, "change_pct": -2.2, "horizon_days": 10},
        "equities_us_growth": {"direction": -1, "change_pct": -1.5, "horizon_days": 10},
    },
}


def lookup_impacts(
    lookup_key: str,
    scale: float = 1.0,
    include_non_core: bool = False,
    overrides: dict[str, dict[str, float | int]] | None = None,
) -> dict[str, dict[str, float | int]]:
    row = lookup[lookup_key]
    impacts: dict[str, dict[str, float | int]] = {}
    for bucket_name, default_delay in (("primary_drivers", "immediate"), ("secondary_drivers", "1-4w")):
        for item in row.get(bucket_name, []):
            driver = item["driver"]
            if not include_non_core and driver not in core_driver_ids:
                continue
            raw = min(0.98, round(item["intensity"] * scale, 3))
            delay = item.get("delay", default_delay)
            impacts[driver] = {
                "direction": item["dir"],
                "magnitude": raw,
                "delay_days": delay_days(delay),
            }
    for driver, patch in (overrides or {}).items():
        current = impacts.setdefault(driver, {"direction": 1, "magnitude": 0.4, "delay_days": 14})
        current.update(patch)
    return impacts


episodes_raw = [
    {
        "label": "Volcker shock tightening",
        "date": "1979-10-06",
        "lookup_key": "MONETARY_POLICY.emergency_action_tightening",
        "geography": ["US"],
        "scale": 1.1,
        "asset_template": "hawkish_cb",
        "data_quality": "medium",
        "lessons": [
            "Policy shock can dominate recession fears in the first phase.",
            "Cross-asset reaction is strongest when inflation credibility is broken.",
        ],
    },
    {
        "label": "ECB rate hike into sovereign stress",
        "date": "2011-04-07",
        "lookup_key": "MONETARY_POLICY.rate_decision_hike",
        "geography": ["EZ"],
        "scale": 1.0,
        "asset_template": "hawkish_cb",
        "data_quality": "high",
        "lessons": [
            "Late-cycle hikes amplify sovereign and bank fragility.",
            "EUR support is short-lived when credit transmission breaks.",
        ],
    },
    {
        "label": "Fed QE1 expansion",
        "date": "2009-03-18",
        "lookup_key": "MONETARY_POLICY.qe_announcement",
        "geography": ["US"],
        "scale": 1.0,
        "asset_template": "qe",
        "data_quality": "high",
        "lessons": [
            "Balance-sheet policy compresses sovereign and credit premia quickly.",
            "USD weakness and gold strength are common first-order effects.",
        ],
    },
    {
        "label": "Taper Tantrum signal",
        "date": "2013-05-22",
        "lookup_key": "MONETARY_POLICY.tapering",
        "geography": ["US", "GLOBAL"],
        "scale": 1.05,
        "asset_template": "hawkish_cb",
        "data_quality": "high",
        "lessons": [
            "Unexpected liquidity withdrawal shocks EM FX before growth data move.",
            "Communication surprise matters more than the first mechanical flow reduction.",
        ],
    },
    {
        "label": "Fed liftoff inflation cycle",
        "date": "2022-03-16",
        "lookup_key": "MONETARY_POLICY.rate_decision_hike",
        "geography": ["US", "GLOBAL"],
        "scale": 1.0,
        "asset_template": "hawkish_cb",
        "data_quality": "high",
        "lessons": [
            "Rate hikes transmit fastest through duration and USD.",
            "Credit and growth damage builds with a lag, not on day one.",
        ],
    },
    {
        "label": "US CPI upside shock",
        "date": "2022-06-10",
        "lookup_key": "MACRO_DATA_RELEASE.inflation_cpi_above",
        "geography": ["US"],
        "scale": 1.1,
        "asset_template": "inflation_upside",
        "data_quality": "high",
        "lessons": [
            "Inflation surprises can reroute the entire rates path in a single session.",
            "Growth equities underperform before credit does.",
        ],
    },
    {
        "label": "Pandemic PMI collapse",
        "date": "2020-03-24",
        "lookup_key": "MACRO_DATA_RELEASE.pmi_contraction",
        "geography": ["GLOBAL"],
        "scale": 1.15,
        "asset_template": "growth_down",
        "data_quality": "high",
        "lessons": [
            "PMI contractions are powerful early warnings for capex and trade weakness.",
            "Market pricing moves ahead of GDP releases.",
        ],
    },
    {
        "label": "US payrolls collapse",
        "date": "2020-04-03",
        "lookup_key": "MACRO_DATA_RELEASE.nfp_below",
        "geography": ["US"],
        "scale": 1.2,
        "asset_template": "growth_down",
        "data_quality": "high",
        "lessons": [
            "Labor shocks hit consumption immediately even when policy support follows.",
            "Bond rally is strongest when payroll weakness coincides with falling oil.",
        ],
        "overrides": {
            "consommation": {"direction": -1, "magnitude": 0.75, "delay_days": 7},
        },
    },
    {
        "label": "Iraq invades Kuwait",
        "date": "1990-08-02",
        "lookup_key": "GEOPOLITICAL_SHOCK.armed_conflict_start",
        "geography": ["MIDDLE_EAST", "GLOBAL"],
        "scale": 1.0,
        "asset_template": "war_shock",
        "data_quality": "medium",
        "lessons": [
            "Oil and gold react immediately to military escalation near supply routes.",
            "Safe-haven dollar demand can coexist with weaker global growth expectations.",
        ],
    },
    {
        "label": "Russia invades Ukraine",
        "date": "2022-02-24",
        "lookup_key": "GEOPOLITICAL_SHOCK.armed_conflict_start",
        "geography": ["EUROPE", "GLOBAL"],
        "scale": 1.1,
        "asset_template": "war_shock",
        "data_quality": "high",
        "lessons": [
            "Europe transmits geopolitical energy shocks faster than the US.",
            "Gas, FX and sovereign spread channels matter alongside crude.",
        ],
    },
    {
        "label": "US restores Iran oil sanctions",
        "date": "2018-11-05",
        "lookup_key": "GEOPOLITICAL_SHOCK.sanctions_announcement",
        "geography": ["US", "MIDDLE_EAST", "GLOBAL"],
        "scale": 1.0,
        "asset_template": "war_shock",
        "data_quality": "high",
        "lessons": [
            "Sanctions shocks move trade balances and oil before they move GDP.",
            "USD and sovereign spreads are key spillover channels.",
        ],
    },
    {
        "label": "Arab oil embargo",
        "date": "1973-10-17",
        "lookup_key": "ENERGY_COMMODITY_SHOCK.oil_supply_disruption",
        "geography": ["MIDDLE_EAST", "GLOBAL"],
        "scale": 1.15,
        "asset_template": "oil_shock",
        "data_quality": "medium",
        "lessons": [
            "Supply shocks generate persistent headline inflation and growth drag.",
            "Energy equities hedge the first-round inflation impulse better than broad equities.",
        ],
    },
    {
        "label": "OPEC+ production cut",
        "date": "2022-10-05",
        "lookup_key": "ENERGY_COMMODITY_SHOCK.opec_cut",
        "geography": ["GLOBAL"],
        "scale": 1.0,
        "asset_template": "oil_shock",
        "data_quality": "high",
        "lessons": [
            "Quota cuts reprice energy inflation quickly even without immediate physical scarcity.",
            "Market positioning changes the second-round rates move.",
        ],
    },
    {
        "label": "Nord Stream halt and EU gas panic",
        "date": "2022-09-02",
        "lookup_key": "ENERGY_COMMODITY_SHOCK.gas_supply_disruption",
        "geography": ["EZ", "GLOBAL"],
        "scale": 1.1,
        "asset_template": "oil_shock",
        "data_quality": "high",
        "lessons": [
            "Regional gas shocks can overwhelm local macro despite limited direct US impact.",
            "Utilities and sovereign curves diverge from US assets in Europe-specific crises.",
        ],
        "overrides": {
            "prix_petrole": {"direction": 1, "magnitude": 0.42, "delay_days": 7},
            "inflation_headline": {"direction": 1, "magnitude": 0.88, "delay_days": 7},
            "croissance_pib": {"direction": -1, "magnitude": 0.58, "delay_days": 60},
        },
    },
    {
        "label": "US-China tariff round",
        "date": "2018-07-06",
        "lookup_key": "TRADE_POLICY.trade_war_escalation",
        "geography": ["US", "CN", "GLOBAL"],
        "scale": 1.0,
        "asset_template": "trade_war",
        "data_quality": "high",
        "lessons": [
            "Trade policy shocks hit confidence and capex before official trade data roll over.",
            "EM FX and industrial metals are efficient fast indicators.",
        ],
    },
    {
        "label": "US-China phase one truce",
        "date": "2020-01-15",
        "lookup_key": "TRADE_POLICY.trade_war_deescalation",
        "geography": ["US", "CN", "GLOBAL"],
        "scale": 1.0,
        "asset_template": "trade_war_relief",
        "data_quality": "high",
        "lessons": [
            "Trade relief improves cyclical beta more than long duration assets.",
            "FX relief is stronger in EM than in EUR crosses.",
        ],
    },
    {
        "label": "US debt ceiling and S&P downgrade",
        "date": "2011-08-05",
        "lookup_key": "FISCAL_REGULATORY_POLICY.debt_ceiling_crisis",
        "geography": ["US", "GLOBAL"],
        "scale": 1.1,
        "asset_template": "sovereign_stress",
        "data_quality": "high",
        "lessons": [
            "Political fiscal brinkmanship widens sovereign premia and damages sentiment.",
            "USD safe-haven behaviour can offset domestic fiscal stress in the short run.",
        ],
    },
    {
        "label": "American Rescue Plan",
        "date": "2021-03-11",
        "lookup_key": "FISCAL_REGULATORY_POLICY.fiscal_stimulus_major",
        "geography": ["US"],
        "scale": 1.0,
        "asset_template": "fiscal_stimulus",
        "data_quality": "high",
        "lessons": [
            "Large fiscal stimulus lifts growth, inflation and debt simultaneously.",
            "Banks and value equities outperform when nominal growth rises.",
        ],
    },
    {
        "label": "Lehman bankruptcy",
        "date": "2008-09-15",
        "lookup_key": "FINANCIAL_STABILITY.bank_failure",
        "geography": ["US", "GLOBAL"],
        "scale": 1.2,
        "asset_template": "bank_failure",
        "data_quality": "high",
        "lessons": [
            "Bank failures propagate instantly via liquidity, credit and confidence.",
            "Credit spreads and bank equities are the fastest stress barometers.",
        ],
    },
    {
        "label": "Silicon Valley Bank collapse",
        "date": "2023-03-10",
        "lookup_key": "FINANCIAL_STABILITY.bank_failure",
        "geography": ["US"],
        "scale": 1.0,
        "asset_template": "bank_failure",
        "data_quality": "high",
        "lessons": [
            "Duration losses can morph into liquidity crises even without immediate credit losses.",
            "Front-end rates can reverse sharply when financial stability replaces inflation as the policy focus.",
        ],
        "overrides": {
            "taux_directeurs": {"direction": -1, "magnitude": 0.32, "delay_days": 7},
        },
    },
    {
        "label": "Ever Given blocks Suez",
        "date": "2021-03-23",
        "lookup_key": "SUPPLY_CHAIN_DISRUPTION.shipping_disruption",
        "geography": ["GLOBAL"],
        "scale": 1.0,
        "asset_template": "supply_chain",
        "data_quality": "high",
        "lessons": [
            "Shipping bottlenecks feed inflation faster than they hit GDP.",
            "Commodity curves react sooner than broad equity indices.",
        ],
    },
    {
        "label": "China lockdown supply shock",
        "date": "2020-02-23",
        "lookup_key": "SUPPLY_CHAIN_DISRUPTION.pandemic_supply_shock",
        "geography": ["CN", "GLOBAL"],
        "scale": 1.1,
        "asset_template": "supply_chain",
        "data_quality": "high",
        "lessons": [
            "Factory shutdowns propagate through inventories, shipping and final goods inflation.",
            "Growth-sensitive commodities underperform after the initial scarcity spike.",
        ],
    },
    {
        "label": "European drought disrupts rivers and crops",
        "date": "2022-07-20",
        "lookup_key": "CLIMATE_NATURAL_DISASTER.drought_major",
        "geography": ["EZ", "GLOBAL"],
        "scale": 1.0,
        "asset_template": "climate",
        "data_quality": "medium",
        "lessons": [
            "Climate shocks hit agriculture, logistics and power costs simultaneously.",
            "Inflation linkers and utilities are more resilient than cyclical equities.",
        ],
        "overrides": {
            "inflation_headline": {"direction": 1, "magnitude": 0.62, "delay_days": 14},
            "balance_commerciale": {"direction": -1, "magnitude": 0.34, "delay_days": 30},
            "croissance_pib": {"direction": -1, "magnitude": 0.31, "delay_days": 60},
        },
    },
    {
        "label": "US chip export ban on China",
        "date": "2022-10-07",
        "lookup_key": "TECHNOLOGY_STRUCTURAL.tech_export_ban",
        "geography": ["US", "CN", "GLOBAL"],
        "scale": 1.0,
        "asset_template": "tech_ban",
        "data_quality": "high",
        "lessons": [
            "Strategic technology controls behave like a blend of trade and geopolitical shocks.",
            "Semiconductor restrictions weaken EM equities before they hit top-line trade data.",
        ],
        "overrides": {
            "risque_geopolitique": {"direction": 1, "magnitude": 0.51, "delay_days": 0},
            "balance_commerciale": {"direction": -1, "magnitude": 0.42, "delay_days": 30},
            "investissement": {"direction": -1, "magnitude": 0.33, "delay_days": 45},
        },
    },
]

episodes = []
for episode in episodes_raw:
    row = lookup[episode["lookup_key"]]
    driver_impacts = lookup_impacts(
        episode["lookup_key"],
        scale=episode.get("scale", 1.0),
        overrides=episode.get("overrides"),
    )
    notes = " | ".join(episode["lessons"])
    episodes.append(
        {
            "episode_id": stable_uuid("episode", f"{episode['date']}|{episode['lookup_key']}|{episode['label']}"),
            "label": episode["label"],
            "date": episode["date"],
            "cat_id": row["cat_id"],
            "subtype_id": row["subtype_id"],
            "geography": episode["geography"],
            "drivers_impacted": driver_impacts,
            "calibration_lessons": episode["lessons"],
            "asset_outcomes": event_outcome_templates[episode["asset_template"]],
            "data_quality": episode["data_quality"],
            "notes": notes,
        }
    )

kb = {
    "version": "knowledge_base_v1",
    "generated_on": "2026-04-27",
    "propagation": {
        "attenuation_per_level": PROPAGATION_ATTENUATION,
        "note": "Kairos standard attenuation applied at each propagation level.",
    },
    "coverage": {
        "taxonomy_categories": taxonomy_cat_counts,
        "lookup_entries": len(lookup),
        "lookup_entries_touching_core_network": len(lookup),
        "non_core_lookup_drivers": non_core_lookup_drivers,
        "note": "Core KB v1 keeps 20 pivot drivers while all 101 lookup entries still map into the core network.",
    },
    "drivers": drivers,
    "causal_arcs": arcs,
    "historical_episodes": episodes,
    "asset_sensitivity": [
        {
            "driver_id": row["driver_id"],
            "asset_id": row["asset_id"],
            "direction": row["direction"],
            "intensity": row["intensity"],
            "horizon": row["horizon"],
            "sensitivity": row["signed_sensitivity"],
        }
        for row in asset_sensitivity_rows
    ],
}


def driver_sql_values() -> str:
    lines = []
    for driver in drivers:
        lines.append(
            "("
            + ", ".join(
                [
                    sql_quote(driver["slug"]),
                    sql_quote(driver["label_fr"]),
                    sql_quote(driver["label_en"]),
                    sql_quote(driver["category"]),
                    sql_quote(driver["unite"]),
                    sql_quote(driver["description"]),
                ]
            )
            + ")"
        )
    return ",\n  ".join(lines)


def arcs_sql_values() -> str:
    lines = []
    for arc in arcs:
        lines.append(
            "("
            + ", ".join(
                [
                    sql_quote(arc["arc_id"]),
                    sql_quote(arc["source_driver"]),
                    sql_quote(arc["target_driver"]),
                    str(arc["direction"]),
                    sql_quote(arc["intensity"]),
                    f"{arc['coefficient']:.3f}",
                    sql_quote(arc["delay"]),
                    sql_json(arc["conditions"]),
                    f"{arc['confidence']:.3f}",
                    sql_quote(arc["empirical_justification"]),
                ]
            )
            + ")"
        )
    return ",\n  ".join(lines)


def episodes_sql_values() -> str:
    lines = []
    for episode in episodes:
        lines.append(
            "("
            + ", ".join(
                [
                    sql_quote(episode["episode_id"]),
                    sql_quote(episode["cat_id"]),
                    sql_quote(episode["subtype_id"]),
                    sql_quote(episode["date"]),
                    sql_quote(episode["label"]),
                    sql_array(episode["geography"]),
                    sql_json(episode["drivers_impacted"]),
                    sql_json(episode["asset_outcomes"]),
                    sql_quote(episode["notes"]),
                    sql_quote(episode["data_quality"]),
                ]
            )
            + ")"
        )
    return ",\n  ".join(lines)


def asset_sql_values() -> str:
    lines = []
    for row in asset_sensitivity_rows:
        lines.append(
            "("
            + ", ".join(
                [
                    sql_quote(row["asset_id"]),
                    sql_quote(row["driver_id"]),
                    f"{row['sensitivity']:.3f}",
                    str(row["direction"]),
                    sql_quote(row["delay"]),
                    sql_quote(row["asset_class"]),
                    sql_quote(row["asset_label_fr"]),
                    sql_quote(f"{row['intensity']} / {row['horizon']}"),
                ]
            )
            + ")"
        )
    return ",\n  ".join(lines)


sql = f"""-- ============================================================================
-- Kairos knowledge base v1
-- Generated from scripts/generate_knowledge_base_v1.py
-- Core KB: 20 drivers, 50 causal arcs, 24 historical episodes, 280 asset rows
-- Kairos propagation attenuation standard: {PROPAGATION_ATTENUATION} per level
-- ============================================================================

BEGIN;

INSERT INTO drivers (driver_id, label_fr, label_en, category, unit, description)
VALUES
  {driver_sql_values()}
ON CONFLICT (driver_id) DO UPDATE SET
  label_fr = EXCLUDED.label_fr,
  label_en = EXCLUDED.label_en,
  category = EXCLUDED.category,
  unit = EXCLUDED.unit,
  description = EXCLUDED.description,
  active = TRUE;

INSERT INTO causal_arcs (
  arc_id, source_driver, target_driver, direction, intensity,
  intensity_coefficient, delay, conditions, confidence, notes
)
VALUES
  {arcs_sql_values()}
ON CONFLICT (source_driver, target_driver) DO UPDATE SET
  arc_id = EXCLUDED.arc_id,
  direction = EXCLUDED.direction,
  intensity = EXCLUDED.intensity,
  intensity_coefficient = EXCLUDED.intensity_coefficient,
  delay = EXCLUDED.delay,
  conditions = EXCLUDED.conditions,
  confidence = EXCLUDED.confidence,
  notes = EXCLUDED.notes,
  active = TRUE,
  last_calibrated = NOW(),
  updated_at = NOW();

INSERT INTO historical_episodes (
  episode_id, cat_id, subtype_id, episode_date, label, geography,
  driver_impacts, asset_outcomes, notes, data_quality
)
VALUES
  {episodes_sql_values()}
ON CONFLICT (episode_id) DO UPDATE SET
  cat_id = EXCLUDED.cat_id,
  subtype_id = EXCLUDED.subtype_id,
  episode_date = EXCLUDED.episode_date,
  label = EXCLUDED.label,
  geography = EXCLUDED.geography,
  driver_impacts = EXCLUDED.driver_impacts,
  asset_outcomes = EXCLUDED.asset_outcomes,
  notes = EXCLUDED.notes,
  data_quality = EXCLUDED.data_quality;

INSERT INTO asset_sensitivity (
  asset_id, driver_id, sensitivity, direction, delay, asset_class, asset_label_fr, notes
)
VALUES
  {asset_sql_values()}
ON CONFLICT (asset_id, driver_id) DO UPDATE SET
  sensitivity = EXCLUDED.sensitivity,
  direction = EXCLUDED.direction,
  delay = EXCLUDED.delay,
  asset_class = EXCLUDED.asset_class,
  asset_label_fr = EXCLUDED.asset_label_fr,
  notes = EXCLUDED.notes,
  last_reviewed = CURRENT_DATE;

COMMIT;
"""


def main() -> None:
    assert len(drivers) == 20
    assert len(arcs) == 50
    assert len(episodes) == 24
    assert len(asset_sensitivity_templates) == 14
    assert len(asset_sensitivity_rows) == 280
    assert {arc["source_driver"] for arc in arcs}.issubset(core_driver_ids)
    assert {arc["target_driver"] for arc in arcs}.issubset(core_driver_ids)
    assert {episode["cat_id"] for episode in episodes} == set(taxonomy_cat_counts)
    assert all(
        any(
            item["driver"] in core_driver_ids
            for item in row.get("primary_drivers", []) + row.get("secondary_drivers", [])
        )
        for row in lookup.values()
    )
    KB_PATH.write_text(json.dumps(kb, ensure_ascii=True, indent=2) + "\n")
    SQL_PATH.write_text(sql)


if __name__ == "__main__":
    main()
