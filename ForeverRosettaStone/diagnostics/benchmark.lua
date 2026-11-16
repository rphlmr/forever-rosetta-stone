local _, Addon = ...

-- Keep sampling call sites inert in release builds. The local development module replaces these.
function Addon:BeginBenchmarkSample() end
function Addon:EndBenchmarkSample() end
function Addon:StopBenchmark() end
