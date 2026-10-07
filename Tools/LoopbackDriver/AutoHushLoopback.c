// AutoHush Loopback: a virtual audio device for testing AutoHush, never shipped
// with it. Whatever apps play to its output comes back on its input, so a
// recorder hears exactly what would have reached the speakers, after macOS
// has mixed every app and applied every tap (see Tools/ListenToFades).
//
// A Core Audio server plug-in (AudioServerPlugIn.h): one device, 48 kHz
// stereo 32-bit float, one output and one input stream sharing a ring buffer.
// The output is written into the ring at its sample time; the input reads
// the same sample times back, then clears them, so nothing old loops.
//
// Build with build.sh, install with install.sh (needs an administrator).

#include <CoreAudio/AudioServerPlugIn.h>
#include <mach/mach_time.h>
#include <pthread.h>
#include <string.h>

// MARK: - Objects and format

enum {
    kObjectPlugIn = kAudioObjectPlugInObject,
    kObjectDevice = 2,
    kObjectInputStream = 3,
    kObjectOutputStream = 4,
};

#define kSampleRate 48000.0
#define kChannels 2
#define kBytesPerFrame (kChannels * sizeof(Float32))
/// The ring holds about a third of a second; it's also the zero time stamp period.
#define kRingFrames 16384
#define kDeviceUID "AutoHushLoopback_UID"
#define kModelUID "AutoHushLoopback_Model"

static AudioServerPlugInHostRef gHost = NULL;
static UInt32 gRefCount = 0;
static pthread_mutex_t gStateLock = PTHREAD_MUTEX_INITIALIZER;
static UInt32 gIOClients = 0;
static UInt64 gAnchorHostTime = 0;
static Float64 gHostTicksPerFrame = 0;
static Float32 gRing[kRingFrames * kChannels];

static AudioStreamBasicDescription Format(void) {
    AudioStreamBasicDescription format = {0};
    format.mSampleRate = kSampleRate;
    format.mFormatID = kAudioFormatLinearPCM;
    format.mFormatFlags = kAudioFormatFlagIsFloat | kAudioFormatFlagsNativeEndian | kAudioFormatFlagIsPacked;
    format.mBytesPerPacket = kBytesPerFrame;
    format.mFramesPerPacket = 1;
    format.mBytesPerFrame = kBytesPerFrame;
    format.mChannelsPerFrame = kChannels;
    format.mBitsPerChannel = 32;
    return format;
}

// MARK: - The interface

