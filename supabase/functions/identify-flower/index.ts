import { createClient } from "npm:@supabase/supabase-js@2";
import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import {
  createIdentifyFlowerHandler,
  type SupabaseClientLike,
} from "./handler.ts";

serve(createIdentifyFlowerHandler({
  createClient: (url, key, options) =>
    createClient(url, key, options) as unknown as SupabaseClientLike,
  env: (name) => Deno.env.get(name),
  fetch: (input, init) => fetch(input, init),
  scheduleTimeout: (callback, delay) => setTimeout(callback, delay),
  cancelTimeout: (handle) => clearTimeout(handle as number),
}));
