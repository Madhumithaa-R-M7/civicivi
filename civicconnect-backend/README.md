# CivicConnect Node.js + Express + PostgreSQL Backend

A modular REST API server for the CivicConnect platform, replacing Firebase with PostgreSQL managed via pgAdmin.

---

## 🛠️ Tech Stack
- **Runtime**: Node.js
- **Framework**: Express.js
- **Database**: PostgreSQL (managed with pgAdmin)
- **Authentication**: JWT & bcrypt
- **File Uploads**: Multer (stores issue photos in `uploads/`)

---

## 🚀 Quick Setup

### 1. Database Configuration (.env)
Open the [`.env`](file:///c:/Users/lokes/Downloads/civicconnect/civicconnect-backend/.env) file and verify your PostgreSQL credentials:

```env
PORT=5000
DB_USER=postgres
DB_PASSWORD=your_actual_pgadmin_password
DB_HOST=localhost
DB_PORT=5432
DB_NAME=civicconnect
JWT_SECRET=civicconnect_super_secret_jwt_key_2026
```

### 2. Initialize Database Tables in pgAdmin
You have two options:
- **Option A (Automatic)**: Once the password in `.env` is correct, starting the server will automatically run [`schema.sql`](file:///c:/Users/lokes/Downloads/civicconnect/civicconnect-backend/schema.sql) and create all tables.
- **Option B (Manual via pgAdmin)**:
  1. Open **pgAdmin**.
  2. Right-click on your `civicconnect` database → click **Query Tool**.
  3. Open or paste the contents of [`schema.sql`](file:///c:/Users/lokes/Downloads/civicconnect/civicconnect-backend/schema.sql).
  4. Click the **Execute/Run** button (F5).

### 3. Run the Backend
```bash
# In c:\Users\lokes\Downloads\civicconnect\civicconnect-backend
npm run dev
```

---

## 📡 API Endpoints

### 🔐 Authentication (`/api/auth`)
| Method | Endpoint | Description |
|---|---|---|
| `POST` | `/api/auth/register` | Register a new user (`name`, `email` or `phone`, `password`) |
| `POST` | `/api/auth/login` | Login with identifier and password |
| `POST` | `/api/auth/send-otp` | Request mobile verification OTP (`phone`) |
| `POST` | `/api/auth/verify-otp` | Verify OTP code (`verificationId`, `otp`) |
| `GET` | `/api/auth/profile` | Get current logged-in user profile (Requires `Authorization: Bearer <token>`) |

### 📋 Complaints & Reports (`/api/complaints`)
| Method | Endpoint | Description |
|---|---|---|
| `POST` | `/api/complaints` | Submit new complaint (Supports multipart/form-data with image) |
| `GET` | `/api/complaints` | Get complaints (supports `?userId=<id>` and `?status=Pending|In Progress|Resolved`) |
| `GET` | `/api/complaints/:id` | Get details of a single complaint |
| `PATCH`| `/api/complaints/:id/status` | Update complaint status and resolution notes (admin/staff) |

### 🔔 Notifications & Rewards
| Method | Endpoint | Description |
|---|---|---|
| `GET` | `/api/notifications?userId=<id>` | Fetch all notifications for citizen |
| `PATCH`| `/api/notifications/:id/read` | Mark notification as read |
| `GET` | `/api/rewards/stats?userId=<id>` | Get points breakdown, counts, and history |

---

## 📱 Connecting Flutter
- For **Android Emulator**: Use `http://10.0.2.2:5000`
- For **Physical Android/iOS Device**: Use your local PC IP (e.g. `http://192.168.1.X:5000`)
- For **Windows/Web Flutter**: Use `http://localhost:5000`