static HRESULT QueryInterface(void* inDriver, REFIID inUUID, LPVOID* outInterface);
static ULONG AddRef(void* inDriver);
static ULONG Release(void* inDriver);
static OSStatus Initialize(AudioServerPlugInDriverRef inDriver, AudioServerPlugInHostRef inHost);
static OSStatus CreateDevice(AudioServerPlugInDriverRef inDriver, CFDictionaryRef inDescription, const AudioServerPlugInClientInfo* inClientInfo, AudioObjectID* outDeviceObjectID);
static OSStatus DestroyDevice(AudioServerPlugInDriverRef inDriver, AudioObjectID inDeviceObjectID);
static OSStatus AddDeviceClient(AudioServerPlugInDriverRef inDriver, AudioObjectID inDeviceObjectID, const AudioServerPlugInClientInfo* inClientInfo);
static OSStatus RemoveDeviceClient(AudioServerPlugInDriverRef inDriver, AudioObjectID inDeviceObjectID, const AudioServerPlugInClientInfo* inClientInfo);
static OSStatus PerformDeviceConfigurationChange(AudioServerPlugInDriverRef inDriver, AudioObjectID inDeviceObjectID, UInt64 inChangeAction, void* inChangeInfo);
static OSStatus AbortDeviceConfigurationChange(AudioServerPlugInDriverRef inDriver, AudioObjectID inDeviceObjectID, UInt64 inChangeAction, void* inChangeInfo);
static Boolean HasProperty(AudioServerPlugInDriverRef inDriver, AudioObjectID inObjectID, pid_t inClientProcessID, const AudioObjectPropertyAddress* inAddress);
static OSStatus IsPropertySettable(AudioServerPlugInDriverRef inDriver, AudioObjectID inObjectID, pid_t inClientProcessID, const AudioObjectPropertyAddress* inAddress, Boolean* outIsSettable);
static OSStatus GetPropertyDataSize(AudioServerPlugInDriverRef inDriver, AudioObjectID inObjectID, pid_t inClientProcessID, const AudioObjectPropertyAddress* inAddress, UInt32 inQualifierDataSize, const void* inQualifierData, UInt32* outDataSize);
static OSStatus GetPropertyData(AudioServerPlugInDriverRef inDriver, AudioObjectID inObjectID, pid_t inClientProcessID, const AudioObjectPropertyAddress* inAddress, UInt32 inQualifierDataSize, const void* inQualifierData, UInt32 inDataSize, UInt32* outDataSize, void* outData);
static OSStatus SetPropertyData(AudioServerPlugInDriverRef inDriver, AudioObjectID inObjectID, pid_t inClientProcessID, const AudioObjectPropertyAddress* inAddress, UInt32 inQualifierDataSize, const void* inQualifierData, UInt32 inDataSize, const void* inData);
static OSStatus StartIO(AudioServerPlugInDriverRef inDriver, AudioObjectID inDeviceObjectID, UInt32 inClientID);
static OSStatus StopIO(AudioServerPlugInDriverRef inDriver, AudioObjectID inDeviceObjectID, UInt32 inClientID);
static OSStatus GetZeroTimeStamp(AudioServerPlugInDriverRef inDriver, AudioObjectID inDeviceObjectID, UInt32 inClientID, Float64* outSampleTime, UInt64* outHostTime, UInt64* outSeed);
static OSStatus WillDoIOOperation(AudioServerPlugInDriverRef inDriver, AudioObjectID inDeviceObjectID, UInt32 inClientID, UInt32 inOperationID, Boolean* outWillDo, Boolean* outWillDoInPlace);
static OSStatus BeginIOOperation(AudioServerPlugInDriverRef inDriver, AudioObjectID inDeviceObjectID, UInt32 inClientID, UInt32 inOperationID, UInt32 inIOBufferFrameSize, const AudioServerPlugInIOCycleInfo* inIOCycleInfo);
static OSStatus DoIOOperation(AudioServerPlugInDriverRef inDriver, AudioObjectID inDeviceObjectID, AudioObjectID inStreamObjectID, UInt32 inClientID, UInt32 inOperationID, UInt32 inIOBufferFrameSize, const AudioServerPlugInIOCycleInfo* inIOCycleInfo, void* ioMainBuffer, void* ioSecondaryBuffer);
static OSStatus EndIOOperation(AudioServerPlugInDriverRef inDriver, AudioObjectID inDeviceObjectID, UInt32 inClientID, UInt32 inOperationID, UInt32 inIOBufferFrameSize, const AudioServerPlugInIOCycleInfo* inIOCycleInfo);

static AudioServerPlugInDriverInterface gInterface = {
    NULL,
    QueryInterface, AddRef, Release,
    Initialize, CreateDevice, DestroyDevice, AddDeviceClient, RemoveDeviceClient,
    PerformDeviceConfigurationChange, AbortDeviceConfigurationChange,
    HasProperty, IsPropertySettable, GetPropertyDataSize, GetPropertyData, SetPropertyData,
    StartIO, StopIO, GetZeroTimeStamp, WillDoIOOperation, BeginIOOperation, DoIOOperation, EndIOOperation,
};
static AudioServerPlugInDriverInterface* gInterfacePointer = &gInterface;
static AudioServerPlugInDriverRef gDriver = &gInterfacePointer;

/// The factory named in Info.plist.
void* AutoHushLoopback_Create(CFAllocatorRef inAllocator, CFUUIDRef inRequestedTypeUUID) {
    (void)inAllocator;
    if (!CFEqual(inRequestedTypeUUID, kAudioServerPlugInTypeUUID)) return NULL;
    return gDriver;
}

