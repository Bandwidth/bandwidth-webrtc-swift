# Bandwidth WebRTC Swift

Bandwidth WebRTC Swift is an open-source implementation of [Bandwidth WebRTC](https://dev.bandwidth.com/webrtc/about.html) suitable for iOS devices.

In order to take advantage of this package a Bandwidth account with WebRTC Audio and/or Video must be enabled.

## Quick Start

```swift

import WebRTC
import BandwidthWebRTC

class WebRTCService {
    let bandwidth = RTCBandwidth()
    
    var localVideoTrack: RTCVideoTrack?
    var localCameraVideoCapturer: RTCCameraVideoCapturer?

    var remoteVideoTrack: RTCVideoTrack?

    init() {
        bandwidth.delegate = self

        getToken { token in
            try? self.bandwidth.connect(using: token) {
                self.bandwidth.publish(audio: true, video: true, alias: "Bolg") { endpointId, mediaTypes, audioRTPSender, videoRTPSender in
                    self.localVideoTrack = videoRTPSender?.track as? RTCVideoTrack
                    // localRenderer should be a UIView of type RTCVideoRenderer. This is the view which displays the local video.
                    self.localVideoTrack?.add(self.localRenderer)

                    self.localCameraVideoCapturer = RTCCameraVideoCapturer()
                    self.localCameraVideoCapturer?.delegate = self.localVideoTrack?.source

                    // Grab the front facing camera. TODO: Add support for additional cameras.
                    guard let device = RTCCameraVideoCapturer.captureDevices().first(where: { $0.position == .front }) else {
                        return
                    }
                    
                    // Grab the highest resolution available.
                    guard let format = RTCCameraVideoCapturer.supportedFormats(for: device)
                        .sorted(by: { CMVideoFormatDescriptionGetDimensions($0.formatDescription).width < CMVideoFormatDescriptionGetDimensions($1.formatDescription).width })
                        .last else {
                        return
                    }
                    
                    // Grab the highest fps available.
                    guard let fps = format.videoSupportedFrameRateRanges
                        .compactMap({ $0.maxFrameRate })
                        .sorted()
                        .last else {
                        return
                    }
                    
                    // Start capturing local video with the given parameters.
                    self.localCameraVideoCapturer?.startCapture(with: device, format: format, fps: Int(fps))
                }
            }
        }
    }

    func getToken(completion: @escaping (String) -> Void) {
        // Return a Bandwidth WebRTC participant token from your application server. https://dev.bandwidth.com/webrtc/methods/participants/createParticipant.html
    }
}

extension WebRTCService: RTCBandwidthDelegate {
    func bandwidth(_ bandwidth: RTCBandwidth, streamAvailableAt endpointId: String, participantId: String, alias: String?, mediaTypes: [MediaType], rtpReceiver) {
        if let remoteVideoTrack = rtpReceiver.track as? RTCVideoTrack {
            self.remoteVideoTrack = remoteVideoTrack
            
            DispatchQueue.main.async {
                // remoteRenderer should be a UIView of type RTCVideoRenderer. This is the view which displays the remote video.
                self.remoteVideoTrack?.add(self.remoteRenderer)
            }
        }
    }

    func bandwidth(_ bandwidth: RTCBandwidth, streamUnavailableAt endpointId: String) {
        
    }
}
```

## Samples

A number of samples using Bandwidth WebRTC Swift may be found within [Bandwidth-Samples](https://github.com/Bandwidth-Samples).

## Compatibility

Bandwidth WebRTC Swift follows [SemVer 2.0.0](https://semver.org/#semantic-versioning-200).