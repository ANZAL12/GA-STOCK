# Global Agencies — Godown Management System (GA-STOCK)

> **Enterprise-grade, real-time Godown Inventory & Serial Number Tracking System** engineered for **Global Agencies**.  
> Tracks consumer electronics and appliances (LED TVs, Refrigerators, Washing Machines, Split Air Conditioners, etc.) across their complete lifecycle: factory inward receiving, godown shelf storage, dealer shop dispatch, customer/dealer returns, and damaged unit triage.

---

## 📑 Table of Contents

1. [System Overview & Architecture](#-system-overview--architecture)
2. [Technology Stack](#-technology-stack)
3. [Key Highlights & Business Logic](#-key-highlights--business-logic)
   - [Zero-Friction Go-Live Architecture](#1-zero-friction-go-live-architecture)
   - [The 4-Case Outward Dispatch Rule](#2-the-4-case-outward-dispatch-rule-spec-5)
   - [Split Air Conditioner Dual-Serial System](#3-split-air-conditioner-dual-serial-system)
   - [Retroactive Tracking on Dealer Returns](#4-retroactive-tracking-on-dealer-returns)
   - [Hardware Device Whitelisting & Mobile Security](#5-hardware-device-whitelisting--mobile-security)
   - [Offline Queue & Dead-Zone Protection](#6-offline-queue--dead-zone-protection)
   - [Tally Prime Style Delivery Challan Generator](#7-tally-prime-style-delivery-challan-generator)
4. [System Architecture & Data Flow](#-system-architecture--data-flow)
5. [Database Schema & Entity Models](#-database-schema--entity-models)
6. [API Endpoints Reference](#-api-endpoints-reference)
7. [Frontend Web Dashboard](#-frontend-web-dashboard)
8. [Mobile Scanner App (Flutter)](#-mobile-scanner-app-flutter)
9. [Operations, Deployment & Automation](#-operations-deployment--automation)
10. [Local Development & Setup Guide](#-local-development--setup-guide)

---

## 🌟 System Overview & Architecture

Global Agencies operates a central godown distribution hub delivering high-value electronics and appliances to dozens of retail shops across the region. 

Traditional inventory software tracks bulk counts, but fails to prevent counterfeit returns, misplaced stock, or dispatch errors. GA-STOCK introduces **serialized physical tracking** paired with an **unmatched-dispatch grace model**:

```
 ┌─────────────────────────────────────────────────────────────┐
 │                      CENTRAL WAREHOUSE                      │
 └──────────────────────────────┬──────────────────────────────┘
                                │
          ┌─────────────────────┴─────────────────────┐
          ▼                                           ▼
┌──────────────────┐                       ┌──────────────────┐
│  Mobile Scanners │                       │  Admin Dashboard │
│  (Flutter App)   │                       │  (React 19 Vite) │
│  - Inward Bay    │                       │  - Live Monitor  │
│  - Outward Bay   │                       │  - Master Data   │
│  - Barcode / QR  │                       │  - Bills & P&L   │
│  - Offline Cache │                       │  - Whitelist     │
└─────────┬────────┘                       └─────────┬────────┘
          │                                          │
          └─────────────────────┬────────────────────┘
                                │ HTTP / REST + WebSockets
                                ▼
         ┌──────────────────────────────────────────────┐
         │       FastAPI Application Server (ASGI)      │
         │  - Async SQLAlchemy 2.0 Engine               │
         │  - WebSocket Real-Time Event Hub             │
         │  - Tally-Prime Delivery Challan PDF Engine   │
         │  - Excel (.xlsx) / CSV Exporter              │
         │  - Argon2 Security & Device Whitelisting     │
         └──────────────────────┬───────────────────────┘
                                │ AsyncPG Pool
                                ▼
         ┌──────────────────────────────────────────────┐
         │       PostgreSQL 17 Relational Database      │
         │  - ACID-compliant Batch Transactions         │
         │  - Globally Unique Serial Indices            │
         │  - Immutable Chronological Lifecycle Audits  │
         └──────────────────────────────────────────────┘
```

---

## 🛠 Technology Stack

### Backend API
- **Framework**: [FastAPI](https://fastapi.tiangolo.com/) (Python 3.11+)
- **Server**: [Uvicorn](https://www.uvicorn.org/) (ASGI) with Starlette SPA routing fallback
- **Database ORM**: [SQLAlchemy 2.0](https://www.sqlalchemy.org/) (Full Async API with AsyncSession)
- **Database Driver**: [asyncpg](https://github.com/MagicStack/asyncpg) (High-performance PostgreSQL async client)
- **Database Engine**: PostgreSQL 17
- **Migrations**: [Alembic](https://alembic.sqlalchemy.org/)
- **Security & Hashing**: [Argon2](https://github.com/hynek/argon2-cffi) via Passlib, JWT tokens via Python-Jose
- **Real-Time Layer**: WebSockets (`/ws` & `/api/v1/ws`) with topic-based connection pooling
- **Document & Data Generation**: [openpyxl](https://openpyxl.readthedocs.io/) (Excel spreadsheets), [ReportLab](https://www.reportlab.com/) (Server-side PDF streaming)

### Frontend Web Dashboard
- **Framework**: [React 19](https://react.dev/) + [TypeScript](https://www.typescriptlang.org/)
- **Bundler & Tooling**: [Vite](https://vitejs.dev/) + Oxlint
- **Styling**: [Tailwind CSS v4](https://tailwindcss.com/)
- **Icons**: [Lucide React](https://lucide.dev/)
- **Routing**: [React Router DOM v7](https://reactrouter.com/) (Protected Role-based routes: Staff vs Admin)
- **Client-Side PDF Engine**: [jsPDF](https://github.com/parallax/jsPDF) + [jspdf-autotable](https://github.com/simonbengtsson/jsPDF-AutoTable)
- **Spreadsheets**: [SheetJS (xlsx)](https://sheetjs.com/)

### Mobile Scanner Application
- **Framework**: [Flutter 3.47](https://flutter.dev/) (Dart 3.13+)
- **Scanning Core**: `mobile_scanner` (Google ML Kit camera barcode & QR reader)
- **Hardware PDA Scanner**: BroadcastReceiver integration for enterprise Android barcode guns (Zebra, Honeywell, Newland, Urovo)
- **Audio & Haptic Feedback**: `audioplayers` with dedicated sound effects for success, mismatch, and duplicate alerts
- **Offline Storage**: Local persistent caching via `shared_preferences` and transactional sync
- **Thermal & A4 Printing**: Direct Bluetooth / Wi-Fi printing via `pdf` and `printing` packages

---

## 💡 Key Highlights & Business Logic

### 1. Zero-Friction Go-Live Architecture
When switching an active warehouse to serial-number tracking, taking a multi-day shutdown to scan 10,000+ existing boxes is impossible. GA-STOCK solves this:
- **Opening Stock Support**: Products are created with an initial `opening_stock_qty` representing legacy, un-scanned stock on shelves.
- **Graceful Dispatches**: When an older, untracked box is dispatched to a dealer, staff simply scan its barcode. The system records it under **Case 2 (Recorded Only)**, decrements the product count, and **never stops the dispatch truck**.

### 2. The 4-Case Outward Dispatch Rule (Spec §5)
During outward scanning, every barcode is checked against the database in real-time and mapped to one of four states:

| Case | State | Visual Badge | Audio Cue | System Behavior |
| :--- | :--- | :--- | :--- | :--- |
| **Case 1** | **Matched** | 🟢 Green Badge | Crisp soft chime | Serial exists in DB as `available` for this model. Marked as `dispatched` to destination shop; stock count decremented. |
| **Case 2** | **Unmatched (Old Stock)** | ⚪ Calm Grey Badge | Low neutral tone | Serial does not exist in DB (pre-go-live inventory). Recorded as outward line for full traceability; stock count decremented (floored at 0). Dispatches are **never blocked**. |
| **Case 3** | **Status Warning** | 🟡 Amber Badge | Warning beep | Serial exists in DB, but its status is `dispatched`, `damaged`, `under_repair`, etc. Requires staff confirmation; flagged for admin review. |
| **Case 4** | **Model Mismatch** | 🔴 Red Badge | Error buzz | Serial exists in DB, but belongs to a completely different appliance model. Prevents loading the wrong product onto the delivery vehicle. |

### 3. Split Air Conditioner Dual-Serial System
- Split Air Conditioners comprise two separate physical boxes: the **Indoor Unit (IDU)** and the **Outdoor Unit (ODU)**.
- Instead of forcing warehouse workers to find matching pairs in dimly lit aisles, both units are scanned as **independent serial numbers under the same product model** with a `unit_type` flag (`indoor` vs `outdoor`).
- Both serials are printed clearly on the delivery challan for warranty registration.

### 4. Retroactive Tracking on Dealer Returns
- If a shop returns an appliance that was originally dispatched as **Case 2 (Unmatched Pre-Go-Live Stock)**, recording the return in the system **automatically provisions a new tracked serial record** in the database.
- It retroactively links to the outward line. From that moment forward, that unit is **100% serialized and tracked**.

### 5. Hardware Device Whitelisting & Mobile Security
- Any Android phone or scanner gun that installs `ga_scanner.apk` generates a hardware device fingerprint (UID).
- On initial launch, the app displays:  
  `"Device Authorization Required: Awaiting Administrator Approval"`
- The Admin approves or rejects the device from the **Mobile Devices** tab (`/devices`) on the Web Dashboard. Unapproved devices cannot query stock or submit batches.

### 6. Offline Queue & Dead-Zone Protection
- In warehouse basements or tin-roofed godowns where Wi-Fi drops, scans are not lost.
- Scans are queued in phone storage. Once Wi-Fi or cellular service resumes, staff tap **Offline Sync Queue** to upload all pending batches in a single atomic payload.

### 7. Tally Prime Style Delivery Challan Generator
- Built-in PDF generator creates classic, high-contrast, black-and-white Delivery Challans matching the familiar layout of **Tally Prime** invoices:
  - Header box split into Consignor / Dispatcher and Consignee / Destination Dealer.
  - Full GSTIN, address, and vehicle/transport reference details.
  - Comprehensive item grid with individual serial numbers cleanly wrapped.
  - Dual-column totals, declarations, and authorized signatory blocks.
  - Zero solid color fills for fast, ink-saving monochrome laser or thermal printing.

---

## 🏛 System Architecture & Data Flow

### Inward Flow (Receiving Factory Shipments)
```
[Factory Truck Arrives]
       │
       ▼
Staff selects Model on GA Scanner App (e.g. "LG 43-inch 4K Smart TV")
       │
       ▼
Continuous Camera / Laser Scan of box barcodes
       │ ├── Validates against duplicate scans in current batch
       │ └── Validates against already received serial numbers in DB
       ▼
Review Batch Summary -> Tap "Submit Inward Batch (+X Stock)"
       │
       ▼
FastAPI Backend (POST /api/v1/inward/multi-batch):
  ├── Runs inside single atomic DB transaction
  ├── Inserts serials into `serial_numbers` (status: 'available')
  ├── Records `inward_batches` & `inward_lines`
  ├── Writes immutable entries to `serial_history` (action: 'inward_recorded')
  ├── Increments `products.current_stock_qty`
  └── Sets `products.has_had_inward = True`
```

### Outward Flow (Dispatching to Dealer Shops)
```
[Delivery Order Picklist]
       │
       ▼
Staff selects Destination Shop + Appliance Model
       │
       ▼
Continuous Barcode Scan with 4-Case Live Evaluation
       │ ├── Matched (Case 1) ───► Green indicator
       │ ├── Unmatched (Case 2) ─► Neutral Grey indicator (Allowed!)
       │ ├── Wrong Status (Case 3) ──► Amber warning alert
       │ └── Wrong Model (Case 4) ──► Red mismatch rejection
       ▼
Review Outward Summary (Matched vs Recorded Only Counts)
       │
       ▼
FastAPI Backend (POST /api/v1/outward/multi-batch):
  ├── Updates matched serials to status: 'dispatched'
  ├── Records batch in `outward_batches` (with Bill No / Delivery Ref)
  ├── Inserts all lines into `outward_lines` (storing raw `serial_text`)
  ├── Decrements `products.current_stock_qty` (floored at 0)
  ├── Appends to `serial_history`
  └── Emits WebSocket event to live Web Dashboard
```

---

## 🗄 Database Schema & Entity Models

```
┌─────────────────┐       ┌─────────────────┐       ┌─────────────────┐
│   categories    │       │     users       │       │     devices     │
├─────────────────┤       ├─────────────────┤       ├─────────────────┤
│ id (UUID, PK)   │       │ id (UUID, PK)   │       │ id (UUID, PK)   │
│ name            │       │ username        │       │ device_id (UID) │
│ description     │       │ hashed_password │       │ label           │
│ is_active       │       │ role (Enum)     │       │ is_active       │
└────────┬────────┘       │ is_active       │       └────────┬────────┘
         │ 1              └────────┬────────┘                │
         │                         │                         │
         │ N                       │                         │
┌────────┴────────┐                │                         │
│    products     │                │                         │
├─────────────────┤                │                         │
│ id (UUID, PK)   │                │                         │
│ category_id(FK) ◄─┐              │                         │
│ name            │ │              │                         │
│ brand           │ │              │                         │
│ model           │ │              │                         │
│ size_capacity   │ │              │                         │
│ opening_stock   │ │              │                         │
│ current_stock   │ │              │                         │
│ has_had_inward  │ │              │                         │
└────────┬────────┘ │              │                         │
         │ 1        │              │                         │
         │          │              │                         │
         │ N        │              │                         │
┌────────┴────────┐ │              │                         │
│ serial_numbers  │ │              │                         │
├─────────────────┤ │              │                         │
│ id (UUID, PK)   │ │              │                         │
│ serial_number   │ │              │                         │
│ product_id (FK)─┼─┘              │                         │
│ status (Enum)   │                │                         │
│ last_shop_id(FK)┼─┐              │                         │
│ unit_type       │ │              │                         │
└────────┬────────┘ │              │                         │
         │          │              │                         │
         │          │              │                         │
┌────────┴────────┐ │              │                         │
│ serial_history  │ │              │                         │
├─────────────────┤ │              │                         │
│ id (UUID, PK)   │ │              │                         │
│ serial_num_id(FK│ │              │                         │
│ serial_text     │ │              │                         │
│ action (Enum)   │ │              │                         │
│ from_status     │ │              │                         │
│ to_status       │ │              │                         │
│ shop_id (FK)────┼─┤              │                         │
│ user_id (FK)────┼─┼──────────────┘                         │
│ device_id (FK)──┼─┼────────────────────────────────────────┘
└─────────────────┘ │
                    │
┌─────────────────┐ │     ┌───────────────────┐     ┌───────────────────┐
│     shops       │ │     │  inward_batches   │     │  outward_batches  │
├─────────────────┤ │     ├───────────────────┤     ├───────────────────┤
│ id (UUID, PK)   │ │     │ id (UUID, PK)     │     │ id (UUID, PK)     │
│ name            │ └─────► product_id (FK)   │     │ product_id (FK)   │
│ code            │       │ invoice_reference │     │ shop_id (FK)      │
│ city            │       │ quantity          │     │ bill_number       │
│ phone           │       │ transaction_date  │     │ delivery_ref      │
│ gstin           │       │ user_id (FK)      │     │ quantity          │
└─────────────────┘       └─────────┬─────────┘     │ matched_count     │
                                    │               │ unmatched_count   │
                                    │ 1             │ flagged_count     │
                                    │               └─────────┬─────────┘
                                    │ N                       │ 1
                          ┌─────────┴─────────┐               │
                          │   inward_lines    │               │ N
                          ├───────────────────┤     ┌─────────┴─────────┐
                          │ id (UUID, PK)     │     │   outward_lines   │
                          │ batch_id (FK)     │     ├───────────────────┤
                          │ serial_num_id(FK) │     │ id (UUID, PK)     │
                          └───────────────────┘     │ batch_id (FK)     │
                                                    │ serial_num_id(FK) │
                                                    │ serial_text       │
                                                    │ is_matched        │
                                                    │ is_flagged        │
                                                    │ shop_id (FK)      │
                                                    └───────────────────┘
```

---

## 📡 API Endpoints Reference

Base URL: `http://<server-ip>:8000/api/v1`

### 1. Authentication & Users (`/auth`, `/users`)
- `POST /auth/login` — Authenticates user via username and password; returns JWT token and role.
- `GET /auth/me` — Fetches current authenticated user profile.
- `GET /users` — Admin only: Lists all user accounts.
- `POST /users` — Admin only: Creates a new staff or admin user.
- `PATCH /users/{id}` — Admin only: Updates password, active status, or user roles.

### 2. Device Authorization (`/devices`)
- `POST /devices/register` — Mobile app registers its hardware UID.
- `GET /devices/status` — Mobile checks if its UID has been approved by admin.
- `GET /devices` — Admin: Lists all registered devices with active status.
- `PATCH /devices/{id}/approve` — Admin: Approves pending scanner phone and assigns a label.
- `PATCH /devices/{id}/revoke` — Admin: Revokes device access immediately.

### 3. Product Catalog & Categories (`/products`, `/categories`)
- `GET /categories` — Lists all product categories (LED TV, Refrigerator, etc.).
- `POST /categories` — Creates a new category.
- `GET /products` — Lists all products with real-time stock counters (`opening_stock_qty`, `current_stock_qty`, `has_had_inward`).
- `POST /products` — Creates a new appliance model with initial opening stock.
- `GET /products/{id}` — Fetches details and movement summary of a specific product.
- `PATCH /products/{id}` — Updates product details, SKU, size/capacity, or active flag.

### 4. Serial Numbers & Lifecycle (`/serials`)
- `GET /serials` — Global serial search with filtering by product, status, shop, and query text.
- `GET /serials/{serial_number}` — Complete serial card showing lifecycle history, destination shop, and unit type.
- `PATCH /serials/{serial_number}/status` — Manually changes serial status (`damaged`, `under_repair`, `available`, `lost`).

### 5. Inward Receiving (`/inward`)
- `POST /inward/validate-serial` — Live scanner pre-check verifying serial eligibility before submitting batch.
- `POST /inward/batch` — Submits a single-model inward batch.
- `POST /inward/multi-batch` — Submits a multi-product inward shipment in a single atomic transaction.
- `GET /inward/batches` — Lists past inward shipments with filters.

### 6. Outward Dispatch & Bills (`/outward`)
- `POST /outward/check-serial` — Evaluates barcode against the 4-case logic in real-time.
- `POST /outward/multi-batch` — Submits outward dispatch with bill number, shop ID, and serials.
- `GET /outward/bills` — Aggregated delivery bills list grouped by Bill Number / Delivery Ref.
- `GET /outward/bills/{bill_number}` — Full bill detail with all appliance models and scanned serials.

### 7. Returns Processing (`/returns`)
- `POST /returns` — Records returned appliance from a shop. Automatically converts unmatched pre-go-live stock into tracked serial numbers.
- `PATCH /returns/{id}/inspect` — Records physical inspection outcome (`available` to return to shelf, or `damaged`).
- `GET /returns` — Lists past dealer returns and pending inspections.

### 8. Reports & Analytics (`/reports`)
- `GET /reports/overview` — Dashboard header counters, today's movements, and attention pills.
- `GET /reports/stock-by-model` — Stock breakdown per model with CSV / XLSX / PDF export.
- `GET /reports/today-timeline` — Chronological vertical event feed of today's godown activities.
- `GET /reports/stock-out` — Complete outward dispatch ledger with 'Matched' vs 'Recorded Only' status.
- `GET /reports/unmatched-outward` — Dedicated audit report of all pre-go-live stock dispatched.
- `GET /reports/damaged` — Triage report of damaged and under-repair units.

---

## 💻 Frontend Web Dashboard

The web dashboard is built for warehouse managers and administrators to oversee stock levels, print bills, and approve hardware:

- **Overview (`/`)**:
  - Live inventory metrics: tracked items on shelves, total inward since go-live, today's dispatches.
  - "Needs Attention" pills: out-of-stock models, flagged dispatches, damaged units, pending device approvals.
  - Live vertical timeline showing every barcode scan happening on the warehouse floor.
- **Stock Management (`/stock`)**:
  - Comprehensive catalog of appliances with category filters and real-time stock badges.
  - Quick-action modal to add new appliance models or edit opening stock counts.
- **Serial Numbers Tracker (`/serials`)**:
  - Instant barcode query bar.
  - Visual timeline rendering full lifecycle: `Inward Received -> Dispatched to Dealer -> Returned -> Inspected`.
- **Dealer Shops (`/shops`)**:
  - Directory of all destination retail shops with contact numbers, addresses, and GSTIN.
  - Complete dispatch history ledger per dealer.
- **Bills & Delivery Challans (`/bills`)**:
  - Searchable list of all dispatch vouchers and invoice numbers.
  - One-click **Print Delivery Challan** generating an ink-saving Tally-Prime styled PDF.
- **Reports & Audits (`/reports`)**:
  - Detailed stock-out reports separating matched vs un-matched dispatches.
  - 1-click download to **Excel (.xlsx)** or **PDF**.
- **Admin Management (`/users`, `/devices`)**:
  - Staff user accounts creation and password management.
  - Real-time mobile device approval center.

---

## 📱 Mobile Scanner App (Flutter)

The mobile scanner app (`A:\GA STOCK\ga_scanner.apk`) turns any Android smartphone or dedicated rugged warehouse PDA into an enterprise-grade barcode scanner.

### App Screens & Features
1. **Hardware Whitelist Gate (`device_approval_screen.dart`)**:
   - Locks unauthorized phones with a clear approval status screen.
   - Pings server automatically or lets user tap "Check Approval Status".
2. **Warehouse Hub (`home_screen.dart`)**:
   - Large touch targets for warehouse floor workers wearing gloves.
   - One-tap navigation to Inward Receiving, Outward Dispatch, Serial Lookup, and Offline Sync.
3. **Inward Receiving (`inward_screen.dart`)**:
   - Continuous camera or laser scanning with audible chime per box.
   - Instant duplicate detection: vibrating error alert if a barcode is scanned twice.
4. **Outward Dispatch (`outward_screen.dart`)**:
   - 4-case color badges rendered directly under the camera viewfinder.
   - Allows dispatches to proceed smoothly even when scanning older, untracked stock.
5. **Direct Bill & Challan Printing (`print_bill_screen.dart`)**:
   - Allows warehouse dispatches to print thermal delivery receipts directly from the phone via Bluetooth or Wi-Fi ESC/POS printers.
6. **Offline Queue Sync (`offline_queue_screen.dart`)**:
   - Displays all offline scanned batches saved locally.
   - 1-tap bulk synchronization with the central server when back in Wi-Fi range.

---

## ⚙️ Operations, Deployment & Automation

### Automated Directory Scripts
All production scripts are located in the root and `scripts/` directory:

| Script | Purpose |
| :--- | :--- |
| `START_SERVER.bat` | One-click desktop launcher to run the server and launch the Web Dashboard in browser. |
| `SETUP_SERVER.bat` | Automated setup script: verifies Python & Node, builds frontend, installs dependencies, verifies `.env`. |
| `UPDATE_PROJECT.bat` | Pulls latest Git changes, re-installs Python packages, and rebuilds frontend distribution. |
| `scripts\install_windows_service.ps1` | Registers the FastAPI server as a persistent Windows background service (survives system reboots). |
| `scripts\backup_db.ps1` | Creates timestamped PostgreSQL dumps in `backups\` with automatic 30-day retention. |
| `scripts\restore_db.ps1` | Safe database restoration tool with verification prompts. |
| `scripts\health_watchdog.ps1` | Self-healing monitor that checks `http://localhost:8000/health` and auto-restarts the service if unresponsive. |

### Nightly Database Backup Automation
To schedule automatic nightly database backups at 2:00 AM:
```powershell
# Open PowerShell as Administrator:
$Action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-ExecutionPolicy Bypass -File `"A:\GA STOCK\scripts\backup_db.ps1`""
$Trigger = New-ScheduledTaskTrigger -Daily -At 2am
Register-ScheduledTask -TaskName "GlobalAgenciesGodownNightlyBackup" -Action $Action -Trigger $Trigger -User "SYSTEM" -RunLevel Highest
```

---

## 🚀 Local Development & Setup Guide

### 1. Prerequisites
- **Python**: 3.11 or higher
- **Node.js**: 20 LTS or higher (with npm)
- **PostgreSQL**: 16 or 17
- **Flutter SDK**: 3.47+ (only if compiling mobile app)

### 2. Initial Setup
Run the automated server setup script:
```cmd
A:\GA STOCK\SETUP_SERVER.bat
```
This automatically initializes the virtual environment (`backend\.venv`), installs Python packages, builds the React frontend, and creates `backend\.env`.

### 3. Database Configuration
Edit `backend\.env` to match your local PostgreSQL credentials:
```env
DATABASE_URL=postgresql+asyncpg://godown_user:password@localhost:5432/godown_db
SECRET_KEY=generate_a_64_character_random_secret_key_here
ALGORITHM=HS256
ACCESS_TOKEN_EXPIRE_MINUTES=60
REFRESH_TOKEN_EXPIRE_DAYS=30
DEBUG=false
```

### 4. Apply Database Migrations
```bash
cd backend
.venv\Scripts\activate
alembic upgrade head
```

### 5. Running the Application
#### Development Mode (Hot Reload):
- **Backend API**:
  ```bash
  cd backend
  .venv\Scripts\activate
  uvicorn app.main:app --reload --port 8000
  ```
- **Frontend Web UI**:
  ```bash
  cd frontend
  npm run dev
  ```
- **Mobile Scanner**:
  ```bash
  cd mobile
  flutter run
  ```

#### Production Mode:
Simply double-click `START_SERVER.bat` in the project root. The FastAPI server serves both the JSON API at `/api/v1` and the compiled React single-page app at `/`.

---

## 🔒 Default Credentials

- **Web Dashboard**: `http://127.0.0.1:8000`
- **API Documentation**: `http://127.0.0.1:8000/api/docs`
- **Default Administrator**:
  - **Username**: `admin`
  - **Password**: `Admin@12345`

---

*Developed for Global Agencies — Central Godown Management & Distribution Operations.*