static HRESULT QueryInterface(void* inDriver, REFIID inUUID, LPVOID* outInterface) {
    if (inDriver != gDriver || outInterface == NULL) return kAudioHardwareBadObjectError;
    CFUUIDRef requested = CFUUIDCreateFromUUIDBytes(NULL, inUUID);
    HRESULT result = E_NOINTERFACE;
    if (CFEqual(requested, IUnknownUUID) || CFEqual(requested, kAudioServerPlugInDriverInterfaceUUID)) {
        pthread_mutex_lock(&gStateLock);
        gRefCount++;
        pthread_mutex_unlock(&gStateLock);
        *outInterface = gDriver;
        result = S_OK;
    }
    CFRelease(requested);
    return result;
}

static ULONG AddRef(void* inDriver) {
    if (inDriver != gDriver) return 0;
    pthread_mutex_lock(&gStateLock);
    ULONG count = ++gRefCount;
    pthread_mutex_unlock(&gStateLock);
    return count;
}

static ULONG Release(void* inDriver) {
    if (inDriver != gDriver) return 0;
    pthread_mutex_lock(&gStateLock);
    if (gRefCount > 0) gRefCount--;
    ULONG count = gRefCount;
    pthread_mutex_unlock(&gStateLock);
    return count;
}

static OSStatus Initialize(AudioServerPlugInDriverRef inDriver, AudioServerPlugInHostRef inHost) {
    if (inDriver != gDriver) return kAudioHardwareBadObjectError;
    gHost = inHost;
    mach_timebase_info_data_t timebase;
    mach_timebase_info(&timebase);
    gHostTicksPerFrame = (1e9 / kSampleRate) * (Float64)timebase.denom / (Float64)timebase.numer;
    return kAudioHardwareNoError;
}

// One device, made at load: nothing to create, destroy or reconfigure.
static OSStatus CreateDevice(AudioServerPlugInDriverRef inDriver, CFDictionaryRef inDescription, const AudioServerPlugInClientInfo* inClientInfo, AudioObjectID* outDeviceObjectID) {
    (void)inDriver; (void)inDescription; (void)inClientInfo; (void)outDeviceObjectID;
    return kAudioHardwareUnsupportedOperationError;
}
static OSStatus DestroyDevice(AudioServerPlugInDriverRef inDriver, AudioObjectID inDeviceObjectID) {
    (void)inDriver; (void)inDeviceObjectID;
    return kAudioHardwareUnsupportedOperationError;
}
static OSStatus AddDeviceClient(AudioServerPlugInDriverRef inDriver, AudioObjectID inDeviceObjectID, const AudioServerPlugInClientInfo* inClientInfo) {
    (void)inDriver; (void)inDeviceObjectID; (void)inClientInfo;
    return kAudioHardwareNoError;
}
static OSStatus RemoveDeviceClient(AudioServerPlugInDriverRef inDriver, AudioObjectID inDeviceObjectID, const AudioServerPlugInClientInfo* inClientInfo) {
    (void)inDriver; (void)inDeviceObjectID; (void)inClientInfo;
    return kAudioHardwareNoError;
}
static OSStatus PerformDeviceConfigurationChange(AudioServerPlugInDriverRef inDriver, AudioObjectID inDeviceObjectID, UInt64 inChangeAction, void* inChangeInfo) {
    (void)inDriver; (void)inDeviceObjectID; (void)inChangeAction; (void)inChangeInfo;
    return kAudioHardwareNoError;
}
static OSStatus AbortDeviceConfigurationChange(AudioServerPlugInDriverRef inDriver, AudioObjectID inDeviceObjectID, UInt64 inChangeAction, void* inChangeInfo) {
    (void)inDriver; (void)inDeviceObjectID; (void)inChangeAction; (void)inChangeInfo;
    return kAudioHardwareNoError;
}

// MARK: - Properties

static Boolean IsStream(AudioObjectID object) { return object == kObjectInputStream || object == kObjectOutputStream; }

/// The streams in a scope: input, output, or both (global).
static UInt32 Streams(AudioObjectPropertyScope scope, AudioObjectID* out) {
    UInt32 count = 0;
    if (scope == kAudioObjectPropertyScopeGlobal || scope == kAudioObjectPropertyScopeInput) out[count++] = kObjectInputStream;
    if (scope == kAudioObjectPropertyScopeGlobal || scope == kAudioObjectPropertyScopeOutput) out[count++] = kObjectOutputStream;
    return count;
}

