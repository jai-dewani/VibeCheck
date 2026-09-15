import Foundation
import CoreMotion
import Combine

struct AccelSample {
    let timestamp: TimeInterval
    let x: Double
    let y: Double
    let z: Double
    let magnitude: Double
}

struct RecordingSession: Identifiable, Codable {
    let id: UUID
    let startTime: Date
    let duration: TimeInterval
    let peakG: Double
    let rmsG: Double
    let sampleCount: Int
    let fileName: String
}

class MotionManager: ObservableObject {
    private let motionManager = CMMotionManager()
    private let queue = OperationQueue()
    
    @Published var isRecording = false
    @Published var currentSample: AccelSample?
    @Published var peakG: Double = 0.0
    @Published var rmsG: Double = 0.0
    @Published var sampleCount: Int = 0
    @Published var elapsedTime: TimeInterval = 0.0
    @Published var sessions: [RecordingSession] = []
    
    private var fileHandle: FileHandle?
    private var fileURL: URL?
    private var startTime: Date?
    private var sumSquaredMagnitude: Double = 0.0
    private var timer: Timer?
    private var lastSample: AccelSample?
    
    private let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
    private let sessionsKey = "VibeCheck_Sessions"
    
    init() {
        queue.maxConcurrentOperationCount = 1
        queue.qualityOfService = .userInitiated
        loadSessions()
    }
    
    func startRecording() {
        guard motionManager.isAccelerometerAvailable else {
            print("Accelerometer not available")
            return
        }
        
        peakG = 0.0
        rmsG = 0.0
        sampleCount = 0
        elapsedTime = 0.0
        sumSquaredMagnitude = 0.0
        startTime = Date()
        
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let fileName = "VibeCheck_\(formatter.string(from: startTime!)).csv"
        fileURL = documentsURL.appendingPathComponent(fileName)
        
        do {
            let header = "timestamp_ms,accel_x_g,accel_y_g,accel_z_g,magnitude_g\n"
            try header.write(to: fileURL!, atomically: true, encoding: .utf8)
            fileHandle = try FileHandle(forWritingTo: fileURL!)
            try fileHandle?.seekToEnd()
        } catch {
            print("Error setting up file: \(error)")
            return
        }
        
        motionManager.accelerometerUpdateInterval = 1.0 / 100.0 // 100 Hz
        isRecording = true
        
        DispatchQueue.main.async {
            self.timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 20.0, repeats: true) { [weak self] _ in
                guard let self = self, let lastSample = self.lastSample else { return }
                self.currentSample = lastSample
                self.elapsedTime = Date().timeIntervalSince(self.startTime!)
            }
        }
        
        motionManager.startAccelerometerUpdates(to: queue) { [weak self] data, error in
            guard let data = data, let self = self else { return }
            
            let x = data.acceleration.x
            let y = data.acceleration.y
            let z = data.acceleration.z
            let mag = sqrt(x*x + y*y + z*z)
            let timestampMs = (Date().timeIntervalSince(self.startTime!)) * 1000.0
            
            let sample = AccelSample(timestamp: timestampMs, x: x, y: y, z: z, magnitude: mag)
            self.lastSample = sample
            
            let csvLine = String(format: "%.0f,%.3f,%.3f,%.3f,%.3f\n", timestampMs, x, y, z, mag)
            if let dataLine = csvLine.data(using: .utf8) {
                try? self.fileHandle?.write(contentsOf: dataLine)
            }
            
            DispatchQueue.main.async {
                self.sampleCount += 1
                if mag > self.peakG { self.peakG = mag }
                self.sumSquaredMagnitude += (mag * mag)
                self.rmsG = sqrt(self.sumSquaredMagnitude / Double(self.sampleCount))
            }
        }
    }
    
    func stopRecording() {
        motionManager.stopAccelerometerUpdates()
        timer?.invalidate()
        timer = nil
        isRecording = false
        
        do {
            try fileHandle?.synchronize()
            try fileHandle?.close()
        } catch {
            print("Error closing file: \(error)")
        }
        fileHandle = nil
        
        if let start = startTime, let url = fileURL {
            let session = RecordingSession(
                id: UUID(),
                startTime: start,
                duration: Date().timeIntervalSince(start),
                peakG: peakG,
                rmsG: rmsG,
                sampleCount: sampleCount,
                fileName: url.lastPathComponent
            )
            sessions.insert(session, at: 0)
            saveSessions()
        }
    }
    
    func exportURL(for session: RecordingSession) -> URL {
        return documentsURL.appendingPathComponent(session.fileName)
    }
    
    private func saveSessions() {
        if let data = try? JSONEncoder().encode(sessions) {
            UserDefaults.standard.set(data, forKey: sessionsKey)
        }
    }
    
    private func loadSessions() {
        if let data = UserDefaults.standard.data(forKey: sessionsKey),
           let decoded = try? JSONDecoder().decode([RecordingSession].self, from: data) {
            sessions = decoded
        }
    }
    
    func deleteSession(_ session: RecordingSession) {
        sessions.removeAll { $0.id == session.id }
        saveSessions()
        let file = exportURL(for: session)
        try? FileManager.default.removeItem(at: file)
    }
}
