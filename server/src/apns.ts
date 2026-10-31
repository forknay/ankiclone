import type { PushDevice, PushMessage, SendPush } from "./push";

export interface ApnsConfig {
  APNS_KEY: string;
  APNS_KEY_ID: string;
  APNS_TEAM_ID: string;
  APNS_TOPIC: string;
}

const base64url = (data: ArrayBuffer | string) => {
  const bytes = typeof data === "string" ? new TextEncoder().encode(data) : new Uint8Array(data);
  return btoa(String.fromCharCode(...bytes)).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
};

async function providerToken(config: ApnsConfig, now: Date): Promise<string> {
  const der = Uint8Array.from(
    atob(config.APNS_KEY.replace(/-----[^-]+-----/g, "").replace(/\s/g, "")),
    (char) => char.charCodeAt(0),
  );
  const key = await crypto.subtle.importKey("pkcs8", der, { name: "ECDSA", namedCurve: "P-256" }, false, ["sign"]);
  const header = base64url(JSON.stringify({ alg: "ES256", kid: config.APNS_KEY_ID }));
  const claims = base64url(JSON.stringify({ iss: config.APNS_TEAM_ID, iat: Math.floor(now.getTime() / 1000) }));
  const signature = await crypto.subtle.sign({ name: "ECDSA", hash: "SHA-256" }, key, new TextEncoder().encode(`${header}.${claims}`));
  return `${header}.${claims}.${base64url(signature)}`;
}

export function apnsSender(config: ApnsConfig, now: Date): SendPush {
  let token: Promise<string> | undefined;
  return async (device: PushDevice, message: PushMessage) => {
    token ??= providerToken(config, now);
    const host = device.environment === "sandbox" ? "api.sandbox.push.apple.com" : "api.push.apple.com";
    const response = await fetch(`https://${host}/3/device/${device.token}`, {
      method: "POST",
      headers: {
        authorization: `bearer ${await token}`,
        "apns-topic": config.APNS_TOPIC,
        "apns-push-type": "alert",
      },
      body: JSON.stringify({
        aps: { alert: { title: message.title, body: message.body }, sound: "default" },
        lessonDate: message.lessonDate,
      }),
    });
    if (response.ok) return "sent";
    if (response.status === 410) return "gone";
    const reason = await response.text();
    console.error(`APNs ${response.status}: ${reason}`);
    return reason.includes("BadDeviceToken") ? "gone" : "failed";
  };
}