static Boolean HasProperty(AudioServerPlugInDriverRef inDriver, AudioObjectID inObjectID, pid_t inClientProcessID, const AudioObjectPropertyAddress* inAddress) {
    (void)inClientProcessID;
    if (inDriver != gDriver || inAddress == NULL) return false;
    UInt32 size = 0;
    return GetPropertyDataSize(inDriver, inObjectID, 0, inAddress, 0, NULL, &size) == kAudioHardwareNoError;
}

static OSStatus IsPropertySettable(AudioServerPlugInDriverRef inDriver, AudioObjectID inObjectID, pid_t inClientProcessID, const AudioObjectPropertyAddress* inAddress, Boolean* outIsSettable) {
    if (!HasProperty(inDriver, inObjectID, inClientProcessID, inAddress)) return kAudioHardwareUnknownPropertyError;
    switch (inAddress->mSelector) {
    case kAudioDevicePropertyNominalSampleRate:
    case kAudioStreamPropertyVirtualFormat:
    case kAudioStreamPropertyPhysicalFormat:
        *outIsSettable = true; // only to what it is already
        break;
    default:
        *outIsSettable = false;
    }
    return kAudioHardwareNoError;
}

static OSStatus GetPropertyDataSize(AudioServerPlugInDriverRef inDriver, AudioObjectID inObjectID, pid_t inClientProcessID, const AudioObjectPropertyAddress* inAddress, UInt32 inQualifierDataSize, const void* inQualifierData, UInt32* outDataSize) {
    (void)inClientProcessID; (void)inQualifierDataSize; (void)inQualifierData;
    if (inDriver != gDriver || inAddress == NULL || outDataSize == NULL) return kAudioHardwareIllegalOperationError;
    AudioObjectID streams[2];
    switch (inObjectID) {
    case kObjectPlugIn:
        switch (inAddress->mSelector) {
        case kAudioObjectPropertyBaseClass:
        case kAudioObjectPropertyClass: *outDataSize = sizeof(AudioClassID); return 0;
        case kAudioObjectPropertyOwner: *outDataSize = sizeof(AudioObjectID); return 0;
        case kAudioObjectPropertyManufacturer:
        case kAudioPlugInPropertyResourceBundle: *outDataSize = sizeof(CFStringRef); return 0;
        case kAudioObjectPropertyOwnedObjects:
        case kAudioPlugInPropertyDeviceList:
        case kAudioPlugInPropertyTranslateUIDToDevice: *outDataSize = sizeof(AudioObjectID); return 0;
        }
        break;
    case kObjectDevice:
        switch (inAddress->mSelector) {
        case kAudioObjectPropertyBaseClass:
        case kAudioObjectPropertyClass: *outDataSize = sizeof(AudioClassID); return 0;
        case kAudioObjectPropertyOwner: *outDataSize = sizeof(AudioObjectID); return 0;
        case kAudioObjectPropertyName:
        case kAudioObjectPropertyManufacturer:
        case kAudioDevicePropertyDeviceUID:
        case kAudioDevicePropertyModelUID: *outDataSize = sizeof(CFStringRef); return 0;
        case kAudioObjectPropertyOwnedObjects:
        case kAudioDevicePropertyStreams: *outDataSize = Streams(inAddress->mScope, streams) * sizeof(AudioObjectID); return 0;
        case kAudioObjectPropertyControlList: *outDataSize = 0; return 0;
        case kAudioDevicePropertyRelatedDevices: *outDataSize = sizeof(AudioObjectID); return 0;
        case kAudioDevicePropertyTransportType:
        case kAudioDevicePropertyClockDomain:
        case kAudioDevicePropertyDeviceIsAlive:
        case kAudioDevicePropertyDeviceIsRunning:
        case kAudioDevicePropertyDeviceCanBeDefaultDevice:
        case kAudioDevicePropertyDeviceCanBeDefaultSystemDevice:
        case kAudioDevicePropertyLatency:
        case kAudioDevicePropertySafetyOffset:
        case kAudioDevicePropertyIsHidden:
        case kAudioDevicePropertyZeroTimeStampPeriod: *outDataSize = sizeof(UInt32); return 0;
        case kAudioDevicePropertyNominalSampleRate: *outDataSize = sizeof(Float64); return 0;
        case kAudioDevicePropertyAvailableNominalSampleRates: *outDataSize = sizeof(AudioValueRange); return 0;
        case kAudioDevicePropertyPreferredChannelsForStereo: *outDataSize = 2 * sizeof(UInt32); return 0;
        case kAudioDevicePropertyPreferredChannelLayout:
            *outDataSize = (UInt32)(offsetof(AudioChannelLayout, mChannelDescriptions) + kChannels * sizeof(AudioChannelDescription));
            return 0;
        }
        break;
    case kObjectInputStream:
    case kObjectOutputStream:
        switch (inAddress->mSelector) {
        case kAudioObjectPropertyBaseClass:
        case kAudioObjectPropertyClass: *outDataSize = sizeof(AudioClassID); return 0;
        case kAudioObjectPropertyOwner: *outDataSize = sizeof(AudioObjectID); return 0;
        case kAudioObjectPropertyOwnedObjects: *outDataSize = 0; return 0;
        case kAudioStreamPropertyIsActive:
        case kAudioStreamPropertyDirection:
        case kAudioStreamPropertyTerminalType:
        case kAudioStreamPropertyStartingChannel:
        case kAudioStreamPropertyLatency: *outDataSize = sizeof(UInt32); return 0;
        case kAudioStreamPropertyVirtualFormat:
        case kAudioStreamPropertyPhysicalFormat: *outDataSize = sizeof(AudioStreamBasicDescription); return 0;
        case kAudioStreamPropertyAvailableVirtualFormats:
        case kAudioStreamPropertyAvailablePhysicalFormats: *outDataSize = sizeof(AudioStreamRangedDescription); return 0;
        }
        break;
    }
    return kAudioHardwareUnknownPropertyError;
}

