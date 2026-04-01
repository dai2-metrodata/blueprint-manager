-- =============================================================================
-- ACMECORP - PRE-FLIGHT CHECKLIST & PLACEHOLDER REFERENCE
-- =============================================================================
-- Run this BEFORE executing the deployment scripts to verify readiness
-- =============================================================================

-- #############################################################################
-- SECTION 1: PLACEHOLDER VALUES TO REPLACE
-- #############################################################################
-- Search and replace these values across all SQL files before execution.
-- ⚠️  DO NOT execute any script until ALL placeholders are resolved.
--
-- +---------------------------------------------+-----------------------------------+
-- | Placeholder                                 | Where to Get It                   |
-- +---------------------------------------------+-----------------------------------+
-- | <REPLACE_WITH_SECURE_PASSWORD>              | Generate with password manager     |
-- |                                             | Min 14 chars, upper+lower+digit+  |
-- |                                             | special. UNIQUE per user.         |
-- +---------------------------------------------+-----------------------------------+
-- | <AZURE_TENANT_ID>                           | Azure Portal > Azure AD >         |
-- |                                             | Properties > Tenant ID            |
-- +---------------------------------------------+-----------------------------------+
-- | <PASTE_BASE64_CERTIFICATE_FROM_AZURE_AD>    | Azure Portal > Enterprise Apps >  |
-- |                                             | Snowflake > SAML > Certificate    |
-- |                                             | (Base64 format, no headers)       |
-- +---------------------------------------------+-----------------------------------+
-- | <SCIM_IDP_IP_1>, <SCIM_IDP_IP_2>           | Azure AD SCIM service IPs:        |
-- |                                             | docs.microsoft.com/azure/active-  |
-- |                                             | directory/app-provisioning/       |
-- |                                             | Known IP ranges for SCIM traffic  |
-- +---------------------------------------------+-----------------------------------+


-- #############################################################################
-- SECTION 2: PRE-FLIGHT VERIFICATION QUERIES
-- #############################################################################

-- Check 1: Verify you have ORGADMIN role
USE ROLE ORGADMIN;
SELECT 'ORGADMIN role available' AS check_result;

-- Check 2: Verify ACCOUNTADMIN role
USE ROLE ACCOUNTADMIN;
SELECT 'ACCOUNTADMIN role available' AS check_result;

-- Check 3: Verify Enterprise Edition
SELECT 
  SYSTEM$GET_ACCOUNT_EDITION() AS edition,
  CASE 
    WHEN SYSTEM$GET_ACCOUNT_EDITION() IN ('ENTERPRISE', 'BUSINESS_CRITICAL') 
    THEN 'PASS' 
    ELSE 'FAIL - Enterprise Edition or higher required' 
  END AS status;

-- Check 4: Verify organization name
SELECT 
  CURRENT_ORGANIZATION_NAME() AS org_name,
  CASE 
    WHEN CURRENT_ORGANIZATION_NAME() IS NOT NULL THEN 'PASS'
    ELSE 'FAIL - Organization not configured'
  END AS status;

-- Check 5: Verify region
SELECT 
  CURRENT_REGION() AS region;

-- Check 6: Verify no conflicting objects exist
SHOW DATABASES LIKE 'PLAT_INFRA';
SHOW ROLES LIKE 'AAD_PROVISIONER';
SHOW RESOURCE MONITORS LIKE 'account_resource_monitor';


-- #############################################################################
-- SECTION 3: EXECUTION ORDER
-- #############################################################################
/*
Execute the main deployment script (01_platform_foundation_setup.sql) in order.
Each step is designed to be run sequentially.

TASK 1: PLATFORM FOUNDATION (run from initial/primary account)
  Step 1.1  Determine Account Strategy              ~read-only
  Step 1.2  Configure Organization Name              ~read-only
  Step 1.3  Enable Organization Account              ~read-only check
  Step 1.4  Create Organization Account              ~CREATES ACCOUNT
  Step 1.5  Create Infrastructure Database           ~CREATES DB + SCHEMA
  Step 1.6  Define Domains & Naming Conventions      ~CREATES TAGS
  Step 1.7  Configure DB Replication                 ~CREATES REPL GROUP

  >>> LOG INTO ACME_ORG ACCOUNT BEFORE CONTINUING <<<

TASK 2: SECURITY & IDENTITY (run from ACME_ORG account)
  Step 2.1  Select Identity Management               ~documentation only
  Step 2.2  Configure SCIM Integration               ~CREATES INTEGRATION
  Step 2.3  Provision Account Administrators          ~CREATES USERS
  Step 2.4  Configure SAML/SSO                       ~CREATES INTEGRATION
  Step 2.5  Create Break-Glass Access                 ~CREATES USERS + POLICIES
  Step 2.6  Configure Network Rules & Policies        ~CREATES RULES + POLICY
  Step 2.7  Configure Authentication Policies         ~CREATES POLICIES
  Step 2.8  Enable Multi-Factor Authentication        ~read-only monitoring

TASK 3: COST MANAGEMENT (run from ACME_ORG account)
  Step 3.1  Configure Spending Budgets                ~ACTIVATES BUDGET
  Step 3.2  Configure Resource Monitors               ~CREATES MONITOR
  Step 3.3  Configure Cost Allocation Tags            ~CREATES TAGS + VIEWS

TASK 4: OBSERVABILITY (run from ACME_ORG account)
  Step 4.1  Configure Telemetry Parameters            ~SETS PARAMETERS
*/


-- #############################################################################
-- SECTION 4: POST-DEPLOYMENT VALIDATION
-- #############################################################################

-- After running the full deployment, execute these checks:

USE ROLE ACCOUNTADMIN;

-- Validate Infrastructure
SHOW DATABASES LIKE 'PLAT_INFRA';
SHOW SCHEMAS IN DATABASE PLAT_INFRA;
SHOW TAGS IN SCHEMA PLAT_INFRA.GOVERNANCE;

-- Validate Identity
SHOW SECURITY INTEGRATIONS;
SHOW USERS;

-- Validate Network
SHOW NETWORK POLICIES;
SHOW NETWORK RULES IN SCHEMA PLAT_INFRA.GOVERNANCE;
SHOW PARAMETERS LIKE 'NETWORK_POLICY' IN ACCOUNT;

-- Validate Auth
SHOW AUTHENTICATION POLICIES;
SHOW PARAMETERS LIKE 'AUTHENTICATION_POLICY' IN ACCOUNT;

-- Validate Cost Controls
SHOW RESOURCE MONITORS;
CALL SNOWFLAKE.LOCAL.ACCOUNT_ROOT_BUDGET!GET_SPENDING_LIMIT();

-- Validate Observability
SHOW PARAMETERS LIKE 'EVENT_TABLE' IN ACCOUNT;
SHOW PARAMETERS LIKE 'LOG_LEVEL' IN ACCOUNT;

-- Validate Replication
SHOW REPLICATION GROUPS;

/*
=============================================================================
ALL CHECKS COMPLETE
=============================================================================
If all validations pass, proceed to:
  1. Account Creation blueprint  - Create ACME_DEV, ACME_TEST, ACME_PROD
  2. Data Product Setup blueprint - Deploy data products
  3. RBAC Hardening blueprint     - Harden access controls
=============================================================================
*/
