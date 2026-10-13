import { createDispatchHandler } from "./worker.ts";

Deno.serve(createDispatchHandler());
