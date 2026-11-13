# MATLAB-FPGA Communication Testbed

English | [中文](README_zh.md)

This testbed helps engineers and students who develop communication algorithms in MATLAB evaluate them over real-world channels. MATLAB controls FPGA-based hardware to transmit and capture waveforms, so users can test their MATLAB algorithms without first reimplementing every algorithm in Verilog. This is especially useful for AI-based communication methods, which can be difficult to implement directly on an FPGA.

The FPGA provides the hardware interface for waveform transmission and acquisition; modulation, synchronization, decoding, AI inference, and performance analysis can remain in the user's MATLAB workflow. An algorithm must still produce a real passband waveform compatible with the hardware and process the received samples.

## How it works

```text
MATLAB algorithm → TCP → FPGA transmitter → DAC → real channel
MATLAB algorithm ← TCP ← FPGA receiver    ← ADC ← real channel
```

MATLAB prepares a waveform and sends it to the transmitter. The transmitter adds hardware synchronization signals and guard intervals. The receiver captures the signal and sends samples back to MATLAB for processing.

## Current reference configuration

- PYNQ-Z2-based transmitter and receiver with external DAC and ADC modules.
- Passband sampling rate: **1 MHz**; current receive filter target band: **20–30 kHz**.
- Current experiments: single-frame tests around **25 kHz**, including underwater acoustic channels.
- Built-in MATLAB examples: FSK and OFDM; an example interface is provided for user algorithms.
- Original development tools: **Vivado/Vitis 2026.1**. MATLAB release and toolbox requirements should be checked against the [MATLAB user guide](matlab/README.md).

Other frequency bands, bandwidths, boards, and analog front ends require appropriate hardware and configuration changes and independent validation. The current project is a release candidate; clean reconstruction and third-party licensing still require review.

## Repository layout

```text
matlab/          MATLAB platform, algorithms, and user guide
hardware/tx/     FPGA transmitter project, RTL, and constraints
hardware/rx/     FPGA receiver project, RTL, and constraints
hardware/ip_repo/ Custom FPGA control IP
firmware/tx/     Transmitter PS application sources
firmware/rx/     Receiver PS application sources
docs/            Release checklist and supporting documentation
third_party/     Local lwIP repository package and installation notes, if present
```

## Single-frame test

See the [MATLAB user guide](matlab/README.md) for hardware setup, network settings, and algorithm interfaces. In two MATLAB sessions:

1. Select the algorithm and run `prepare_tx_frame` in the transmit session.
2. Run `run_rx` in the receive session and wait until it reports ready.
3. Run `run_tx` in the transmit session; inspect the captured waveform and algorithm results.

Keep both sessions' configurations consistent. Generated MAT files can be overwritten by later tests. TX and RX PS sources are provided, but a complete from-scratch Vitis platform and BSP reconstruction procedure still needs verification.

## Current limitations

The reference receiver uses a fixed hardware capture scheme and filter; the physical frame includes FPGA-added LFM signals and guard intervals. Output voltage depends on the DAC, analog circuitry, load, and calibration. The maximum supported capture and transmit lengths, startup recovery, and supported tool versions must be checked for the selected hardware configuration.

Review the [release checklist](docs/RELEASE_CHECKLIST.md) and third-party notices and licenses before public redistribution.

## License

Project-owned contributions are available under the [MIT License](LICENSE). Third-party files retain their own terms; see [Third-party notices](THIRD_PARTY_NOTICES.md).
