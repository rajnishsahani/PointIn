# 📍 PointIn — AR-Powered Campus Building Intelligence

<p align="center">
  <img src="app_icon.png" width="120" alt="PointIn App Icon">
</p>

<p align="center">
  <strong>An AR-powered mobile app for navigating Syracuse University's campus and buildings</strong>
</p>

<p align="center">
  CIS651 — Mobile Application Programming | Syracuse University | Spring 2026
</p>

<p align="center">
  <strong>Rajnish Sahani</strong> | SUID: 211529650 | rsahani@syr.edu
</p>

---

## 🎯 What is PointIn?

PointIn is a cross-platform mobile application built with **Flutter** that transforms how students navigate Syracuse University. It combines three core capabilities into a single experience that no existing app provides:

| Feature | Description |
|---------|-------------|
| 🎯 **AR Outdoor Navigation** | Point your camera at any campus building to identify it. Get AR-guided walking directions with a live rotating mini-map. |
| 🏛️ **Campus Intelligence** | Faculty directories, room listings, department search, building history, and study room reservations for 19 SU buildings. |
| 🏢 **Indoor Library Guide** | 7-floor Bird Library navigation with GPS positioning, 174+ room search, compass guidance, and multi-floor stair/elevator routing. |

---

## 📱 Screenshots

### Campus Map & Building Detail
| Map with Pins | Building Preview | Overview | Rooms |
|:---:|:---:|:---:|:---:|
| 19 SU buildings with custom orange pins | Tap any pin for preview card | Photo, description, departments | Reserve study rooms |

### AR Camera & Navigation
| Building Recognition | AR Navigation | Explore Nearby |
|:---:|:---:|:---:|
| Point at a building → identify it | AR arrow + live mini-map + walking route | 12 categories, photos, ratings |

### Bird Library Indoor Navigation
| Floor Selector | Find Room | Indoor AR + Elevator | Room Guide |
|:---:|:---:|:---:|:---:|
| 7 floors (B through 6) | 174+ searchable rooms | AR arrow to stairs/elevator | Face direction to find room |

---

## 🛠️ Technical Stack

| Technology | Purpose |
|-----------|---------|
| **Flutter + Dart** | Cross-platform framework (iOS & Android) |
| **BLoC Architecture** | Event-driven state management |
| **Google Maps SDK** | Campus map with custom pins |
| **Google Places API** | Nearby search, photos, ratings, open/closed |
| **Google Directions API** | Walking route polylines |
| **Wikipedia API** | Building history & notable events |
| **flutter_compass** | Magnetometer for AR compass heading |
| **Camera API** | Live camera preview for AR overlay |
| **Hive** | Local NoSQL database (bookmarks) |
| **Geolocator** | GPS position stream |

---

## 🏗️ Architecture

```
┌──────────────────────────────────────────────────────┐
│                    User Interface                      │
│  MapScreen │ CameraScreen │ SearchScreen │ DetailScreen│
├──────────────────────────────────────────────────────┤
│                    BLoC Layer                          │
│         BuildingBloc  │  SearchBloc                    │
├──────────────────────────────────────────────────────┤
│                   Services Layer                       │
│  BuildingService  │ PlacesService  │ LocationService   │
│  LibrarySearchService │ IndoorPositionService          │
│  IndoorNavigationService │ WikipediaService            │
├──────────────────────────────────────────────────────┤
│                    Data Layer                          │
│  su_buildings.json │ bird_library_indoor.json │ Hive   │
└──────────────────────────────────────────────────────┘
```

---

## 📂 Project Structure

```
lib/
├── main.dart
├── models/
│   └── building.dart              # Building, Faculty, Room models
├── blocs/
│   ├── building_bloc.dart         # Building state management
│   └── search_bloc.dart           # Live search filtering
├── services/
│   ├── building_service.dart      # JSON data loading (19 buildings)
│   ├── places_service.dart        # Google Places + Directions APIs
│   ├── location_service.dart      # GPS position stream
│   ├── library_search_service.dart    # Indoor room search (174+ rooms)
│   ├── indoor_position_service.dart   # GPS-to-floor-plan mapping
│   └── indoor_navigation_service.dart # Multi-floor stair/elevator routing
├── views/
│   ├── screens/
│   │   ├── home_screen.dart           # Tab navigation shell
│   │   ├── map_screen.dart            # Google Maps with building pins
│   │   ├── camera_screen.dart         # AR camera + indoor mode
│   │   ├── search_screen.dart         # Building/faculty search
│   │   └── building_detail_screen.dart # Tabbed detail view
│   └── widgets/
├── utils/
│   ├── constants.dart
│   └── helpers.dart
assets/
├── data/
│   ├── su_buildings.json              # 19 buildings, 33 faculty, 112 rooms
│   └── bird_library_indoor.json       # 7 floors, 174+ rooms, compass guides
└── library_maps/                      # 7 cropped floor plan images
    ├── bird_floor_B.jpg
    ├── bird_floor_1.jpg ... bird_floor_6.jpg
```

