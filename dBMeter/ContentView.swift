//
//  ContentView.swift
//  dBMeter
//
//  Created by Sam Glover on 3/13/26.
//

import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var audioMeter: AudioMeter

    private var yellowThresholdBinding: Binding<Double> {
        Binding(
            get: { Double(audioMeter.yellowThreshold) },
            set: { audioMeter.setYellowThreshold($0) }
        )
    }

    private var redThresholdBinding: Binding<Double> {
        Binding(
            get: { Double(audioMeter.redThreshold) },
            set: { audioMeter.setRedThreshold($0) }
        )
    }

    private var isRunningBinding: Binding<Bool> {
        Binding(
            get: { audioMeter.isRunning },
            set: { newValue in
                guard newValue != audioMeter.isRunning else { return }
                audioMeter.toggleRunning()
            }
        )
    }

    private var meterTintColor: Color {
        switch audioMeter.alertLevel {
        case .red:
            return .red
        case .yellow:
            return .yellow
        case .none:
            return .accentColor
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Text("dB Meter").bold()
                
                Spacer()
                
                Toggle("Start/stop", isOn: isRunningBinding)
                    .toggleStyle(.switch)
                    .labelsHidden()
            }
            
            Picker(selection: Binding(
                get: { audioMeter.selectedInputID },
                set: { audioMeter.setSelectedInput(id: $0) }
            )) {
                ForEach(audioMeter.availableInputs) { input in
                    Text(input.name)
                }
            } label: {
                Text("Input device")
            }

            Text("Active input: \(audioMeter.activeInputName)")
                .font(.caption)
                .foregroundStyle(.secondary)

            Divider()
            
            Text(audioMeter.readout)
                .font(.system(size: 28, weight: .semibold, design: .rounded))
                .monospacedDigit()

            Text(audioMeter.measurementLabel)
                .font(.caption)
                .foregroundStyle(.secondary)

            ProgressView(value: audioMeter.normalizedLevel)
                .progressViewStyle(.linear)
                .tint(meterTintColor)

            Text(audioMeter.estimatedSPLReadout)
                .font(.caption)
                .foregroundStyle(.secondary)

            Text(audioMeter.gainMetadataReadout)
                .font(.caption2)
                .foregroundStyle(.secondary)
            
            Divider()

            Text("Metering")

            HStack {
                VStack(alignment: .leading) {
                    Text("Weighting")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Picker("Weighting", selection: $audioMeter.weighting) {
                        ForEach(AudioMeter.FrequencyWeighting.allCases) { option in
                            Text(option.rawValue).tag(option)
                        }
                    }
                    .pickerStyle(.segmented)
//                    .frame(width: 120)
                    .labelsHidden()
                }
                
                Spacer()
                
                VStack(alignment: .leading) {
                    Text("Integration")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Picker("Integration", selection: $audioMeter.integrationPreset) {
                        ForEach(AudioMeter.IntegrationPreset.allCases) { option in
                            Text(option.rawValue).tag(option)
                        }
                    }
                    .pickerStyle(.segmented)
//                    .frame(width: 120)
                    .labelsHidden()
                }
            }

            Divider()

            HStack {
                Text("Smoothing")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(audioMeter.smoothingPercent)%")
                    .font(.caption.monospacedDigit())
            }

            Slider(value: $audioMeter.smoothing, in: 0.0...0.95)

            Divider()

            Text("Thresholds")
            
            HStack {
                VStack(alignment: .leading) {
                    Text("Yellow")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Stepper(
                        value: yellowThresholdBinding,
                        in: 40.0...110.0,
                        step: 1.0
                    ) {
                        Text(audioMeter.yellowThresholdReadout)
                            .monospacedDigit()
                    }
                }

                Spacer()

                VStack(alignment: .leading) {
                    Text("Red")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Stepper(
                        value: redThresholdBinding,
                        in: 41.0...120.0,
                        step: 1.0
                    ) {
                        Text(audioMeter.redThresholdReadout)
                            .monospacedDigit()
                    }
                }
            }

            Divider()

            Button("Quit") {
                NSApp.terminate(nil)
            }
        }
        .padding(10)
        .frame(width: 260)
        .onAppear {
            audioMeter.refreshInputDevices()
            audioMeter.startIfNeeded()
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(AudioMeter())
}
