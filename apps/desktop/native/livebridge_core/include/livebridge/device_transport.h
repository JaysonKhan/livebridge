// How an audio endpoint is attached, for the device list (`transport` in docs/bridge-contract.md).
#pragma once

#include <string>

namespace livebridge {

/// Windows: the transport of an audio endpoint from the device id its topology connector is connected to (the KS
/// filter of the driver, e.g. `{2}.\\?\bthhfenum#…` for a Bluetooth hands-free headset). Returns `bluetooth`, `usb`
/// or `other`; an empty or unknown id is `other`.
std::string TransportFromConnectorId(const std::string& connector_id);

}  // namespace livebridge
