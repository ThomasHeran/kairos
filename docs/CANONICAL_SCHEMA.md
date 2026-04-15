# Kairos — Schéma de données canonique inter-couches (C1 → C2 → C3 → C4 → C5)

> **Version** : 1.0.0 — 2026-04-15
> **Référence taxonomie** : `config/taxonomy_v1.json`
> **Base de données** : migrations dans `db/schema_v2.sql`

Ce document est la **fondation de tout le système Kairos**. Chaque couche (worker) doit s'y conformer exactement. Le champ `cat_id` / `subtype_id` présent en C2, C3, C4 et C5 est une **clé étrangère** vers la table `event_taxonomy` et doit correspondre aux valeurs définies dans `taxonomy_v1.json`.

---

## Vue d'ensemble du pipeline

```
[Sources web]
     │
     ▼
  C1 — Articles bruts (scraping / RSS / API)
     │
     ▼
  C2 — Events qualifiés (classification taxonomie fermée + déduplication)
     │
     ▼
  C3 — Graphe causal (arcs drivers ↔ assets)
     │
     ▼
  C4 — Analyses (moteur de raisonnement, scores d'actifs)
     │
     ▼
  C5 — Prédictions archivées (suivi, vérification, recalibration)
```

---

## 1. Schéma C1 — Article brut

Produit par les agents de scraping / RSS. Stocké dans la table `articles`.

```json
{
  "$schema": "https://json-schema.org/draft/07/schema",
  "title": "C1_RawArticle",
  "description": "Article brut issu du scraping, avant toute qualification.",
  "type": "object",
  "required": ["article_id", "timestamp_scraped", "source", "title", "text_raw", "url"],
  "properties": {
    "article_id": {
      "type": "string",
      "format": "uuid",
      "description": "Identifiant unique de l'article (UUID v4)."
    },
    "timestamp_scraped": {
      "type": "string",
      "format": "date-time",
      "description": "Horodatage ISO8601 du moment où l'article a été collecté."
    },
    "source": {
      "type": "object",
      "required": ["name", "type", "url"],
      "properties": {
        "name": { "type": "string", "description": "Nom lisible de la source (ex: 'Le Monde')." },
        "type": { "type": "string", "enum": ["rss", "scraping", "api"], "description": "Mode de collecte." },
        "url": { "type": "string", "format": "uri", "description": "URL du feed ou de la page source." },
        "authority_score": {
          "type": "number", "minimum": 0.0, "maximum": 1.0,
          "description": "Score de fiabilité/autorité de la source (0=inconnue, 1=source primaire officielle)."
        }
      }
    },
    "title": { "type": "string", "description": "Titre original de l'article." },
    "text_raw": { "type": "string", "description": "Texte complet brut dans la langue d'origine." },
    "text_en": {
      "type": ["string", "null"],
      "description": "Texte traduit en anglais (null si non encore traduit)."
    },
    "language_original": {
      "type": "string",
      "pattern": "^[a-z]{2}$",
      "description": "Code ISO 639-1 de la langue d'origine (ex: 'fr', 'en', 'de')."
    },
    "url": {
      "type": "string", "format": "uri",
      "description": "URL canonique de l'article source."
    },
    "published_at": {
      "type": ["string", "null"], "format": "date-time",
      "description": "Date de publication originale (peut être null si non fournie)."
    },
    "country": {
      "type": ["string", "null"],
      "pattern": "^[A-Z]{2}$",
      "description": "Code ISO 3166-1 alpha-2 du pays de la source (ex: 'FR', 'US')."
    },
    "region": {
      "type": ["string", "null"],
      "enum": ["US", "EZ", "UK", "JP", "CN", "EM", "GLOBAL", null],
      "description": "Région économique principale : US=États-Unis, EZ=Zone Euro, UK=Royaume-Uni, JP=Japon, CN=Chine, EM=Émergents, GLOBAL=mondial."
    }
  }
}
```

### Exemple C1

