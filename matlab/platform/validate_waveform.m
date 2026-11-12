function validate_waveform(x, fs, cfg)
assert(isnumeric(x) && isvector(x) && ~isempty(x) && isreal(x) && all(isfinite(x(:))), ...
    '发射波形必须是非空、有限实数向量。');
assert(isscalar(fs) && isfinite(fs) && fs == cfg.fsPassband && fs == 1e6, '硬件通带采样率必须是 1 MHz。');
assert(numel(x) <= cfg.txMaxSamples, '发射波形超过硬件 10 秒限制。');
assert(any(x(:) ~= 0), '发射波形不能全为零。');
end
