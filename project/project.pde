#include <Arduino.h>
#include <WiFi.h>
#include <HTTPClient.h>
#include <ArduinoJson.h>
#include <TFT_eSPI.h>
#include <time.h>
#include <LilyGo_AMOLED.h>
#include <LV_Helper.h>
#include <lvgl.h>

// 🧠 Replace these with your real Wi-Fi credentials
static const char* WIFI_SSID     = "YOUR_WIFI_SSID";
static const char* WIFI_PASSWORD = "YOUR_WIFI_PASSWORD";

// Global display object
LilyGo_Class amoled;

// LVGL objects
static lv_obj_t* tileview;
static lv_obj_t* t1;
static lv_obj_t* t2;
static lv_obj_t* t1_label;
static lv_obj_t* t2_label;

// --- Helper: Set background + text color theme ---
static void apply_tile_colors(lv_obj_t* tile, lv_obj_t* label, bool dark)
{
  lv_obj_set_style_bg_opa(tile, LV_OPA_COVER, 0);
  lv_obj_set_style_bg_color(tile, dark ? lv_color_black() : lv_color_white(), 0);
  lv_obj_set_style_text_color(label, dark ? lv_color_white() : lv_color_black(), 0);
}

// --- WiFi Connection ---
static void connect_wifi()
{
  Serial.printf("Connecting to WiFi SSID: %s\n", WIFI_SSID);
  WiFi.mode(WIFI_STA);
  WiFi.begin(WIFI_SSID, WIFI_PASSWORD);

  uint32_t start = millis();
  while (WiFi.status() != WL_CONNECTED && (millis() - start) < 15000) {
    Serial.print(".");
    delay(250);
  }
  Serial.println();

  if (WiFi.status() == WL_CONNECTED) {
    Serial.println("✅ WiFi connected!");
  } else {
    Serial.println("❌ WiFi connection failed (timeout).");
  }
}

// --- Fetch weather data from SMHI API ---
static String getWeatherSummary()
{
  const char* apiUrl = "https://opendata-download-metfcst.smhi.se/api/category/pmp3g/version/2/geotype/point/lon/15.5869/lat/56.1612/data.json";

  if (WiFi.status() != WL_CONNECTED) {
    return "WiFi not connected";
  }

  HTTPClient http;
  http.begin(apiUrl);
  int httpCode = http.GET();

  if (httpCode != 200) {
    Serial.printf("HTTP Error: %d\n", httpCode);
    http.end();
    return "SMHI API Error";
  }

  String payload = http.getString();
  http.end();

  StaticJsonDocument<30000> doc;
  DeserializationError err = deserializeJson(doc, payload);
  if (err) {
    Serial.println("❌ JSON parse error!");
    return "Parse Error";
  }

  JsonArray series = doc["timeSeries"];
  float tempAtNoon = NAN;
  String condition = "?";

  // Find the first forecast at 12:00
  for (JsonObject entry : series) {
    String time = entry["validTime"];
    if (time.indexOf("T12:00:00Z") > 0) {
      for (JsonObject param : entry["parameters"].as<JsonArray>()) {
        String name = param["name"];
        if (name == "t") tempAtNoon = param["values"][0];
        if (name == "Wsymb2") {
          int code = param["values"][0];
          switch (code) {
            case 1: condition = "☀️ Clear"; break;
            case 2: condition = "🌤️ Light Cloud"; break;
            case 3: condition = "⛅ Cloudy"; break;
            case 4: condition = "☁️ Overcast"; break;
            case 5: condition = "🌧️ Rain"; break;
            case 6: condition = "❄️ Snow"; break;
            case 7: condition = "⚡ Thunder"; break;
            default: condition = "?";
          }
        }
      }
      break;  // Only need first noon entry
    }
  }

  if (!isnan(tempAtNoon)) {
    char buf[64];
    sprintf(buf, "%s\n%.1f°C", condition.c_str(), tempAtNoon);
    return String(buf);
  }

  return "No forecast available";
}

// --- Create UI Layout ---
static void create_ui()
{
  tileview = lv_tileview_create(lv_scr_act());
  lv_obj_set_size(tileview, lv_disp_get_hor_res(NULL), lv_disp_get_ver_res(NULL));
  lv_obj_set_scrollbar_mode(tileview, LV_SCROLLBAR_MODE_OFF);

  // Create two horizontal tiles
  t1 = lv_tileview_add_tile(tileview, 0, 0, LV_DIR_HOR);
  t2 = lv_tileview_add_tile(tileview, 1, 0, LV_DIR_HOR);

  // --- Tile 1: Startup info screen (US1.1B) ---
  t1_label = lv_label_create(t1);
  lv_label_set_text(t1_label, "Weather Station\nVersion 1.0\nGroup 5");
  lv_obj_set_style_text_font(t1_label, &lv_font_montserrat_28, 0);
  lv_obj_center(t1_label);
  apply_tile_colors(t1, t1_label, /*dark=*/false);

  // --- Tile 2: Weather Forecast (US1.2B / US1.3) ---
  t2_label = lv_label_create(t2);
  lv_label_set_text(t2_label, "Fetching weather...");
  lv_obj_set_style_text_font(t2_label, &lv_font_montserrat_28, 0);
  lv_obj_center(t2_label);
  apply_tile_colors(t2, t2_label, /*dark=*/false);

  // Fetch weather after UI setup
  String forecast = getWeatherSummary();
  lv_label_set_text(t2_label, forecast.c_str());
  lv_obj_center(t2_label);
}

// --- Setup ---
void setup()
{
  Serial.begin(115200);
  delay(200);

  if (!amoled.begin()) {
    Serial.println("❌ Failed to init LilyGO AMOLED.");
    while (true) delay(1000);
  }

  beginLvglHelper(amoled);   // Initialize LVGL for LilyGo board
  connect_wifi();            // Connect to Wi-Fi
  create_ui();               // Create interface
}

// --- Loop ---
void loop()
{
  lv_timer_handler();  // LVGL main loop
  delay(5);
}
