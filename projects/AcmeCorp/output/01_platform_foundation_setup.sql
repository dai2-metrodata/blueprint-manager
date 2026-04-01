-- =============================================================================
-- ACMECORP PLATFORM FOUNDATION SETUP
-- Complete Deployment Package
-- =============================================================================
-- Blueprint:    Platform Foundation Setup (blueprint_4d563df2)
-- Customer:     AcmeCorp
-- Strategy:     Multi-Account (Environment-based)
-- Edition:      Enterprise
-- Region:       us-east-2
-- Generated:    2026-04-01
-- =============================================================================
--
-- DEPLOYMENT ORDER:
--   Task 1: Platform Foundation         (Steps 1.1 - 1.7)
--   Task 2: Security & Identity         (Steps 2.1 - 2.9)
--   Task 3: Cost Management             (Steps 3.1 - 3.6)
--   Task 4: Observability               (Step  4.1)
--
-- PREREQUISITES:
--   - Snowflake account with ORGADMIN and ACCOUNTADMIN privileges
--   - Enterprise Edition or higher
--   - Azure AD (Entra ID) tenant configured
--   - IP ranges for corporate network, VPN, and cloud services
--
-- ⚠️  PLACEHOLDERS TO REPLACE BEFORE EXECUTION:
--   <REPLACE_WITH_SECURE_PASSWORD>  - Strong unique passwords (min 14 chars)
--   <AZURE_TENANT_ID>               - Azure AD tenant GUID
--   <PASTE_BASE64_CERTIFICATE_FROM_AZURE_AD> - SAML X.509 certificate
--   <SCIM_IDP_IP_1>, etc.           - Azure AD SCIM service IP ranges
-- =============================================================================


-- #############################################################################
-- TASK 1: PLATFORM FOUNDATION
-- #############################################################################
-- Personas: Platform Administrator, Cloud/Infrastructure Team
-- Role Required: ORGADMIN or ACCOUNTADMIN
-- =============================================================================


-- =============================================================================
-- STEP 1.1: DETERMINE ACCOUNT STRATEGY
-- =============================================================================

-- Verify current account information
SELECT 
  CURRENT_ACCOUNT() AS current_account,
  CURRENT_ACCOUNT_NAME() AS account_name,
  CURRENT_ORGANIZATION_NAME() AS organization_name,
  CURRENT_REGION() AS region;

-- Check if organization is enabled
SHOW ORGANIZATION ACCOUNTS;

-- Get account edition and other details
SELECT 
  SYSTEM$GET_SNOWFLAKE_PLATFORM_INFO() AS platform_info;

/*
Strategy Selected: Multi-Account (Environment-based)

Key Characteristics:
- Primary Isolation: Physical (Account per Environment)
- Cost Tracking: Separate Bills per Environment
- SDLC Data Sharing: Secure Data Sharing
- Complexity: Medium
*/


-- =============================================================================
-- STEP 1.2: CONFIGURE ORGANIZATION NAME FOR CONNECTIVITY
-- =============================================================================

-- Get current organization name
SELECT CURRENT_ORGANIZATION_NAME() AS organization_name;

-- Get current account name
SELECT CURRENT_ACCOUNT_NAME() AS account_name;

-- Get full account identifier
SELECT 
  CURRENT_ORGANIZATION_NAME() || '-' || CURRENT_ACCOUNT_NAME() AS account_identifier;

/*
Organization Configuration:
- Organization Name: ACMECORP
- Account Name Prefix: ACME
- Account Identifier Pattern: ACMECORP-ACME_<account_name>

Web UI URL:
https://acmecorp-acme_<account_name>.snowflakecomputing.com

SnowSQL Connection:
snowsql -a ACMECORP-ACME_<account_name>

Python Connector:
account = "acmecorp-acme_<account_name>"
*/


-- =============================================================================
-- STEP 1.3: ENABLE ORGANIZATION ACCOUNT
-- =============================================================================

-- You have chosen to create an Organization Account for centralized management.

USE ROLE ACCOUNTADMIN;

-- Check your current organization name
SELECT CURRENT_ORGANIZATION_NAME() AS organization_name;

-- Verify your account edition (must be Enterprise or higher)
SELECT CURRENT_ACCOUNT() AS account,
       SYSTEM$GET_ACCOUNT_EDITION() AS edition;

-- Check if ORGADMIN role exists
SHOW ROLES LIKE 'ORGADMIN';


-- =============================================================================
-- STEP 1.4: CREATE ORGANIZATION ACCOUNT
-- =============================================================================

USE ROLE ORGADMIN;

-- Check current organization
SELECT CURRENT_ORGANIZATION_NAME() AS organization_name;

-- List existing accounts in the organization
SHOW ORGANIZATION ACCOUNTS;

-- ⚠️  IMPORTANT: Replace <REPLACE_WITH_SECURE_PASSWORD> with a strong, unique
--    password before executing. Min 14 chars, 1+ uppercase, 1+ lowercase,
--    1+ digit, 1+ special character.

