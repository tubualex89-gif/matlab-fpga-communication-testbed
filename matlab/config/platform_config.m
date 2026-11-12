function cfg = platform_config()
cfg.algorithm = 'ofdm_pilot_interp'; % ofdm_lts_pilot / ofdm_pilot_interp / fsk_noncoherent
cfg.fsPassband = 1e6;
cfg.txIp = '192.168.1.10'; cfg.txPort = 6001;
cfg.rxIp = '192.168.2.10'; cfg.rxPort = 6002;
cfg.corrThreshold = 0.20; cfg.corrMinEnergy = 100000;
cfg.txMaxSamples = 10000000; cfg.rxMaxSamples = 12000000;
cfg.targetVpp = 1.8; cfg.dacFullScaleVpp = 8.0; cfg.calibrationFactor = 1.8/2.3;
cfg.txTimeout = 90; cfg.rxIdleTimeout = 120; cfg.chunkBytes = 32768;
cfg.plotTx = false; cfg.plotRx = false;
end
