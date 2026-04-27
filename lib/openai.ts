import { createHash } from "node:crypto";

const OPENAI_API_BASE = "https://api.openai.com/v1";
const LOCAL_EMBEDDING_DIMENSIONS = 1536;

type ChatCompletionMessage = {
  role: "system" | "user";
  content: string;
};

type JsonSchemaResponse = {
  choices?: Array<{
    message?: {
      content?: string | Array<{ type?: string; text?: string }>;
    };
  }>;
  error?: {
    message?: string;
  };
};

type EmbeddingsResponse = {
  data?: Array<{
    embedding?: number[];
  }>;
  error?: {
    message?: string;
  };
};

function getOpenAiApiKey() {
  const apiKey = process.env.OPENAI_API_KEY;

  if (!apiKey) {
    throw new Error("OPENAI_API_KEY is not configured");
  }

  return apiKey;
}

function hasOpenAiApiKey() {
  return Boolean(process.env.OPENAI_API_KEY);
}

function createLocalEmbedding(input: string) {
  const vector = new Array<number>(LOCAL_EMBEDDING_DIMENSIONS).fill(0);
  const tokens = input
    .toLowerCase()
    .split(/[^a-z0-9]+/i)
    .map((token) => token.trim())
    .filter((token) => token.length >= 2);

  for (const token of tokens) {
    const digest = createHash("sha256").update(token).digest();
    const index = digest.readUInt16BE(0) % LOCAL_EMBEDDING_DIMENSIONS;
    const sign = digest[2] % 2 === 0 ? 1 : -1;
    const weight = 1 + Math.min(token.length, 12) / 12;
    vector[index] += sign * weight;
  }

  const norm = Math.sqrt(vector.reduce((accumulator, value) => accumulator + value * value, 0));
  if (norm === 0) {
    return vector;
  }

  return vector.map((value) => value / norm);
}

async function callOpenAi<T>(path: string, body: Record<string, unknown>) {
  const response = await fetch(`${OPENAI_API_BASE}${path}`, {
    method: "POST",
    headers: {
      Authorization: `Bearer ${getOpenAiApiKey()}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify(body),
  });

  const json = (await response.json().catch(() => ({}))) as T & {
    error?: { message?: string };
  };

  if (!response.ok) {
    throw new Error(json.error?.message ?? `OpenAI request failed with status ${response.status}`);
  }

  return json;
}

export async function createEmbedding(
  input: string,
  model = "text-embedding-3-small",
) {
  if (!hasOpenAiApiKey()) {
    return createLocalEmbedding(input);
  }

  const response = await callOpenAi<EmbeddingsResponse>("/embeddings", {
    model,
    input,
  });

  const embedding = response.data?.[0]?.embedding;

  if (!embedding || embedding.length === 0) {
    throw new Error("OpenAI embeddings response did not include an embedding vector");
  }

  return embedding;
}

function readAssistantText(payload: JsonSchemaResponse) {
  const content = payload.choices?.[0]?.message?.content;

  if (typeof content === "string") {
    return content;
  }

  if (Array.isArray(content)) {
    return content
      .map((item) => item.text ?? "")
      .filter(Boolean)
      .join("\n")
      .trim();
  }

  return "";
}

export async function createStructuredJson<T>({
  model = "gpt-4o-mini",
  system,
  user,
  schemaName,
  schema,
  temperature = 0,
}: {
  model?: string;
  system: string;
  user: string;
  schemaName: string;
  schema: Record<string, unknown>;
  temperature?: number;
}) {
  const response = await callOpenAi<JsonSchemaResponse>("/chat/completions", {
    model,
    temperature,
    messages: [
      { role: "system", content: system },
      { role: "user", content: user },
    ] satisfies ChatCompletionMessage[],
    response_format: {
      type: "json_schema",
      json_schema: {
        name: schemaName,
        strict: true,
        schema,
      },
    },
  });

  const text = readAssistantText(response);

  if (!text) {
    throw new Error("OpenAI structured output response was empty");
  }

  return JSON.parse(text) as T;
}

export async function createPlainTextCompletion({
  model = "gpt-4o-mini",
  system,
  user,
  temperature = 0,
}: {
  model?: string;
  system: string;
  user: string;
  temperature?: number;
}) {
  const response = await callOpenAi<JsonSchemaResponse>("/chat/completions", {
    model,
    temperature,
    messages: [
      { role: "system", content: system },
      { role: "user", content: user },
    ] satisfies ChatCompletionMessage[],
  });

  const text = readAssistantText(response);

  if (!text) {
    throw new Error("OpenAI completion response was empty");
  }

  return text;
}