CREATE ORGANIZATION ACCOUNT ACME_ORG
  ADMIN_NAME = 'platform_admin'
  ADMIN_PASSWORD = '<REPLACE_WITH_SECURE_PASSWORD>'
  ADMIN_USER_TYPE = PERSON
  EMAIL = 'platform-admin@acmecorp.com'
  MUST_CHANGE_PASSWORD = TRUE
  EDITION = ENTERPRISE
  REGION = 'us-east-2'
  COMMENT = 'Organization Account for centralized management';

-- Verify account creation
SHOW ORGANIZATION ACCOUNTS;

SELECT * FROM SNOWFLAKE.ORGANIZATION_USAGE.ACCOUNTS 
WHERE ACCOUNT_NAME = 'ACME_ORG';

/*
NEXT STEPS:
1. The initial administrator (platform_admin) will receive an email 
   with login credentials
2. Log into the new Organization Account at:
   https://ACMECORP-ACME_ORG.snowflakecomputing.com
3. Change the initial password on first login
4. Set up MFA for the ACCOUNTADMIN user
5. Continue the remaining workflow steps in the Organization Account
*/


-- =============================================================================
-- STEP 1.5: CREATE INFRASTRUCTURE DATABASE
-- =============================================================================

USE ROLE ACCOUNTADMIN;

CREATE DATABASE IF NOT EXISTS PLAT_INFRA
  COMMENT = 'Infrastructure database for platform-wide metadata and governance objects';

USE DATABASE PLAT_INFRA;

CREATE SCHEMA IF NOT EXISTS GOVERNANCE
  WITH MANAGED ACCESS
  COMMENT = 'Schema for governance policies, tags, and security objects';

-- Grant USAGE on database to SYSADMIN and SECURITYADMIN
GRANT USAGE ON DATABASE PLAT_INFRA TO ROLE SYSADMIN;
GRANT USAGE ON DATABASE PLAT_INFRA TO ROLE SECURITYADMIN;

-- Grant USAGE on schema
GRANT USAGE ON SCHEMA PLAT_INFRA.GOVERNANCE TO ROLE SYSADMIN;
GRANT USAGE ON SCHEMA PLAT_INFRA.GOVERNANCE TO ROLE SECURITYADMIN;

-- Grant CREATE TAG privilege
GRANT CREATE TAG ON SCHEMA PLAT_INFRA.GOVERNANCE TO ROLE SYSADMIN;

-- Verification
SHOW DATABASES LIKE 'PLAT_INFRA';
SHOW SCHEMAS IN DATABASE PLAT_INFRA;
DESC SCHEMA PLAT_INFRA.GOVERNANCE;


-- =============================================================================
-- STEP 1.6: DEFINE DOMAINS, ENVIRONMENTS, AND NAMING CONVENTIONS
-- =============================================================================

USE ROLE ACCOUNTADMIN;
USE DATABASE PLAT_INFRA;
USE SCHEMA GOVERNANCE;

-- Create core platform tags
CREATE TAG IF NOT EXISTS domain
  ALLOWED_VALUES = 'engineering'
  COMMENT = 'Business domain identifier (e.g., engineering, finance)';

CREATE TAG IF NOT EXISTS environment
  ALLOWED_VALUES = 'dev', 'test', 'prod'
  COMMENT = 'SDLC environment stage';

CREATE TAG IF NOT EXISTS dataproduct
  COMMENT = 'Data product identifier within a domain';

CREATE TAG IF NOT EXISTS workload
  ALLOWED_VALUES = 'ingest', 'transform', 'query', 'bi', 'admin'
  COMMENT = 'Workload type for cost allocation';

CREATE TAG IF NOT EXISTS zone
  ALLOWED_VALUES = 'raw', 'curated', 'consumption'
  COMMENT = 'Data zone in the medallion architecture';

CREATE TAG IF NOT EXISTS data_classification
  ALLOWED_VALUES = 'public', 'internal', 'confidential', 'restricted'
  COMMENT = 'Data sensitivity classification level';

-- Verification
SHOW TAGS IN SCHEMA PLAT_INFRA.GOVERNANCE;

/*
Naming Convention: <domain>_<env>_<dataproduct>

Example Objects:
- Database:  ENGINEERING_PROD_RAW
- Warehouse: ENGINEERING_PROD_TRANSFORM_WH
- Role:      ENGINEERING_PROD_ADMIN

Domains: engineering
Environments: dev, test, prod
Zones: raw, curated, consumption
*/


-- =============================================================================
-- STEP 1.7: CONFIGURE INFRASTRUCTURE DATABASE REPLICATION
-- =============================================================================

USE ROLE ACCOUNTADMIN;

-- Verify replication is enabled
SHOW REPLICATION ACCOUNTS;

-- Create the replication group (30-minute schedule)
CREATE REPLICATION GROUP IF NOT EXISTS INFRASTRUCTURE_REPLICATION_GROUP
  OBJECT_TYPES = DATABASES
  ALLOWED_DATABASES = PLAT_INFRA
  ALLOWED_ACCOUNTS = ACMECORP.ACME_ORG
  REPLICATION_SCHEDULE = '30 MINUTE'
  COMMENT = 'Replication group for infrastructure database - governance objects across organization accounts';

-- Verification
SHOW REPLICATION GROUPS LIKE 'INFRASTRUCTURE_REPLICATION_GROUP';

