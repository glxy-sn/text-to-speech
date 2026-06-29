import Foundation
import AVFoundation
import Combine

class AudioRecordingService: NSObject, ObservableObject, AVAudioRecorderDelegate {
    private var audioRecorder: AVAudioRecorder?
    @Published var isRecording = false
    @Published var recordingURL: URL?
    
    func startRecording() throws {
        let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        let docDir = paths[0]
        let audioFilename = docDir.appendingPathComponent("user_speech.wav")
        
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatLinearPCM),
            AVSampleRateKey: 16000.0,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false
        ]
        
        audioRecorder = try AVAudioRecorder(url: audioFilename, settings: settings)
        audioRecorder?.delegate = self
        audioRecorder?.record()
        
        DispatchQueue.main.async {
            self.isRecording = true
            self.recordingURL = nil
        }
    }
    
    func stopRecording() {
        audioRecorder?.stop()
        let url = audioRecorder?.url
        DispatchQueue.main.async {
            self.isRecording = false
            self.recordingURL = url
        }
    }
}
