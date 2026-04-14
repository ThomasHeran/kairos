import { BaseSourceAgent } from "@/agents/base-agent";
import { ForumAgent } from "@/agents/forum_agent";
import { NewsAgent } from "@/agents/news_agent";
import { RedditAgent } from "@/agents/reddit_agent";
import { RSSAgent } from "@/agents/rss_agent";
import { TwitterAgent } from "@/agents/twitter_agent";
import type { SourceType } from "@/agents/types";

const registry = {
  rss: new RSSAgent(),
  reddit: new RedditAgent(),
  twitter: new TwitterAgent(),
  forum: new ForumAgent(),
  news: new NewsAgent(),
} satisfies Record<SourceType, BaseSourceAgent>;

export function getAgentForType(type: SourceType) {
  return registry[type];
}

export function listAvailableAgents() {
  return Object.keys(registry);
}