```json
{
  "article_id": "550e8400-e29b-41d4-a716-446655440000",
  "timestamp_scraped": "2026-04-15T09:32:00Z",
  "source": {
    "name": "Reuters",
    "type": "rss",
    "url": "https://feeds.reuters.com/reuters/businessNews",
    "authority_score": 0.92
  },
  "title": "Fed raises rates by 25 bps, signals pause ahead",
  "text_raw": "The Federal Reserve raised its benchmark interest rate by a quarter point on Wednesday...",
  "text_en": "The Federal Reserve raised its benchmark interest rate by a quarter point on Wednesday...",
  "language_original": "en",
  "url": "https://www.reuters.com/business/fed-raises-rates-2026-04-15/",
  "published_at": "2026-04-15T18:00:00Z",
  "country": "US",
  "region": "US"
}
```

---

## 2. Schéma C2 — Event qualifié

Produit par le pipeline de qualification (C2 worker). Stocké dans la table `events`.
**⚠️ Le champ `cat_id` / `subtype_id` est une FK vers `event_taxonomy` — valeurs dans `taxonomy_v1.json`.**

```json
{
  "$schema": "https://json-schema.org/draft/07/schema",
  "title": "C2_QualifiedEvent",
  "description": "Event macro-financier classifié selon la taxonomie fermée Kairos v1.",
  "type": "object",
  "required": ["event_id", "raw_article_ids", "timestamp", "source_best", "classification", "importance_score", "routing"],
  "properties": {
    "event_id": {
      "type": "string", "format": "uuid",
      "description": "Identifiant unique de l'event qualifié."
    },
    "raw_article_ids": {
      "type": "array",
      "items": { "type": "string", "format": "uuid" },
      "minItems": 1,
      "description": "Liste des article_id C1 agrégés dans cet event (cluster de déduplication)."
    },
    "dedup_cluster_id": {
      "type": ["string", "null"], "format": "uuid",
      "description": "ID du cluster de déduplication. Null si l'event est unique (pas de doublon détecté)."
    },
    "cluster_size": {
      "type": "integer", "minimum": 1,
      "description": "Nombre d'articles dans le cluster. 1 = article isolé."
    },
    "timestamp": {
      "type": "string", "format": "date-time",
      "description": "Horodatage de création de l'event (ISO8601)."
    },
    "source_best": {
      "type": "object",
      "required": ["name", "authority_score"],
      "properties": {
        "name": { "type": "string" },
        "authority_score": { "type": "number", "minimum": 0.0, "maximum": 1.0 }
      },
      "description": "Meilleure source du cluster (authority_score le plus élevé)."
    },
    "classification": {
      "type": "object",
      "required": ["cat_id", "category", "subtype_id", "subtype_label", "confidence"],
      "properties": {
        "cat_id": {
          "type": "string",
          "pattern": "^CAT-\\d{2}$",
          "description": "Identifiant de catégorie. FK → event_taxonomy.cat_id. Ex: 'CAT-01'."
        },
        "category": {
          "type": "string",
          "enum": [
            "MONETARY_POLICY", "FISCAL_POLICY", "INFLATION", "GROWTH_ACTIVITY",
            "FINANCIAL_STABILITY", "GEOPOLITICAL_RISK", "CORPORATE_EARNINGS",
            "COMMODITY_MARKETS", "TRADE_FLOWS", "MARKET_STRUCTURE"
          ],
          "description": "Nom de catégorie. Doit correspondre au cat_id."
        },
        "subtype_id": {
          "type": "string",
          "description": "Identifiant du sous-type. FK → event_taxonomy.subtype_id. Ex: 'rate_decision_hike'."
        },
        "subtype_label": {
          "type": "string",
          "description": "Libellé humain du sous-type (issu de taxonomy_v1.json)."
        },
        "confidence": {
          "type": "number", "minimum": 0.0, "maximum": 1.0,
          "description": "Confiance du modèle de classification (0=incertain, 1=certain)."
        },
        "geography": {
          "type": "array",
          "items": { "type": "string" },
          "description": "Liste des géographies impactées (codes ISO2 ou régions Kairos)."
        },
        "horizon": {
          "type": "string",
          "enum": ["immediate", "weeks", "months", "structural"],
          "description": "Horizon temporel de l'impact anticipé de l'event."
        }
      }
    },
    "entities": {
      "type": "object",
      "properties": {
        "actors": {
          "type": "array",
          "items": { "type": "string" },
          "description": "Acteurs mentionnés (Fed, BCE, gouvernement X, entreprise Y...)."
        },
        "assets_mentioned": {
          "type": "array",
          "items": { "type": "string" },
          "description": "Actifs financiers explicitement mentionnés dans l'article (ex: 'US10Y', 'EUR/USD')."
        },
        "key_figures": {
          "type": "array",
          "items": {
            "type": "object",
            "required": ["label", "value", "unit"],
            "properties": {
              "label": { "type": "string", "description": "Nom de la figure (ex: 'rate', 'inflation', 'gdp_growth')." },
              "value": { "type": "number" },
              "unit": { "type": "string", "description": "Unité (ex: '%', 'bps', 'USD/barrel')." }
            }
          },
          "description": "Chiffres clés extraits de l'article."
        }
      }
    },
    "importance_score": {
      "type": "number", "minimum": 0.0, "maximum": 1.0,
      "description": "Score d'importance de l'event (0=anecdotique, 1=événement systémique). Détermine le routing."
    },
    "routing": {
      "type": "string",
      "enum": ["full_pipeline", "archive"],
      "description": "Décision de routing : 'full_pipeline' = traité par C3/C4, 'archive' = archivé sans analyse."
    },
    "text_en_canonical": {
      "type": "string",
      "description": "Texte consolidé en anglais représentant l'event (meilleur article ou synthèse)."
    }
  }
}
```

