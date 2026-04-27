import taxonomyDocument from "@/config/taxonomy_v1.json";

type TaxonomySubtypeDocument = {
  subtype_id: string;
  label: string;
  description?: string;
  detection_keywords?: string[];
  authority_floor: number;
  typical_geography?: string[];
  drivers_mapping?: {
    primary?: Array<{
      horizon?: string;
    }>;
  };
};

type TaxonomyCategoryDocument = {
  cat_id: string;
  category: string;
  label_fr: string;
  description?: string;
  subtypes: TaxonomySubtypeDocument[];
};

type TaxonomyDocument = {
  version: string;
  categories: TaxonomyCategoryDocument[];
};

export type TaxonomySubtype = {
  cat_id: string;
  category: string;
  category_label_fr: string;
  subtype_id: string;
  subtype_label: string;
  description: string;
  detection_keywords: string[];
  authority_floor: number;
  typical_geography: string[];
  default_horizon: "immediate" | "weeks" | "months" | "structural";
};

const taxonomy = taxonomyDocument as TaxonomyDocument;

const subtypeIndex = new Map<string, TaxonomySubtype>();
const categoryIndex = new Map<string, TaxonomyCategoryDocument>();

for (const category of taxonomy.categories) {
  categoryIndex.set(category.cat_id, category);

  for (const subtype of category.subtypes) {
    const defaultHorizon = resolveDefaultHorizon(subtype);
    subtypeIndex.set(subtype.subtype_id, {
      cat_id: category.cat_id,
      category: category.category,
      category_label_fr: category.label_fr,
      subtype_id: subtype.subtype_id,
      subtype_label: subtype.label,
      description: subtype.description ?? "",
      detection_keywords: subtype.detection_keywords ?? [],
      authority_floor: subtype.authority_floor,
      typical_geography: subtype.typical_geography ?? [],
      default_horizon: defaultHorizon,
    });
  }
}

function resolveDefaultHorizon(
  subtype: TaxonomySubtypeDocument,
): "immediate" | "weeks" | "months" | "structural" {
  const primaryHorizon = subtype.drivers_mapping?.primary?.[0]?.horizon ?? "immediate";

  if (primaryHorizon === "immediate" || primaryHorizon === "weeks" || primaryHorizon === "months") {
    return primaryHorizon;
  }

  if (primaryHorizon === "1-4w") {
    return "weeks";
  }

  if (primaryHorizon === "1-6m" || primaryHorizon === "6-12m") {
    return "months";
  }

  return "structural";
}

export function getTaxonomyCategories() {
  return taxonomy.categories.map((category) => ({
    cat_id: category.cat_id,
    category: category.category,
    label_fr: category.label_fr,
    subtype_count: category.subtypes.length,
  }));
}

export function getTaxonomySubtype(subtypeId: string) {
  return subtypeIndex.get(subtypeId);
}

export function getTaxonomySubtypeByCategory(catId: string, subtypeId: string) {
  const subtype = subtypeIndex.get(subtypeId);
  if (!subtype || subtype.cat_id !== catId) {
    return null;
  }

  return subtype;
}

export function getTaxonomySubtypes() {
  return [...subtypeIndex.values()];
}

export function getTaxonomyCategory(catId: string) {
  return categoryIndex.get(catId);
}

export function isKnownKairosSubtype(subtypeId: string) {
  return subtypeIndex.has(subtypeId);
}
