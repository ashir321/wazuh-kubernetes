# Wazuh Kubernetes - Credentials Inventory

This document provides a complete inventory of all usernames, passwords, secrets, and encryption keys used across the Wazuh Kubernetes deployment, and maps which credentials are used by which components.

---

## 1. Kubernetes Secrets (Credential Pairs)

### 1.1 Wazuh Indexer Credentials

| Field    | Value                  |
|----------|------------------------|
| Secret Name | `indexer-cred` |
| File     | `wazuh/secrets/indexer-cred-secret.yaml` |
| Username | `admin` |
| Password | `KibanaS3rv3r@2026!` |

**Used by components:**

| Component | How it's consumed | Purpose |
|-----------|-------------------|---------|
| **Wazuh Dashboard** | Env vars `INDEXER_USERNAME` / `INDEXER_PASSWORD` (`dashboard-deploy.yaml:61-72`) | Dashboard connects to the Indexer API to query/display data |
| **Wazuh Manager Master** | Env vars `INDEXER_USERNAME` / `INDEXER_PASSWORD` (`wazuh-master-sts.yaml:116-125`) | Filebeat on the master ships alerts/logs to the Indexer |
| **Wazuh Manager Worker** | Env vars `INDEXER_USERNAME` / `INDEXER_PASSWORD` (`wazuh-worker-sts.yaml:115-126`) | Filebeat on workers ships alerts/logs to the Indexer |

---

### 1.2 Wazuh Dashboard Credentials

| Field    | Value                  |
|----------|------------------------|
| Secret Name | `dashboard-cred` |
| File     | `wazuh/secrets/dashboard-cred-secret.yaml` |
| Username | `kibanaserver` |
| Password | `KibanaS3rv3r@2026!` |

**Used by components:**

| Component | How it's consumed | Purpose |
|-----------|-------------------|---------|
| **Wazuh Dashboard** | Env vars `DASHBOARD_USERNAME` / `DASHBOARD_PASSWORD` (`dashboard-deploy.yaml:73-82`) | Internal service account the Dashboard uses to manage its own saved objects, index patterns, and session state within the Indexer |

> **Note:** The `kibanaserver` user must also be defined in the Indexer's `internal_users.yml` (see Section 3) with a matching bcrypt hash for authentication to succeed.

---

### 1.3 Wazuh API Credentials

| Field    | Value                  |
|----------|------------------------|
| Secret Name | `wazuh-api-cred` |
| File     | `wazuh/secrets/wazuh-api-cred-secret.yaml` |
| Username | `wazuh-wui` |
| Password | `KibanaS3rv3r@2026!` |

**Used by components:**

| Component | How it's consumed | Purpose |
|-----------|-------------------|---------|
| **Wazuh Dashboard** | Env vars `API_USERNAME` / `API_PASSWORD` (`dashboard-deploy.yaml:91-100`) | Dashboard calls the Wazuh Manager REST API (port 55000) for agent management, rule configuration, etc. |
| **Wazuh Manager Master** | Env vars `API_USERNAME` / `API_PASSWORD` (`wazuh-master-sts.yaml:134-143`) | Configures the Wazuh API user on the master manager at startup |

---

### 1.4 Wazuh Authd Registration Password

| Field    | Value                  |
|----------|------------------------|
| Secret Name | `wazuh-authd-pass` |
| File     | `wazuh/secrets/wazuh-authd-pass-secret.yaml` |
| Key      | `authd.pass` |
| Password | `KibanaS3rv3r@2026!` |

**Used by components:**

| Component | How it's consumed | Purpose |
|-----------|-------------------|---------|
| **Wazuh Manager Master** | Mounted as `/var/ossec/etc/authd.pass` | Agents must provide this password when auto-registering via the authd service (port 1515). Controlled by `<use_password>yes</use_password>` in `master.conf` |
| **Wazuh Agents** (external) | Provided at agent enrollment time | Agents supply this password during `agent-auth` or automatic enrollment |

---