### Exemple C2

```json
{
  "event_id": "7f3a9d2e-1b4c-4f8a-9e2d-3a7f1b4c8e9d",
  "raw_article_ids": [
    "550e8400-e29b-41d4-a716-446655440000",
    "661f9511-f30c-52e5-b827-557766551111"
  ],
  "dedup_cluster_id": "aabbccdd-0011-2233-4455-aabbccdd0011",
  "cluster_size": 2,
  "timestamp": "2026-04-15T18:05:00Z",
  "source_best": { "name": "Reuters", "authority_score": 0.92 },
  "classification": {
    "cat_id": "CAT-01",
    "category": "MONETARY_POLICY",
    "subtype_id": "rate_decision_hike",
    "subtype_label": "Hausse de taux directeur",
    "confidence": 0.97,
    "geography": ["US"],
    "horizon": "immediate"
  },
  "entities": {
    "actors": ["Federal Reserve", "Jerome Powell"],
    "assets_mentioned": ["US10Y", "USD"],
    "key_figures": [
      { "label": "rate_change", "value": 0.25, "unit": "%" },
      { "label": "fed_funds_rate", "value": 5.50, "unit": "%" }
    ]
  },
  "importance_score": 0.94,
  "routing": "full_pipeline",
  "text_en_canonical": "The Federal Reserve raised its benchmark interest rate by 25 basis points to 5.50%, signaling a potential pause in its tightening cycle."
}
```

---

## 3. Schéma C3 — Arc du graphe causal

Représente une relation causale entre deux variables macro (drivers). Stocké dans la table `causal_arcs`.
Les arcs sont stables : créés/calibrés par l'équipe et recalibrés automatiquement par feedback C5.

