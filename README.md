# City Guest — Flutter Multi-Platform App (Mobile, Tablet, Windows Desktop)

Cross-platform Flutter application for **Guest Relation Management**, fully integrated with the **Supabase backend** shared with the `city-guest` Web application.

---

## 🚀 Key Features

- **Unified Database Sync**: Operates on the exact same Supabase PostgreSQL database as the React web application.
- **Multi-Platform Adaptive UI**:
  - **Mobile (iOS / Android)**: Touch-optimized single column layout with bottom navigation bar.
  - **Tablet**: Master-detail dual column split screens.
  - **Windows Desktop**: High-density desktop side navigation rail, wide tabular data view, keyboard navigation, and file system export.
- **Guest Management**: Form validation, address autocomplete, photo upload, international guest toggle, multiple visited place arrays, and duplicate entry detection.
- **Guest Task Assignments**: Real-time assignment board between Super Admin and Sub Admins with urgent alerts.
- **PDF & Excel Export**: Generate receipt PDFs and save Excel (`.xlsx`) reports directly to desktop or mobile file storage.
- **Role-Based Security**: Super Admin vs Sub Admin access controls enforced through Supabase Row-Level Security (RLS).

---

## 🛠️ How to Run the App

### 1. Supabase SQL Setup (Required once)
Copy and run the SQL code from `supabase_setup.sql` in your **Supabase Dashboard -> SQL Editor**.

### 2. Run on Windows Desktop
```bash
cd city_guest_flutter
flutter pub get
flutter run -d windows
```

### 3. Run on Mobile / Tablet (Android / iOS)
```bash
# Android
flutter run -d android

# iOS (macOS host)
flutter run -d ios
```

### 4. Build Production Executable for Windows Desktop
```bash
flutter build windows
```
The compiled release executable will be saved in `build/windows/x64/runner/Release/`.
