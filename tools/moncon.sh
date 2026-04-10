#!/bin/bash

# Target Address
TARGET="www.ibm.com"
LOGFILE="$HOME/connection_log.txt"
COUNT=0
RUNNING=true
PING_ATTEMPTS=3  # Number of ping attempts before reporting failure

# Initialize the log file
echo "Log started on $(date)" > "$LOGFILE"
echo "Monitoring connection to $TARGET..." >> "$LOGFILE"

# Table Header
print_table_header() {
  printf "+---------------------+--------+-----------------+-------------------+------------+---------+--------+-----------+----------------+----------------+\n"
  printf "| Date & Time         | Loop   | SSID            | BSSID             | RSSI       | Channel | Noise  | Tx-Rate   | IPv4           | Quality        |\n"
  printf "+---------------------+--------+-----------------+-------------------+------------+---------+--------+-----------+----------------+----------------+\n"
}

# Function: Print Table Row
print_table_row() {
  local datetime="$1"
  local loop="$2"
  local ssid="$3"
  local bssid="$4"
  local rssi="$5"
  local channel="$6"
  local noise="$7"
  local txrate="$8"
  local ipv4="$9"
  local quality="${10}"

  printf "| %-19s | %-6s | %-15s | %-17s | %-10s | %-7s | %-6s | %-9s | %-14s | %-14s |\n" \
    "$datetime" "$loop" "$ssid" "$bssid" "$rssi" "$channel" "$noise" "$txrate" "$ipv4" "$quality"
}

# Table Footer
print_table_footer() {
  printf "+---------------------+--------+-----------------+-------------------+------------+---------+--------+-----------+----------------+----------------+\n"
}

# Function: Alert on Connection Loss
warn_connection_loss() {
  for i in {1..4}; do
    afplay /System/Library/Sounds/Funk.aiff
    sleep 0.5
  done
  osascript -e 'tell application "System Events" to display dialog "Connection to $TARGET lost!" buttons {"OK"} with title "Warning" with icon caution'
  echo "Connection lost on $(date)" >> "$LOGFILE"
}

# Function: Get Wi-Fi Connection Details
get_connection_details() {
  WIFI_INFO=$(sudo wdutil info)
  echo "WIFI_INFO: $WIFI_INFO" >> "$LOGFILE"  # Debugging: Log full output
  
  SSID=$(echo "$WIFI_INFO" | grep -m 1 "SSID" | awk -F ": " '{print $2}')
  echo "SSID: $SSID" >> "$LOGFILE"  # Debugging
  
  BSSID=$(echo "$WIFI_INFO" | grep -m 1 "BSSID" | awk -F ": " '{print $2}')
  echo "BSSID: $BSSID" >> "$LOGFILE"  # Debugging
  
  RSSI=$(echo "$WIFI_INFO" | grep -m 1 "RSSI" | awk -F ": " '{print $2}' | sed 's/ dBm//')
  echo "RSSI: $RSSI" >> "$LOGFILE"  # Debugging
  
  CHANNEL=$(echo "$WIFI_INFO" | grep -m 1 "Channel" | awk -F ": " '{print $2}')
  echo "CHANNEL: $CHANNEL" >> "$LOGFILE"  # Debugging
  
  NOISE=$(echo "$WIFI_INFO" | grep -m 1 "Noise" | awk -F ": " '{print $2}' | sed 's/ dBm//')
  echo "NOISE: $NOISE" >> "$LOGFILE"  # Debugging
  
  TX_RATE=$(echo "$WIFI_INFO" | grep -m 1 "Tx Rate" | awk -F ": " '{print $2}' | sed 's/ Mbps//')
  echo "TX_RATE: $TX_RATE" >> "$LOGFILE"  # Debugging
  
  IPV4=$(echo "$WIFI_INFO" | grep -m 1 "IPv4 Address" | awk -F ": " '{print $2}')
  echo "IPV4: $IPV4" >> "$LOGFILE"  # Debugging

  # Assess Quality
  local quality_reason=""
  if [[ "$RSSI" -gt -50 ]] && (( $(echo "$TX_RATE > 500" | bc -l) )); then
    QUALITY="Excellent"
  elif [[ "$RSSI" -le -50 ]] && [[ "$RSSI" -gt -65 ]] && (( $(echo "$TX_RATE > 300" | bc -l) )); then
    QUALITY="Good"
  elif [[ "$RSSI" -le -65 ]] || (( $(echo "$TX_RATE <= 300" | bc -l) )); then
    QUALITY="Poor"
    if [[ "$RSSI" -le -65 ]]; then
      quality_reason="Low RSSI"
    fi
    if (( $(echo "$TX_RATE <= 300" | bc -l) )); then
      [[ -n "$quality_reason" ]] && quality_reason="$quality_reason, "
      quality_reason="${quality_reason}Low Tx-Rate"
    fi
  else
    QUALITY="Fair"
  fi

  echo "$SSID;$BSSID;$RSSI;$CHANNEL;$NOISE;$TX_RATE;$IPV4;$QUALITY ($quality_reason)"
}

# Function: Retry Ping
ping_with_retries() {
  local attempts=0
  while [[ $attempts -lt $PING_ATTEMPTS ]]; do
    if ping -c 1 -W 5 "$TARGET" > /dev/null 2>&1; then
      return 0
    fi
    attempts=$((attempts + 1))
    sleep 1
  done
  return 1
}

# Print Table Header
print_table_header

# Main Loop: Monitor Connection
while $RUNNING; do
  COUNT=$((COUNT + 1))
  DATETIME=$(date "+%Y-%m-%d %H:%M:%S")
  CONNECTION_DETAILS=$(get_connection_details)
  echo "CONNECTION_DETAILS: $CONNECTION_DETAILS" >> "$LOGFILE"  # Debugging
  IFS=";" read -r SSID BSSID RSSI CHANNEL NOISE TX_RATE IPV4 QUALITY <<< "$CONNECTION_DETAILS"

  if ! ping_with_retries; then
    print_table_footer
    echo "$(date): Connection lost after $COUNT loops. SSID: $SSID, BSSID: $BSSID, RSSI: $RSSI, Channel: $CHANNEL, Noise Level: $NOISE, Tx-Rate: $TX_RATE, IPv4: $IPV4, Quality: $QUALITY" >> "$LOGFILE"
    warn_connection_loss
    break
  else
    print_table_row "$DATETIME" "$COUNT" "$SSID" "$BSSID" "$RSSI" "$CHANNEL" "$NOISE" "$TX_RATE" "$IPV4" "$QUALITY"
    echo "$(date): Loop $COUNT - Connection successful. SSID: $SSID, BSSID: $BSSID, RSSI: $RSSI, Channel: $CHANNEL, Noise Level: $NOISE, Tx-Rate: $TX_RATE, IPv4: $IPV4, Quality: $QUALITY" >> "$LOGFILE"
  fi

  # Check for 'q' to quit
  if read -t 1 -n 1 key 2>/dev/null && [[ $key == "q" ]]; then
    RUNNING=false
    echo "Quit detected. Stopping script..." | tee -a "$LOGFILE"
    print_table_footer
    break
  fi

  sleep 2
done