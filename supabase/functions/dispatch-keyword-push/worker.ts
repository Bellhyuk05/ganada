import { createClient } from "npm:@supabase/supabase-js@2.49.8";
import { JWT } from "npm:google-auth-library@9.15.1";

type Job = { notification_id: string; lease_id: string; attempts: number };
type Notice = {
  id: string;
  user_id: string;
  ride_id: string;
  title: string;
  body: string;
};
type ServiceAccount = {
  project_id: string;
  client_email: string;
  private_key: string;
};

function requiredValue(
  name: string,
  env: (name: string) => string | undefined,
): string {
  const value = env(name);
  if (!value) throw new Error(`Missing server configuration: ${name}`);
  return value;
}
function checked<T>(result: { data: T; error: unknown }): T {
  if (result.error) throw new Error("Database operation failed");
  return result.data;
}
async function secretMatches(
  actual: string,
  expected: string,
): Promise<boolean> {
  const encoder = new TextEncoder();
  const a = new Uint8Array(
    await crypto.subtle.digest("SHA-256", encoder.encode(actual)),
  );
  const b = new Uint8Array(
    await crypto.subtle.digest("SHA-256", encoder.encode(expected)),
  );
  let delta = 0;
  for (let i = 0; i < a.length; i++) delta |= a[i] ^ b[i];
  return delta === 0;
}