```json
{
  "$schema": "https://json-schema.org/draft/07/schema",
  "title": "C3_CausalArc",
  "description": "Arc orienté du graphe causal Kairos entre deux drivers macro-financiers.",
  "type": "object",
  "required": ["arc_id", "source_driver", "target_driver", "direction", "intensity", "intensity_coefficient", "delay", "confidence"],
  "properties": {
    "arc_id": {
      "type": "string", "format": "uuid",
      "description": "Identifiant unique de l'arc causal."
    },
    "source_driver": {
      "type": "string",
      "description": "Driver source. FK → drivers.driver_id. Ex: 'taux_directeurs'."
    },
    "target_driver": {
      "type": "string",
      "description": "Driver cible. FK → drivers.driver_id. Ex: 'conditions_credit'."
    },
    "direction": {
      "type": "integer",
      "enum": [1, -1],
      "description": "Sens de l'effet : 1=positif (hausse→hausse), -1=négatif (hausse→baisse)."
    },
    "intensity": {
      "type": "string",
      "enum": ["low", "moderate", "strong"],
      "description": "Intensité qualitative de la transmission causale."
    },
    "intensity_coefficient": {
      "type": "number", "minimum": 0.0, "maximum": 1.0,
      "description": "Coefficient quantitatif de l'intensité (0=nul, 1=transmission totale)."
    },
    "delay": {
      "type": "string",
      "enum": ["immediate", "1-4w", "1-6m", "6m+"],
      "description": "Délai de transmission : immediate=<1 semaine, 1-4w=1-4 semaines, 1-6m=1-6 mois, 6m+=long terme."
    },
    "conditions": {
      "type": "array",
      "items": {
        "type": "object",
        "required": ["driver", "operator", "threshold"],
        "properties": {
          "driver": { "type": "string", "description": "Driver conditionnel. FK → drivers.driver_id." },
          "operator": { "type": "string", "enum": [">", "<", ">=", "<=", "=="], "description": "Opérateur de comparaison." },
          "threshold": { "type": "number", "description": "Seuil numérique (ex: 0.02 pour 2%)." }
        }
      },
      "description": "Conditions d'activation de l'arc (peut être vide = toujours actif)."
    },
    "confidence": {
      "type": "number", "minimum": 0.0, "maximum": 1.0,
      "description": "Confiance dans la relation causale (fondée sur données historiques + jugement expert)."
    },
    "last_calibrated": {
      "type": "string", "format": "date-time",
      "description": "Date de dernière calibration de l'arc (ISO8601)."
    }
  }
}
```

### Exemple C3

```json
{
  "arc_id": "carc-0001-0000-0000-000000000001",
  "source_driver": "taux_directeurs",
  "target_driver": "conditions_credit",
  "direction": -1,
  "intensity": "strong",
  "intensity_coefficient": 0.82,
  "delay": "1-4w",
  "conditions": [
    { "driver": "inflation_headline", "operator": ">", "threshold": 0.02 }
  ],
  "confidence": 0.88,
  "last_calibrated": "2026-03-01T00:00:00Z"
}
```

---

## 4. Schéma C4 — Output du moteur de raisonnement

Produit par le C4 worker (moteur de raisonnement causal). Stocké dans la table `analyses`.
Référence l'event C2 et les arcs C3 pour produire des scores d'actifs.

