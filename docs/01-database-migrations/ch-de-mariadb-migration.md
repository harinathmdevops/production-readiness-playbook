[ Switzerland Production ]                       [ Germany Non-Production ]
+---------------------------+                    +---------------------------+
|  On-Prem or Azure Cloud   |   Secure Network   |      Azure Linux VM       |
|    MariaDB (800 GB)       |===================>|    MariaDB Target DB      |
|  Contains Raw PII       |  (VPN / Peering)   |  Data Masked in Flight  |
+---------------------------+                    +---------------------------+

### Key Prerequisites
- **Target Storage:** The German Azure VM must have a fast-attached data disk (SSD preferred) with **at least 1.5 TB of storage** to accommodate both the raw compressed backup files and the uncompressed ingestion state.
- **Operating System:** Linux-based distributions (Ubuntu/RHEL) are assumed for optimal terminal performance.

---

## 📋 Architectural Migration Roadmap

### Phase 1: Secure Networking & Firewall Lockdown
Before extracting any files, establish an isolated network corridor between the two geographical regions.

1. **Network Bridging:**
   - *If Swiss source is On-Premises:* Implement a Site-to-Site VPN or **[Azure ExpressRoute](https://microsoft.com)** into the target Virtual Network (VNet) in Germany.
   - *If Swiss source is Azure Cloud:* Implement **Cross-Region VNet Peering** between the Swiss and German VNets.
2. **Network Security Group (NSG) Configuration:** Keep the database server closed to the public web. Open port `3306` on the German VM's firewall **only** to the specific internal or public IP address of the Swiss extraction machine.

### Phase 2: Target Database Optimization for Fast Ingestion
Standard database engine safety rules drastically slow down batch record insertion. Before importing the data, tune the German VM's MariaDB engine configurations (`my.cnf`) for raw throughput:

```ini
[mysqld]
# Allocate ~70% of total VM RAM to the buffer pool (e.g., for a 64GB VM, set to 45G)
innodb_buffer_pool_size = 45G
innodb_log_file_size = 2G
innodb_write_io_threads = 16

# HIGH ACCELERATION SETTINGS (Revert these post-migration)
innodb_flush_log_at_trx_commit = 0  # Bypasses disk flush on every transaction commit
unique_checks = 0                    # Disables unique key verification during bulk insert
foreign_key_checks = 0               # Disables foreign key constraint evaluation during copy
```

> ⚠️ **Warning:** Ensure that application servers pointing to the German non-prod instance are shut down during this process to prevent anyone from reading raw data before anonymization completes.

---

## 🚀 Execution Guide

### Step 1: Multi-Threaded Extraction (Switzerland)
Standard `mysqldump` is single-threaded and would take days to process 800 GB. Install and use **`mydumper`**, a multi-threaded alternative that splits tables into small, compressed chunk files.

1. **Install Mydumper:**
   ```bash
   # Ubuntu / Debian
   sudo apt-get install mydumper

   # RHEL / CentOS
   sudo dnf install mydumper
   ```

2. **Execute the Parallel Export:**
   ```bash
   mydumper --host=swiss-db-endpoint \
            --user=backup_user \
            --password=your_secure_password \
            --threads=8 \
            --build-empty-files \
            --less-locking \
            --compress \
            --outputdir=./swiss_dump
   ```
   *Note: The `--less-locking` flag reduces read-lock time on production tables.*

### Step 2: Secure Cross-Border Transfer
Stream the chunked data from Switzerland into the German Azure VM using `rsync` over SSH. `rsync` is strongly recommended over standard `scp` because it allows file transfer resumption if a network drop occurs over the 800 GB payload.

```bash
rsync -avz -e "ssh -i private_key.pem" ./swiss_dump/ azureuser@german-vm-ip:/mnt/data/german_landing/
```

### Step 3: Parallel Data Ingestion (Germany)
Once the files completely land in the `/mnt/data/german_landing/` directory on the German VM, use **`myloader`** to pull the chunks back into the target schema concurrently.

```bash
myloader --host=localhost \
         --user=root \
         --password=your_root_password \
         --threads=8 \
         --directory=/mnt/data/german_landing \
         --queries-per-transaction=50000
```

---

## 🛡️ Data Anonymization & FADP/GDPR Compliance

Because the data is landing in a non-production environment out of the original jurisdiction, you must scrub all Personally Identifiable Information (PII) immediately following data load. 

### Native Masking Script (`mask_pii.sql`)
Create a custom masking script on the German VM. This script replaces real consumer data with deterministic strings using row IDs to retain data usability without exposing PII.

```sql
-- Select your target non-prod database
USE non_prod_db;

-- 1. Scramble Personal Identification Records
UPDATE users 
SET first_name = CONCAT('User_', id), 
    last_name = 'Anonymous',
    phone_number = CONCAT('+4100000', id);

-- 2. Anonymize Email Structures
UPDATE users 
SET email = CONCAT('user_', id, '@nonprod.local');

-- 3. Clear Sensitive History / Payment Audit Tables completely
TRUNCATE TABLE payment_gateway_logs;
TRUNCATE TABLE security_audit_trails;

-- Refresh data dictionary indexes
ANALYZE TABLE users;
```

### Running the Anonymization
Execute the file via the terminal prompt right after the `myloader` step finishes:
```bash
mysql -u root -p < /path/to/mask_pii.sql
```

---

## 🏁 Post-Migration Checklist

To secure and normalize the target database for your development and QA engineering teams, revert the database parameters back to secure execution values.

1. **Re-enable Safety Constraints:** Update `my.cnf` to turn safety features back on:
   ```ini
   innodb_flush_log_at_trx_commit = 1
   unique_checks = 1
   foreign_key_checks = 1
   ```
2. **Apply Configurations:** Restart the MariaDB service daemon:
   ```bash
   sudo systemctl restart mariadb
   ```
3. **Data Integrity Audit:** Run row count cross-checks on top tables to ensure zero data packet losses during data processing.

---
*Disclaimer: Ensure your corporate data privacy officer clears the network schema architecture adjustments before staging massive records migrations.*