#define PUT(type, value) do { \
    if (inDataSize < sizeof(type)) return kAudioHardwareBadPropertySizeError; \
    *((type*)outData) = (value); *outDataSize = sizeof(type); return kAudioHardwareNoError; \
} while (0)

static OSStatus GetPropertyData(AudioServerPlugInDriverRef inDriver, AudioObjectID inObjectID, pid_t inClientProcessID, const AudioObjectPropertyAddress* inAddress, UInt32 inQualifierDataSize, const void* inQualifierData, UInt32 inDataSize, UInt32* outDataSize, void* outData) {
    (void)inClientProcessID;
    if (inDriver != gDriver || inAddress == NULL || outDataSize == NULL || outData == NULL) return kAudioHardwareIllegalOperationError;
    AudioObjectID streams[2];
    switch (inObjectID) {
    case kObjectPlugIn:
        switch (inAddress->mSelector) {
        case kAudioObjectPropertyBaseClass: PUT(AudioClassID, kAudioObjectClassID);
        case kAudioObjectPropertyClass: PUT(AudioClassID, kAudioPlugInClassID);
        case kAudioObjectPropertyOwner: PUT(AudioObjectID, kAudioObjectUnknown);
        case kAudioObjectPropertyManufacturer: PUT(CFStringRef, CFSTR("AutoHush (test tool)"));
        case kAudioPlugInPropertyResourceBundle: PUT(CFStringRef, CFSTR(""));
        case kAudioObjectPropertyOwnedObjects:
        case kAudioPlugInPropertyDeviceList: PUT(AudioObjectID, kObjectDevice);
        case kAudioPlugInPropertyTranslateUIDToDevice: {
            AudioObjectID found = kAudioObjectUnknown;
            if (inQualifierDataSize == sizeof(CFStringRef) && inQualifierData != NULL
                && CFStringCompare(*((CFStringRef*)inQualifierData), CFSTR(kDeviceUID), 0) == kCFCompareEqualTo) found = kObjectDevice;
            PUT(AudioObjectID, found);
        }
        }
        break;
    case kObjectDevice:
        switch (inAddress->mSelector) {
        case kAudioObjectPropertyBaseClass: PUT(AudioClassID, kAudioObjectClassID);
        case kAudioObjectPropertyClass: PUT(AudioClassID, kAudioDeviceClassID);
        case kAudioObjectPropertyOwner: PUT(AudioObjectID, kObjectPlugIn);
        case kAudioObjectPropertyName: PUT(CFStringRef, CFSTR("AutoHush Loopback"));
        case kAudioObjectPropertyManufacturer: PUT(CFStringRef, CFSTR("AutoHush (test tool)"));
        case kAudioDevicePropertyDeviceUID: PUT(CFStringRef, CFSTR(kDeviceUID));
        case kAudioDevicePropertyModelUID: PUT(CFStringRef, CFSTR(kModelUID));
        case kAudioDevicePropertyTransportType: PUT(UInt32, kAudioDeviceTransportTypeVirtual);
        case kAudioDevicePropertyRelatedDevices: PUT(AudioObjectID, kObjectDevice);
        case kAudioDevicePropertyClockDomain: PUT(UInt32, 0);
        case kAudioDevicePropertyDeviceIsAlive: PUT(UInt32, 1);
        case kAudioDevicePropertyDeviceIsRunning: {
            pthread_mutex_lock(&gStateLock);
            UInt32 running = gIOClients > 0;
            pthread_mutex_unlock(&gStateLock);
            PUT(UInt32, running);
        }
        case kAudioDevicePropertyDeviceCanBeDefaultDevice: PUT(UInt32, 1);
        // Never the system's alert device: alerts would land in recordings.
        case kAudioDevicePropertyDeviceCanBeDefaultSystemDevice: PUT(UInt32, 0);
        case kAudioDevicePropertyLatency: PUT(UInt32, 0);
        case kAudioDevicePropertySafetyOffset: PUT(UInt32, 0);
        case kAudioDevicePropertyIsHidden: PUT(UInt32, 0);
        case kAudioDevicePropertyZeroTimeStampPeriod: PUT(UInt32, kRingFrames);
        case kAudioDevicePropertyNominalSampleRate: PUT(Float64, kSampleRate);
        case kAudioDevicePropertyAvailableNominalSampleRates: {
            AudioValueRange range = { kSampleRate, kSampleRate };
            PUT(AudioValueRange, range);
        }
        case kAudioObjectPropertyOwnedObjects:
        case kAudioDevicePropertyStreams: {
            UInt32 count = Streams(inAddress->mScope, streams);
            UInt32 wanted = count * sizeof(AudioObjectID);
            if (inDataSize < wanted) count = inDataSize / sizeof(AudioObjectID);
            memcpy(outData, streams, count * sizeof(AudioObjectID));
            *outDataSize = count * sizeof(AudioObjectID);
            return kAudioHardwareNoError;
        }
        case kAudioObjectPropertyControlList: *outDataSize = 0; return kAudioHardwareNoError;
        case kAudioDevicePropertyPreferredChannelsForStereo: {
            if (inDataSize < 2 * sizeof(UInt32)) return kAudioHardwareBadPropertySizeError;
            ((UInt32*)outData)[0] = 1;
            ((UInt32*)outData)[1] = 2;
            *outDataSize = 2 * sizeof(UInt32);
            return kAudioHardwareNoError;
        }
        case kAudioDevicePropertyPreferredChannelLayout: {
            UInt32 size = (UInt32)(offsetof(AudioChannelLayout, mChannelDescriptions) + kChannels * sizeof(AudioChannelDescription));
            if (inDataSize < size) return kAudioHardwareBadPropertySizeError;
            AudioChannelLayout* layout = (AudioChannelLayout*)outData;
            memset(layout, 0, size);
            layout->mChannelLayoutTag = kAudioChannelLayoutTag_UseChannelDescriptions;
            layout->mNumberChannelDescriptions = kChannels;
            layout->mChannelDescriptions[0].mChannelLabel = kAudioChannelLabel_Left;
            layout->mChannelDescriptions[1].mChannelLabel = kAudioChannelLabel_Right;
            *outDataSize = size;
            return kAudioHardwareNoError;
        }
        }
        break;
    case kObjectInputStream:
    case kObjectOutputStream: {
        Boolean isInput = inObjectID == kObjectInputStream;
        switch (inAddress->mSelector) {
        case kAudioObjectPropertyBaseClass: PUT(AudioClassID, kAudioObjectClassID);
        case kAudioObjectPropertyClass: PUT(AudioClassID, kAudioStreamClassID);
        case kAudioObjectPropertyOwner: PUT(AudioObjectID, kObjectDevice);
        case kAudioObjectPropertyOwnedObjects: *outDataSize = 0; return kAudioHardwareNoError;
        case kAudioStreamPropertyIsActive: PUT(UInt32, 1);
        case kAudioStreamPropertyDirection: PUT(UInt32, isInput ? 1 : 0);
        case kAudioStreamPropertyTerminalType: PUT(UInt32, isInput ? kAudioStreamTerminalTypeLine : kAudioStreamTerminalTypeSpeaker);
        case kAudioStreamPropertyStartingChannel: PUT(UInt32, 1);
        case kAudioStreamPropertyLatency: PUT(UInt32, 0);
        case kAudioStreamPropertyVirtualFormat:
        case kAudioStreamPropertyPhysicalFormat: PUT(AudioStreamBasicDescription, Format());
        case kAudioStreamPropertyAvailableVirtualFormats:
        case kAudioStreamPropertyAvailablePhysicalFormats: {
            AudioStreamRangedDescription ranged;
            ranged.mFormat = Format();
            ranged.mSampleRateRange.mMinimum = kSampleRate;
            ranged.mSampleRateRange.mMaximum = kSampleRate;
            PUT(AudioStreamRangedDescription, ranged);
        }
        }
        break;
    }
    }
    return kAudioHardwareUnknownPropertyError;
}

