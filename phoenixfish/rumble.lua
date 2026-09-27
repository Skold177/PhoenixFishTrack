local ffi = require('ffi');

pcall(ffi.cdef, [[
    typedef struct { uint32_t Data1; uint16_t Data2; uint16_t Data3; uint8_t Data4[8]; } pf_guid;
    typedef struct { uint32_t cbSize; pf_guid InterfaceClassGuid; uint32_t Flags; uintptr_t Reserved; } pf_interface_data;
    typedef struct { uint32_t Size; uint16_t VendorID; uint16_t ProductID; uint16_t VersionNumber; } pf_hid_attributes;
    typedef struct { uint16_t Usage; uint16_t UsagePage; uint16_t InputReportByteLength; uint16_t OutputReportByteLength; uint16_t Rest[28]; } pf_hidp_caps;
    typedef struct { uint16_t wLeftMotorSpeed; uint16_t wRightMotorSpeed; } pf_xinput_vibration;

    void*    __stdcall SetupDiGetClassDevsW(const pf_guid* ClassGuid, const uint16_t* Enumerator, void* hwndParent, uint32_t Flags);
    int      __stdcall SetupDiEnumDeviceInterfaces(void* DeviceInfoSet, void* DeviceInfoData, const pf_guid* InterfaceClassGuid, uint32_t MemberIndex, pf_interface_data* DeviceInterfaceData);
    int      __stdcall SetupDiGetDeviceInterfaceDetailW(void* DeviceInfoSet, pf_interface_data* DeviceInterfaceData, void* DeviceInterfaceDetailData, uint32_t DeviceInterfaceDetailDataSize, uint32_t* RequiredSize, void* DeviceInfoData);
    int      __stdcall SetupDiDestroyDeviceInfoList(void* DeviceInfoSet);
    void     __stdcall HidD_GetHidGuid(pf_guid* HidGuid);
    uint8_t  __stdcall HidD_GetAttributes(void* HidDeviceObject, pf_hid_attributes* Attributes);
    uint8_t  __stdcall HidD_GetPreparsedData(void* HidDeviceObject, void** PreparsedData);
    uint8_t  __stdcall HidD_FreePreparsedData(void* PreparsedData);
    int32_t  __stdcall HidP_GetCaps(void* PreparsedData, pf_hidp_caps* Capabilities);
    void*    __stdcall CreateFileW(const uint16_t* lpFileName, uint32_t dwDesiredAccess, uint32_t dwShareMode, void* lpSecurityAttributes, uint32_t dwCreationDisposition, uint32_t dwFlagsAndAttributes, void* hTemplateFile);
    int      __stdcall WriteFile(void* hFile, const void* lpBuffer, uint32_t nNumberOfBytesToWrite, uint32_t* lpNumberOfBytesWritten, void* lpOverlapped);
    int      __stdcall CloseHandle(void* hObject);
    uint32_t __stdcall XInputSetState(uint32_t dwUserIndex, pf_xinput_vibration* pVibration);
]]);

local setupapi = ffi.load('setupapi');
local hid      = ffi.load('hid');

local xinput_ok, xinput = pcall(ffi.load, 'xinput1_4');
if (not xinput_ok) then
    xinput_ok, xinput = pcall(ffi.load, 'xinput9_1_0');
end

local SONY              = 0x054C;
local DUALSENSE         = { [0x0CE6] = true, [0x0DF2] = true };
local DIGCF_HID_PRESENT = 0x12;
local READ_WRITE        = 0xC0000000;
local SHARE_READ_WRITE  = 3;
local OPEN_EXISTING     = 3;
local HIDP_SUCCESS      = 0x00110000;
local BLUETOOTH_LENGTH  = 78;
local SEARCH_INTERVAL   = 5;

local state = {
    handle      = nil,
    length      = 0,
    stop_at     = nil,
    next_search = 0,
};

local function invalid(handle)
    return handle == nil or ffi.cast('intptr_t', handle) == -1;
end

local function output_length(handle)
    local preparsed = ffi.new('void*[1]');
    if (hid.HidD_GetPreparsedData(handle, preparsed) == 0) then
        return 0;
    end
    local caps   = ffi.new('pf_hidp_caps');
    local status = hid.HidP_GetCaps(preparsed[0], caps);
    hid.HidD_FreePreparsedData(preparsed[0]);
    if (status ~= HIDP_SUCCESS) then
        return 0;
    end
    return caps.OutputReportByteLength;
