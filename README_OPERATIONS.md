# Global Agencies — Godown Management System
## Operations, Go-Live & Scanner Handbook

---

### 1. System Overview & Architecture

The Godown Management System tracks all inward and outward appliance serial numbers for **Global Agencies** (TVs, Refrigerators, Washing Machines, Air Conditioners, etc.).

| Component | Technology | Default URL / Location |
| :--- | :--- | :--- |
| **FastAPI Backend** | Python 3.11, PostgreSQL 17, SQLAlchemy, Argon2 | `http://127.0.0.1:8000/api/v1` |
| **Web Dashboard** | React 19, TypeScript, Tailwind CSS v4 | `http://127.0.0.1:8000/` |
| **Mobile Scanner App** | Flutter 3.47, Dart 3.13, Camera MLKit | `A:\GA STOCK\ga_scanner.apk` |
| **Database** | PostgreSQL 17 (`godown_db`) | `localhost:5432` |

---

### 2. Starting the Server

#### Method A: One-Click Desktop Launcher
Simply double-click the launcher script in the root directory:
```
scripts\start_godown_server.bat
```
This automatically:
1. Starts the backend API on port `8000`.
2. Serves the pre-compiled Web Dashboard.
3. Opens `http://127.0.0.1:8000` in your default browser.

#### Method B: Persistent Windows Background Service
To run the server continuously in the background whenever Windows starts up (without keeping a terminal window open):
1. Open PowerShell as **Administrator**.
2. Run:
```powershell
powershell -ExecutionPolicy Bypass -File "A:\GA STOCK\scripts\install_windows_service.ps1"
```

---

### 3. Default Login Credentials

- **URL:** [http://127.0.0.1:8000/login](http://127.0.0.1:8000/login)
- **Administrator Username:** `admin`
- **Administrator Password:** `Admin@12345`

> **Security Note:** You can add additional staff accounts or update passwords under the **User Accounts & Staff** tab (`/users`).

---

### 4. Android Scanner App Installation & Hardware Approval

#### Step 1: Install APK on Mobile Scanner Phones
1. Locate the built APK file:
   ```
   A:\GA STOCK\ga_scanner.apk
   ```
2. Transfer `ga_scanner.apk` to warehouse Android phones via USB cable, WhatsApp, or Google Drive.
3. Tap the file on the phone and tap **Install** (enable *"Install unknown apps"* if prompted).

#### Step 2: Approve the Phone on Admin Dashboard
1. Open the **GA Scanner** app on the phone.
2. The app will register its unique hardware identifier (UID) with the server and display:
   ```
   Device Authorization Required: Awaiting Administrator Approval
   ```
3. On your desktop browser, log in to the Web Dashboard and click **Mobile Devices** (`/devices`).
4. You will see an amber banner notifying you of the pending scanner device.
5. Click **Approve Device**, give it a recognizable label (e.g., *"Inward Bay Phone 1 - Anzal"*), and confirm.
6. On the phone, tap **Check Approval Status**. The phone immediately unlocks and presents the staff login screen.

---

### 5. Warehouse Floor Scanning Workflows

#### A. Inward Receiving Flow (Factory Shipments)
1. Open app and select **Inward Stock Scan**.
2. **Step 1: Select Model First** — Select the appliance being received from the list.
3. **Step 2: Continuous Scan** — Aim phone camera at box barcodes or QR codes.
   - The scanner validates each barcode in real-time.
   - If a barcode has already been scanned or clashes with another model, the phone vibrates with an alert.
4. Tap **Save Inward Batch (+X Stock)** to register items onto godown shelves.

#### B. Outward Dispatch Flow (Dealer Shipments)
1. Select **Outward Dispatch Scan**.
2. **Step 1: Select Destination Shop** (e.g., *"Modern Electronics, Calicut"*).
3. **Step 2: Select Appliance Model** and optionally enter vehicle or delivery reference (e.g., *"DEL-4412"*).
4. **Step 3: Continuous Scan** with live 4-case feedback:
   - **Case 1 (Matched):** Available tracked unit found -> Crisp green indicator & soft beep.
   - **Case 2 (Recorded Only):** Pre-go-live stock without inward record -> Calm neutral grey badge. **Never blocked from dispatch**.
   - **Case 3 (Status Warning):** Serial already marked dispatched or damaged -> Amber warning alert with option to dispatch and flag for admin review.
   - **Case 4 (Model Mismatch):** Serial belongs to a different model -> Red alert dialog.
5. Tap **Submit Dispatch** to record the transaction.

#### C. Air Conditioner Dual-Serial Handling
- Split Air Conditioners have two separate serial numbers: **Indoor Unit (IDU)** and **Outdoor Unit (ODU)**.
- Both serials are scanned as **two independent serial numbers under the same AC model**. No pairing table is needed.

#### D. Returns of Unmatched Pre-Go-Live Stock
- If a shop returns an appliance that was previously dispatched as *"Recorded only"* (pre-go-live stock), recording the return in the system **automatically creates a tracked serial record** for that unit from that moment forward.

#### E. Offline Queue (Dead-Zone Protection)
- If Wi-Fi cuts out in warehouse basements, scans are preserved safely in local phone memory.
- When connection returns, tap the **Offline Sync Queue** cloud icon on the home screen to upload all batches in one tap.

---

### 6. Automated Nightly Backups & Disaster Recovery

#### Automated Daily Backup Script
A backup script is pre-configured at:
```
A:\GA STOCK\scripts\backup_db.ps1
```
It creates consistent SQL dumps with automatic 30-day rotation inside `A:\GA STOCK\backups\`.

#### To schedule automatic nightly execution at 2:00 AM:
1. Open PowerShell as Administrator.
2. Run:
```powershell
$Action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-ExecutionPolicy Bypass -File `"A:\GA STOCK\scripts\backup_db.ps1`""
$Trigger = New-ScheduledTaskTrigger -Daily -At 2am
Register-ScheduledTask -TaskName "GlobalAgenciesGodownNightlyBackup" -Action $Action -Trigger $Trigger -User "SYSTEM" -RunLevel Highest
```

#### Restoring a Backup
To restore any previous database backup:
```powershell
powershell -ExecutionPolicy Bypass -File "A:\GA STOCK\scripts\restore_db.ps1" -BackupFile "A:\GA STOCK\backups\godown_db_YYYYMMDD_HHMMSS.sql"
```
The script will verify the archive and prompt you to type `RESTORE` before executing.

---

### 7. Live Health Watchdog

A self-healing health watchdog is located at:
```
A:\GA STOCK\scripts\health_watchdog.ps1
```
It pings `http://127.0.0.1:8000/health`. If the server ever encounters a network or database interruption, it automatically restarts the service and writes recovery events to `backend\logs\watchdog.log`.