/// Only what it already is can be set: 48 kHz, its one format.
static OSStatus SetPropertyData(AudioServerPlugInDriverRef inDriver, AudioObjectID inObjectID, pid_t inClientProcessID, const AudioObjectPropertyAddress* inAddress, UInt32 inQualifierDataSize, const void* inQualifierData, UInt32 inDataSize, const void* inData) {
    (void)inClientProcessID; (void)inQualifierDataSize; (void)inQualifierData;
    if (inDriver != gDriver || inAddress == NULL || inData == NULL) return kAudioHardwareIllegalOperationError;
    if (inObjectID == kObjectDevice && inAddress->mSelector == kAudioDevicePropertyNominalSampleRate) {
        if (inDataSize != sizeof(Float64)) return kAudioHardwareBadPropertySizeError;
        return *((const Float64*)inData) == kSampleRate ? kAudioHardwareNoError : kAudioHardwareIllegalOperationError;
    }
    if (IsStream(inObjectID) && (inAddress->mSelector == kAudioStreamPropertyVirtualFormat || inAddress->mSelector == kAudioStreamPropertyPhysicalFormat)) {
        if (inDataSize != sizeof(AudioStreamBasicDescription)) return kAudioHardwareBadPropertySizeError;
        const AudioStreamBasicDescription* format = inData;
        return format->mSampleRate == kSampleRate && format->mChannelsPerFrame == kChannels ? kAudioHardwareNoError : kAudioDeviceUnsupportedFormatError;
    }
    return kAudioHardwareUnknownPropertyError;
}

