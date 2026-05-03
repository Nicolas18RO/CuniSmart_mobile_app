# TechDesign-CuniSmart-MVP.md

# Technical Design Document: CuniSmart MVP

---

## 🚀 How We’ll Build It

### ✅ Recommended Approach: Flutter + Django (Simple Monolithic Architecture)

**Primary Recommendation:** Flutter (mobile) + Django REST + PostgreSQL

### Why this is perfect for you:
- You already know Flutter → faster development
- You already used Django REST → no learning curve
- Works offline-first (critical for your user)
- Full control → no vendor lock-in
- 100% possible with free tools

### 💰 Cost:
- Development: $0  
- Hosting: $0–$10/month (optional)

### ⏱ Time to MVP:
- 7–14 days

### ⚠️ Limitations:
- Backend setup required
- IoT setup required
- Voice needs configuration

---

## 🔄 Alternative Options Compared

| Option | Pros | Cons | Cost | Time |
|------|------|------|------|------|
| Flutter + Django (Recommended) | Flexible, known stack | Setup needed | Free | 1–2 weeks |
| Firebase + Flutter | Fast backend | Vendor lock-in | Free → Paid | ~1 week |
| No-code tools | Easy | Not good for IoT/offline | Paid | 1–2 weeks |

---

## 🧱 Project Setup Checklist

### Backend Setup

```bash
python -m venv venv
source venv/bin/activate
pip install django djangorestframework psycopg2
django-admin startproject cunismart_backend
cd cunismart_backend
python manage.py startapp core