### 1.5 Wazuh Cluster Key

| Field    | Value                  |
|----------|------------------------|
| Secret Name | `wazuh-cluster-key` |
| File     | `wazuh/secrets/wazuh-cluster-key-secret.yaml` |
| Key      | `key` |
| Value    | `KibanaS3rv3r@2026!` |

**Used by components:**

| Component | How it's consumed | Purpose |
|-----------|-------------------|---------|
| **Wazuh Manager Master** | Env var `WAZUH_CLUSTER_KEY` (`wazuh-master-sts.yaml:144-148`) | Shared encryption key for manager-to-manager cluster communication (port 1516). Replaces `to_be_replaced_by_cluster_key` in `master.conf` at runtime |
| **Wazuh Manager Worker** | Env var `WAZUH_CLUSTER_KEY` (`wazuh-worker-sts.yaml:135-139`) | Same key so workers can join the cluster |

> **Note:** The commented-out original value was `123a45bc67def891gh23i45jk67l8mn9` (32-char hex string). It has been replaced with the same password used elsewhere.

---

## 2. Encryption Keys (Non-Credential Secrets)

These are not username/password pairs but are sensitive values stored in configuration files.

| Key | Value | File | Purpose |
|-----|-------|------|---------|
| Compliance salt | `15e0ab9171d5ed1e` | `indexer_conf/opensearch.yml:32` | Field masking salt. Must be identical 16-char string on all indexer nodes |
| SQL datasource master key | `2b9973a42188de6b9a1dd3e89a09dc02` | `indexer_conf/opensearch.yml:38` | Encrypts SQL datasource connection credentials stored in the Indexer |

---

## 3. Wazuh Indexer Internal Users

These users are defined in `wazuh/indexer_stack/wazuh-indexer/indexer_conf/internal_users.yml` with bcrypt password hashes. They are the security plugin's built-in user database.

| Username | Backend Roles | Reserved | Purpose | Used By |
|----------|--------------|----------|---------|---------|
| `admin` | `admin` | Yes | Full admin access to the Indexer | Filebeat (via `indexer-cred` secret), direct Indexer API access |
| `kibanaserver` | *(none)* | Yes | Dashboard service account for managing index patterns and saved objects | Dashboard (via `dashboard-cred` secret) |
| `kibanaro` | `kibanauser`, `readall` | No | Demo read-only dashboard user | Not actively used in this deployment |
| `logstash` | `logstash` | No | Demo logstash ingestion user | Not actively used in this deployment |
| `readall` | `readall` | No | Demo read-only user | Not actively used in this deployment |
| `snapshotrestore` | `snapshotrestore` | No | Demo snapshot/restore user | Not actively used in this deployment |

> **Important:** The bcrypt hashes in `internal_users.yml` must match the plaintext passwords in the corresponding Kubernetes Secrets. If you change a password in a Secret file, you must also regenerate the bcrypt hash and update `internal_users.yml`.

---

## 4. TLS/SSL Certificates

Certificates are generated by scripts and referenced as Kubernetes Secrets.

### 4.1 Indexer Cluster Certificates

Generated by: `wazuh/certs/indexer_cluster/generate_certs.sh`

| Certificate | CN (Common Name) | Subject | Used By |
|-------------|-------------------|---------|---------|
| Root CA | *(self-signed)* | Root CA for the indexer cluster | All components as trust anchor |
| Admin cert | `admin` | `CN=admin,O=Company,L=California,C=US` | Indexer security plugin admin operations |
| Node cert | `indexer` | `CN=indexer,O=Company,L=California,C=US` | Indexer node-to-node (transport) and HTTPS |
| Dashboard cert | `dashboard` | `CN=dashboard,O=Company,L=California,C=US` | Dashboard connecting to Indexer |
| Filebeat cert | `filebeat` | `CN=filebeat,O=Company,L=California,C=US` | Filebeat shipping logs to Indexer |

Stored in Kubernetes Secret: `indexer-certs` (via `kustomization.yml` secretGenerator)