/*
ADDING NEW ACCOUNTS TO THE REPLICATION GROUP:
When you create ACME_DEV, ACME_TEST, ACME_PROD:

ALTER REPLICATION GROUP INFRASTRUCTURE_REPLICATION_GROUP
  SET ALLOWED_ACCOUNTS = ACMECORP.ACME_ORG, ACMECORP.<new_account_name>;

Then, in the new account:
CREATE REPLICATION GROUP INFRASTRUCTURE_REPLICATION_GROUP
  AS REPLICA OF ACMECORP.ACME_ORG.INFRASTRUCTURE_REPLICATION_GROUP;
ALTER REPLICATION GROUP INFRASTRUCTURE_REPLICATION_GROUP REFRESH;
*/


-- #############################################################################
-- TASK 2: SECURITY & IDENTITY
-- #############################################################################
-- Personas: Security Administrator, Identity Team, Platform Administrator
-- Role Required: ACCOUNTADMIN
-- Prerequisites: Task 1 completed, Azure AD tenant ready
-- =============================================================================


-- =============================================================================
-- STEP 2.1: SELECT IDENTITY MANAGEMENT APPROACH
-- =============================================================================

/*
SUMMARY:
- User Provisioning Method: Azure AD (Entra ID)
- SAML/SSO Configuration: Yes

Next: Configure SCIM Integration to set up automated user provisioning.
*/


-- =============================================================================
-- STEP 2.2: CONFIGURE SCIM INTEGRATION (Azure AD)
-- =============================================================================

USE ROLE ACCOUNTADMIN;

-- Create dedicated SCIM provisioner role
CREATE ROLE IF NOT EXISTS AAD_PROVISIONER;

GRANT CREATE USER ON ACCOUNT TO ROLE AAD_PROVISIONER;
GRANT CREATE ROLE ON ACCOUNT TO ROLE AAD_PROVISIONER;
GRANT ROLE AAD_PROVISIONER TO ROLE ACCOUNTADMIN;

-- Create network rule for SCIM (restrict to Azure AD IPs)
-- ⚠️  Replace with actual Azure AD SCIM service IP ranges
CREATE OR REPLACE NETWORK RULE scim_network_rule
  TYPE = IPV4
  MODE = INGRESS
  VALUE_LIST = ('<SCIM_IDP_IP_1>', '<SCIM_IDP_IP_2>')
  COMMENT = 'Network rule for Azure AD (Entra ID) SCIM integration';

-- Create network policy for SCIM
CREATE OR REPLACE NETWORK POLICY scim_network_policy
  ALLOWED_NETWORK_RULE_LIST = (scim_network_rule)
  COMMENT = 'Network policy for Azure AD (Entra ID) SCIM integration';

-- Create SCIM security integration
CREATE OR REPLACE SECURITY INTEGRATION AZURE_AD_SCIM
  TYPE = SCIM
  SCIM_CLIENT = 'AZURE'
  RUN_AS_ROLE = 'AAD_PROVISIONER'
  NETWORK_POLICY = 'scim_network_policy'
  SYNC_PASSWORD = FALSE
  COMMENT = 'Azure AD SCIM integration for user provisioning';

-- ⚠️  IMPORTANT: Run this and copy the token to Azure AD - shown only once!
SELECT SYSTEM$GENERATE_SCIM_ACCESS_TOKEN('AZURE_AD_SCIM') AS scim_token;

/*
SCIM ENDPOINT URL (configure in Azure AD):
https://acmecorp-acme_org.snowflakecomputing.com/scim/v2/
*/

-- Verification
SHOW ROLES LIKE 'AAD_PROVISIONER';
SHOW NETWORK POLICIES LIKE 'scim_network_policy';
SHOW SECURITY INTEGRATIONS LIKE 'AZURE_AD_SCIM';
DESC SECURITY INTEGRATION AZURE_AD_SCIM;


-- =============================================================================
-- STEP 2.3: PROVISION ACCOUNT ADMINISTRATORS
-- =============================================================================
-- Bootstrap admin users created directly (before SCIM is active)

USE ROLE ACCOUNTADMIN;

-- Create user: Platform Admin (ACCOUNTADMIN)
-- ⚠️  Replace <REPLACE_WITH_SECURE_PASSWORD> with a strong, unique password
CREATE USER IF NOT EXISTS PLATFORM_ADMIN
  PASSWORD = '<REPLACE_WITH_SECURE_PASSWORD>'
  LOGIN_NAME = 'PLATFORM_ADMIN'
  DISPLAY_NAME = 'Platform Admin'
  FIRST_NAME = 'Platform'
  LAST_NAME = 'Admin'
  EMAIL = 'platform-admin@acmecorp.com'
  MUST_CHANGE_PASSWORD = TRUE
  DEFAULT_ROLE = 'SYSADMIN'
  COMMENT = 'Administrator created during platform setup';

-- Create user: System Admin (SYSADMIN)
CREATE USER IF NOT EXISTS SYS_ADMIN
  PASSWORD = '<REPLACE_WITH_SECURE_PASSWORD>'
  LOGIN_NAME = 'SYS_ADMIN'
  DISPLAY_NAME = 'System Admin'
  FIRST_NAME = 'System'
  LAST_NAME = 'Admin'
  EMAIL = 'sysadmin@acmecorp.com'
  MUST_CHANGE_PASSWORD = TRUE
  DEFAULT_ROLE = 'SYSADMIN'
  COMMENT = 'Administrator created during platform setup';

