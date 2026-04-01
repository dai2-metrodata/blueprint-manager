# AcmeCorp Platform Foundation - Deployment Guide

> **Blueprint:** Platform Foundation Setup (blueprint_4d563df2)
> **Generated:** 2026-04-01 | **Edition:** Enterprise | **Region:** us-east-2

---

## Table of Contents

1. [Executive Summary](#1-executive-summary)
2. [Architecture Overview](#2-architecture-overview)
3. [Prerequisites](#3-prerequisites)
4. [Placeholder Reference](#4-placeholder-reference)
5. [Deployment Plan](#5-deployment-plan)
6. [Task 1: Platform Foundation](#6-task-1-platform-foundation)
7. [Task 2: Security & Identity](#7-task-2-security--identity)
8. [Task 3: Cost Management](#8-task-3-cost-management)
9. [Task 4: Observability](#9-task-4-observability)
10. [Post-Deployment Validation](#10-post-deployment-validation)
11. [Day-2 Operations Runbook](#11-day-2-operations-runbook)
12. [Rollback Procedures](#12-rollback-procedures)
13. [Next Workflows](#13-next-workflows)
14. [Appendix](#14-appendix)

---

## 1. Executive Summary

This document provides the complete deployment instructions for AcmeCorp's Snowflake Platform Foundation. The deployment establishes a **Multi-Account (Environment-based)** architecture with enterprise-grade security, identity management, cost controls, and observability.

### What Gets Created

| Category | Objects Created |
|----------|----------------|
| **Accounts** | 1 Organization Account (ACME_ORG), 3 environment accounts planned (DEV/TEST/PROD) |
| **Databases** | PLAT_INFRA with GOVERNANCE schema (managed access) |
| **Tags** | 10 tags (6 core + 4 FinOps) |
| **Integrations** | AZURE_AD_SCIM (SCIM), AZURE_AD_SAML (SSO) |
| **Users** | 3 admins + 2 break-glass accounts |
| **Roles** | AAD_PROVISIONER |
| **Network** | 4 network rules, 4 network policies |
| **Auth Policies** | 3 (human, service, break-glass) |
| **Cost Controls** | 1 budget, 1 account resource monitor, 4 FinOps tags |
| **Views** | 3 cost reporting views |
| **Replication** | 1 replication group (30-min schedule) |

### Timeline Estimate

| Task | Duration | Personas |
|------|----------|----------|
| Task 1: Platform Foundation | 30-45 min | Platform Admin, Cloud Team |
| Task 2: Security & Identity | 45-60 min | Security Admin, Identity Team |
| Task 3: Cost Management | 35-45 min | FinOps Team, Finance |
| Task 4: Observability | 5-10 min | Platform Admin, SRE |
| **Total** | **~2-3 hours** | |

---

## 2. Architecture Overview

```
                    ┌─────────────────────────────────┐
                    │     SNOWFLAKE ORGANIZATION       │
                    │          ACMECORP                │
                    └───────────────┬─────────────────┘
                                    │
                    ┌───────────────▼─────────────────┐
                    │   ORGANIZATION ACCOUNT           │
                    │   ACME_ORG                       │
                    │   ┌─────────────────────────┐   │
                    │   │ PLAT_INFRA Database      │   │
                    │   │  └─ GOVERNANCE Schema    │   │
                    │   │     ├─ Tags (10)         │   │
                    │   │     ├─ Network Rules (4) │   │
                    │   │     └─ Cost Views (3)    │   │
                    │   └─────────────────────────┘   │
                    │   Azure AD: SCIM + SAML/SSO     │
                    │   Budget: 6,667 cr/mo            │
                    │   Monitor: 7,500 cr/mo           │
                    └──┬──────────┬──────────┬────────┘
                       │          │          │
            ┌──────────▼──┐ ┌────▼──────┐ ┌─▼──────────┐
            │  ACME_DEV   │ │ ACME_TEST │ │ ACME_PROD  │
            │  (planned)  │ │ (planned) │ │ (planned)  │
            └─────────────┘ └───────────┘ └────────────┘
               ▲               ▲              ▲
               └───────── DB Replication (every 30 min) ──┘

    Data Zones per Account:
    ┌─────────┐     ┌──────────┐     ┌─────────────┐
    │   RAW   │ ──► │ CURATED  │ ──► │ CONSUMPTION │
    └─────────┘     └──────────┘     └─────────────┘

    Naming Pattern: <domain>_<env>_<dataproduct>
    Example: ENGINEERING_PROD_RAW
```

### Network Security Architecture

```
    ALLOWED                              BLOCKED
    ┌─────────────────────┐             ┌──────────────────┐
    │ CORPORATE_NETWORK   │             │ GUEST_WIFI_BLOCK │
    │ 10.0.0.0/8          │             │ 10.50.0.0/16     │
    ├─────────────────────┤             └──────────────────┘
    │ VPN_ENDPOINTS       │
    │ 172.16.0.0/12       │
    ├─────────────────────┤
    │ CLOUD_SERVICES      │
    │ 198.51.100.0/24     │
    └─────────────────────┘
              │
              ▼
    ┌─────────────────────────────────────────┐
    │ account_network_policy                   │
    │ Applied: Account-level (all users)       │
    └─────────────────────────────────────────┘

    Break-Glass (bypass):
    ├─ BREAKGLASS_ADMIN       → 10.0.0.0/8    (own policy)
    └─ BREAKGLASS_SECONDARY   → 172.16.0.0/12 (own policy)
```

### Cost Control Architecture

```
    ┌─────────── SPENDING BUDGET ────────────┐
    │ Limit: 6,667 credits/mo (~$20K)        │
    │ Alert: 75% → finops/platform/finance   │
    │ Type:  SOFT (notify only)              │
    │ Refresh: Every 6.5 hours               │
    └────────────────────────────────────────┘
              │ (early warning)
              ▼
    ┌─────────── RESOURCE MONITOR ───────────┐
    │ Limit: 7,500 credits/mo                │
    │  75% → NOTIFY (5,625 cr)               │
    │  90% → NOTIFY (6,750 cr)               │
    │ 100% → SUSPEND (7,500 cr)              │
    │ Type:  HARD (suspend after queries)    │
    │ Reset: Monthly                         │
    └────────────────────────────────────────┘
```

---

## 3. Prerequisites

### 3.1 Snowflake Requirements

| Requirement | Status |
|-------------|--------|
| Snowflake account provisioned | ☐ |
| Enterprise Edition or higher | ☐ |
| ORGADMIN role available | ☐ |
| ACCOUNTADMIN role available | ☐ |
| SNOWFLAKE database IMPORTED PRIVILEGES | ☐ |

### 3.2 Azure AD Requirements

| Requirement | Status |
|-------------|--------|
| Azure AD (Entra ID) tenant configured | ☐ |
| Azure AD tenant ID (GUID) obtained | ☐ |
| Enterprise Application for Snowflake created | ☐ |
| SAML signing certificate exported (Base64) | ☐ |
| SCIM provisioning configured in Azure AD | ☐ |
| Azure AD SCIM service IP ranges identified | ☐ |

### 3.3 Network Requirements

| Requirement | Status |
|-------------|--------|
| Corporate network CIDR(s) documented | ☐ |
| VPN endpoint CIDR(s) documented | ☐ |
| Cloud service CIDR(s) documented | ☐ |
| Guest WiFi CIDR(s) to block documented | ☐ |

### 3.4 Stakeholder Requirements

| Requirement | Status |
|-------------|--------|
| Monthly credit budget approved by finance (~$20K) | ☐ |
| Administrator list approved (3 admins) | ☐ |
| Break-glass procedure owners designated | ☐ |
| Budget alert distribution lists created | ☐ |
| MFA enrollment communication plan ready | ☐ |

---

## 4. Placeholder Reference

Before executing **any** SQL, search and replace all placeholders:

| # | Placeholder | Value to Provide | Occurrences | Security |
|---|-------------|------------------|-------------|----------|
| 1 | `<REPLACE_WITH_SECURE_PASSWORD>` | Unique strong password per user (min 14 chars, upper+lower+digit+special) | 6 | Use password manager; never reuse |
| 2 | `<AZURE_TENANT_ID>` | Azure Portal → Azure AD → Properties → Tenant ID | 2 | Not a secret, but validate |
| 3 | `<PASTE_BASE64_CERTIFICATE_FROM_AZURE_AD>` | Azure Portal → Enterprise Apps → Snowflake → SAML → Certificate (Base64, no PEM headers) | 1 | Treat as sensitive |
| 4 | `<SCIM_IDP_IP_1>`, `<SCIM_IDP_IP_2>` | Azure AD provisioning service IP ranges ([MS docs](https://learn.microsoft.com/en-us/entra/identity/app-provisioning/)) | 1 | Public IPs, but validate |

### Password Requirements for Each User

| User | Placeholder Instance | Delivery Method |
|------|---------------------|-----------------|
| ACME_ORG initial admin (platform_admin) | Step 1.4 | Secure channel to platform-admin@acmecorp.com |
| PLATFORM_ADMIN | Step 2.3 | Secure channel to platform-admin@acmecorp.com |
| SYS_ADMIN | Step 2.3 | Secure channel to sysadmin@acmecorp.com |
| SECURITY_ADMIN | Step 2.3 | Secure channel to security-admin@acmecorp.com |
| BREAKGLASS_ADMIN | Step 2.5 | Store in enterprise vault (CyberArk, 1Password, etc.) |
| BREAKGLASS_SECONDARY | Step 2.5 | Store in separate vault/location from primary |

---

## 5. Deployment Plan

### 5.1 Execution Order

```
PHASE 1: Initial Account (your current Snowflake account)
├── Step 1.1  Determine Account Strategy           [read-only]
├── Step 1.2  Configure Organization Name           [read-only]
├── Step 1.3  Enable Organization Account           [read-only check]
└── Step 1.4  Create Organization Account           [CREATES ACCOUNT]

    ⚠️  SWITCH: Log into ACME_ORG account before continuing

PHASE 2: Organization Account (ACME_ORG)
├── Step 1.5  Create Infrastructure Database        [CREATES DB + SCHEMA]
├── Step 1.6  Define Domains & Naming Conventions   [CREATES TAGS]
├── Step 1.7  Configure DB Replication              [CREATES REPL GROUP]
├── Step 2.1  Select Identity Management            [documentation only]
├── Step 2.2  Configure SCIM Integration            [CREATES INTEGRATION]
├── Step 2.3  Provision Account Administrators      [CREATES USERS]
├── Step 2.4  Configure SAML/SSO                    [CREATES INTEGRATION]
├── Step 2.5  Create Break-Glass Access             [CREATES USERS + POLICIES]
├── Step 2.6  Configure Network Rules & Policies    [CREATES RULES + POLICY]
│   ⚠️  TEST: Verify your own access still works before proceeding!
├── Step 2.7  Configure Authentication Policies     [CREATES POLICIES]
├── Step 2.8  Enable Multi-Factor Authentication    [read-only monitoring]
├── Step 3.1  Configure Spending Budgets            [ACTIVATES BUDGET]
├── Step 3.2  Configure Resource Monitors           [CREATES MONITOR]
├── Step 3.3  Configure Cost Allocation Tags        [CREATES TAGS + VIEWS]
└── Step 4.1  Configure Telemetry Parameters        [SETS PARAMETERS]
```

### 5.2 Critical Checkpoints

| After Step | Checkpoint | Action If Failed |
|------------|------------|------------------|
| 1.4 | Can log into ACME_ORG | Check email for admin credentials; verify org name in URL |
| 2.2 | SCIM token generated and saved | Re-run `SYSTEM$GENERATE_SCIM_ACCESS_TOKEN`; token shown only once |
| 2.5 | Break-glass accounts tested | Verify from allowed IP; check network policy and auth policy |
| 2.6 | **YOUR access still works** after network policy | If locked out, use break-glass account to fix policy |
| 2.7 | Auth policy applied without lockout | Break-glass bypasses; fix policy if needed |
| 3.2 | Resource monitor active | Verify with `SHOW RESOURCE MONITORS` |

---

## 6. Task 1: Platform Foundation

**Duration:** 30-45 minutes
**Role Required:** ORGADMIN, ACCOUNTADMIN
**Account Context:** Initial account (Steps 1.1-1.4), then ACME_ORG (Steps 1.5-1.7)

### Step 1.1: Determine Account Strategy

**Action:** Read-only verification
**What it does:** Validates current account info and documents the multi-account strategy choice.

**Key Decision:** Multi-Account (Environment-based) — separate accounts for DEV, TEST, PROD. This provides:
- Physical isolation between environments
- Separate billing per environment
- Secure Data Sharing for cross-environment access

### Step 1.2: Configure Organization Name for Connectivity

**Action:** Read-only verification
**What it does:** Documents the org name (ACMECORP), account prefix (ACME), and connection patterns.

**Connection Pattern:**
- Web UI: `https://acmecorp-acme_<account>.snowflakecomputing.com`
- SnowSQL: `snowsql -a ACMECORP-ACME_<account>`
- Python: `account = "acmecorp-acme_<account>"`

### Step 1.3: Enable Organization Account

**Action:** Read-only prerequisite check
**What it does:** Verifies Enterprise Edition and ORGADMIN role availability.

### Step 1.4: Create Organization Account

**Action:** ⚡ Creates ACME_ORG account
**Role:** ORGADMIN

**⚠️ IMPORTANT:**
1. Replace `<REPLACE_WITH_SECURE_PASSWORD>` before executing
2. The initial admin (platform_admin) will receive an email with login credentials
3. After creation, **log into ACME_ORG** before continuing:
   `https://ACMECORP-ACME_ORG.snowflakecomputing.com`

### Step 1.5: Create Infrastructure Database

**Action:** ⚡ Creates PLAT_INFRA database and GOVERNANCE schema
**Role:** ACCOUNTADMIN (in ACME_ORG)

**Objects Created:**
- `PLAT_INFRA` database
- `PLAT_INFRA.GOVERNANCE` schema (WITH MANAGED ACCESS)
- USAGE grants to SYSADMIN and SECURITYADMIN
- CREATE TAG grant to SYSADMIN

### Step 1.6: Define Domains, Environments, and Naming Conventions

**Action:** ⚡ Creates 6 core platform tags
**Role:** ACCOUNTADMIN

**Tags Created in `PLAT_INFRA.GOVERNANCE`:**

| Tag | Allowed Values | Purpose |
|-----|---------------|---------|
| `domain` | engineering | Business domain |
| `environment` | dev, test, prod | SDLC stage |
| `dataproduct` | (any) | Data product identifier |
| `workload` | ingest, transform, query, bi, admin | Cost allocation |
| `zone` | raw, curated, consumption | Medallion zone |
| `data_classification` | public, internal, confidential, restricted | Sensitivity |

### Step 1.7: Configure Infrastructure Database Replication

**Action:** ⚡ Creates replication group
**Role:** ACCOUNTADMIN

- Group: `INFRASTRUCTURE_REPLICATION_GROUP`
- Schedule: Every 30 minutes
- Allowed accounts: `ACMECORP.ACME_ORG`
- When new accounts are created (ACME_DEV, etc.), add them to the replication group

---

## 7. Task 2: Security & Identity

**Duration:** 45-60 minutes
**Role Required:** ACCOUNTADMIN
**Account Context:** ACME_ORG
**Prerequisites:** Task 1 completed, Azure AD tenant ready

### Step 2.1: Select Identity Management Approach

**Action:** Documentation only
**Decision:** Azure AD (Entra ID) with SCIM + SAML/SSO

### Step 2.2: Configure SCIM Integration

**Action:** ⚡ Creates SCIM provisioner role and integration
**Role:** ACCOUNTADMIN

**Objects Created:**
- Role: `AAD_PROVISIONER`
- Network rule: `scim_network_rule` (Azure AD IPs)
- Network policy: `scim_network_policy`
- Security integration: `AZURE_AD_SCIM`

**⚠️ CRITICAL:** The SCIM access token is shown **only once**. Copy it immediately and configure in Azure AD:
- SCIM Endpoint: `https://acmecorp-acme_org.snowflakecomputing.com/scim/v2/`
- Bearer Token: (from `SYSTEM$GENERATE_SCIM_ACCESS_TOKEN`)

### Step 2.3: Provision Account Administrators

**Action:** ⚡ Creates 3 bootstrap admin users
**Role:** ACCOUNTADMIN

| User | Role | Email | Default Role |
|------|------|-------|-------------|
| PLATFORM_ADMIN | ACCOUNTADMIN | platform-admin@acmecorp.com | SYSADMIN |
| SYS_ADMIN | SYSADMIN | sysadmin@acmecorp.com | SYSADMIN |
| SECURITY_ADMIN | SECURITYADMIN | security-admin@acmecorp.com | SECURITYADMIN |

All users created with `MUST_CHANGE_PASSWORD = TRUE`. Deliver passwords via secure channel.

### Step 2.4: Configure SAML/SSO

**Action:** ⚡ Creates SAML security integration
**Role:** ACCOUNTADMIN

**⚠️ PLACEHOLDERS:** Replace `<AZURE_TENANT_ID>` and `<PASTE_BASE64_CERTIFICATE_FROM_AZURE_AD>`

**Objects Created:**
- Security integration: `AZURE_AD_SAML`
- SSO login button enabled on Snowflake login page

**Testing:**
1. SP-Initiated: Navigate to `https://acmecorp-acme_org.snowflakecomputing.com` → click SSO button
2. IdP-Initiated: Log into Azure AD → click Snowflake tile

### Step 2.5: Create Break-Glass Emergency Access

**Action:** ⚡ Creates 2 emergency access accounts
**Role:** ACCOUNTADMIN

| Account | Allowed IPs | Auth Policy | Purpose |
|---------|------------|-------------|---------|
| BREAKGLASS_ADMIN | 10.0.0.0/8 (corporate) | Password + OTP, UI only | Primary emergency |
| BREAKGLASS_SECONDARY | 172.16.0.0/12 (VPN) | Password + OTP, UI only | Secondary emergency |

**Objects Created per account:**
- Network rule + network policy (user-level)
- User with ACCOUNTADMIN role
- `breakglass_auth_policy` (shared)

**⚠️ POST-STEP:** Generate OTPs and store in enterprise vault:
```sql
ALTER USER BREAKGLASS_ADMIN ADD MFA METHOD OTP COUNT = 10;
ALTER USER BREAKGLASS_SECONDARY ADD MFA METHOD OTP COUNT = 10;
```

### Step 2.6: Configure Network Rules and Policies

**Action:** ⚡ Creates network rules and applies account-level policy
**Role:** ACCOUNTADMIN

**⚠️ HIGH RISK STEP:** This applies a network policy to **all users**. If your current IP is not in the allowed list, you will be locked out.

**Pre-execution checklist:**
- [ ] Verify your current IP is within 10.0.0.0/8, 172.16.0.0/12, or 198.51.100.0/24
- [ ] Verify break-glass accounts are created and tested (Step 2.5)
- [ ] Have break-glass credentials accessible

**Objects Created:**
- Rules: CORPORATE_NETWORK, VPN_ENDPOINTS, CLOUD_SERVICES, GUEST_WIFI_BLOCK
- Policy: `account_network_policy` (applied at account level)

### Step 2.7: Configure Authentication Policies

**Action:** ⚡ Creates auth policies and applies account-level policy
**Role:** ACCOUNTADMIN

| Policy | Methods | MFA | Applies To |
|--------|---------|-----|-----------|
| `human_user_auth_policy` | PASSWORD | Required (TOTP + Passkey) | Account-level default |
| `service_account_auth_policy` | KEYPAIR | N/A | Applied per service user |
| `breakglass_auth_policy` | PASSWORD | Required (OTP only) | Break-glass users |

### Step 2.8: Enable Multi-Factor Authentication

**Action:** Read-only monitoring
**What it does:** Provides queries to monitor MFA enrollment across all users.

**MFA Enrollment Timeline:**
- Grace period: **7 days** from first login
- Preferred method: TOTP (Authenticator App)
- Support contact: it-helpdesk@acmecorp.com

---

## 8. Task 3: Cost Management

**Duration:** 35-45 minutes
**Role Required:** ACCOUNTADMIN
**Account Context:** ACME_ORG
**Prerequisites:** Task 1 & 2 completed

### Step 3.1: Configure Spending Budgets

**Action:** ⚡ Activates and configures account budget

| Setting | Value |
|---------|-------|
| Monthly limit | 6,667 credits (~$20,000 at $3/credit) |
| Alert threshold | 75% (alerts when projected > 5,000 credits) |
| Refresh interval | 6.5 hours (default) |
| Alert recipients | finops@acmecorp.com, platform-admin@acmecorp.com, finance-alerts@acmecorp.com |

### Step 3.2: Configure Resource Monitors

**Action:** ⚡ Creates account-level resource monitor

| Setting | Value |
|---------|-------|
| Credit quota | 7,500 credits/month |
| 75% threshold | NOTIFY (5,625 credits) |
| 90% threshold | NOTIFY (6,750 credits) |
| 100% threshold | SUSPEND (7,500 credits) |
| Reset | Monthly |
| Action type | Suspend After Current Queries |

**How budget + monitor work together:**
1. At ~5,000 credits: Budget predicts overage → email alert (early warning)
2. At 5,625 credits: Resource monitor hits 75% → NOTIFY
3. At 6,667 credits: Budget limit reached → continued alerting
4. At 6,750 credits: Resource monitor hits 90% → final NOTIFY
5. At 7,500 credits: Resource monitor hits 100% → **ALL WAREHOUSES SUSPENDED**

### Step 3.3: Configure Cost Allocation Tags

**Action:** ⚡ Creates FinOps tags and cost reporting views

**Additional Tags:**

| Tag | Purpose |
|-----|---------|
| `cost_center` | Accounting cost center code |
| `owner` | Team or individual responsible |
| `project` | Project or initiative name |
| `application` | Application or system name |

**Cost Reporting Views Created:**

| View | Purpose |
|------|---------|
| `PLAT_INFRA.GOVERNANCE.cost_by_domain` | Daily credit usage aggregated by domain tag |
| `PLAT_INFRA.GOVERNANCE.cost_by_environment` | Daily credit usage aggregated by environment tag |
| `PLAT_INFRA.GOVERNANCE.untagged_warehouses` | Warehouses missing domain tags (compliance) |

---

## 9. Task 4: Observability

**Duration:** 5-10 minutes
**Role Required:** ACCOUNTADMIN
**Account Context:** ACME_ORG

### Step 4.1: Configure Telemetry Parameters

**Action:** ⚡ Sets account-level telemetry parameters

| Parameter | Value | Purpose |
|-----------|-------|---------|
| EVENT_TABLE | SNOWFLAKE.TELEMETRY.EVENTS | Target for all telemetry data |
| LOG_LEVEL | WARN | Capture warnings and above from handler code |
| METRIC_LEVEL | ALL | Collect execution metrics |
| TRACE_LEVEL | ON_EVENT | Capture trace spans when events are added |
| SQL_TRACE_QUERY_TEXT | ON | Capture SQL text of traced statements |

---

## 10. Post-Deployment Validation

Run these validation queries after completing all 4 tasks:

```sql
USE ROLE ACCOUNTADMIN;

-- Infrastructure
SHOW DATABASES LIKE 'PLAT_INFRA';                          -- Expect: 1 row
SHOW SCHEMAS IN DATABASE PLAT_INFRA;                        -- Expect: GOVERNANCE + PUBLIC
SHOW TAGS IN SCHEMA PLAT_INFRA.GOVERNANCE;                  -- Expect: 10 tags

-- Identity
SHOW SECURITY INTEGRATIONS;                                 -- Expect: AZURE_AD_SCIM, AZURE_AD_SAML
SHOW USERS LIKE 'PLATFORM_ADMIN';                           -- Expect: 1 row
SHOW USERS LIKE 'BREAKGLASS%';                              -- Expect: 2 rows
SHOW ROLES LIKE 'AAD_PROVISIONER';                          -- Expect: 1 row

-- Network
SHOW NETWORK RULES IN SCHEMA PLAT_INFRA.GOVERNANCE;         -- Expect: 3+ rules
SHOW NETWORK POLICIES;                                      -- Expect: 4+ policies
SHOW PARAMETERS LIKE 'NETWORK_POLICY' IN ACCOUNT;           -- Expect: account_network_policy

-- Authentication
SHOW AUTHENTICATION POLICIES;                               -- Expect: 3 policies
SHOW PARAMETERS LIKE 'AUTHENTICATION_POLICY' IN ACCOUNT;    -- Expect: human_user_auth_policy

-- Cost Controls
CALL SNOWFLAKE.LOCAL.ACCOUNT_ROOT_BUDGET!GET_SPENDING_LIMIT(); -- Expect: 6667
SHOW RESOURCE MONITORS LIKE 'account_resource_monitor';      -- Expect: 1 row, quota=7500

-- Replication
SHOW REPLICATION GROUPS;                                     -- Expect: 1 group

-- Observability
SHOW PARAMETERS LIKE 'EVENT_TABLE' IN ACCOUNT;               -- Expect: SNOWFLAKE.TELEMETRY.EVENTS
SHOW PARAMETERS LIKE 'LOG_LEVEL' IN ACCOUNT;                 -- Expect: WARN
```

### Validation Checklist

| # | Check | Expected Result | Status |
|---|-------|-----------------|--------|
| 1 | PLAT_INFRA database exists | 1 database | ☐ |
| 2 | GOVERNANCE schema has managed access | IS_MANAGED_ACCESS = Y | ☐ |
| 3 | 10 tags created | 6 core + 4 FinOps | ☐ |
| 4 | SCIM integration active | AZURE_AD_SCIM exists | ☐ |
| 5 | SAML integration active | AZURE_AD_SAML exists | ☐ |
| 6 | 3 admin users created | PLATFORM_ADMIN, SYS_ADMIN, SECURITY_ADMIN | ☐ |
| 7 | 2 break-glass users created | BREAKGLASS_ADMIN, BREAKGLASS_SECONDARY | ☐ |
| 8 | Account network policy applied | account_network_policy | ☐ |
| 9 | Account auth policy applied | human_user_auth_policy | ☐ |
| 10 | Budget active at 6,667 credits | GET_SPENDING_LIMIT = 6667 | ☐ |
| 11 | Resource monitor at 7,500 credits | quota = 7500, suspend action | ☐ |
| 12 | Replication group exists | 30-min schedule | ☐ |
| 13 | Telemetry configured | LOG_LEVEL = WARN | ☐ |
| 14 | SSO login works | Test SP-initiated login | ☐ |
| 15 | Break-glass access works | Test from allowed IP | ☐ |

---

## 11. Day-2 Operations Runbook

### 11.1 Break-Glass Emergency Procedure

**When to use:** SSO/Azure AD is down, or all admin accounts are locked out.

```
1. Retrieve credentials from enterprise vault:
   - Username: BREAKGLASS_ADMIN (or BREAKGLASS_SECONDARY)
   - Password: (from vault)
   - OTP codes: (from vault)

2. Connect from an allowed IP:
   - BREAKGLASS_ADMIN: Must be on corporate network (10.0.0.0/8)
   - BREAKGLASS_SECONDARY: Must be on VPN (172.16.0.0/12)

3. Navigate to: https://acmecorp-acme_org.snowflakecomputing.com

4. Log in with username + password

5. Enter OTP code when prompted

6. Perform recovery actions with ACCOUNTADMIN role

7. Document all actions taken during emergency

8. Rotate OTPs after use:
   ALTER USER BREAKGLASS_ADMIN ADD MFA METHOD OTP COUNT = 10;
```

### 11.2 Adding a New Environment Account

When creating ACME_DEV, ACME_TEST, or ACME_PROD:

```sql
-- 1. In ACME_ORG: Add account to replication group
ALTER REPLICATION GROUP INFRASTRUCTURE_REPLICATION_GROUP
  SET ALLOWED_ACCOUNTS = ACMECORP.ACME_ORG, ACMECORP.ACME_DEV;

-- 2. In ACME_DEV: Create secondary replication group
CREATE REPLICATION GROUP INFRASTRUCTURE_REPLICATION_GROUP
  AS REPLICA OF ACMECORP.ACME_ORG.INFRASTRUCTURE_REPLICATION_GROUP;

-- 3. In ACME_DEV: Initial refresh
ALTER REPLICATION GROUP INFRASTRUCTURE_REPLICATION_GROUP REFRESH;
```

Then use the **Account Creation** blueprint for full configuration.

### 11.3 Adding a New Domain

```sql
-- In ACME_ORG:
USE ROLE ACCOUNTADMIN;
ALTER TAG PLAT_INFRA.GOVERNANCE.domain
  ADD ALLOWED_VALUES = 'newdomain';
```

### 11.4 Budget Alert Response Procedure

| Alert Level | Action |
|-------------|--------|
| Budget 75% projected | Review top-consuming warehouses; investigate anomalies |
| Monitor 75% actual | Identify and right-size over-consuming warehouses |
| Monitor 90% actual | Pause non-critical workloads; notify management |
| Monitor 100% SUSPEND | All warehouses suspended; increase limit or wait for reset |

**To temporarily increase resource monitor limit:**
```sql
USE ROLE ACCOUNTADMIN;
ALTER RESOURCE MONITOR account_resource_monitor SET CREDIT_QUOTA = 9000;
-- Remember to reset after investigation
```

### 11.5 Rotating SCIM Token

SCIM tokens should be rotated periodically:

```sql
USE ROLE ACCOUNTADMIN;
SELECT SYSTEM$GENERATE_SCIM_ACCESS_TOKEN('AZURE_AD_SCIM') AS new_scim_token;
-- Update the token in Azure AD Enterprise Application immediately
```

### 11.6 Periodic RBAC Review

Run monthly from ACME_ORG:

```sql
-- Users with ACCOUNTADMIN (should be minimal)
SELECT grantee_name, role, created_on
FROM snowflake.account_usage.grants_to_users
WHERE role = 'ACCOUNTADMIN' AND deleted_on IS NULL;

-- Users without MFA
SELECT name, email, last_success_login
FROM snowflake.account_usage.users
WHERE deleted_on IS NULL AND has_mfa = FALSE
  AND name NOT LIKE '%SERVICE%' AND name NOT LIKE '%BREAKGLASS%';

-- Untagged warehouses
SELECT * FROM PLAT_INFRA.GOVERNANCE.untagged_warehouses;
```

---

## 12. Rollback Procedures

### 12.1 Network Policy Lockout Recovery

If the account-level network policy locks out users:

```sql
-- Use break-glass account, then:
USE ROLE ACCOUNTADMIN;
ALTER ACCOUNT UNSET NETWORK_POLICY;
-- Fix the policy, then re-apply
```

### 12.2 Authentication Policy Lockout Recovery

```sql
-- Use break-glass account (has its own auth policy), then:
USE ROLE ACCOUNTADMIN;
ALTER ACCOUNT UNSET AUTHENTICATION POLICY;
-- Fix the policy, then re-apply
```

### 12.3 Resource Monitor Suspension Recovery

```sql
-- If warehouses are suspended due to monitor:
USE ROLE ACCOUNTADMIN;
-- Option 1: Increase the limit
ALTER RESOURCE MONITOR account_resource_monitor SET CREDIT_QUOTA = 10000;
-- Option 2: Temporarily remove
ALTER ACCOUNT UNSET RESOURCE_MONITOR;
-- Resume specific warehouses
ALTER WAREHOUSE <wh_name> RESUME;
```

### 12.4 Full Rollback (Nuclear Option)

```sql
-- ⚠️ CAUTION: Only if the entire deployment needs reversal
USE ROLE ACCOUNTADMIN;

-- Remove account-level settings
ALTER ACCOUNT UNSET NETWORK_POLICY;
ALTER ACCOUNT UNSET AUTHENTICATION POLICY;
ALTER ACCOUNT UNSET RESOURCE_MONITOR;
ALTER ACCOUNT UNSET SAML_IDENTITY_PROVIDER;

-- Drop cost controls
DROP RESOURCE MONITOR IF EXISTS account_resource_monitor;

-- Drop auth policies
DROP AUTHENTICATION POLICY IF EXISTS human_user_auth_policy;
DROP AUTHENTICATION POLICY IF EXISTS service_account_auth_policy;
DROP AUTHENTICATION POLICY IF EXISTS breakglass_auth_policy;

-- Drop network policies and rules (in order)
DROP NETWORK POLICY IF EXISTS account_network_policy;
DROP NETWORK POLICY IF EXISTS breakglass_admin_network_policy;
DROP NETWORK POLICY IF EXISTS breakglass_secondary_network_policy;
DROP NETWORK POLICY IF EXISTS scim_network_policy;

-- Drop users
DROP USER IF EXISTS BREAKGLASS_ADMIN;
DROP USER IF EXISTS BREAKGLASS_SECONDARY;
-- DO NOT drop admin users if they are actively in use

-- Drop integrations
DROP SECURITY INTEGRATION IF EXISTS AZURE_AD_SCIM;
DROP SECURITY INTEGRATION IF EXISTS AZURE_AD_SAML;

-- Drop roles
DROP ROLE IF EXISTS AAD_PROVISIONER;

-- Drop infrastructure (destroys all tags and views)
DROP DATABASE IF EXISTS PLAT_INFRA;

-- Drop replication
DROP REPLICATION GROUP IF EXISTS INFRASTRUCTURE_REPLICATION_GROUP;
```

---

## 13. Next Workflows

After completing Platform Foundation Setup:

| # | Blueprint | Purpose | When |
|---|-----------|---------|------|
| 1 | **Account Creation** | Create ACME_DEV, ACME_TEST, ACME_PROD accounts | Immediately after |
| 2 | **Data Product Setup** | Deploy data products with databases, roles, warehouses | Per data product |
| 3 | **RBAC Hardening** | Audit and harden access controls | After data products deployed, then periodically |

---

## 14. Appendix

### A. Complete Object Inventory

| Object Type | Name | Owner | Location |
|-------------|------|-------|----------|
| Database | PLAT_INFRA | ACCOUNTADMIN | ACME_ORG |
| Schema | GOVERNANCE | ACCOUNTADMIN | PLAT_INFRA |
| Tag | domain | ACCOUNTADMIN | PLAT_INFRA.GOVERNANCE |
| Tag | environment | ACCOUNTADMIN | PLAT_INFRA.GOVERNANCE |
| Tag | dataproduct | ACCOUNTADMIN | PLAT_INFRA.GOVERNANCE |
| Tag | workload | ACCOUNTADMIN | PLAT_INFRA.GOVERNANCE |
| Tag | zone | ACCOUNTADMIN | PLAT_INFRA.GOVERNANCE |
| Tag | data_classification | ACCOUNTADMIN | PLAT_INFRA.GOVERNANCE |
| Tag | cost_center | ACCOUNTADMIN | PLAT_INFRA.GOVERNANCE |
| Tag | owner | ACCOUNTADMIN | PLAT_INFRA.GOVERNANCE |
| Tag | project | ACCOUNTADMIN | PLAT_INFRA.GOVERNANCE |
| Tag | application | ACCOUNTADMIN | PLAT_INFRA.GOVERNANCE |
| View | cost_by_domain | ACCOUNTADMIN | PLAT_INFRA.GOVERNANCE |
| View | cost_by_environment | ACCOUNTADMIN | PLAT_INFRA.GOVERNANCE |
| View | untagged_warehouses | ACCOUNTADMIN | PLAT_INFRA.GOVERNANCE |
| Role | AAD_PROVISIONER | ACCOUNTADMIN | Account |
| User | PLATFORM_ADMIN | ACCOUNTADMIN | Account |
| User | SYS_ADMIN | ACCOUNTADMIN | Account |
| User | SECURITY_ADMIN | ACCOUNTADMIN | Account |
| User | BREAKGLASS_ADMIN | ACCOUNTADMIN | Account |
| User | BREAKGLASS_SECONDARY | ACCOUNTADMIN | Account |
| Security Integration | AZURE_AD_SCIM | ACCOUNTADMIN | Account |
| Security Integration | AZURE_AD_SAML | ACCOUNTADMIN | Account |
| Network Rule | CORPORATE_NETWORK | ACCOUNTADMIN | PLAT_INFRA.GOVERNANCE |
| Network Rule | VPN_ENDPOINTS | ACCOUNTADMIN | PLAT_INFRA.GOVERNANCE |
| Network Rule | CLOUD_SERVICES | ACCOUNTADMIN | PLAT_INFRA.GOVERNANCE |
| Network Rule | GUEST_WIFI_BLOCK | ACCOUNTADMIN | PLAT_INFRA.GOVERNANCE |
| Network Rule | scim_network_rule | ACCOUNTADMIN | Account |
| Network Rule | breakglass_admin_network_rule | ACCOUNTADMIN | Account |
| Network Rule | breakglass_secondary_network_rule | ACCOUNTADMIN | Account |
| Network Policy | account_network_policy | ACCOUNTADMIN | Account |
| Network Policy | scim_network_policy | ACCOUNTADMIN | Account |
| Network Policy | breakglass_admin_network_policy | ACCOUNTADMIN | Account |
| Network Policy | breakglass_secondary_network_policy | ACCOUNTADMIN | Account |
| Auth Policy | human_user_auth_policy | ACCOUNTADMIN | Account |
| Auth Policy | service_account_auth_policy | ACCOUNTADMIN | Account |
| Auth Policy | breakglass_auth_policy | ACCOUNTADMIN | Account |
| Resource Monitor | account_resource_monitor | ACCOUNTADMIN | Account |
| Replication Group | INFRASTRUCTURE_REPLICATION_GROUP | ACCOUNTADMIN | Account |

### B. Contact Reference

| Role | Contact | Email |
|------|---------|-------|
| Platform Admin | Platform Admin | platform-admin@acmecorp.com |
| System Admin | System Admin | sysadmin@acmecorp.com |
| Security Admin | Security Admin | security-admin@acmecorp.com |
| Break-Glass Primary | Emergency Access | breakglass@acmecorp.com |
| Break-Glass Secondary | Emergency Access | breakglass-secondary@acmecorp.com |
| FinOps Team | Cost Alerts | finops@acmecorp.com |
| Finance Alerts | Budget Notifications | finance-alerts@acmecorp.com |
| IT Helpdesk | MFA Support | it-helpdesk@acmecorp.com |

### C. File Manifest

```
/projects/AcmeCorp/
├── answers/
│   └── platform-foundation-setup/
│       └── answers_acmecorp.yaml          # Configuration answers
├── output/
│   ├── 00_preflight_checklist.sql         # Pre-flight verification
│   ├── 01_platform_foundation_setup.sql   # Complete rendered SQL
│   └── DEPLOYMENT_GUIDE.md                # This document
└── acmecorp_architecture.html             # Visual architecture diagram
```
