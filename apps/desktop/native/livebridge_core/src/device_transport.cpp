#include "livebridge/device_transport.h"

#include <algorithm>
#include <cctype>

namespace livebridge {

std::string TransportFromConnectorId(const std::string& connector_id) {
  std::string id = connector_id;
  std::transform(id.begin(), id.end(), id.begin(), [](unsigned char c) { return static_cast<char>(std::tolower(c)); });
  // A2DP (stereo) hangs off BTHENUM, hands-free off BTHHFENUM, LE Audio off BTHLEDEVICE.
  for (const char* bluetooth : {"bthenum", "bthhfenum", "bthledevice"}) {
    if (id.find(bluetooth) != std::string::npos) return "bluetooth";
  }
  if (id.find("usb") != std::string::npos) return "usb";
  return "other";
}

}  // namespace livebridge