-- Create user: Security Admin (SECURITYADMIN)
CREATE USER IF NOT EXISTS SECURITY_ADMIN
  PASSWORD = '<REPLACE_WITH_SECURE_PASSWORD>'
  LOGIN_NAME = 'SECURITY_ADMIN'
  DISPLAY_NAME = 'Security Admin'
  FIRST_NAME = 'Security'
  LAST_NAME = 'Admin'
  EMAIL = 'security-admin@acmecorp.com'
  MUST_CHANGE_PASSWORD = TRUE
  DEFAULT_ROLE = 'SECURITYADMIN'
  COMMENT = 'Administrator created during platform setup';

-- Grant administrative roles
GRANT ROLE ACCOUNTADMIN TO USER PLATFORM_ADMIN;
GRANT ROLE SYSADMIN TO USER SYS_ADMIN;
GRANT ROLE SECURITYADMIN TO USER SECURITY_ADMIN;

-- ACCOUNTADMIN users also get SECURITYADMIN and SYSADMIN
GRANT ROLE SECURITYADMIN TO USER PLATFORM_ADMIN;
GRANT ROLE SYSADMIN TO USER PLATFORM_ADMIN;

-- Verification
SHOW USERS;

SELECT 
  grantee_name,
  role,
  granted_by,
  created_on
FROM snowflake.account_usage.grants_to_users
WHERE role IN ('ACCOUNTADMIN', 'SECURITYADMIN', 'SYSADMIN', 'USERADMIN')
  AND deleted_on IS NULL
ORDER BY role, grantee_name;


-- =============================================================================
-- STEP 2.4: CONFIGURE SAML/SSO (Azure AD)
-- =============================================================================

USE ROLE ACCOUNTADMIN;

-- ⚠️  Replace <AZURE_TENANT_ID> and <PASTE_BASE64_CERTIFICATE_FROM_AZURE_AD>
CREATE OR REPLACE SECURITY INTEGRATION AZURE_AD_SAML
  TYPE = SAML2
  ENABLED = TRUE
  SAML2_ISSUER = 'https://sts.windows.net/<AZURE_TENANT_ID>/'
  SAML2_SSO_URL = 'https://login.microsoftonline.com/<AZURE_TENANT_ID>/saml2'
  SAML2_PROVIDER = 'CUSTOM'
  SAML2_X509_CERT = '<PASTE_BASE64_CERTIFICATE_FROM_AZURE_AD>'
  SAML2_SP_INITIATED_LOGIN_PAGE_LABEL = 'Azure AD (Entra ID) SSO'
  SAML2_ENABLE_SP_INITIATED = TRUE
  SAML2_SNOWFLAKE_ACS_URL = 'https://acmecorp-acme_org.snowflakecomputing.com/fed/login'
  SAML2_SNOWFLAKE_ISSUER_URL = 'https://acmecorp-acme_org.snowflakecomputing.com'
  COMMENT = 'Azure AD (Entra ID) SAML SSO integration';

-- Enable SSO button on the login page
ALTER ACCOUNT SET SAML_IDENTITY_PROVIDER = 'AZURE_AD_SAML';

-- Verification
SHOW SECURITY INTEGRATIONS LIKE 'AZURE_AD_SAML';
DESC SECURITY INTEGRATION AZURE_AD_SAML;

/*
TESTING:
1. SP-Initiated SSO:
   Navigate to: https://acmecorp-acme_org.snowflakecomputing.com
   Click "Log in using Azure AD (Entra ID) SSO"

2. IdP-Initiated SSO:
   Log into Azure AD and click the Snowflake application tile

3. Verify in Snowflake:
   SELECT CURRENT_USER(), CURRENT_ROLE(), CURRENT_SESSION();
*/


-- =============================================================================
-- STEP 2.5: CREATE BREAK-GLASS EMERGENCY ACCESS
-- =============================================================================

USE ROLE ACCOUNTADMIN;

-- Create authentication policy for break-glass accounts
CREATE OR REPLACE AUTHENTICATION POLICY breakglass_auth_policy
  AUTHENTICATION_METHODS = (PASSWORD)
  MFA_ENROLLMENT = 'REQUIRED'
  MFA_POLICY = (ALLOWED_METHODS = ('OTP'))
  CLIENT_TYPES = (SNOWFLAKE_UI)
  SECURITY_INTEGRATIONS = ()
  COMMENT = 'Authentication policy for break-glass emergency access - password + OTP, UI only';

-- -----------------------------------------------------------------------------
-- Break-Glass Account 1: BREAKGLASS_ADMIN
-- -----------------------------------------------------------------------------

CREATE OR REPLACE NETWORK RULE breakglass_admin_network_rule
  TYPE = IPV4
  MODE = INGRESS
  VALUE_LIST = ('10.0.0.0/8')
  COMMENT = 'Network rule for break-glass account BREAKGLASS_ADMIN';

CREATE OR REPLACE NETWORK POLICY breakglass_admin_network_policy
  ALLOWED_NETWORK_RULE_LIST = (breakglass_admin_network_rule)
  COMMENT = 'Network policy for break-glass account BREAKGLASS_ADMIN';

