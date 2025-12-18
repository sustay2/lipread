# LipRead – Admin Backend & Mobile App Setup Guide

This repository contains:

* **FastAPI Admin Backend** (content management, users, billing, analytics)
* **Flutter Mobile App** (lip-reading learning app)
* **Firebase / Firestore** (primary database)
* **Stripe** (subscriptions & payments)
* **Local Media Server** (images & videos served from disk)
* **Optional Nginx** (recommended for video streaming stability)

---

## 1. System Requirements

### Backend (PC)

* Python **3.11+**
* Windows / macOS / Linux
* Firebase project (Firestore enabled)
* Stripe account (test mode supported)

### Mobile App

* Flutter **3.16+**
* Android device or emulator
* USB cable (recommended) or same LAN network

---

## 2. Project Structure (Relevant Parts)

```
lipread/
├── admin_panel/
│   ├── backend/
│   │   ├── app/
│   │   │   ├── main.py
│   │   │   ├── routers/
│   │   │   ├── services/
│   │   │   └── templates/
│   │   ├── main.py          # Backend entrypoint
│   │   └── requirements.txt
│   └── nginx/               # Optional
├── flutter_app/
│   ├── lib/
│   │   ├── services/
│   │   ├── common/utils/
│   │   └── env.dart
│   └── pubspec.yaml
└── C:/lipread_media/         # Local media storage (default)
```

---

## 3. Firebase Setup

### 3.1 Create Firebase Project

1. Go to [https://console.firebase.google.com](https://console.firebase.google.com)
2. Create a project
3. Enable **Firestore (Native mode)**

### 3.2 Service Account

1. Project Settings → Service Accounts
2. Generate a **Private Key**
3. Copy values into the backend `.env` file

### 3.3 Required Firestore Collections

```
users
courses
media
subscription_plans
user_subscriptions
payments
```

---

## 4. Backend Setup (FastAPI)

### 4.1 Create Virtual Environment

```bash
cd admin_panel/backend
python -m venv .venv
.venv\Scripts\activate   # Windows
```

### 4.2 Install Dependencies

```bash
pip install -r requirements.txt
```

---

### 4.3 Environment Variables

Create a `.env` file inside `admin_panel/backend`:

```env
# Firebase
FIREBASE_PROJECT_ID=your_project_id
FIREBASE_CLIENT_EMAIL=xxxx@xxxx.iam.gserviceaccount.com
FIREBASE_PRIVATE_KEY="-----BEGIN PRIVATE KEY-----\n...\n-----END PRIVATE KEY-----\n"

# Backend
ADMIN_SESSION_SECRET=change-me
UVICORN_LOG_LEVEL=info

# Media
MEDIA_ROOT=C:/lipread_media
MEDIA_BASE_URL=http://127.0.0.1:8000/media

# Stripe
STRIPE_SECRET_KEY=sk_test_xxx
STRIPE_WEBHOOK_SECRET=whsec_xxx
```

---

### 4.4 Start Backend (Development)

```bash
python backend/main.py
```

Backend will run at:

```
http://localhost:8000
```

Admin panel:

```
http://localhost:8000/users
```

---

## 5. Media Storage & Serving

### 5.1 Media Folder Structure

Default media directory:

```
C:/lipread_media/
├── images/
├── videos/
└── badge_icons/
```

Each uploaded media file is indexed in Firestore under the `media` collection.

### 5.2 Media URL Format

```
http://<backend-host>:8000/media/<type>/<filename>
```

Example:

```
http://localhost:8000/media/videos/example.mp4
```

---

## 6. Flutter App Setup

### 6.1 Install Dependencies

```bash
cd flutter_app
flutter pub get
```

---

### 6.2 API Configuration

Edit `lib/env.dart`:

```dart
const String kApiBase = String.fromEnvironment(
  'API_BASE',
  defaultValue: 'http://10.0.2.2:8000',
);

const String kTranscribeBase = String.fromEnvironment(
  'TRANSCRIBE_BASE',
  defaultValue: 'http://10.0.2.2:8001',
);
```

---

### 6.3 Run on Emulator

```bash
flutter run \
  --dart-define=API_BASE=http://10.0.2.2:8000 \
  --dart-define=TRANSCRIBE_BASE=http://10.0.2.2:8001
```

---

### 6.4 Run on Physical Android Device (USB – Recommended)

```bash
flutter run \
  --dart-define=API_BASE=http://10.0.2.2:8000 \
  --dart-define=TRANSCRIBE_BASE=http://10.0.2.2:8001
```

This avoids mobile hotspot and LAN routing issues.

---

## 7. Video Playback Notes

* Flutter video players **require HTTP Range support**
* FastAPI `StaticFiles` is unreliable for mobile streaming
* Mobile hotspot networks often break partial content streaming

---

## 8. Recommended: Nginx for Media Streaming

### 8.1 Why Nginx

* Proper **byte-range** handling
* Stable video playback on mobile
* Works reliably with hotspot and USB

### 8.2 Minimal Nginx Configuration (Windows)

```nginx
worker_processes  1;

events {
    worker_connections  1024;
}

http {
    include       mime.types;
    default_type  application/octet-stream;

    sendfile on;
    tcp_nopush on;
    tcp_nodelay on;

    server {
        listen 8000;

        location /media/ {
            root C:/lipread_media;
            add_header Accept-Ranges bytes;
            add_header Access-Control-Allow-Origin *;
        }

        location / {
            proxy_pass http://127.0.0.1:8002;
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
        }
    }
}
```

### 8.3 Start Nginx

```bash
cd C:\nginx
nginx
```

Backend should run on port `8002`, while clients access via port `8000`.

---

## 9. Stripe Setup

### 9.1 Products

* Monthly subscription
* Currency: **MYR**
* Billing interval: **month**

### 9.2 Webhooks

Enable the following events:

```
invoice.paid
customer.subscription.created
customer.subscription.updated
customer.subscription.deleted
```

---

## 10. Common Issues & Fixes

### Videos load in browser but not in Flutter

* Use **adb reverse** or **Nginx**
* Avoid mobile hotspot without a proxy

### Port already in use

```bash
netstat -ano | findstr 8000
taskkill /PID <pid> /F
```

---

## 11. Recommended Development Workflow

| Task            | Tool               |
| --------------- | ------------------ |
| Backend API     | FastAPI            |
| Media streaming | Nginx              |
| Mobile testing  | USB + adb reverse  |
| Payments        | Stripe (test mode) |
| Database        | Firestore          |

---

## 12. Final Notes

* Prefer **USB tethering or adb reverse** for development
* Use **Nginx** for production-grade video streaming
* Firestore is the source of truth
* Stripe is used only for billing state synchronization