end

local function is_dualsense(path)
    local probe = ffi.C.CreateFileW(path, 0, SHARE_READ_WRITE, nil, OPEN_EXISTING, 0, nil);
    if (invalid(probe)) then
        return false;
    end
    local attributes = ffi.new('pf_hid_attributes');
    attributes.Size = ffi.sizeof(attributes);
    local found = hid.HidD_GetAttributes(probe, attributes) ~= 0 and attributes.VendorID == SONY and DUALSENSE[attributes.ProductID] == true;
    ffi.C.CloseHandle(probe);
    return found;
end

local function open_usb(path)
    local handle = ffi.C.CreateFileW(path, READ_WRITE, SHARE_READ_WRITE, nil, OPEN_EXISTING, 0, nil);
    if (invalid(handle)) then
        return nil, 0;
    end
    local length = output_length(handle);
    if (length == 0 or length >= BLUETOOTH_LENGTH) then
        ffi.C.CloseHandle(handle);
        return nil, 0;
    end
    return handle, length;
end

local function find_dualsense()
    local guid = ffi.new('pf_guid');
    hid.HidD_GetHidGuid(guid);
    local set = setupapi.SetupDiGetClassDevsW(guid, nil, nil, DIGCF_HID_PRESENT);
    if (invalid(set)) then
        return nil, 0;
    end

    local data = ffi.new('pf_interface_data');
    data.cbSize = ffi.sizeof(data);

    local handle, length = nil, 0;
    local index = 0;
    while (not handle and setupapi.SetupDiEnumDeviceInterfaces(set, nil, guid, index, data) ~= 0) do
        index = index + 1;
        local required = ffi.new('uint32_t[1]');
        setupapi.SetupDiGetDeviceInterfaceDetailW(set, data, nil, 0, required, nil);
        if (required[0] > 0) then
            local detail = ffi.new('uint8_t[?]', required[0]);
            ffi.cast('uint32_t*', detail)[0] = ffi.abi('64bit') and 8 or 6;
            if (setupapi.SetupDiGetDeviceInterfaceDetailW(set, data, detail, required[0], nil, nil) ~= 0) then
                local path = ffi.cast('const uint16_t*', detail + 4);
                if (is_dualsense(path)) then
                    handle, length = open_usb(path);
                end
            end
        end
    end

    setupapi.SetupDiDestroyDeviceInfoList(set);
    return handle, length;
end

local function write_dualsense(strong, weak)
    if (not state.handle) then
        return false;
    end
    local report = ffi.new('uint8_t[?]', state.length);
    report[0] = 0x02;
    report[1] = 0x03;
    report[3] = weak;
    report[4] = strong;
    local written = ffi.new('uint32_t[1]');
    if (ffi.C.WriteFile(state.handle, report, state.length, written, nil) ~= 0) then
        return true;
    end
    ffi.C.CloseHandle(state.handle);
    state.handle = nil;
    return false;
end

local function write_xinput(strong, weak)
    if (not xinput_ok) then
        return false;
    end
    local vibration = ffi.new('pf_xinput_vibration');
    vibration.wLeftMotorSpeed  = strong * 257;
    vibration.wRightMotorSpeed = weak * 257;
    local sent = false;
    for pad = 0, 3 do
        if (xinput.XInputSetState(pad, vibration) == 0) then
            sent = true;
        end
    end
    return sent;
end

local rumble = {};

function rumble.pulse(strong, weak, seconds)
    if (not state.handle and os.clock() >= state.next_search) then
        state.next_search         = os.clock() + SEARCH_INTERVAL;
        state.handle, state.length = find_dualsense();
    end

    local dualsense = write_dualsense(strong, weak);
    local pad       = write_xinput(strong, weak);
    if (dualsense or pad) then
        state.stop_at = os.clock() + seconds;
        return true;
    end
    return false;
end

function rumble.stop()
    state.stop_at = nil;
    write_dualsense(0, 0);
    write_xinput(0, 0);
end

function rumble.update()
    if (state.stop_at and os.clock() >= state.stop_at) then
        rumble.stop();
    end
end

function rumble.close()
    rumble.stop();
    if (state.handle) then
        ffi.C.CloseHandle(state.handle);
        state.handle = nil;
    end
end

return rumble;
