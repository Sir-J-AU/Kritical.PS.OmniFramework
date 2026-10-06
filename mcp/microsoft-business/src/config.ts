export type AppConfig = {
  tenantId: string;
  clientId: string;
  clientSecret: string;
  d365OrgUrl?: string;
  bcEnvironment: string;
  bcCompanyId?: string;
  enableWrites: boolean;
  serverName: string;
};

function required(name: string): string {
  const value = process.env[name]?.trim();
  if (!value) throw new Error(`Missing required environment variable: ${name}`);
  return value;
}

export function loadConfig(): AppConfig {
  return {
    tenantId: required('AZURE_TENANT_ID'),
    clientId: required('AZURE_CLIENT_ID'),
    clientSecret: required('AZURE_CLIENT_SECRET'),
    d365OrgUrl: process.env.D365_ORG_URL?.replace(/\/$/, ''),
    bcEnvironment: process.env.BC_ENVIRONMENT?.trim() || 'Production',
    bcCompanyId: process.env.BC_COMPANY_ID?.trim() || undefined,
    enableWrites: /^true$/i.test(process.env.MCP_ENABLE_WRITES || ''),
    serverName: process.env.MCP_SERVER_NAME?.trim() || 'kritical-microsoft-business'
  };
}

export function requireWrites(config: AppConfig): void {
  if (!config.enableWrites) {
    throw new Error('Write operation refused: MCP_ENABLE_WRITES is not true.');
  }
}
