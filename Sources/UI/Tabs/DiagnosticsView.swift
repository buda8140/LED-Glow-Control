import SwiftUI

struct DiagnosticsView: View {
    @EnvironmentObject var btManager: BluetoothManager
    @State private var rawHex = ""
    @State private var logs: [String] = []
    
    var body: some View {
        ZStack {
            Theme.background()
            
            VStack(spacing: 20) {
                HStack {
                    Text(NSLocalizedString("DIAGNOSTICS", comment: ""))
                        .premiumTitle()
                    Spacer()
                    Button(NSLocalizedString("RESET", comment: "")) {
                        logs.removeAll()
                    }
                    .font(.caption.bold())
                    .foregroundColor(Theme.secondaryNeon)
                }
                .padding(.horizontal, 25)
                .padding(.top, 40)
                
                // Real-time Logs
                GlassCard {
                    ScrollViewReader { proxy in
                        ScrollView {
                            VStack(alignment: .leading, spacing: 10) {
                                ForEach(logs.indices, id: \.self) { i in
                                    Text(logs[i])
                                        .font(.system(.caption2, design: .monospaced))
                                        .foregroundColor(logs[i].contains("TX") ? Theme.primaryNeon : .white)
                                        .id(i)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(height: 300)
                        .onChange(of: logs.count) { _ in
                            withAnimation { proxy.scrollTo(logs.count - 1) }
                        }
                    }
                }
                .padding(.horizontal)
                
                // Raw Sender
                GlassCard {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("RAW HEX SENDER")
                            .font(.caption2.bold())
                            .foregroundColor(.white.opacity(0.4))
                        
                        HStack {
                            TextField("7E 04 04 01 ...", text: $rawHex)
                                .font(.system(.body, design: .monospaced))
                                .padding(12)
                                .background(Color.white.opacity(0.05))
                                .cornerRadius(12)
                            
                            Button(action: sendRaw) {
                                Image(systemName: "paperplane.fill")
                                    .font(.title3)
                                    .foregroundColor(.black)
                                    .padding(12)
                                    .background(Theme.primaryNeon)
                                    .clipShape(Circle())
                            }
                        }
                    }
                }
                .padding(.horizontal)
                
                // Device Info
                GlassCard {
                    VStack(spacing: 12) {
                        InfoRow(label: "Peripheral", value: btManager.connectedPeripheral?.name ?? "N/A")
                        InfoRow(label: "Identifier", value: btManager.connectedPeripheral?.identifier.uuidString.prefix(12).appending("...") ?? "N/A")
                        InfoRow(label: "Status", value: btManager.connectionStatus)
                    }
                }
                .padding(.horizontal)
                
                Spacer()
            }
        }
        .onAppear {
            setupLogging()
        }
    }
    
    private func setupLogging() {
        // In a real app, we'd hook into the actual write calls.
        // For this demo, we'll simulate the bridge.
        if logs.isEmpty {
            logs.append("[SYSTEM] Logger initialized")
        }
    }
    
    private func sendRaw() {
        let hex = rawHex.replacingOccurrences(of: " ", with: "")
        guard let data = hex.hexData() else { return }
        
        // This would require a bypass in BluetoothManager, but we'll simulate for now
        logs.append("TX: \(hex.uppercased())")
        rawHex = ""
        Haptics.play(.medium)
    }
}

extension String {
    func hexData() -> Data? {
        var data = Data(capacity: self.count / 2)
        let regex = try! NSRegularExpression(pattern: "[0-9a-f]{1,2}", options: .caseInsensitive)
        regex.enumerateMatches(in: self, range: NSRange(location: 0, length: self.count)) { match, _, _ in
            let byteString = (self as NSString).substring(with: match!.range)
            let num = UInt8(byteString, radix: 16)!
            data.append(num)
        }
        return data
    }
}
