import { JWT } from "npm:google-auth-library@10.6.2";

type PushJob = {
  job_id: string;
  attempt: number;
  installation_id: string;
  recipient_id: string;
  conversation_id: string;
  message_id: string;
};

function requiredEnv(name: string): string {
  const value = Deno.env.get(name);
  if (!value) throw new Error("Missing server configuration");
  return value;
}

async function hasWorkerSecret(supplied: string): Promise<boolean> {
  const expected = Deno.env.get("PRIVATE_PUSH_WORKER_SECRET");
  if (!expected || !supplied) return false;
  const encoder = new TextEncoder();
  const digest = (value: string) =>
    crypto.subtle.digest("SHA-256", encoder.encode(value));
  const [left, right] = await Promise.all([digest(supplied), digest(expected)]);
  const a = new Uint8Array(left);
  const b = new Uint8Array(right);
  let difference = 0;
  for (let i = 0; i < a.length; i++) difference |= a[i] ^ b[i];
  return difference === 0;
}

async function rpc<T>(name: string, body: object): Promise<T> {
  const key = requiredEnv("SUPABASE_SERVICE_ROLE_KEY");
  const response = await fetch(
    requiredEnv("SUPABASE_URL") + "/rest/v1/rpc/" + name,
    {
      method: "POST",
      headers: {
        "apikey": key,
        "Authorization": "Bearer " + key,
        "Content-Type": "application/json",
      },
      body: JSON.stringify(body),
      signal: AbortSignal.timeout(10_000),
    },
  );
  if (!response.ok) throw new Error("Could not process queue");
  return response.status === 204 ? undefined as T : await response.json();
}

async function deliver(
  job: PushJob,
  project: string,
  accessToken: string,
): Promise<"sent" | "invalid" | "retry"> {
  const response = await fetch(
    "https://fcm.googleapis.com/v1/projects/" + encodeURIComponent(project) +
      "/messages:send",
    {
      method: "POST",
      headers: {
        "Authorization": "Bearer " + accessToken,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        message: {
          fid: job.installation_id,
          notification: {
            title: "Conecta2",
            body: "Tienes un mensaje nuevo.",
          },
          data: {
            type: "private_message",
            conversation_id: job.conversation_id,
            recipient_id: job.recipient_id,
            message_id: job.message_id,
          },
          android: {
            ttl: "3600s",
            notification: { tag: job.conversation_id },
          },
          apns: {
            headers: {
              "apns-collapse-id": job.conversation_id,
              "apns-expiration": String(Math.floor(Date.now() / 1000) + 3600),
            },
          },
        },
      }),
      signal: AbortSignal.timeout(10_000),
    },
  );

  let invalidInstallation = false;
  if (!response.ok) {
    const result = await response.json().catch(() => null);
    invalidInstallation = result?.error?.details?.some(
      (detail: { errorCode?: string }) => detail.errorCode === "UNREGISTERED",
    ) === true;
    if (!invalidInstallation) {
      console.warn(
        "FCM rejected a private message notification",
        response.status,
      );
      return "retry";
    }
  }

  await rpc("finish_private_message_push", {
    p_job_id: job.job_id,
    p_attempt: job.attempt,
    p_invalid_installation_id: invalidInstallation ? job.installation_id : null,
  });
  return invalidInstallation ? "invalid" : "sent";
}

Deno.serve(async (request) => {
  if (request.method !== "POST") return new Response(null, { status: 405 });
  if (
    !await hasWorkerSecret(request.headers.get("x-push-worker-secret") ?? "")
  ) {
    return new Response(null, { status: 401 });
  }

  try {
    const account = JSON.parse(requiredEnv("FCM_SERVICE_ACCOUNT_JSON"));
    if (
      typeof account?.project_id !== "string" ||
      typeof account.client_email !== "string" ||
      typeof account.private_key !== "string"
    ) {
      throw new Error("Invalid Firebase configuration");
    }

    const jobs = await rpc<PushJob[]>("claim_private_message_pushes", {});
    if (jobs.length === 0) {
      return Response.json({ claimed: 0, sent: 0, retrying: 0 });
    }
    const auth = new JWT({
      email: account.client_email,
      key: account.private_key,
      scopes: ["https://www.googleapis.com/auth/firebase.messaging"],
    });
    const { access_token: accessToken } = await auth.authorize();
    if (!accessToken) throw new Error("Could not authorize Firebase");
    const results = await Promise.allSettled(
      jobs.map((job) => deliver(job, account.project_id, accessToken)),
    );
    return Response.json({
      claimed: jobs.length,
      sent: results.filter((r) =>
        r.status === "fulfilled" && r.value === "sent"
      ).length,
      retrying: results.filter((r) =>
        r.status === "rejected" || r.value === "retry"
      ).length,
    });
  } catch (_) {
    console.error("Could not process private message notifications");
    return new Response(null, { status: 503 });
  }
});
