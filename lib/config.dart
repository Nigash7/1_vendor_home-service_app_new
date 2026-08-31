// Same rules as the customer app:
//   - Android Emulator  -> http://10.0.2.2:8000
//   - Real phone (same WiFi as your PC) -> http://<YOUR_PC_LAN_IP>:8000
//     Find it with `ipconfig` on Windows. Run Django with 0.0.0.0:8000.
const String kApiBaseUrl = "http://192.168.1.9:8000/api";