-- ⚠️  Replace <REPLACE_WITH_SECURE_PASSWORD>
CREATE USER IF NOT EXISTS BREAKGLASS_ADMIN
  PASSWORD = '<REPLACE_WITH_SECURE_PASSWORD>'
  EMAIL = 'breakglass@acmecorp.com'
  MUST_CHANGE_PASSWORD = TRUE
  DEFAULT_ROLE = 'ACCOUNTADMIN'
  DEFAULT_WAREHOUSE = NULL
  COMMENT = 'Break-glass emergency access account - use OTP workflow';

GRANT ROLE ACCOUNTADMIN TO USER BREAKGLASS_ADMIN;
ALTER USER BREAKGLASS_ADMIN SET AUTHENTICATION POLICY breakglass_auth_policy;
ALTER USER BREAKGLASS_ADMIN SET NETWORK POLICY breakglass_admin_network_policy;

-- -----------------------------------------------------------------------------
-- Break-Glass Account 2: BREAKGLASS_SECONDARY
-- -----------------------------------------------------------------------------

CREATE OR REPLACE NETWORK RULE breakglass_secondary_network_rule
  TYPE = IPV4
  MODE = INGRESS
  VALUE_LIST = ('172.16.0.0/12')
  COMMENT = 'Network rule for break-glass account BREAKGLASS_SECONDARY';

CREATE OR REPLACE NETWORK POLICY breakglass_secondary_network_policy
  ALLOWED_NETWORK_RULE_LIST = (breakglass_secondary_network_rule)
  COMMENT = 'Network policy for break-glass account BREAKGLASS_SECONDARY';

-- ⚠️  Replace <REPLACE_WITH_SECURE_PASSWORD>
CREATE USER IF NOT EXISTS BREAKGLASS_SECONDARY
  PASSWORD = '<REPLACE_WITH_SECURE_PASSWORD>'
  EMAIL = 'breakglass-secondary@acmecorp.com'
  MUST_CHANGE_PASSWORD = TRUE
  DEFAULT_ROLE = 'ACCOUNTADMIN'
  DEFAULT_WAREHOUSE = NULL
  COMMENT = 'Break-glass emergency access account - use OTP workflow';

GRANT ROLE ACCOUNTADMIN TO USER BREAKGLASS_SECONDARY;
ALTER USER BREAKGLASS_SECONDARY SET AUTHENTICATION POLICY breakglass_auth_policy;
ALTER USER BREAKGLASS_SECONDARY SET NETWORK POLICY breakglass_secondary_network_policy;

-- Generate OTPs (uncomment when ready - store securely!)
-- ALTER USER BREAKGLASS_ADMIN ADD MFA METHOD OTP COUNT = 10;
-- ALTER USER BREAKGLASS_SECONDARY ADD MFA METHOD OTP COUNT = 10;

-- Verification
SHOW USERS LIKE 'BREAKGLASS%';
SHOW AUTHENTICATION POLICIES LIKE 'breakglass_auth_policy';
SHOW NETWORK POLICIES;


-- =============================================================================
-- STEP 2.6: CONFIGURE NETWORK RULES AND POLICIES
-- =============================================================================

USE ROLE ACCOUNTADMIN;
USE DATABASE PLAT_INFRA;
USE SCHEMA GOVERNANCE;

-- Allowed network rules
CREATE OR REPLACE NETWORK RULE CORPORATE_NETWORK
  TYPE = IPV4
  MODE = INGRESS
  VALUE_LIST = ('10.0.0.0/8')
  COMMENT = 'Allowed network rule: CORPORATE_NETWORK';

CREATE OR REPLACE NETWORK RULE VPN_ENDPOINTS
  TYPE = IPV4
  MODE = INGRESS
  VALUE_LIST = ('172.16.0.0/12')
  COMMENT = 'Allowed network rule: VPN_ENDPOINTS';

CREATE OR REPLACE NETWORK RULE CLOUD_SERVICES
  TYPE = IPV4
  MODE = INGRESS
  VALUE_LIST = ('198.51.100.0/24')
  COMMENT = 'Allowed network rule: CLOUD_SERVICES';

-- Blocked network rules
CREATE OR REPLACE NETWORK RULE GUEST_WIFI_BLOCK
  TYPE = IPV4
  MODE = INGRESS
  VALUE_LIST = ('10.50.0.0/16')
  COMMENT = 'Blocked network rule: GUEST_WIFI_BLOCK';

-- Create network policy
CREATE OR REPLACE NETWORK POLICY account_network_policy
  ALLOWED_NETWORK_RULE_LIST = (
    PLAT_INFRA.GOVERNANCE.CORPORATE_NETWORK,
    PLAT_INFRA.GOVERNANCE.VPN_ENDPOINTS,
    PLAT_INFRA.GOVERNANCE.CLOUD_SERVICES
  )
  BLOCKED_NETWORK_RULE_LIST = (
    PLAT_INFRA.GOVERNANCE.GUEST_WIFI_BLOCK
  )
  COMMENT = 'Primary network policy for account access';

-- Apply network policy at the account level
-- ⚠️  WARNING: Ensure all required IPs are included before running this!
ALTER ACCOUNT SET NETWORK_POLICY = account_network_policy;

