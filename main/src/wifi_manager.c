#include "esp_wifi.h"
#include "esp_event.h"
#include "esp_log.h"
#include "nvs_flash.h"
#include <string.h>
#include "freertos/event_groups.h"
#include "esp_netif.h"
#include "esp_http_server.h"

static const char *TAG = "wifi_manager";
static EventGroupHandle_t s_wifi_event_group;
static esp_netif_t *esp_netif_ap = NULL;
static esp_netif_t *esp_netif_sta = NULL;
static httpd_handle_t server = NULL;

#define WIFI_CONNECTED_BIT BIT0
#define WIFI_FAIL_BIT      BIT1

static void wifi_event_handler(void *arg, esp_event_base_t event_base,
                             int32_t event_id, void *event_data)
{
    if (event_base == WIFI_EVENT) {
        switch (event_id) {
            case WIFI_EVENT_STA_START:
                esp_wifi_connect();
                break;
            case WIFI_EVENT_STA_DISCONNECTED:
                xEventGroupSetBits(s_wifi_event_group, WIFI_FAIL_BIT);
                break;
            case WIFI_EVENT_AP_STACONNECTED:
                ESP_LOGI(TAG, "Station connected to AP");
                break;
            case WIFI_EVENT_AP_STADISCONNECTED:
                ESP_LOGI(TAG, "Station disconnected from AP");
                break;
        }
    } else if (event_base == IP_EVENT && event_id == IP_EVENT_STA_GOT_IP) {
        xEventGroupSetBits(s_wifi_event_group, WIFI_CONNECTED_BIT);
    }
}

static esp_err_t handle_post_request(httpd_req_t *req)
{
    char content[100];
    size_t recv_size = MIN(req->content_len, sizeof(content)-1);

    int ret = httpd_req_recv(req, content, recv_size);
    if (ret <= 0) {
        return ESP_FAIL;
    }
    content[ret] = '\0';

    ESP_LOGI(TAG, "Received POST data: %s", content);

    const char resp[] = "Command received\n";
    httpd_resp_send(req, resp, HTTPD_RESP_USE_STRLEN);
    return ESP_OK;
}

esp_err_t wifi_manager_init(void)
{
    esp_err_t ret = nvs_flash_init();
    if (ret == ESP_ERR_NVS_NO_FREE_PAGES || ret == ESP_ERR_NVS_NEW_VERSION_FOUND) {
        ESP_ERROR_CHECK(nvs_flash_erase());
        ret = nvs_flash_init();
    }
    ESP_ERROR_CHECK(ret);

    ESP_ERROR_CHECK(esp_netif_init());
    ESP_ERROR_CHECK(esp_event_loop_create_default());
    
    s_wifi_event_group = xEventGroupCreate();
    
    wifi_init_config_t cfg = WIFI_INIT_CONFIG_DEFAULT();
    ESP_ERROR_CHECK(esp_wifi_init(&cfg));
    
    ESP_ERROR_CHECK(esp_event_handler_instance_register(WIFI_EVENT,
                    ESP_EVENT_ANY_ID,
                    &wifi_event_handler,
                    NULL,
                    NULL));
    ESP_ERROR_CHECK(esp_event_handler_instance_register(IP_EVENT,
                    IP_EVENT_STA_GOT_IP,
                    &wifi_event_handler,
                    NULL,
                    NULL));
                    
    ESP_ERROR_CHECK(esp_wifi_set_mode(WIFI_MODE_APSTA));
    
    return ESP_OK;
}