// MARK: - IO

static OSStatus StartIO(AudioServerPlugInDriverRef inDriver, AudioObjectID inDeviceObjectID, UInt32 inClientID) {
    (void)inClientID;
    if (inDriver != gDriver || inDeviceObjectID != kObjectDevice) return kAudioHardwareBadObjectError;
    pthread_mutex_lock(&gStateLock);
    if (gIOClients++ == 0) {
        memset(gRing, 0, sizeof(gRing));
        gAnchorHostTime = mach_absolute_time();
    }
    pthread_mutex_unlock(&gStateLock);
    return kAudioHardwareNoError;
}

static OSStatus StopIO(AudioServerPlugInDriverRef inDriver, AudioObjectID inDeviceObjectID, UInt32 inClientID) {
    (void)inClientID;
    if (inDriver != gDriver || inDeviceObjectID != kObjectDevice) return kAudioHardwareBadObjectError;
    pthread_mutex_lock(&gStateLock);
    if (gIOClients > 0) gIOClients--;
    pthread_mutex_unlock(&gStateLock);
    return kAudioHardwareNoError;
}

/// The device's clock: one time stamp per ring's worth of frames since IO started.
static OSStatus GetZeroTimeStamp(AudioServerPlugInDriverRef inDriver, AudioObjectID inDeviceObjectID, UInt32 inClientID, Float64* outSampleTime, UInt64* outHostTime, UInt64* outSeed) {
    (void)inClientID;
    if (inDriver != gDriver || inDeviceObjectID != kObjectDevice) return kAudioHardwareBadObjectError;
    Float64 ticksPerRing = gHostTicksPerFrame * kRingFrames;
    UInt64 rings = (UInt64)((Float64)(mach_absolute_time() - gAnchorHostTime) / ticksPerRing);
    *outSampleTime = (Float64)(rings * kRingFrames);
    *outHostTime = gAnchorHostTime + (UInt64)((Float64)rings * ticksPerRing);
    *outSeed = 1;
    return kAudioHardwareNoError;
}

