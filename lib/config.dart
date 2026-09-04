// Base URL of the Django backend.
//
// This used to be a fixed LAN address, which meant every installed copy of
// the app tried to reach one particular laptop on one particular home WiFi.
// It is now supplied at build time, exactly like the customer app.
//
// While developing, the default below is used:
//   - Android Emulator  -> http://10.0.2.2:8000/api
//   - Real phone on the same WiFi as your PC -> http://<YOUR_PC_LAN_IP>:8000/api
//     Find the IP with `ipconfig` on Windows, and run Django with
//     `python manage.py runserver 0.0.0.0:8000` so it listens beyond localhost.
//
// For any build a real vendor will install, pass the production URL:
//   flutter build apk --dart-define=API_BASE_URL=https://api.example.com/api
//
// Note there is no trailing slash, and https is required once the backend
// enforces it -- an https page cannot call an http API.
const String kApiBaseUrl = String.fromEnvironment(
  'API_BASE_URL',
  defaultValue: "http://192.168.1.9:8000/api",
);
