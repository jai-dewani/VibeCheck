import SwiftUI
import Charts
import Combine

import Accelerate

struct ChartDataPoint: Identifiable {
    let id = UUID()
    let time: Double
    let magnitude: Double
    let x: Double
    let y: Double
    let z: Double
}

class SessionDetailViewModel: ObservableObject {
    @Published var isLoading = true
    @Published var chartData: [ChartDataPoint] = []
    
    @Published var peakX: Double = 0.0
    @Published var peakY: Double = 0.0
    @Published var peakZ: Double = 0.0
    
    @Published var timeGreen: Double = 0.0
    @Published var timeYellow: Double = 0.0
    @Published var timeRed: Double = 0.0
    
    @Published var dominantFrequency: Double = 0.0
    @Published var estimatedRPM: Double = 0.0
    
    func loadData(fileURL: URL, sessionDuration: TimeInterval) {
        DispatchQueue.global(qos: .userInitiated).async {
            guard let content = try? String(contentsOf: fileURL) else {
                DispatchQueue.main.async { self.isLoading = false }
                return
            }
            
            let lines = content.components(separatedBy: .newlines).filter { !$0.isEmpty && !$0.starts(with: "timestamp") }
            guard !lines.isEmpty else {
                DispatchQueue.main.async { self.isLoading = false }
                return
            }
            
            var allMagnitudes = [Double]()
            var pX = 0.0, pY = 0.0, pZ = 0.0
            var tG = 0, tY = 0, tR = 0
            
            // Downsampling prep: target ~300 points for the chart
            let downsampleFactor = max(1, lines.count / 300)
            var downsampled = [ChartDataPoint]()
            
            var currentBucketMag = 0.0, currentBucketX = 0.0, currentBucketY = 0.0, currentBucketZ = 0.0
            var currentBucketTime = 0.0
            var bucketCount = 0
            
            for (index, line) in lines.enumerated() {
                let columns = line.components(separatedBy: ",")
                if columns.count >= 5,
                   let t = Double(columns[0]),
                   let x = Double(columns[1]),
                   let y = Double(columns[2]),
                   let z = Double(columns[3]),
                   let m = Double(columns[4]) {
                    
                    allMagnitudes.append(m)
                    
                    pX = max(pX, abs(x))
                    pY = max(pY, abs(y))
                    pZ = max(pZ, abs(z))
                    
                    if m < 1.5 { tG += 1 }
                    else if m < 3.0 { tY += 1 }
                    else { tR += 1 }
                    
                    // Downsampling
                    currentBucketMag = max(currentBucketMag, m)
                    currentBucketX = max(currentBucketX, abs(x))
                    currentBucketY = max(currentBucketY, abs(y))
                    currentBucketZ = max(currentBucketZ, abs(z))
                    if bucketCount == 0 { currentBucketTime = t / 1000.0 }
                    bucketCount += 1
                    
                    if bucketCount >= downsampleFactor {
                        downsampled.append(ChartDataPoint(time: currentBucketTime, magnitude: currentBucketMag, x: currentBucketX, y: currentBucketY, z: currentBucketZ))
                        currentBucketMag = 0; currentBucketX = 0; currentBucketY = 0; currentBucketZ = 0; bucketCount = 0
                    }
                }
            }
            
            // FFT calculation for dominant frequency
            let sampleRate = 100.0 // 100 Hz
            let freq = self.calculateDominantFrequency(magnitudes: allMagnitudes, sampleRate: sampleRate)
            let rpm = freq * 60.0
            
            DispatchQueue.main.async {
                self.peakX = pX
                self.peakY = pY
                self.peakZ = pZ
                
                let total = Double(tG + tY + tR)
                if total > 0 {
                    self.timeGreen = (Double(tG) / total) * 100.0
                    self.timeYellow = (Double(tY) / total) * 100.0
                    self.timeRed = (Double(tR) / total) * 100.0
                }
                
                self.dominantFrequency = freq
                self.estimatedRPM = rpm
                self.chartData = downsampled
                self.isLoading = false
            }
        }
    }
    
    private func calculateDominantFrequency(magnitudes: [Double], sampleRate: Double) -> Double {
        let n = magnitudes.count
        guard n > 0 else { return 0.0 }
        
        let log2n = vDSP_Length(log2(Float(n)))
        let powerOfTwoCount = Int(1 << log2n)
        
        let truncated = magnitudes.prefix(powerOfTwoCount).map { Float($0) }
        guard let fftSetup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2)) else { return 0.0 }
        
        var real = [Float](truncated)
        var imag = [Float](repeating: 0.0, count: powerOfTwoCount)
        
        var splitComplex = DSPSplitComplex(realp: &real, imagp: &imag)
        vDSP_fft_zip(fftSetup, &splitComplex, 1, log2n, FFTDirection(FFT_FORWARD))
        
        var magnitudesOut = [Float](repeating: 0.0, count: powerOfTwoCount / 2)
        vDSP_zvmags(&splitComplex, 1, &magnitudesOut, 1, vDSP_Length(powerOfTwoCount / 2))
        
        vDSP_destroy_fftsetup(fftSetup)
        
        // Ignore DC offset (0 Hz) by setting it to 0
        magnitudesOut[0] = 0.0
        
        var maxMag: Float = 0.0
        var maxIndex: vDSP_Length = 0
        vDSP_maxvi(&magnitudesOut, 1, &maxMag, &maxIndex, vDSP_Length(powerOfTwoCount / 2))
        
        let freq = Double(maxIndex) * sampleRate / Double(powerOfTwoCount)
        return freq
    }
}