```json
{
  "$schema": "https://json-schema.org/draft/07/schema",
  "title": "C4_Analysis",
  "description": "Output du moteur de raisonnement causal Kairos pour un event qualifié C2.",
  "type": "object",
  "required": ["analysis_id", "event_id", "event_taxonomy", "causal_paths", "asset_scores", "overall_confidence", "confidence_label", "narrative"],
  "properties": {
    "analysis_id": {
      "type": "string", "format": "uuid",
      "description": "Identifiant unique de l'analyse."
    },
    "event_id": {
      "type": "string", "format": "uuid",
      "description": "FK → events.event_id (C2)."
    },
    "event_taxonomy": {
      "type": "object",
      "required": ["cat_id", "category", "subtype_id"],
      "properties": {
        "cat_id": { "type": "string", "description": "FK → event_taxonomy.cat_id." },
        "category": { "type": "string" },
        "subtype_id": { "type": "string", "description": "FK → event_taxonomy.subtype_id." }
      },
      "description": "Snapshot de la classification taxonomique de l'event (dénormalisé pour performance)."
    },
    "causal_paths": {
      "type": "array",
      "items": {
        "type": "object",
        "required": ["path", "direction", "intensity_central", "intensity_range", "delay", "confidence"],
        "properties": {
          "path": {
            "type": "array",
            "items": { "type": "string" },
            "minItems": 2,
            "description": "Séquence ordonnée de drivers (FK → drivers.driver_id). Ex: ['taux_directeurs', 'conditions_credit', 'investissement']."
          },
          "direction": {
            "type": "integer", "enum": [1, -1],
            "description": "Direction nette du chemin causal (produit des directions de chaque arc)."
          },
          "intensity_central": {
            "type": "number", "minimum": 0.0, "maximum": 1.0,
            "description": "Intensité centrale (estimée médiane)."
          },
          "intensity_range": {
            "type": "array",
            "items": { "type": "number" },
            "minItems": 3, "maxItems": 3,
            "description": "Intervalle d'intensité [p10, p50, p90]."
          },
          "delay": {
            "type": "string",
            "description": "Délai total du chemin (délai du maillon le plus lent)."
          },
          "confidence": {
            "type": "number", "minimum": 0.0, "maximum": 1.0,
            "description": "Confiance dans le chemin (produit des confidences des arcs)."
          },
          "historical_episodes": {
            "type": "integer", "minimum": 0,
            "description": "Nombre d'épisodes historiques similaires retrouvés en base."
          },
          "historical_variance": {
            "type": "string",
            "enum": ["low", "medium", "high"],
            "description": "Variance observée des outcomes dans les épisodes historiques."
          }
        }
      }
    },
    "asset_scores": {
      "type": "object",
      "description": "Scores nets par classe d'actif. Clés = identifiants d'actifs de la table asset_sensitivity.",
      "additionalProperties": {
        "type": "object",
        "required": ["net_score", "signal", "confidence", "horizon"],
        "properties": {
          "net_score": {
            "type": "number", "minimum": -1.0, "maximum": 1.0,
            "description": "Score net agrégé : -1=très bearish, 0=neutre, +1=très bullish."
          },
          "signal": {
            "type": "string",
            "enum": ["bullish", "bearish", "mixed", "neutral"],
            "description": "Signal qualitatif résultant."
          },
          "confidence": {
            "type": "number", "minimum": 0.0, "maximum": 1.0
          },
          "horizon": {
            "type": "string",
            "description": "Horizon temporel du signal."
          },
          "contributing_paths": {
            "type": "array",
            "items": { "type": "integer" },
            "description": "Indices (0-based) des causal_paths contribuant à ce score."
          }
        }
      }
    },
    "overall_confidence": {
      "type": "number", "minimum": 0.0, "maximum": 1.0,
      "description": "Confiance globale de l'analyse (moyenne pondérée des paths)."
    },
    "confidence_label": {
      "type": "string",
      "enum": ["low", "medium", "high", "very_high"],
      "description": "Niveau de confiance qualitatif : low<0.4, medium<0.6, high<0.8, very_high>=0.8."
    },
    "narrative": {
      "type": "string",
      "description": "Narrative synthétique en anglais expliquant l'analyse (max ~500 mots)."
    },
    "report_canonical": {
      "type": "object",
      "description": "Rapport structuré complet (format libre JSON, destiné au front C5 et à l'archivage)."
    }
  }
}
```

### Exemple C4

