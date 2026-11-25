#include "audio_devices.h"

#include <windows.h>

// Before the property keys: it makes this file the one that defines PKEY_Device_FriendlyName (the header below only
// declares the keys otherwise, and the linker would not find it).
#include <initguid.h>

#include <objbase.h>

#include <audioclient.h>
#include <mmdeviceapi.h>
#include <functiondiscoverykeys_devpkey.h>
#include <propidl.h>
#include <wrl/client.h>

#include <utility>
#include <vector>

#include "utils.h"
#include "win_util.h"

namespace audio_devices {
namespace {

using Microsoft::WRL::ComPtr;
using livebridge::Json;

struct Device {
  std::string uid;
  std::string name;
  int input_channels = 0;
  int output_channels = 0;
  double sample_rate = 0;
  bool is_virtual = false;
  bool is_default_input = false;
  bool is_default_output = false;
};

// Windows has no API that tells a software device from hardware, so this is a guess from the name: it covers
// VB-CABLE ("CABLE Input", "VB-Audio Virtual Cable") and the drivers that call themselves virtual.
bool LooksVirtual(const std::string& name) {
  static const char* const kMarks[] = {"CABLE", "VB-Audio", "Virtual"};
  for (const char* mark : kMarks) {
    if (name.find(mark) != std::string::npos) return true;
  }
  return false;
}

bool CreateEnumerator(ComPtr<IMMDeviceEnumerator>& enumerator) {
  return SUCCEEDED(::CoCreateInstance(__uuidof(MMDeviceEnumerator), nullptr, CLSCTX_ALL,
                                      IID_PPV_ARGS(enumerator.GetAddressOf())));
}

// The endpoint id as UTF-8; empty when it cannot be read.
std::string DeviceId(IMMDevice* device) {
  LPWSTR id = nullptr;
  std::string uid;
  if (SUCCEEDED(device->GetId(&id)) && id != nullptr) uid = Utf8FromUtf16(id);
  ::CoTaskMemFree(id);
  return uid;
}

// The id of the default endpoint for capture or playback; empty when there is none.
std::string DefaultDeviceId(IMMDeviceEnumerator* enumerator, EDataFlow flow) {
  ComPtr<IMMDevice> device;
  if (FAILED(enumerator->GetDefaultAudioEndpoint(flow, eConsole, device.GetAddressOf())) || device.Get() == nullptr) {
    return std::string();
  }
  return DeviceId(device.Get());
}

// Reads one endpoint. False when it has no id or does not say whether it captures or plays. An endpoint whose mix
// format cannot be read is still described, with no channels: it exists, it just cannot be used.
bool Describe(IMMDevice* device, Device& out) {
  out.uid = DeviceId(device);
  if (out.uid.empty()) return false;

  ComPtr<IMMEndpoint> endpoint;
  EDataFlow flow = eRender;
  if (FAILED(device->QueryInterface(IID_PPV_ARGS(endpoint.GetAddressOf()))) || FAILED(endpoint->GetDataFlow(&flow))) {
    return false;
  }

  ComPtr<IPropertyStore> properties;
  if (SUCCEEDED(device->OpenPropertyStore(STGM_READ, properties.GetAddressOf()))) {
    PROPVARIANT value;
    PropVariantInit(&value);
    if (SUCCEEDED(properties->GetValue(PKEY_Device_FriendlyName, &value)) && value.vt == VT_LPWSTR &&
        value.pwszVal != nullptr) {
      out.name = Utf8FromUtf16(value.pwszVal);
    }
    // Frees the string; there is nothing to do about a failure.
    ::PropVariantClear(&value);
  }
  if (out.name.empty()) out.name = out.uid;
  out.is_virtual = LooksVirtual(out.name);

  // The format the system mixes this endpoint in: its channel count and sample rate.
  int channels = 0;
  ComPtr<IAudioClient> client;
  if (SUCCEEDED(device->Activate(__uuidof(IAudioClient), CLSCTX_ALL, nullptr,
                                 reinterpret_cast<void**>(client.GetAddressOf())))) {
    WAVEFORMATEX* format = nullptr;
    if (SUCCEEDED(client->GetMixFormat(&format)) && format != nullptr) {
      channels = format->nChannels;
      out.sample_rate = static_cast<double>(format->nSamplesPerSec);
    }
    ::CoTaskMemFree(format);
  }
  if (flow == eCapture) {
    out.input_channels = channels;
  } else {
    out.output_channels = channels;
  }
  return true;
}

std::vector<Device> List() {
  std::vector<Device> devices;
  ComPtr<IMMDeviceEnumerator> enumerator;
  ComPtr<IMMDeviceCollection> endpoints;
  UINT count = 0;
  if (!CreateEnumerator(enumerator) ||
      FAILED(enumerator->EnumAudioEndpoints(eAll, DEVICE_STATE_ACTIVE, endpoints.GetAddressOf())) ||
      endpoints.Get() == nullptr || FAILED(endpoints->GetCount(&count))) {
    return devices;
  }
  const std::string default_input = DefaultDeviceId(enumerator.Get(), eCapture);
  const std::string default_output = DefaultDeviceId(enumerator.Get(), eRender);
  for (UINT i = 0; i < count; i++) {
    ComPtr<IMMDevice> endpoint;
    Device device;
    if (FAILED(endpoints->Item(i, endpoint.GetAddressOf())) || endpoint.Get() == nullptr ||
        !Describe(endpoint.Get(), device)) {
      continue;
    }
    device.is_default_input = device.uid == default_input;
    device.is_default_output = device.uid == default_output;
    devices.push_back(std::move(device));
  }
  return devices;
}

// The system's listener for device changes. COM keeps it alive by reference count; it deletes itself.
class NotificationClient final : public IMMNotificationClient {
 public:
  explicit NotificationClient(std::shared_ptr<std::atomic<bool>> changed) : changed_(std::move(changed)) {}