---

## 🔑 Key Features

### Outdoor Features
- **Interactive Campus Map** — 19 SU buildings with custom orange pins on Google Maps
- **Building Preview Cards** — Tap a pin to see photo, description, and distance
- **Building Detail Screen** — Tabbed view with Overview, Faculty, Rooms, History
- **Faculty Directory** — 33 real SU faculty with tap-to-email/call
- **AR Building Recognition** — Point camera at a building, GPS + compass identifies it (800m range, 20° tolerance)
- **AR Walking Navigation** — Directional arrow + live rotating mini-map with real walking route polyline
- **Explore Nearby** — Google Places with 12 category filters, photos, ratings, distance
- **Search** — Real-time filtering across buildings and faculty via SearchBloc
- **Bookmarks** — Hive local persistence, survives app restarts

### Indoor Features (Bird Library)
- **Automatic Detection** — Indoor mode activates when GPS is within 70m of Bird Library
- **Floor Selector** — Choose from 7 floors (Lower Level B through Floor 6)
- **Rotating Floor Map** — Floor plan image rotates with compass inside a circular mini-map
- **GPS Floor Positioning** — Blue dot shows your position on the floor plan using 8 GPS reference points
- **Compass Guide** — "Facing N → Open Study Area, Assistive Technology (123), Security/DPS (125)"
- **Room Search** — Search 174+ rooms by number ("403"), name ("Map Room"), or amenity ("printer", "quiet", "café")
- **Multi-Floor Navigation** — Choose elevator or stairs when destination is on a different floor
- **Smart Stair Routing** — South Stairs (B↔1↔2), North Stairs (2↔3↔4↔5), Elevator (all floors), Floor 6 elevator-only
- **Multi-Leg Routes** — Floor 1→5 via stairs: South Stairs to Floor 2, walk to North Stairs, North Stairs to Floor 5
- **Progress Tracking** — Step-by-step progress bar with "Switch Floor" buttons

---

## 📊 By The Numbers

| Metric | Count |
|--------|-------|
| SU Buildings | 19 |
| Faculty Members | 33 |
| Rooms Mapped | 112 |
| Departments | 65 |
| Bird Library Rooms | 174+ |
| Library Floors | 7 |
| Explore Categories | 12 |
| GPS Reference Points | 8 |
| Custom Services | 6 |
| APIs Integrated | 4 |

---

## 🚀 Getting Started

### Prerequisites
- Flutter 3.7+ installed
- Android Studio or VS Code with Flutter extension
- Google Maps API key
- Android device or emulator

### Setup
```bash
git clone https://github.com/rajnishsahani/PointIn.git
cd PointIn
flutter pub get
flutter run
```

### API Key Setup
The app uses a Google Maps API key configured with Android app restrictions. To run on your device:
1. Create a Google Cloud project and enable Maps SDK, Places API, and Directions API
2. Replace the API key in `android/app/src/main/AndroidManifest.xml` and `lib/services/places_service.dart`

---

## 🏆 Competitive Advantage

| Feature | Google Maps | Yelp | SU Campus Maps | **PointIn** |
|---------|:---:|:---:|:---:|:---:|
| AR building overlay | Limited | ❌ | ❌ | ✅ |
| University data (faculty, rooms) | ❌ | ❌ | Partial | ✅ |
| Indoor floor-by-floor navigation | ❌ | ❌ | ❌ | ✅ |
| Room search inside buildings | ❌ | ❌ | ❌ | ✅ |
| Nearby place exploration | ✅ | ✅ | ❌ | ✅ |
| Building history | ❌ | ❌ | ❌ | ✅ |
| Multi-floor stairs/elevator routing | ❌ | ❌ | ❌ | ✅ |
| GPS positioning on floor plans | ❌ | ❌ | ❌ | ✅ |

---

## 🔮 Future Enhancements

- **BLE Beacon Integration** — Sub-meter indoor positioning using Bluetooth Low Energy beacons
- **Expand to All SU Buildings** — Indoor maps for Schine, Link Hall, Newhouse, and more
- **AR Glasses Support** — Hands-free navigation with Google/Meta AR glasses
- **Crowd-Sourced Data** — Students contribute study spot availability and room occupancy
- **ML Building Recognition** — On-device machine learning for visual building identification

---

## 📄 License

This project was developed as a final project for CIS651 Mobile Application Programming at Syracuse University, Spring 2026.

---

<p align="center">
  Built with ❤️ and ☕ at Syracuse University
</p>