```json
{
  "analysis_id": "a4b5c6d7-e8f9-0a1b-2c3d-4e5f6a7b8c9d",
  "event_id": "7f3a9d2e-1b4c-4f8a-9e2d-3a7f1b4c8e9d",
  "event_taxonomy": {
    "cat_id": "CAT-01",
    "category": "MONETARY_POLICY",
    "subtype_id": "rate_decision_hike"
  },
  "causal_paths": [
    {
      "path": ["taux_directeurs", "conditions_credit", "investissement"],
      "direction": -1,
      "intensity_central": 0.65,
      "intensity_range": [0.45, 0.65, 0.82],
      "delay": "1-4w",
      "confidence": 0.78,
      "historical_episodes": 12,
      "historical_variance": "low"
    },
    {
      "path": ["taux_directeurs", "usd_strength"],
      "direction": 1,
      "intensity_central": 0.71,
      "intensity_range": [0.55, 0.71, 0.88],
      "delay": "immediate",
      "confidence": 0.85,
      "historical_episodes": 18,
      "historical_variance": "low"
    }
  ],
  "asset_scores": {
    "bonds_sovereign_us": {
      "net_score": -0.72,
      "signal": "bearish",
      "confidence": 0.82,
      "horizon": "immediate",
      "contributing_paths": [0]
    },
    "equities_us": {
      "net_score": -0.45,
      "signal": "bearish",
      "confidence": 0.65,
      "horizon": "weeks",
      "contributing_paths": [0, 1]
    },
    "usd_index": {
      "net_score": 0.68,
      "signal": "bullish",
      "confidence": 0.84,
      "horizon": "immediate",
      "contributing_paths": [1]
    }
  },
  "overall_confidence": 0.81,
  "confidence_label": "very_high",
  "narrative": "A 25bps Fed hike tightens credit conditions over 1-4 weeks, weighing on investment and equities. Simultaneously, higher US rates strengthen the USD immediately. Sovereign bonds face bearish pressure as yields reprice. Historical precedent across 12+ similar episodes shows consistent transmission with low variance.",
  "report_canonical": {
    "version": "1.0",
    "generated_at": "2026-04-15T18:10:00Z",
    "event_summary": "Fed +25bps, pause signaled",
    "key_risks": ["Fed reversal if recession", "EM capital outflows"]
  }
}
```

---

## 5. Schéma C5 — Prédiction archivée / Rapport canonique

Produit au moment de l'archivage de l'analyse C4 pour suivi futur. Enrichi lors de la vérification.
Stocké dans la table `predictions`.

```json
{
  "$schema": "https://json-schema.org/draft/07/schema",
  "title": "C5_Prediction",
  "description": "Prédiction archivée et suivi de vérification pour recalibration du graphe causal.",
  "type": "object",
  "required": ["prediction_id", "analysis_id", "created_at", "verification_due_at", "status", "prediction_snapshot"],
  "properties": {
    "prediction_id": {
      "type": "string", "format": "uuid",
      "description": "Identifiant unique de la prédiction archivée."
    },
    "analysis_id": {
      "type": "string", "format": "uuid",
      "description": "FK → analyses.analysis_id (C4)."
    },
    "created_at": {
      "type": "string", "format": "date-time",
      "description": "Date de création de la prédiction (= date de l'analyse)."
    },
    "verification_due_at": {
      "type": "string", "format": "date-time",
      "description": "Date d'échéance pour vérification (dépend de l'horizon : immediate=+7j, weeks=+30j, months=+90j)."
    },
    "status": {
      "type": "string",
      "enum": ["pending", "verified", "partially_verified", "unverifiable"],
      "description": "Statut de vérification de la prédiction."
    },
    "prediction_snapshot": {
      "type": "object",
      "description": "Snapshot complet de l'analyse C4 au moment de l'archivage (immuable).",
      "required": ["asset_scores", "overall_confidence", "narrative"],
      "properties": {
        "asset_scores": { "type": "object" },
        "overall_confidence": { "type": "number" },
        "narrative": { "type": "string" }
      }
    },
    "reality_data": {
      "type": "object",
      "description": "Données réelles collectées à la date de vérification (prix, indicateurs...).",
      "additionalProperties": {
        "type": "object",
        "properties": {
          "actual_direction": { "type": "integer", "enum": [1, -1, 0] },
          "actual_change_pct": { "type": "number" },
          "data_source": { "type": "string" },
          "verified_at": { "type": "string", "format": "date-time" }
        }
      }
    },
    "error_metrics": {
      "type": "object",
      "description": "Métriques d'erreur calculées lors de la vérification.",
      "properties": {
        "direction_correct": {
          "type": ["boolean", "null"],
          "description": "La direction prédite était-elle correcte ?"
        },
        "intensity_error": {
          "type": ["number", "null"],
          "description": "Erreur absolue sur l'intensité (valeur prédite - valeur réelle)."
        },
        "horizon_error_days": {
          "type": ["integer", "null"],
          "description": "Erreur sur l'horizon en jours (délai réel - délai prédit)."
        },
        "calibration_signal": {
          "type": ["string", "null"],
          "enum": ["recalibrate_up", "recalibrate_down", "ok", null],
          "description": "Signal de recalibration pour le graphe causal."
        }
      }
    }
  }
}
```

