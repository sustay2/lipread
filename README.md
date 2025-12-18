# LipRead – Admin Backend & Mobile App Setup Guide

LipRead is a distributed system consisting of a FastAPI-based admin backend and a Flutter mobile application designed to support English lip-reading learning. The system integrates Firebase, Stripe subscriptions, and a local media server for video and image delivery.

---

## Table of Contents

1. Overview
2. System Requirements
3. Project Structure
4. Firebase Setup
5. Backend Setup (FastAPI)
6. Media Storage & Serving
7. Flutter App Setup
8. Video Playback & Android Security Notes
9. Stripe Setup
10. Common Issues & Fixes
11. Recommended Development Workflow
12. Final Notes

---

## 1. Overview

This repository contains:

* FastAPI Admin Backend for user, course, media, billing, and analytics management
* Flutter Mobile App for English lip-reading learning
* Firebase / Firestore as the primary data store
* Stripe for subscription billing
* Local Media Server for video and image delivery

---

## 2. System Requirements

### Backend (PC)

* Python 3.11 or higher
* Windows, macOS, or Linux
* Firebase project with Firestore enabled
* Stripe account (test mode supported)

### Mobile App

* Flutter 3.16 or higher
* Android emulator or physical Android device
* USB cable recommended for development

---

## 3. Project Structure

```text
lipread/
├── admin_panel/
│   ├── backend/
│   │   ├── app/
│   │   │   ├── main.py
│   │   │   ├── routers/
│   │   │   ├── services/
│   │   │   └── templates/
│   │   ├── main.py
│   │   └── requirements.txt
├── flutter_app/
│   ├── android/
│   │   └── app/
│   │       └── src/
│   │           └── main/
│   │               ├── AndroidManifest.xml
│   │               └── res/xml/network_security_config.xml
│   ├── lib/
│   │   ├── services/
│   │   ├── common/utils/
│   │   └── env.dart
│   └── pubspec.yaml
└── C:/lipread_media/
```

---

## 4. Firebase Setup

### 4.1 Create Firebase Project

Create a new Firebase project and enable Firestore in Native mode.

### 4.2 Service Account

Generate a service account private key and store the credentials in the backend `.env` file.

### 4.3 Required Firestore Collections

* users
* courses
* media
* subscription_plans
* user_subscriptions
* payments

---

## 5. Backend Setup (FastAPI)

### 5.1 Virtual Environment

```bash
cd admin_panel/backend
python -m venv .venv
.venv\Scripts\activate
```

### 5.2 Install Dependencies

```bash
pip install -r requirements.txt
```

### 5.3 Environment Variables

Create `.env` inside `admin_panel/backend`:

```ini
FIREBASE_PROJECT_ID=your_project_id
FIREBASE_CLIENT_EMAIL=xxxx@xxxx.iam.gserviceaccount.com
FIREBASE_PRIVATE_KEY="-----BEGIN PRIVATE KEY-----\n...\n-----END PRIVATE KEY-----\n"

ADMIN_SESSION_SECRET=change-me
UVICORN_LOG_LEVEL=info

MEDIA_ROOT=C:/lipread_media
MEDIA_BASE_URL=http://127.0.0.1:8000/media

STRIPE_SECRET_KEY=sk_test_xxx
STRIPE_WEBHOOK_SECRET=whsec_xxx
```

### 5.4 Run Backend

```bash
python backend/main.py
```

---

## 6. Media Storage & Serving

```text
C:/lipread_media/
├── images/
├── videos/
└── badge_icons/
```

Media is served at:

```
http://<backend-host>:8000/media/<type>/<filename>
```

---

## 7. Flutter App Setup

### 7.1 Install Dependencies

```bash
cd flutter_app
flutter pub get
```

### 7.2 Android Network Security

Create `android/app/src/main/res/xml/network_security_config.xml`:

```xml
<?xml version="1.0" encoding="utf-8"?>
<network-security-config>
    <domain-config cleartextTrafficPermitted="true">
        <domain includeSubdomains="true">10.157.106.118</domain>
        <domain includeSubdomains="true">192.168.0.115</domain>
        <domain includeSubdomains="true">10.0.2.2</domain>
    </domain-config>
    <base-config cleartextTrafficPermitted="true" />
</network-security-config>
```

Update `AndroidManifest.xml`:

```xml
<application
    android:usesCleartextTraffic="true"
    android:networkSecurityConfig="@xml/network_security_config">
</application>
```

### 7.3 API Configuration

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

## 8. Video Playback Notes

Android blocks cleartext HTTP traffic on some networks by default. The network security configuration ensures local video streaming works over hotspot, USB, and LAN.

---

## 9. Stripe Setup

Enable the following webhook events:

* invoice.paid
* customer.subscription.created
* customer.subscription.updated
* customer.subscription.deleted

---

## 10. Common Issues

**Videos load in browser but not in app**
Ensure your local IP is listed in `network_security_config.xml`.

**Port already in use**

```cmd
netstat -ano | findstr 8000
taskkill /PID <pid> /F
```

---

## 11. Recommended Workflow

| Task            | Tool                     |
| --------------- | ------------------------ |
| Backend API     | FastAPI                  |
| Media Streaming | FastAPI + Android Config |
| Mobile Testing  | USB / adb reverse        |
| Payments        | Stripe Test Mode         |
| Database        | Firestore                |

---

## 12. Final Notes

Firestore is the source of truth. Stripe is used only for billing state synchronization. Always ensure your Android security config is updated when switching networks.