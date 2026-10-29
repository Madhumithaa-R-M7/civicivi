# CivicConnect

**CivicConnect** is an enterprise-grade citizen grievance reporting and municipal infrastructure management platform. The system empowers citizens to capture real-time photographic proof with verified GPS coordinates to report civic issues such as potholes, garbage accumulation, water leakages, and broken streetlights, while giving municipal authorities automated classification, priority scoring, duplicate screening, and finite-state machine (FSM) complaint lifecycle tracking.

---

## Architecture & Technology Stack

- **Mobile Application:** Flutter & Dart (Cross-platform Android / iOS / Desktop)
- **Backend API Server:** Node.js with Express.js REST API
- **Database:** PostgreSQL (Managed via pgAdmin)
- **Security & Cryptography:** bcrypt password & OTP hashing, JWT session tracking in PostgreSQL, SHA-256 binary hashing, Perceptual Hashing (pHash) with 2D DCT-II
- **Email Gateway:** Resend API for password recovery OTP delivery
- **Mapping & Geocoding:** OpenStreetMap (`flutter_map` with `latlong2`) and `geolocator`

---

## Core Modules & Implemented Algorithms

### 1. Authentication & Enterprise Security
- **Bcrypt Password Hashing:** 10 salt rounds with constant-time comparison.
- **JWT Session Tracking:** Session tokens tracked and verified in the PostgreSQL `auth_sessions` table with SHA-256 token hashes and instant logout revocation.
- **Role-Based Access Control (RBAC):** Strict permissions across `user` (citizen), `staff`, `admin`, and `super_admin`.
- **API Rate Limiting:** Brute-force protection via `express-rate-limit` on all sensitive authentication and submission routes.
- **Email OTP Verification:** 6-digit cryptographic OTP hashed with bcrypt with 10-minute validity.

### 2. GPS & Camera Evidence
- **GPS Capture & Validation:** Automatic capture of latitude, longitude, location accuracy in meters, and timestamps.
- **Haversine Distance Formula (Algorithm 11):** Great-circle distance calculations between geographic coordinates in meters:
  $$d = 2R \arcsin\left(\sqrt{\sin^2\left(\frac{\Delta\phi}{2}\right) + \cos(\phi_1)\cos(\phi_2)\sin^2\left(\frac{\Delta\lambda}{2}\right)}\right)$$
- **SHA-256 Binary Integrity (Algorithm 3):** Cryptographic SHA-256 hash computed for every photo evidence upload, stored in PostgreSQL, and verifiable against disk storage.
- **Perceptual Hashing (pHash) & Hamming Distance (Algorithm 6):** 32×32 grayscale conversion, 2D Discrete Cosine Transform (DCT-II), and median thresholding to compute a 64-bit fingerprint. Hamming distance ($\le 10$ bits) detects visually similar civic scenes.

### 3. Complaint Processing & Routing
- **Rule-Based Complaint Classification (Algorithm 1):** Real-time NLP keyword matcher categorizing reports into municipal domains (`Roads & Traffic`, `Cleanliness & Waste Management`, `Water Supply & Sanitation`, `Street & Public Lighting`, `Safety & Emergency Hazards`).
- **Automated Department Routing (Algorithm 9):** Automatically assigns complaints to responsible municipal departments (`ROADS`, `SANITATION`, `WATER`, `LIGHTING`, `PUBLIC_WORKS`).
- **Weighted Priority Scoring (Algorithm 8):** Explainable dynamic priority rating [0–100]:
  $$P = 0.25S + 0.20U + 0.15C + 0.15G + 0.10R + 0.15A$$
- **Finite-State Machine (FSM) Lifecycle (Algorithm 13):** Strict status progression (`SUBMITTED` $\to$ `VERIFIED` $\to$ `ASSIGNED` $\to$ `IN_PROGRESS` $\to$ `RESOLVED` $\to$ `CLOSED`) enforced by PostgreSQL row-level locks (`SELECT ... FOR UPDATE`), role guards, mandatory resolution notes, and complete audit logging in `status_history`.

### 4. Duplicate Complaint Detection
- **TF-IDF & Cosine Text Similarity (Algorithms 2 & 4):** Tokenization, stop-word elimination, term frequency, smooth inverse document frequency, and L2-normalized vector similarity.
- **Spatiotemporal Similarity Screening (Algorithm 7):** Fuses Haversine distance ($\le 150\text{m}$), 30-day temporal window, category matching, text cosine similarity ($\ge 0.50$), and image pHash Hamming distance ($\le 10$).
- **Pre-Submission Citizen Warning Dialog:** Warns users before final submission if a matching issue is already pending nearby, allowing them to link their report as corroborating evidence.

### 5. Tracking, SLA & Notifications
- **Event-Driven Notifications (Algorithm 17):** In-app notification dispatch on registration, assignment, and status milestones.
- **SLA Deadline Monitoring (Algorithm 19):** Tracks 24-hour response and 72-hour resolution SLA deadlines in `sla_records`.
- **Status History Audit Timeline:** Visual vertical timeline in Flutter displaying chronological status transitions, timestamps, actors, and notes.

---

## Directory Structure

```
civicconnect/
├── civicconnect-backend/       # Node.js + Express.js API Server
│   ├── middleware/             # JWT auth & RBAC middleware
│   ├── routes/                 # Express REST endpoints
│   ├── services/               # FSM, NLP, Spatial & Image algorithms
│   ├── schema.sql              # PostgreSQL relational schema
│   ├── server.js               # Express application entrypoint
│   ├── test_integration.js     # 54 automated E2E integration tests
│   └── package.json
└── mobile-application/         # Flutter Mobile Application
    ├── lib/
    │   ├── screens/            # Home, Report, My Reports, Rewards, Auth screens
    │   ├── services/           # ApiService connecting to backend
    │   └── main.dart
    └── pubspec.yaml
```

---

## Quick Start

### 1. Backend Setup
```bash
cd civicconnect-backend
npm install
# Configure PostgreSQL credentials in .env
npm start
# Run automated E2E test suite (54 tests):
npm test
```

### 2. Mobile Application Setup
```bash
cd mobile-application
flutter pub get
flutter run
```