### Exemple C5

```json
{
  "prediction_id": "c5d6e7f8-0a1b-2c3d-4e5f-6a7b8c9d0e1f",
  "analysis_id": "a4b5c6d7-e8f9-0a1b-2c3d-4e5f6a7b8c9d",
  "created_at": "2026-04-15T18:10:00Z",
  "verification_due_at": "2026-04-22T18:10:00Z",
  "status": "pending",
  "prediction_snapshot": {
    "asset_scores": {
      "bonds_sovereign_us": { "net_score": -0.72, "signal": "bearish", "confidence": 0.82 },
      "usd_index": { "net_score": 0.68, "signal": "bullish", "confidence": 0.84 }
    },
    "overall_confidence": 0.81,
    "narrative": "A 25bps Fed hike tightens credit conditions..."
  },
  "reality_data": {},
  "error_metrics": {
    "direction_correct": null,
    "intensity_error": null,
    "horizon_error_days": null,
    "calibration_signal": null
  }
}
```

---

## 6. Référence des Drivers (table `drivers`)

Variables pivot du graphe causal — 18 drivers initiaux couvrant les principales transmissions macro-financières.

| driver_id | label_fr | category | unit |
|-----------|----------|----------|------|
| `taux_directeurs` | Taux directeurs banques centrales | monetary | % |
| `conditions_credit` | Conditions de crédit bancaire | monetary | index |
| `inflation_headline` | Inflation headline (IPC) | prices | % yoy |
| `inflation_core` | Inflation core (hors énergie/alim.) | prices | % yoy |
| `croissance_pib` | Croissance PIB | growth | % qoq |
| `emploi_chomage` | Taux de chômage | growth | % |
| `investissement` | Investissement privé | growth | % gdp |
| `consommation` | Consommation des ménages | growth | % gdp |
| `usd_strength` | Force du dollar (DXY) | fx | index |
| `spreads_credit` | Spreads de crédit (IG/HY) | credit | bps |
| `spreads_souverains` | Spreads souverains (vs Bund/T-note) | sovereign | bps |
| `prix_petrole` | Prix du pétrole (Brent) | commodity | USD/bbl |
| `prix_metaux` | Prix des métaux industriels | commodity | index |
| `sentiment_marche` | Sentiment de marché (VIX proxy) | market | index |
| `liquidite_bancaire` | Liquidité du système bancaire | financial | ratio |
| `dette_publique` | Ratio dette publique/PIB | fiscal | % gdp |
| `balance_commerciale` | Solde commercial | trade | USD bn |
| `anticipations_inflation` | Anticipations d'inflation (BEI 5y5y) | expectations | % |

---

## Alignement taxonomy_v1.json ↔ DB

```
config/taxonomy_v1.json
  └── categories[].cat_id          → event_taxonomy.cat_id (PK)
  └── categories[].category        → event_taxonomy.category
  └── categories[].subtypes[].subtype_id  → event_taxonomy.subtype_id (PK composite)
  └── categories[].subtypes[].label       → event_taxonomy.subtype_label

events.cat_id    → FK → event_taxonomy(cat_id)
events.subtype_id → FK → event_taxonomy(subtype_id) [via (cat_id, subtype_id)]

analyses.cat_id    → FK → event_taxonomy(cat_id)   [snapshot dénormalisé]
analyses.subtype_id → FK → event_taxonomy(subtype_id)
```
