# PointIn — AR-Powered Building Intelligence App

[![Flutter](https://img.shields.io/badge/Flutter-3.16+-blue.svg)](https://flutter.dev)
[![Dart](https://img.shields.io/badge/Dart-3.2+-blue.svg)](https://dart.dev)
[![License](https://img.shields.io/badge/License-Academic-orange.svg)]()

**CIS651 Final Project** | Syracuse University  
**Developer:** Rajnish Sahani (SUID: 211529650)

---

## About

PointIn is a cross-platform mobile app built with Flutter that uses **GPS** and **camera** to identify buildings in real time and display contextual information. Simply point your phone at a building to see faculty directories, room listings, restaurant ratings, and architectural history — all from one camera-first interface.

### Three Intelligent Modes

- **University Mode** — Faculty directories, room listings, auditorium schedules (scoped to Syracuse University)
- **Commercial Mode** — Restaurant and shop listings with menus and star ratings via Google Places API
- **History Mode** — Construction year, architect, notable events, and cultural significance via Wikipedia API

---

## Screenshots

| Map View | Building Detail | Camera (AR) | Search |
|----------|----------------|-------------|--------|
| Google Maps with SU building pins | Tabbed view with faculty, rooms, history | Live camera with building detection overlay | Search buildings, faculty, rooms |

---

## Architecture — BLoC Pattern
| BLoC | Responsibility |
|------|---------------|
| **BuildingBloc** | Loads buildings, filters by type, selects detail |
| **SearchBloc** | Real-time search across buildings and faculty |
| **CameraBloc** | Camera initialization, AR overlay state |

---

## Tech Stack

| Category | Technology |
|----------|-----------|
| Framework | Flutter (Dart) |
| State Management | BLoC (flutter_bloc) |
| Maps | Google Maps SDK for Android |
| Location | Geolocator |
| Camera | camera package |
| Database | Firebase Firestore + Hive (local) |
| APIs | Google Places, Wikipedia REST API |
| Storage | Hive (bookmarks, cache) |

---

## Features Implemented

- [x] Google Maps with custom building pins and tap-to-preview
- [x] GPS-based nearest building detection
- [x] Live camera with AR-style building overlay
- [x] Search with live filtering (buildings, faculty, rooms)
- [x] Building detail with tabbed view (Overview / Faculty / Rooms / History)
- [x] Wikipedia API integration for building history
- [x] Bookmark buildings with persistent local storage (Hive)
- [x] Filter by building type (University / Commercial / Mixed)
- [x] Landscape and portrait layout support
- [x] Fade-in animations on detail screens
- [x] Bottom tab navigation (Map / Camera / Search)

---

## Setup

1. Clone this repo
```bash
git clone https://github.com/rajnishsahani/PointIn.git
cd PointIn
```

2. Create `lib/utils/api_keys.dart` with your Google Maps API key

3. Install dependencies and run
```bash
flutter pub get
flutter run
```

---

## Project Structure
lib/
├── main.dart                    # App entry point
├── models/
│   └── building.dart            # Building, Faculty, Room models
├── blocs/
│   ├── building/building_bloc.dart
│   └── search/search_bloc.dart
├── views/
│   ├── screens/                 # Map, Camera, Search, Detail, Bookmarks
│   └── widgets/                 # Reusable UI components
├── services/
│   ├── building_service.dart    # Load/search building data
│   ├── location_service.dart    # GPS wrapper
│   ├── wikipedia_service.dart   # Wikipedia API
│   └── local_storage_service.dart # Hive bookmarks
└── utils/
├── app_theme.dart           # SU Orange theme
├── constants.dart           # App constants
└── helpers.dart             # Distance calculations


---

## Competitive Advantage

No existing app combines AR building recognition, university-specific data, commercial listings, and building history in one experience. PointIn is unique in its contextual mode switching — automatically adapting the displayed information based on building type.

| Feature | Google Maps | Yelp | Google Lens | SU Maps | **PointIn** |
|---------|------------|------|-------------|---------|-------------|
| AR building overlay | ✓ | ✗ | ✗ | ✗ | **✓** |
| University data | ✗ | ✗ | ✗ | ✓ | **✓** |
| Restaurant listings | ✗ | ✓ | ✗ | ✗ | **✓** |
| Building history | ✗ | ✗ | ✗ | ✗ | **✓** |
| Context switching | ✗ | ✗ | ✗ | ✗ | **✓** |


