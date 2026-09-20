import SwiftUI
import Charts
import Combine

import Accelerate

struct ChartDataPoint: Identifiable {
    let id = UUID()
    let time: Double
    let date: Date
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
    
    func loadData(fileURL: URL, sessionDuration: TimeInterval, startTime: Date) {
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
                        let pointDate = startTime.addingTimeInterval(currentBucketTime)
                        downsampled.append(ChartDataPoint(time: currentBucketTime, date: pointDate, magnitude: currentBucketMag, x: currentBucketX, y: currentBucketY, z: currentBucketZ))
                        currentBucketMag = 0; currentBucketX = 0; currentBucketY = 0; currentBucketZ = 0; bucketCount = 0
                    }
                }
            }
            
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
                
                self.chartData = downsampled
                self.isLoading = false
            }
        }
    }
}

struct SessionDetailView: View {
    let session: RecordingSession
    let fileURL: URL
    
    @StateObject private var viewModel = SessionDetailViewModel()
    @State private var selectedChartModes: Set<String> = ["Magnitude"]
    @State private var xVisibleDomain: TimeInterval = 0
    @State private var initialVisibleDomain: TimeInterval = 0
    
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
                            // Zoom hint
                            Text("Pinch to zoom")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            Menu {
                                ForEach(chartModes, id: \.self) { mode in
                                    Button(action: {
                                        if selectedChartModes.contains(mode) {
                                            if selectedChartModes.count > 1 {
                                                selectedChartModes.remove(mode)
                                            }
                                        } else {
                                            selectedChartModes.insert(mode)
                                        }
                                    }) {
                                        HStack {
                                            Text(mode)
                                            if selectedChartModes.contains(mode) {
                                                Image(systemName: "checkmark")
                                            }
                                        }
                                    }
                                }
                            } label: {
                                HStack {
                                    Text("Axes")
                                    Image(systemName: "chevron.down")
                                }
                            }
                        }

                        Chart(viewModel.chartData) { point in
                            ForEach(Array(selectedChartModes), id: \.self) { mode in
                                LineMark(
                                    x: .value("Time", point.time),
                                    y: .value("Value", valueForMode(point, mode: mode))
                                )
                                .foregroundStyle(by: .value("Axis", mode))
                                .interpolationMethod(.catmullRom)
                            }
                        }
                        .chartForegroundStyleScale([
                            "Magnitude": .orange,
                            "X Axis": .red,
                            "Y Axis": .green,
                            "Z Axis": .blue
                        ])
                        // Pin the full data range so 0 is always the left edge
                        .chartXScale(domain: 0...max(session.duration, 1.0))
                        // MM:SS labels on x-axis
                        .chartXAxis {
                            AxisMarks(values: .automatic(desiredCount: 6)) { value in
                                if let seconds = value.as(Double.self) {
                                    let mins = Int(seconds) / 60
                                    let secs = Int(seconds) % 60
                                    AxisValueLabel {
                                        Text(String(format: "%02d:%02d", mins, secs))
                                            .font(.caption2)
                                    }
                                }
                                AxisGridLine()
                                AxisTick()
                            }
                        }
                        .chartScrollableAxes(.horizontal)
                        .chartXVisibleDomain(length: xVisibleDomain > 0 ? xVisibleDomain : max(session.duration, 1.0))
                        .frame(height: 250)
                    }
                    .padding()
                    .background(Color(.secondarySystemBackground))
                    .cornerRadius(15)
                    .padding(.horizontal)
                    // Gesture on the whole card (not just chart frame) for a large hit area.
                    // simultaneousGesture lets the outer ScrollView still scroll vertically.
                    .simultaneousGesture(
                        MagnificationGesture()
                            .onChanged { value in
                                let base = initialVisibleDomain > 0 ? initialVisibleDomain : max(session.duration, 1.0)
                                let maxDomain = max(session.duration, 1.0)
                                let newDomain = base / value.magnitude
                                xVisibleDomain = max(5.0, min(maxDomain, newDomain))
                            }
                            .onEnded { _ in
                                initialVisibleDomain = xVisibleDomain
                            }
                    )
                    
                    Spacer(minLength: 40)
                }
            }
        }
        .navigationTitle("Session Details")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            let fullDomain = max(session.duration, 1.0)
            xVisibleDomain = fullDomain
            initialVisibleDomain = fullDomain
            viewModel.loadData(fileURL: fileURL, sessionDuration: session.duration, startTime: session.startTime)
        }
    }
    
    private func valueForMode(_ point: ChartDataPoint, mode: String) -> Double {
        switch mode {
        case "X Axis": return point.x
        case "Y Axis": return point.y
        case "Z Axis": return point.z
        default: return point.magnitude
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