static OSStatus WillDoIOOperation(AudioServerPlugInDriverRef inDriver, AudioObjectID inDeviceObjectID, UInt32 inClientID, UInt32 inOperationID, Boolean* outWillDo, Boolean* outWillDoInPlace) {
    (void)inDriver; (void)inDeviceObjectID; (void)inClientID;
    *outWillDo = inOperationID == kAudioServerPlugInIOOperationWriteMix || inOperationID == kAudioServerPlugInIOOperationReadInput;
    *outWillDoInPlace = true;
    return kAudioHardwareNoError;
}

static OSStatus BeginIOOperation(AudioServerPlugInDriverRef inDriver, AudioObjectID inDeviceObjectID, UInt32 inClientID, UInt32 inOperationID, UInt32 inIOBufferFrameSize, const AudioServerPlugInIOCycleInfo* inIOCycleInfo) {
    (void)inDriver; (void)inDeviceObjectID; (void)inClientID; (void)inOperationID; (void)inIOBufferFrameSize; (void)inIOCycleInfo;
    return kAudioHardwareNoError;
}

static OSStatus EndIOOperation(AudioServerPlugInDriverRef inDriver, AudioObjectID inDeviceObjectID, UInt32 inClientID, UInt32 inOperationID, UInt32 inIOBufferFrameSize, const AudioServerPlugInIOCycleInfo* inIOCycleInfo) {
    (void)inDriver; (void)inDeviceObjectID; (void)inClientID; (void)inOperationID; (void)inIOBufferFrameSize; (void)inIOCycleInfo;
    return kAudioHardwareNoError;
}

/// The mix played to the output goes into the ring at its sample time; the
/// input reads the same sample times back, then clears them.
static OSStatus DoIOOperation(AudioServerPlugInDriverRef inDriver, AudioObjectID inDeviceObjectID, AudioObjectID inStreamObjectID, UInt32 inClientID, UInt32 inOperationID, UInt32 inIOBufferFrameSize, const AudioServerPlugInIOCycleInfo* inIOCycleInfo, void* ioMainBuffer, void* ioSecondaryBuffer) {
    (void)inDriver; (void)inDeviceObjectID; (void)inStreamObjectID; (void)inClientID; (void)ioSecondaryBuffer;
    Float32* buffer = ioMainBuffer;
    Boolean writing = inOperationID == kAudioServerPlugInIOOperationWriteMix;
    if (!writing && inOperationID != kAudioServerPlugInIOOperationReadInput) return kAudioHardwareNoError;
    Float64 sampleTime = writing ? inIOCycleInfo->mOutputTime.mSampleTime : inIOCycleInfo->mInputTime.mSampleTime;
    UInt64 start = (UInt64)sampleTime % kRingFrames;
    UInt32 done = 0;
    while (done < inIOBufferFrameSize) {
        UInt32 frames = inIOBufferFrameSize - done;
        UInt64 position = (start + done) % kRingFrames;
        if (position + frames > kRingFrames) frames = (UInt32)(kRingFrames - position);
        Float32* ring = gRing + position * kChannels;
        Float32* io = buffer + (UInt64)done * kChannels;
        if (writing) {
            memcpy(ring, io, frames * kBytesPerFrame);
        } else {
            memcpy(io, ring, frames * kBytesPerFrame);
            memset(ring, 0, frames * kBytesPerFrame);
        }
        done += frames;
    }
    return kAudioHardwareNoError;
}