-- Verification
SHOW NETWORK RULES;
SHOW NETWORK POLICIES;
DESC NETWORK POLICY account_network_policy;
SHOW PARAMETERS LIKE 'NETWORK_POLICY' IN ACCOUNT;


-- =============================================================================
-- STEP 2.7: CONFIGURE AUTHENTICATION POLICIES
-- =============================================================================

USE ROLE ACCOUNTADMIN;

-- Human user policy: Password + MFA (TOTP or Passkey)
CREATE OR REPLACE AUTHENTICATION POLICY human_user_auth_policy
  AUTHENTICATION_METHODS = (PASSWORD)
  MFA_ENROLLMENT = 'REQUIRED'
  MFA_POLICY = (ALLOWED_METHODS = ('TOTP', 'PASSKEY'))
  CLIENT_TYPES = (SNOWFLAKE_UI, DRIVERS, SNOWSQL)
  SECURITY_INTEGRATIONS = ()
  COMMENT = 'Human user policy - Password with MFA';

-- Service account policy: Key Pair Only
CREATE OR REPLACE AUTHENTICATION POLICY service_account_auth_policy
  AUTHENTICATION_METHODS = (KEYPAIR)
  CLIENT_TYPES = (DRIVERS)
  SECURITY_INTEGRATIONS = ()
  COMMENT = 'Service account policy - Key pair only, no UI access';

-- Apply human user policy at account level
ALTER ACCOUNT SET AUTHENTICATION POLICY human_user_auth_policy;

-- Note: Break-glass users already have breakglass_auth_policy applied
-- For service accounts created later:
-- ALTER USER <service_account> SET AUTHENTICATION POLICY service_account_auth_policy;

-- Verification
SHOW AUTHENTICATION POLICIES;
DESC AUTHENTICATION POLICY human_user_auth_policy;
DESC AUTHENTICATION POLICY service_account_auth_policy;
DESC AUTHENTICATION POLICY breakglass_auth_policy;
SHOW PARAMETERS LIKE 'AUTHENTICATION_POLICY' IN ACCOUNT;


-- =============================================================================
-- STEP 2.8: ENABLE MULTI-FACTOR AUTHENTICATION
-- =============================================================================

USE ROLE ACCOUNTADMIN;

-- Check current MFA settings
SHOW PARAMETERS LIKE '%MFA%' IN ACCOUNT;

-- Check MFA enrollment status for admin users
SELECT 
  name,
  login_name,
  email,
  has_mfa,
  ext_authn_uid,
  created_on,
  last_success_login
FROM snowflake.account_usage.users
WHERE deleted_on IS NULL
  AND name IN (
    'PLATFORM_ADMIN',
    'SYS_ADMIN',
    'SECURITY_ADMIN'
  )
ORDER BY has_mfa DESC, name;

-- Summary of MFA enrollment across all users
SELECT 
  CASE WHEN has_mfa THEN 'MFA Enrolled' ELSE 'MFA Not Enrolled' END as mfa_status,
  COUNT(*) as user_count
FROM snowflake.account_usage.users
WHERE deleted_on IS NULL
GROUP BY has_mfa;

-- Users without MFA (excluding service and break-glass accounts)
SELECT 
  name,
  login_name,
  email,
  created_on,
  last_success_login
FROM snowflake.account_usage.users
WHERE deleted_on IS NULL
  AND has_mfa = FALSE
  AND name NOT LIKE '%SERVICE%'
  AND name NOT LIKE '%SVC%'
  AND name != 'BREAKGLASS_ADMIN'
  AND name != 'BREAKGLASS_SECONDARY'
ORDER BY last_success_login DESC;

-- Recent MFA enrollment events
SELECT 
  event_timestamp,
  user_name,
  event_type,
  is_success
FROM snowflake.account_usage.login_history
WHERE event_type LIKE '%MFA%'
  AND event_timestamp > DATEADD(day, -30, CURRENT_TIMESTAMP())
ORDER BY event_timestamp DESC
LIMIT 100;

/*
MFA GRACE PERIOD: 7 Days - Allow one week for enrollment
Support Contact: it-helpdesk@acmecorp.com
*/


-- #############################################################################
-- TASK 3: COST MANAGEMENT
-- #############################################################################
-- Personas: FinOps Team, Finance Team, Platform Administrator
-- Role Required: ACCOUNTADMIN
-- Prerequisites: Task 1 & 2 completed
-- =============================================================================


-- =============================================================================
-- STEP 3.1: CONFIGURE SPENDING BUDGETS
-- =============================================================================

USE ROLE ACCOUNTADMIN;

-- Activate account budget
CALL SNOWFLAKE.LOCAL.ACCOUNT_ROOT_BUDGET!ACTIVATE();

-- Set monthly spending limit: 6,667 credits (~$20K/month)
CALL SNOWFLAKE.LOCAL.ACCOUNT_ROOT_BUDGET!SET_SPENDING_LIMIT(6667);

-- Set notification threshold at 75%
CALL SNOWFLAKE.LOCAL.ACCOUNT_ROOT_BUDGET!SET_NOTIFICATION_THRESHOLD(75);