export type WorkerDependencies = {
  db?: ReturnType<typeof createClient>;
  env?: (name: string) => string | undefined;
  getAccessToken?: (
    account: ServiceAccount,
  ) => Promise<string | null | undefined>;
  fetch?: typeof fetch;
  now?: () => number;
};
export function createDispatchHandler(
  deps: WorkerDependencies = {},
): (request: Request) => Promise<Response> {
  const required = (name: string) =>
    requiredValue(name, deps.env ?? Deno.env.get);
  return async (request: Request) => {
    if (request.method !== "POST") {
      return new Response("Method not allowed", { status: 405 });
    }
    try {
      if (
        !await secretMatches(
          request.headers.get("x-dispatch-secret") ?? "",
          required("PUSH_DISPATCH_SECRET"),
        )
      ) {
        return new Response("Unauthorized", { status: 401 });
      }
      const db = deps.db ?? createClient(
        required("SUPABASE_URL"),
        required("SUPABASE_SERVICE_ROLE_KEY"),
        {
          auth: { persistSession: false, autoRefreshToken: false },
        },
      );
      const account: ServiceAccount = JSON.parse(
        required("FIREBASE_SERVICE_ACCOUNT"),
      );
      if (
        !account.project_id || !account.client_email || !account.private_key
      ) {
        throw new Error("Invalid server configuration");
      }
      const auth = new JWT({
        email: account.client_email,
        key: account.private_key,
        scopes: ["https://www.googleapis.com/auth/firebase.messaging"],
      });
      const jobs = checked(
        await db.rpc("claim_keyword_push_jobs", { p_limit: 5 }),
      ) as Job[];

      async function finish(
        job: Job,
        status: string,
        error: string | null = null,
      ) {
        const failed = status === "pending" && job.attempts >= 5;
        checked(
          await db.from("keyword_push_jobs").update({
            status: failed ? "failed" : status,
            available_at: new Date(
              (deps.now ?? Date.now)() +
                Math.min(3600, 30 * 2 ** job.attempts) * 1000,
            ).toISOString(),
            locked_at: null,
            lease_id: null,
            last_error: error,
          }).eq("notification_id", job.notification_id).eq(
            "lease_id",
            job.lease_id,
          ),
        );
      }

      // Recheck the global switch and currently active keywords before sending.
      async function keywordPushAllowed(notice: Notice): Promise<boolean> {
        const ride = checked(
          await db.from("rides").select(
            "host_id,status,origin_name,destination_name,condition_text",
          ).eq("id", notice.ride_id).maybeSingle(),
        ) as {
          host_id: string;
          status: string;
          origin_name: string;
          destination_name: string;
          condition_text: string;
        } | null;
        if (
          !ride || ride.status === "cancelled" ||
          ride.host_id === notice.user_id
        ) return false;
        const preference = checked(
          await db.from("notification_preferences").select("keyword_enabled")
            .eq("user_id", notice.user_id).maybeSingle(),
        ) as { keyword_enabled: boolean } | null;
        if (preference?.keyword_enabled === false) return false;
        const block = checked(
          await db.from("user_blocks").select("blocked_id")
            .eq("blocker_id", notice.user_id).eq("blocked_id", ride.host_id)
            .maybeSingle(),
        );
        if (block) return false;
        const keywords = (checked(
          await db.from("user_keywords").select("normalized_text")
            .eq("user_id", notice.user_id).eq("enabled", true),
        ) ?? []) as { normalized_text: string }[];
        const fields = [
          ride.origin_name,
          ride.destination_name,
          ride.condition_text,
        ].map((text) => (text ?? "").toLowerCase());
        return keywords.some((keyword) =>
          fields.some((text) => text.includes(keyword.normalized_text))
        );
      }

      async function process(job: Job): Promise<string> {
        try {
          const notice = checked(
            await db.from("keyword_notifications").select(
              "id,user_id,ride_id,title,body",
            )
              .eq("id", job.notification_id).maybeSingle(),
          ) as Notice | null;
          if (!notice) {
            await finish(job, "skipped");
            return "skipped";
          }
          if (!await keywordPushAllowed(notice)) {
            await finish(job, "skipped");
            return "skipped";
          }
          const devices = (checked(
            await db.from("device_tokens").select("token").eq(
              "user_id",
              notice.user_id,
            ),
          ) ?? []) as { token: string }[];
          const ownedTokens = new Set(devices.map((d) => d.token));
          if (devices.length) {
            checked(
              await db.from("keyword_push_deliveries").upsert(
                devices.map((d) => ({
                  notification_id: notice.id,
                  token: d.token,
                })),
                { onConflict: "notification_id,token", ignoreDuplicates: true },
              ),
            );
          }
          const deliveries = (checked(
            await db.from("keyword_push_deliveries").select("token,status")
              .eq("notification_id", notice.id).eq("status", "pending"),
          ) ?? []) as { token: string; status: string }[];
          if (!devices.length && !deliveries.length) {
            await finish(job, "skipped");
            return "skipped";
          }
          const accessToken = deps.getAccessToken
            ? await deps.getAccessToken(account)
            : (await auth.getAccessToken()).token;
          if (!accessToken) throw new Error("FCM authentication failed");
          let retry = false;
          for (const delivery of deliveries) {
            if (!ownedTokens.has(delivery.token)) {
              checked(
                await db.from("keyword_push_deliveries").update({
                  status: "skipped",
                })
                  .eq("notification_id", notice.id).eq("token", delivery.token),
              );
              continue;
            }
            // A token may move to another account between job creation and sending.
            const current = checked(
              await db.from("device_tokens").select("user_id")
                .eq("token", delivery.token).eq("user_id", notice.user_id)
                .maybeSingle(),
            );
            if (!current) {
              checked(
                await db.from("keyword_push_deliveries").update({
                  status: "skipped",
                })
                  .eq("notification_id", notice.id).eq("token", delivery.token),
              );
              continue;
            }
            const lease = checked(
              await db.from("keyword_push_jobs").select("lease_id")
                .eq("notification_id", notice.id).eq("lease_id", job.lease_id)
                .maybeSingle(),
            );
            if (!lease) return "lease_lost";
            if (!await keywordPushAllowed(notice)) {
              await finish(job, "skipped");
              return "skipped";
            }
            const result = await (deps.fetch ?? fetch)(
              `https://fcm.googleapis.com/v1/projects/${
                encodeURIComponent(account.project_id)
              }/messages:send`,
              {
                method: "POST",
                signal: AbortSignal.timeout(10000),
                headers: {
                  Authorization: `Bearer ${accessToken}`,
                  "Content-Type": "application/json",
                },
                body: JSON.stringify({
                  message: {
                    token: delivery.token,
                    notification: { title: notice.title, body: notice.body },
                    data: { ride_id: notice.ride_id, notice_id: notice.id },
                    android: {
                      priority: "HIGH",
                      collapse_key: notice.id,
                      notification: { tag: notice.id },
                    },
                  },
                }),
              },
            );
            if (result.ok) {
              checked(
                await db.from("keyword_push_deliveries").update({
                  status: "sent",
                })
                  .eq("notification_id", notice.id).eq("token", delivery.token),
              );
            } else {
              const response = await result.json().catch(() => ({}));
              const unregistered = response.error?.details?.some((
                d: { errorCode?: string },
              ) => d.errorCode === "UNREGISTERED");
              if (unregistered) {
                checked(
                  await db.from("device_tokens").delete().eq(
                    "token",
                    delivery.token,
                  ).eq("user_id", notice.user_id),
                );
                checked(
                  await db.from("keyword_push_deliveries").update({
                    status: "skipped",
                  })
                    .eq("notification_id", notice.id).eq(
                      "token",
                      delivery.token,
                    ),
                );
              } else retry = true;
            }
          }
          await finish(
            job,
            retry ? "pending" : "sent",
            retry ? "FCM delivery failed" : null,
          );
          return retry ? "retry" : "sent";
        } catch (_) {
          // Do not log recipient identity, FCM tokens, service-account contents or HTTP bodies.
          await finish(job, "pending", "Push processing failed");
          return "retry";
        }
      }
      const outcomes = await Promise.all(jobs.map(process));
      return Response.json({ claimed: jobs.length, outcomes });
    } catch (_) {
      return Response.json({
        error: "Push worker configuration or database failure",
      }, { status: 500 });
    }
  };
}