esp_err_t wifi_manager_start_ap(const char* ap_ssid, 
                               const char* ap_password,
                               uint8_t ap_channel,
                               uint8_t max_connections)
{
    esp_netif_ap = esp_netif_create_default_wifi_ap();
    
    wifi_config_t wifi_ap_config = {
        .ap = {
            .channel = ap_channel,
            .max_connection = max_connections,
            .authmode = WIFI_AUTH_WPA2_PSK,
            .pmf_cfg = {
                .required = false,
            },
        },
    };
    
    strncpy((char*)wifi_ap_config.ap.ssid, ap_ssid, sizeof(wifi_ap_config.ap.ssid));
    strncpy((char*)wifi_ap_config.ap.password, ap_password, sizeof(wifi_ap_config.ap.password));
    
    if (strlen(ap_password) == 0) {
        wifi_ap_config.ap.authmode = WIFI_AUTH_OPEN;
    }
    
    ESP_ERROR_CHECK(esp_wifi_set_config(WIFI_IF_AP, &wifi_ap_config));
    
    return ESP_OK;
}

esp_err_t wifi_manager_connect_sta(const char* ssid,
                                  const char* password,
                                  uint32_t timeout_ms,
                                  bool* connected)
{
    *connected = false;
    esp_netif_sta = esp_netif_create_default_wifi_sta();
    
    wifi_config_t wifi_sta_config = {
        .sta = {
            .scan_method = WIFI_ALL_CHANNEL_SCAN,
            .failure_retry_cnt = 5,
            .threshold.authmode = WIFI_AUTH_WPA2_PSK,
            .sae_pwe_h2e = WPA3_SAE_PWE_BOTH,
        },
    };
    
    strncpy((char*)wifi_sta_config.sta.ssid, ssid, sizeof(wifi_sta_config.sta.ssid));
    strncpy((char*)wifi_sta_config.sta.password, password, sizeof(wifi_sta_config.sta.password));
    
    ESP_ERROR_CHECK(esp_wifi_set_config(WIFI_IF_STA, &wifi_sta_config));
    ESP_ERROR_CHECK(esp_wifi_start());
    
    EventBits_t bits = xEventGroupWaitBits(s_wifi_event_group,
                                          WIFI_CONNECTED_BIT | WIFI_FAIL_BIT,
                                          pdTRUE,
                                          pdFALSE,
                                          pdMS_TO_TICKS(timeout_ms));
    
    if (bits & WIFI_CONNECTED_BIT) {
        ESP_LOGI(TAG, "Connected to AP");
        *connected = true;
        esp_netif_set_default_netif(esp_netif_sta);
        if (esp_netif_napt_enable(esp_netif_ap) != ESP_OK) {
            ESP_LOGE(TAG, "NAPT not enabled");
        }
    } else {
        ESP_LOGI(TAG, "Failed to connect to AP");
    }
    
    return ESP_OK;
}

esp_err_t wifi_manager_deinit(void)
{
    ESP_ERROR_CHECK(esp_wifi_stop());
    ESP_ERROR_CHECK(esp_wifi_deinit());
    if (s_wifi_event_group) {
        vEventGroupDelete(s_wifi_event_group);
        s_wifi_event_group = NULL;
    }
    return ESP_OK;
}

esp_err_t wifi_manager_get_ap_ip(char* ip_addr, size_t buffer_size) {
    esp_netif_ip_info_t ip_info;
    esp_netif_get_ip_info(esp_netif_ap, &ip_info);
    snprintf(ip_addr, buffer_size, IPSTR, IP2STR(&ip_info.ip));
    return ESP_OK;
}

const httpd_config_t DEFAULT_SERVER_CONFIG = HTTPD_DEFAULT_CONFIG();

esp_err_t wifi_manager_stop_http_server(void)
{
    if (server) {
        httpd_stop(server);
        server = NULL;
    }
    return ESP_OK;
}

esp_err_t wifi_manager_get_sta_ip(char* ip_addr, size_t buffer_size) {
    esp_netif_t* netif = esp_netif_get_handle_from_ifkey("WIFI_STA_DEF");
    if (netif == NULL) {
        return ESP_FAIL;
    }
    
    esp_netif_ip_info_t ip_info;
    esp_err_t ret = esp_netif_get_ip_info(netif, &ip_info);
    
    if (ret != ESP_OK) {
        return ret;
    }
    
    // Convert IP address to string
    snprintf(ip_addr, buffer_size, IPSTR, IP2STR(&ip_info.ip));
    return ESP_OK;
} 