struct SessionDetailView: View {
    let session: RecordingSession
    let fileURL: URL
    
    @StateObject private var viewModel = SessionDetailViewModel()
    @State private var selectedChartMode = "Magnitude"
    let chartModes = ["Magnitude", "X Axis", "Y Axis", "Z Axis"]
    
    var body: some View {
        ScrollView {
            if viewModel.isLoading {
                ProgressView("Analyzing Vibration Data...")
                    .padding(50)
            } else {
                VStack(spacing: 20) {
                    // 1. SUMMARY METRICS
                    HStack {
                        MetricCard(title: "PEAK MAG", value: session.peakG, color: colorForG(session.peakG))
                        MetricCard(title: "RMS G", value: session.rmsG, color: colorForG(session.rmsG))
                    }.padding(.horizontal)
                    
                    HStack {
                        MiniMetric(title: "Peak X", value: viewModel.peakX)
                        MiniMetric(title: "Peak Y", value: viewModel.peakY)
                        MiniMetric(title: "Peak Z", value: viewModel.peakZ)
                    }.padding(.horizontal)
                    
                    // 2. ENGINE HARMONICS
                    VStack(alignment: .leading) {
                        Text("Engine Harmonics Estimate")
                            .font(.headline)
                        HStack {
                            VStack(alignment: .leading) {
                                Text("\(viewModel.dominantFrequency, specifier: "%.1f") Hz")
                                    .font(.system(size: 28, weight: .bold, design: .rounded))
                                    .foregroundColor(.blue)
                                Text("Dominant Frequency")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            VStack(alignment: .trailing) {
                                Text("\(viewModel.estimatedRPM, specifier: "%.0f") RPM")
                                    .font(.system(size: 28, weight: .bold, design: .rounded))
                                    .foregroundColor(.purple)
                                Text("Est. Engine RPM")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .padding()
                    .background(Color(.secondarySystemBackground))
                    .cornerRadius(15)
                    .padding(.horizontal)
                    
                    // 3. SEVERITY BREAKDOWN
                    VStack(alignment: .leading) {
                        Text("Vibration Severity Breakdown")
                            .font(.headline)
                        GeometryReader { geometry in
                            HStack(spacing: 0) {
                                if viewModel.timeGreen > 0 {
                                    Rectangle().fill(Color.green).frame(width: geometry.size.width * CGFloat(viewModel.timeGreen / 100))
                                }
                                if viewModel.timeYellow > 0 {
                                    Rectangle().fill(Color.yellow).frame(width: geometry.size.width * CGFloat(viewModel.timeYellow / 100))
                                }
                                if viewModel.timeRed > 0 {
                                    Rectangle().fill(Color.red).frame(width: geometry.size.width * CGFloat(viewModel.timeRed / 100))
                                }
                            }
                        }
                        .frame(height: 20)
                        .cornerRadius(10)
                        
                        HStack {
                            Text("Safe: \(viewModel.timeGreen, specifier: "%.1f")%").foregroundColor(.green)
                            Spacer()
                            Text("Warn: \(viewModel.timeYellow, specifier: "%.1f")%").foregroundColor(.yellow)
                            Spacer()
                            Text("Danger: \(viewModel.timeRed, specifier: "%.1f")%").foregroundColor(.red)
                        }.font(.caption).bold()
                    }
                    .padding()
                    .background(Color(.secondarySystemBackground))
                    .cornerRadius(15)
                    .padding(.horizontal)
                    
                    // 4. CHART
                    VStack(alignment: .leading) {
                        HStack {
                            Text("Timeline")
                                .font(.headline)
                            Spacer()
                            Picker("Axis", selection: $selectedChartMode) {
                                ForEach(chartModes, id: \.self) {
                                    Text($0)
                                }
                            }
                            .pickerStyle(MenuPickerStyle())
                        }
                        
                        Chart(viewModel.chartData) { point in
                            LineMark(
                                x: .value("Time (s)", point.time),
                                y: .value("G-Force", valueForMode(point))
                            )
                            .foregroundStyle(colorForMode())
                            .interpolationMethod(.catmullRom)
                        }
                        .frame(height: 250)
                    }
                    .padding()
                    .background(Color(.secondarySystemBackground))
                    .cornerRadius(15)
                    .padding(.horizontal)
                    
                    Spacer(minLength: 40)
                }
            }
        }
        .navigationTitle("Session Details")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            viewModel.loadData(fileURL: fileURL, sessionDuration: session.duration)
        }
    }
    
    private func valueForMode(_ point: ChartDataPoint) -> Double {
        switch selectedChartMode {
        case "X Axis": return point.x
        case "Y Axis": return point.y
        case "Z Axis": return point.z
        default: return point.magnitude
        }
    }
    
    private func colorForMode() -> Color {
        switch selectedChartMode {
        case "X Axis": return .red
        case "Y Axis": return .green
        case "Z Axis": return .blue
        default: return .orange
        }
    }
    
    func colorForG(_ g: Double) -> Color {
        switch g {
        case 0..<1.5: return .green
        case 1.5..<3.0: return .yellow
        case 3.0..<5.0: return .orange
        default: return .red
        }
    }
}

struct MiniMetric: View {
    let title: String
    let value: Double
    
    var body: some View {
        VStack {
            Text(title)
                .font(.caption2)
                .foregroundColor(.secondary)
            Text(String(format: "%.1fg", value))
                .font(.headline)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(Color(.secondarySystemBackground))
        .cornerRadius(10)
    }
}
