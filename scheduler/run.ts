import { orchestrateScrapeCycle } from "@/scheduler/orchestrator";

const result = await orchestrateScrapeCycle();

console.log(JSON.stringify(result, null, 2));
