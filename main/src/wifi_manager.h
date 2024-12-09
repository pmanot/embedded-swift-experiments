#ifndef WIFI_MANAGER_H
#define WIFI_MANAGER_H

#include "esp_err.h"
#include <stdbool.h>
#include "esp_http_server.h"

extern const httpd_config_t DEFAULT_SERVER_CONFIG;

/**
 * @brief Initialize the WiFi system
 * 
 * Initializes NVS, event loop, and WiFi configuration
 * @return ESP_OK on success, other ESP_ERR_* on failure
 */
esp_err_t wifi_manager_init(void);

/**
 * @brief Start WiFi in AP+STA mode
 * 
 * @param ap_ssid SSID for the access point (max 32 chars)
 * @param ap_password Password for the access point (max 64 chars)
 * @param ap_channel WiFi channel for the access point (1-13)
 * @param max_connections Maximum number of clients that can connect to AP
 * @return ESP_OK on success, other ESP_ERR_* on failure
 */
esp_err_t wifi_manager_start_ap(const char* ap_ssid, 
                               const char* ap_password,
                               uint8_t ap_channel,
                               uint8_t max_connections);

/**
 * @brief Connect to a WiFi network
 * 
 * @param ssid SSID of the network to connect to
 * @param password Password of the network
 * @param timeout_ms Timeout in milliseconds to wait for connection
 * @param[out] connected Pointer to bool that will be set to true if connected successfully
 * @return ESP_OK on success (even if connection fails), other ESP_ERR_* on failure
 */
esp_err_t wifi_manager_connect_sta(const char* ssid,
                                  const char* password,
                                  uint32_t timeout_ms,
                                  bool* connected);

/**
 * @brief Deinitialize the WiFi system
 * 
 * Stops WiFi and cleans up resources
 * @return ESP_OK on success, other ESP_ERR_* on failure
 */
esp_err_t wifi_manager_deinit(void);

/**
 * @brief Get the AP IP address
 * 
 * @param[out] ip_addr Buffer to store the IP address string
 * @param buffer_size Size of the buffer
 * @return ESP_OK on success, other ESP_ERR_* on failure
 */
esp_err_t wifi_manager_get_ap_ip(char* ip_addr, size_t buffer_size);

/**
 * @brief Stop HTTP server
 * 
 * @return ESP_OK on success, other ESP_ERR_* on failure
 */
esp_err_t wifi_manager_stop_http_server(void);

/**
 * @brief Get the STA IP address
 * 
 * @param[out] ip_addr Buffer to store the IP address string
 * @param buffer_size Size of the buffer
 * @return ESP_OK on success, other ESP_ERR_* on failure
 */
esp_err_t wifi_manager_get_sta_ip(char* ip_addr, size_t buffer_size);

#endif // WIFI_MANAGER_H 