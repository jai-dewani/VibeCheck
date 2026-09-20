import SwiftUI

struct ShareSheet: UIViewControllerRepresentable {
    var activityItems: [Any]
    
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }
    
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

struct ContentView: View {
    @StateObject private var motionManager = MotionManager()
    @State private var shareURL: URL?
    @State private var showingShareSheet = false
    
    var body: some View {
        NavigationView {
            VStack {
                // Metrics
                HStack(spacing: 20) {
                    MetricCard(title: "PEAK G", value: motionManager.peakG, color: colorForG(motionManager.peakG))
                    MetricCard(title: "RMS G", value: motionManager.rmsG, color: colorForG(motionManager.rmsG))
                }
                .padding()
                
                // Live Readout
                VStack(spacing: 8) {
                    Text("LIVE G-FORCE")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    if let sample = motionManager.currentSample {
                        Text("\(sample.magnitude, specifier: "%.2f")g")
                            .font(.system(size: 64, weight: .black, design: .rounded))
                            .foregroundColor(colorForG(sample.magnitude))
                        
                        HStack(spacing: 15) {
                            Text("X: \(sample.x, specifier: "%.2f")")
                            Text("Y: \(sample.y, specifier: "%.2f")")
                            Text("Z: \(sample.z, specifier: "%.2f")")
                        }
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(.secondary)
                    } else {
                        Text("0.00g")
                            .font(.system(size: 64, weight: .black, design: .rounded))
                            .foregroundColor(.secondary.opacity(0.3))
                        Text("Waiting for data...")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .padding()
                .frame(maxWidth: .infinity)
                .background(Color(.secondarySystemBackground))
                .cornerRadius(15)
                .padding(.horizontal)
                
                // Stats
                VStack(spacing: 5) {
                    Text("Samples: \(motionManager.sampleCount)")
                    Text("Duration: \(timeString(time: motionManager.elapsedTime))")
                    let sizeEstimate = Double(motionManager.sampleCount) * 45.0 / 1024.0 / 1024.0
                    Text(String(format: "Est. file: %.2f MB", sizeEstimate))
                }
                .font(.subheadline)
                .foregroundColor(.secondary)
                .padding()
                
                // Record Button
                Button(action: {
                    if motionManager.isRecording {
                        motionManager.stopRecording()
                        UIApplication.shared.isIdleTimerDisabled = false
                    } else {
                        UIApplication.shared.isIdleTimerDisabled = true
                        motionManager.startRecording()
                    }
                }) {
                    HStack {
                        Image(systemName: motionManager.isRecording ? "square.fill" : "circle.fill")
                        Text(motionManager.isRecording ? "STOP RECORDING" : "START RECORDING")
                            .fontWeight(.bold)
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(motionManager.isRecording ? Color.red : Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(15)
                }
                .padding(.horizontal)
                
                Divider().padding(.vertical)
                
                // Session List
                VStack(alignment: .leading) {
                    Text("Past Sessions")
                        .font(.headline)
                        .padding(.horizontal)
                    
                    List {
                        ForEach(motionManager.sessions) { session in
                            NavigationLink(destination: SessionDetailView(session: session, fileURL: motionManager.exportURL(for: session))) {
                                HStack {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(dateString(date: session.startTime))
                                            .font(.subheadline)
                                            .bold()
                                        Text("\(timeString(time: session.duration)) · Peak \(String(format: "%.1f", session.peakG))g")
                                            .font(.caption)
                                        Text("\(session.sampleCount) samples")
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                    }
                                    Spacer()
                                    Button(action: {
                                        shareURL = motionManager.exportURL(for: session)
                                        showingShareSheet = true
                                    }) {
                                        Image(systemName: "square.and.arrow.up")
                                            .foregroundColor(.blue)
                                            .padding()
                                    }
                                    .buttonStyle(BorderlessButtonStyle())
                                }
                            }
                        }
                        .onDelete(perform: deleteSession)
                    }
                    .listStyle(PlainListStyle())
                }
                
                Spacer()
            }
            .navigationTitle("🏍️ VibeCheck")
            .sheet(isPresented: $showingShareSheet, onDismiss: { shareURL = nil }) {
                if let url = shareURL {
                    ShareSheet(activityItems: [url])
                }
            }
        }
    }
    
    private func deleteSession(at offsets: IndexSet) {
        for index in offsets {
            let session = motionManager.sessions[index]
            motionManager.deleteSession(session)
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
    
    private func timeString(time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
    
    private func dateString(date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

// Extracted MetricCard for reuse
struct MetricCard: View {
    let title: String
    let value: Double
    let color: Color
    
    var body: some View {
        VStack {
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
            Text(String(format: "%.2fg", value))
                .font(.system(size: 32, weight: .bold, design: .rounded))
                .foregroundColor(color)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(15)
    }
}