  HRESULT STDMETHODCALLTYPE QueryInterface(REFIID iid, void** object) override {
    if (object == nullptr) return E_POINTER;
    if (IsEqualIID(iid, __uuidof(IUnknown)) || IsEqualIID(iid, __uuidof(IMMNotificationClient))) {
      *object = static_cast<IMMNotificationClient*>(this);
      AddRef();
      return S_OK;
    }
    *object = nullptr;
    return E_NOINTERFACE;
  }
  ULONG STDMETHODCALLTYPE AddRef() override { return ++references_; }
  ULONG STDMETHODCALLTYPE Release() override {
    const ULONG left = --references_;
    if (left == 0) delete this;
    return left;
  }

  // These run on a system thread and must not block or call back into the device API: they only raise the flag.
  HRESULT STDMETHODCALLTYPE OnDeviceStateChanged(LPCWSTR, DWORD) override { return Changed(); }
  HRESULT STDMETHODCALLTYPE OnDeviceAdded(LPCWSTR) override { return Changed(); }
  HRESULT STDMETHODCALLTYPE OnDeviceRemoved(LPCWSTR) override { return Changed(); }
  HRESULT STDMETHODCALLTYPE OnDefaultDeviceChanged(EDataFlow, ERole, LPCWSTR) override { return Changed(); }
  // Fires for every property of every endpoint, often in bursts; the device list is re-read on the events above.
  HRESULT STDMETHODCALLTYPE OnPropertyValueChanged(LPCWSTR, const PROPERTYKEY) override { return S_OK; }

 private:
  ~NotificationClient() = default;

  HRESULT Changed() {
    changed_->store(true);
    return S_OK;
  }

  std::atomic<ULONG> references_{1};
  const std::shared_ptr<std::atomic<bool>> changed_;
};

}  // namespace

Json ListForBridge() {
  Json::Array list;
  for (const Device& device : List()) {
    Json::Object map;
    map.emplace_back("uid", device.uid);
    map.emplace_back("name", device.name);
    map.emplace_back("inputChannels", device.input_channels);
    map.emplace_back("outputChannels", device.output_channels);
    map.emplace_back("sampleRate", device.sample_rate);
    map.emplace_back("transport", device.is_virtual ? "virtual" : "other");
    map.emplace_back("isDefaultInput", device.is_default_input);
    map.emplace_back("isDefaultOutput", device.is_default_output);
    list.push_back(Json(std::move(map)));
  }
  return Json(std::move(list));
}

bool Find(const std::string& uid, livebridge::DeviceInfo& info) {
  const std::wstring id = Utf16FromUtf8(uid);
  ComPtr<IMMDeviceEnumerator> enumerator;
  ComPtr<IMMDevice> endpoint;
  DWORD state = 0;
  Device device;
  if (id.empty() || !CreateEnumerator(enumerator) ||
      FAILED(enumerator->GetDevice(id.c_str(), endpoint.GetAddressOf())) || endpoint.Get() == nullptr ||
      FAILED(endpoint->GetState(&state)) || state != DEVICE_STATE_ACTIVE || !Describe(endpoint.Get(), device)) {
    return false;
  }
  info.input_channels = device.input_channels;
  info.output_channels = device.output_channels;
  info.is_virtual = device.is_virtual;
  return true;
}

ChangeWatcher::ChangeWatcher(std::shared_ptr<std::atomic<bool>> changed) {
  if (FAILED(::CoCreateInstance(__uuidof(MMDeviceEnumerator), nullptr, CLSCTX_ALL, IID_PPV_ARGS(&enumerator_)))) {
    enumerator_ = nullptr;
    return;
  }
  client_ = new NotificationClient(std::move(changed));
  if (FAILED(enumerator_->RegisterEndpointNotificationCallback(client_))) {
    client_->Release();
    client_ = nullptr;
  }
}

ChangeWatcher::~ChangeWatcher() {
  if (client_ != nullptr) {
    // A failure leaves nothing to undo. Should the system still hold the listener for a moment, it stays valid:
    // it is reference-counted and shares the flag.
    enumerator_->UnregisterEndpointNotificationCallback(client_);
    client_->Release();
  }
  if (enumerator_ != nullptr) enumerator_->Release();
}

}  // namespace audio_devices
