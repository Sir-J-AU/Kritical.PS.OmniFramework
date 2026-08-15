import { ClientSecretCredential } from '@azure/identity';
import type { AppConfig } from './config.js';

export type MicrosoftAudience = 'powerbi' | 'businesscentral' | 'dataverse';

export class MicrosoftClient {
  readonly #credential: ClientSecretCredential;
  readonly #config: AppConfig;

  constructor(config: AppConfig) {
    this.#config = config;
    this.#credential = new ClientSecretCredential(config.tenantId, config.clientId, config.clientSecret);
  }

  async token(audience: MicrosoftAudience): Promise<string> {
    let scope: string;
    switch (audience) {
      case 'powerbi':
        scope = 'https://analysis.windows.net/powerbi/api/.default';
        break;
      case 'businesscentral':
        scope = 'https://api.businesscentral.dynamics.com/.default';
        break;
      case 'dataverse': {
        if (!this.#config.d365OrgUrl) throw new Error('D365_ORG_URL is required for Dataverse operations.');
        scope = `${this.#config.d365OrgUrl}/.default`;
        break;
      }
    }
    const result = await this.#credential.getToken(scope);
    if (!result?.token) throw new Error(`Unable to acquire token for ${audience}.`);
    return result.token;
  }

  async request<T>(audience: MicrosoftAudience, url: string, init: RequestInit = {}): Promise<T> {
    const token = await this.token(audience);
    const headers = new Headers(init.headers);
    headers.set('Authorization', `Bearer ${token}`);
    headers.set('Accept', 'application/json');
    if (init.body && !headers.has('Content-Type')) headers.set('Content-Type', 'application/json');

    const response = await fetch(url, { ...init, headers });
    const text = await response.text();
    let payload: unknown = undefined;
    if (text) {
      try { payload = JSON.parse(text); } catch { payload = text; }
    }
    if (!response.ok) {
      const err = new Error(`${response.status} ${response.statusText}: ${typeof payload === 'string' ? payload : JSON.stringify(payload)}`);
      (err as Error & { status?: number }).status = response.status;
      throw err;
    }
    return payload as T;
  }
}

export function odataQuery(params: Record<string, string | number | undefined>): string {
  const query = new URLSearchParams();
  for (const [key, value] of Object.entries(params)) {
    if (value !== undefined && value !== '') query.set(key.startsWith('$') ? key : `$${key}`, String(value));
  }
  const value = query.toString();
  return value ? `?${value}` : '';
}