-- Add email notification recipients
CALL SNOWFLAKE.LOCAL.ACCOUNT_ROOT_BUDGET!SET_EMAIL_NOTIFICATIONS('finops@acmecorp.com');
CALL SNOWFLAKE.LOCAL.ACCOUNT_ROOT_BUDGET!SET_EMAIL_NOTIFICATIONS('platform-admin@acmecorp.com');
CALL SNOWFLAKE.LOCAL.ACCOUNT_ROOT_BUDGET!SET_EMAIL_NOTIFICATIONS('finance-alerts@acmecorp.com');

-- Using default 6.5-hour refresh interval - no action needed

-- Verification
CALL SNOWFLAKE.LOCAL.ACCOUNT_ROOT_BUDGET!GET_SPENDING_LIMIT();
CALL SYSTEM$GET_BUDGET_REFRESH_TIER();

-- Check current spending against budget
SELECT 
  DATE_TRUNC('month', CURRENT_DATE()) AS budget_month,
  6667 AS budget_limit,
  75 AS threshold_percent,
  ROUND(6667 * 75 / 100, 0) AS alert_trigger_credits,
  SUM(credits_used) AS credits_used_to_date,
  ROUND(SUM(credits_used) / 6667 * 100, 2) AS percentage_used
FROM snowflake.account_usage.metering_history
WHERE start_time >= DATE_TRUNC('month', CURRENT_DATE());


-- =============================================================================
-- STEP 3.2: CONFIGURE RESOURCE MONITORS
-- =============================================================================

USE ROLE ACCOUNTADMIN;

-- Create account-level resource monitor with tiered thresholds
CREATE OR REPLACE RESOURCE MONITOR account_resource_monitor
  WITH CREDIT_QUOTA = 7500
  FREQUENCY = MONTHLY
  START_TIMESTAMP = IMMEDIATELY
  TRIGGERS
    ON 75 PERCENT DO NOTIFY
    ON 90 PERCENT DO NOTIFY
    ON 100 PERCENT DO SUSPEND;

-- Apply resource monitor to the entire account
ALTER ACCOUNT SET RESOURCE_MONITOR = account_resource_monitor;

-- Verification
SHOW RESOURCE MONITORS LIKE 'account_resource_monitor';
SHOW PARAMETERS LIKE 'RESOURCE_MONITOR' IN ACCOUNT;


-- =============================================================================
-- STEP 3.3: CONFIGURE COST ALLOCATION TAGS
-- =============================================================================

USE ROLE ACCOUNTADMIN;
USE DATABASE PLAT_INFRA;
USE SCHEMA GOVERNANCE;

-- Create additional FinOps tags
CREATE TAG IF NOT EXISTS cost_center
  COMMENT = 'Accounting cost center code for chargeback';

CREATE TAG IF NOT EXISTS owner
  COMMENT = 'Team or individual responsible for the resource';

CREATE TAG IF NOT EXISTS project
  COMMENT = 'Project or initiative name for cost allocation';

CREATE TAG IF NOT EXISTS application
  COMMENT = 'Application or system name';

-- Create cost reporting views

-- Credit usage by domain
CREATE OR REPLACE VIEW cost_by_domain AS
SELECT 
  tr.tag_value AS domain,
  DATE_TRUNC('day', wm.start_time) AS usage_date,
  SUM(wm.credits_used) AS total_credits
FROM snowflake.account_usage.warehouse_metering_history wm
JOIN snowflake.account_usage.tag_references tr
  ON wm.warehouse_name = tr.object_name
  AND tr.domain = 'WAREHOUSE'
  AND tr.tag_name = 'DOMAIN'
  AND tr.deleted_on IS NULL
WHERE wm.start_time >= DATEADD(day, -30, CURRENT_TIMESTAMP())
GROUP BY tr.tag_value, DATE_TRUNC('day', wm.start_time)
ORDER BY usage_date DESC, total_credits DESC;

-- Credit usage by environment
CREATE OR REPLACE VIEW cost_by_environment AS
SELECT 
  tr.tag_value AS environment,
  DATE_TRUNC('day', wm.start_time) AS usage_date,
  SUM(wm.credits_used) AS total_credits
FROM snowflake.account_usage.warehouse_metering_history wm
JOIN snowflake.account_usage.tag_references tr
  ON wm.warehouse_name = tr.object_name
  AND tr.domain = 'WAREHOUSE'
  AND tr.tag_name = 'ENVIRONMENT'
  AND tr.deleted_on IS NULL
WHERE wm.start_time >= DATEADD(day, -30, CURRENT_TIMESTAMP())
GROUP BY tr.tag_value, DATE_TRUNC('day', wm.start_time)
ORDER BY usage_date DESC, total_credits DESC;

-- Untagged warehouses (compliance check)
CREATE OR REPLACE VIEW untagged_warehouses AS
SELECT 
  w.name AS warehouse_name,
  w.size,
  w.created_on
FROM snowflake.account_usage.warehouses w
LEFT JOIN (
  SELECT DISTINCT object_name 
  FROM snowflake.account_usage.tag_references 
  WHERE tag_name = 'DOMAIN' AND domain = 'WAREHOUSE' AND deleted_on IS NULL
) d ON w.name = d.object_name
WHERE w.deleted IS NULL
  AND d.object_name IS NULL