### 4.2 Dashboard HTTPS Certificates

Generated by: `wazuh/certs/dashboard_http/generate_certs.sh`

| Certificate | Purpose | Used By |
|-------------|---------|---------|
| `cert.pem` | Dashboard HTTPS server certificate | Dashboard pod serves UI over HTTPS (port 5601) |
| `key.pem` | Dashboard HTTPS private key | Dashboard pod |

Stored in Kubernetes Secret: `dashboard-certs` (via `kustomization.yml` secretGenerator)

---

## 5. Component-to-Credential Mapping (Quick Reference)

### Which credentials does each component need?

#### Wazuh Dashboard
| Credential | Secret Name | Purpose |
|------------|-------------|---------|
| `admin` / `KibanaS3rv3r@2026!` | `indexer-cred` | Query the Indexer |
| `kibanaserver` / `KibanaS3rv3r@2026!` | `dashboard-cred` | Dashboard internal operations on Indexer |
| `wazuh-wui` / `KibanaS3rv3r@2026!` | `wazuh-api-cred` | Call Wazuh Manager REST API |
| Dashboard TLS cert/key | `dashboard-certs` | Serve HTTPS |
| Indexer Root CA + dashboard cert | `indexer-certs` | mTLS to Indexer |

#### Wazuh Manager Master
| Credential | Secret Name | Purpose |
|------------|-------------|---------|
| `admin` / `KibanaS3rv3r@2026!` | `indexer-cred` | Filebeat ships logs to Indexer |
| `wazuh-wui` / `KibanaS3rv3r@2026!` | `wazuh-api-cred` | Configure API user |
| `KibanaS3rv3r@2026!` | `wazuh-cluster-key` | Cluster encryption (master-worker communication) |
| `KibanaS3rv3r@2026!` | `wazuh-authd-pass` | Agent registration password |
| Filebeat cert/key + Root CA | `indexer-certs` | mTLS from Filebeat to Indexer |

#### Wazuh Manager Worker
| Credential | Secret Name | Purpose |
|------------|-------------|---------|
| `admin` / `KibanaS3rv3r@2026!` | `indexer-cred` | Filebeat ships logs to Indexer |
| `KibanaS3rv3r@2026!` | `wazuh-cluster-key` | Cluster encryption (master-worker communication) |
| Filebeat cert/key + Root CA | `indexer-certs` | mTLS from Filebeat to Indexer |

#### Wazuh Indexer
| Credential | Source | Purpose |
|------------|--------|---------|
| Internal users (admin, kibanaserver, etc.) | `internal_users.yml` | Authenticates all incoming API requests |
| Node TLS cert/key + Root CA | `indexer-certs` | Transport and HTTPS encryption |
| Compliance salt | `opensearch.yml` | Field masking |
| SQL master key | `opensearch.yml` | Datasource encryption |

#### Wazuh Agents (External)
| Credential | Source | Purpose |
|------------|--------|---------|
| Authd registration password | Must match `wazuh-authd-pass` secret | Auto-registration with manager via port 1515 |

---

## 6. Security Observations

1. **All five Kubernetes Secrets use the same password** (`KibanaS3rv3r@2026!`). In production, each should have a unique, strong password.
2. **The cluster key reuses the same password** instead of a dedicated 32-character hex key. The commented-out original (`123a45bc67def891gh23i45jk67l8mn9`) is a better format.
3. **Encryption keys are hardcoded** in `opensearch.yml` (compliance salt and SQL master key). Consider managing these as Kubernetes Secrets.
4. **Four demo internal users** (`kibanaro`, `logstash`, `readall`, `snapshotrestore`) are defined but unused. Consider removing them to reduce attack surface.
5. **Bcrypt hashes in `internal_users.yml` must stay in sync** with plaintext passwords in Kubernetes Secrets. A password change requires updating both locations.
6. **Certificate subjects** use placeholder values (`O=Company,L=California,C=US`). Update these for production.
