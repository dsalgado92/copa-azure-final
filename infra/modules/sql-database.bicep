// =====================================================
// Azure SQL Server + Database
// =====================================================
// Servidor lógico + 1 banco "FIFA2026Tickets".
// Firewall:
//   - Default: bloqueia tudo
//   - Adiciona regra para permitir Azure services (necessário
//     para o backend Web App acessar via outbound IPs Azure).
// Para produção real: trocar por Private Endpoint.
//
// ADE-009 Inv 2 / Story 4.1 (AC-4): Azure AD admin no servidor SQL.
//   Pré-requisito para autenticação Entra/Managed Identity (os contained users
//   `FROM EXTERNAL PROVIDER` da @data-engineer NÃO funcionam sem um AD admin no
//   servidor). Recurso OPCIONAL e CONDICIONAL (só materializa quando o objectId é
//   fornecido) — mantém compatível o deploy legado (main.bicep não passa os params).
//   O objectId/login vêm de parâmetro (nunca hardcoded — ADE-003 Inv 3); o valor real
//   é definido no provisionamento (@devops). O SQL auth (administratorLogin/Password)
//   PERMANECE (AC-5) — hardening aditivo, não Entra-only. Remover `AllowAllAzureServices`
//   é escopo da Story 4.2, NÃO desta.
// =====================================================

@description('Nome do servidor SQL (sem .database.windows.net).')
param serverName string

@description('Nome do database.')
param databaseName string

@description('Região Azure.')
param location string

@description('Login admin (SQL auth).')
param adminLogin string

@description('Senha admin.')
@secure()
param adminPassword string

@description('SKU da database.')
param skuName string

// --- ADE-009 Inv 2 / Story 4.1 (AC-4) — Azure AD admin (opcional, condicional) ---
@description('Login/nome de exibição do Azure AD admin do SQL Server (UPN de usuário ou nome de grupo). Vazio = não cria o AD admin (deploy legado).')
param aadAdminLogin string = ''

@description('Object ID (sid) do principal Entra que será AD admin do SQL Server. Vazio = não cria o AD admin. Definido no provisionamento (@devops) — nunca hardcoded.')
param aadAdminObjectId string = ''

@description('Tenant ID do principal Entra do AD admin. Default = tenant da subscription do deploy (derivado, não hardcoded).')
param aadAdminTenantId string = subscription().tenantId

resource sqlServer 'Microsoft.Sql/servers@2023-08-01-preview' = {
  name: serverName
  location: location
  properties: {
    administratorLogin: adminLogin
    administratorLoginPassword: adminPassword
    minimalTlsVersion: '1.2'
    publicNetworkAccess: 'Enabled'
    version: '12.0'
  }
}

// ADE-009 Inv 2 / Story 4.1 (AC-4) — Azure AD admin do servidor (pré-requisito da
// autenticação Entra/MI e dos contained users FROM EXTERNAL PROVIDER). Condicional:
// só materializa quando aadAdminObjectId é fornecido (deploy legado sem os params
// continua válido). name='ActiveDirectory' e administratorType='ActiveDirectory' são
// os valores fixos exigidos pela API (AC-16 — sem invenção).
resource sqlAadAdmin 'Microsoft.Sql/servers/administrators@2023-08-01-preview' = if (!empty(aadAdminObjectId)) {
  parent: sqlServer
  name: 'ActiveDirectory'
  properties: {
    administratorType: 'ActiveDirectory'
    login: aadAdminLogin
    sid: aadAdminObjectId
    tenantId: aadAdminTenantId
  }
}

resource sqlDb 'Microsoft.Sql/servers/databases@2023-08-01-preview' = {
  parent: sqlServer
  name: databaseName
  location: location
  sku: {
    name: skuName
    tier: skuName == 'Basic' ? 'Basic' : 'Standard'
  }
  properties: {
    collation: 'SQL_Latin1_General_CP1_CI_AS'
    maxSizeBytes: skuName == 'Basic' ? 2147483648 : 268435456000
    zoneRedundant: false
  }
}

// Permite que outros serviços Azure (Web Apps) cheguem ao SQL.
// Para apertar: trocar por Private Endpoint + VNet integration.
resource fwAllowAzure 'Microsoft.Sql/servers/firewallRules@2023-08-01-preview' = {
  parent: sqlServer
  name: 'AllowAllAzureServices'
  properties: {
    startIpAddress: '0.0.0.0'
    endIpAddress: '0.0.0.0'
  }
}

output serverFqdn string = sqlServer.properties.fullyQualifiedDomainName
output serverName string = sqlServer.name
output databaseName string = sqlDb.name