ORDER BY w.created_on DESC;

-- Grant access to cost views
GRANT SELECT ON VIEW cost_by_domain TO ROLE SYSADMIN;
GRANT SELECT ON VIEW cost_by_environment TO ROLE SYSADMIN;
GRANT SELECT ON VIEW untagged_warehouses TO ROLE SYSADMIN;

-- Tag the infrastructure database
ALTER DATABASE PLAT_INFRA SET TAG 
  PLAT_INFRA.GOVERNANCE.owner = 'Platform Team';

-- Verification
SHOW TAGS IN SCHEMA PLAT_INFRA.GOVERNANCE;


-- #############################################################################
-- TASK 4: OBSERVABILITY
-- #############################################################################
-- Personas: Platform Administrator, SRE / Observability Team
-- Role Required: ACCOUNTADMIN
-- =============================================================================


-- =============================================================================
-- STEP 4.1: CONFIGURE TELEMETRY PARAMETERS
-- =============================================================================

USE ROLE ACCOUNTADMIN;

-- Set event table for telemetry collection
ALTER ACCOUNT SET EVENT_TABLE = 'SNOWFLAKE.TELEMETRY.EVENTS';

-- Log level: WARN (capture warnings and above)
ALTER ACCOUNT SET LOG_LEVEL = 'WARN';

-- Metric level: ALL (collect execution metrics)
ALTER ACCOUNT SET METRIC_LEVEL = 'ALL';

-- Trace level: ON_EVENT (capture when events are added)
ALTER ACCOUNT SET TRACE_LEVEL = 'ON_EVENT';

-- SQL trace: ON (capture SQL text of traced statements)
ALTER ACCOUNT SET SQL_TRACE_QUERY_TEXT = 'ON';

-- Verification
SHOW PARAMETERS LIKE 'EVENT_TABLE' IN ACCOUNT;
SHOW PARAMETERS LIKE 'LOG_LEVEL' IN ACCOUNT;
SHOW PARAMETERS LIKE 'METRIC_LEVEL' IN ACCOUNT;
SHOW PARAMETERS LIKE 'TRACE_LEVEL' IN ACCOUNT;
SHOW PARAMETERS LIKE 'SQL_TRACE_QUERY_TEXT' IN ACCOUNT;

-- Check for recent telemetry data (may take a few minutes)
SELECT RECORD_TYPE, COUNT(*) AS record_count
FROM SNOWFLAKE.TELEMETRY.EVENTS
WHERE TIMESTAMP > DATEADD('hour', -1, CURRENT_TIMESTAMP())
GROUP BY RECORD_TYPE;


-- #############################################################################
-- PLATFORM FOUNDATION SETUP COMPLETE
-- #############################################################################

/*
=============================================================================
DEPLOYMENT SUMMARY - ACMECORP
=============================================================================

ORGANIZATION:
  - Org Name:       ACMECORP
  - Org Account:    ACME_ORG (Enterprise, us-east-2)
  - Strategy:       Multi-Account (Environment-based)

ACCOUNTS (to be created via Account Creation blueprint):
  - ACME_DEV  (Development)
  - ACME_TEST (Test/Staging)
  - ACME_PROD (Production)

INFRASTRUCTURE:
  - Database:       PLAT_INFRA
  - Schema:         PLAT_INFRA.GOVERNANCE (managed access)
  - Replication:    Every 30 minutes to all accounts

IDENTITY & SECURITY:
  - IdP:            Azure AD (Entra ID) - SCIM + SAML/SSO
  - SCIM:           AZURE_AD_SCIM (AAD_PROVISIONER role)
  - SAML:           AZURE_AD_SAML
  - Human Auth:     Password + MFA (TOTP or Passkey)
  - Service Auth:   Key Pair Only
  - MFA Enrollment: 7-day grace period
  - Network Policy: Account-level (Corporate, VPN, Cloud)
  - Break-Glass:    2 accounts (BREAKGLASS_ADMIN, BREAKGLASS_SECONDARY)

ADMINISTRATORS:
  - PLATFORM_ADMIN  (ACCOUNTADMIN) - platform-admin@acmecorp.com
  - SYS_ADMIN       (SYSADMIN)     - sysadmin@acmecorp.com
  - SECURITY_ADMIN  (SECURITYADMIN) - security-admin@acmecorp.com

COST MANAGEMENT:
  - Budget:           6,667 credits/mo (~$20K), 75% alert threshold
  - Resource Monitor: 7,500 credits/mo, suspend after current queries
  - Tags (Core):      domain, environment, dataproduct, workload, zone
  - Tags (FinOps):    cost_center, owner, project, application
  - Cost Views:       cost_by_domain, cost_by_environment, untagged_warehouses

OBSERVABILITY:
  - Event Table:  SNOWFLAKE.TELEMETRY.EVENTS
  - Log Level:    WARN
  - Metrics:      ALL
  - Traces:       ON_EVENT
  - SQL Trace:    ON

NEXT WORKFLOWS:
  1. Account Creation    - Create ACME_DEV, ACME_TEST, ACME_PROD
  2. Data Product Setup  - Deploy data products with databases, roles, warehouses
  3. RBAC Hardening      - Audit and harden access controls
=============================================================================
*/
