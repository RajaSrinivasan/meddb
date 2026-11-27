# meddb

Ada toolkit for reading clinical waveform files, plus a shared Julia plotter that writes self-contained HTML.

Phase 0–2 covers the shared model and the formats that have open PhysioNet samples: WFDB, EDF/EDF+/BDF, MATLAB `.mat`, and HDF5.

## Layout

| Path | Role |
| --- | --- |
| `crates/meddb_common` | Recording metadata, channels, samples, annotations, CSV + JSON export |
| `crates/meddb_wfdb` | Binding to `libwfdb` |
| `crates/meddb_edf` | Binding to EDFlib (EDF, EDF+, BDF, BDF+) |
| `crates/meddb_mat` | Binding to `libmatio`, plus a WFDB `.hea` reader for companion headers |
| `crates/meddb_hdf5` | Binding to `libhdf5`, with HeartCycle and BUT CGM loaders |
| `tools/meddb-*` | CLIs: `meddb-wfdb`, `meddb-edf`, `meddb-mat`, `meddb-hdf5` |
| `julia/` | `MeddbPlots` HTML plotter |
| `scripts/download_*.sh` | Pinned sample downloads and SHA-256 checks |
| `data/` | Gitignored recordings. Checksums and this README's sibling `data/README.md` are tracked |

Each CLI prints header metadata, channel labels, sampling rates, a short sample window, and annotations. `--export PREFIX` writes `PREFIX.csv` and `PREFIX.json` for the plotter. Without `--duration` or `--full`, the tools load a 30 second window. Channels faster than 2000 Hz are listed but not loaded unless you pass `--duration` or `--full`, so a HeartCycle file that mixes 200 Hz ECG with 44.1 kHz PCG stays interactive by default.

## Build

Ubuntu packages: `gnat`, `gprbuild`, `libhdf5-dev`, `libmatio-dev`, `pkg-config`, `curl`, `make`. Julia 1.10+ is used for plots.

```bash
./scripts/bootstrap_deps.sh    # libwfdb 10.7.0 and EDFlib into /usr/local
alr toolchain --select gnat_external
alr toolchain --select gprbuild=18.0
alr build                      # or: gprbuild -p -P meddb.gpr
```

Binaries land in `bin/`.

## Samples and plots

```bash
./scripts/download_wfdb.sh
./scripts/download_edf.sh
./scripts/download_mat.sh
./scripts/download_hdf5.sh

bin/meddb-wfdb data/wfdb/mitdb/100 --duration 30 --export /tmp/mitdb100
julia --project=julia -e 'using Pkg; Pkg.instantiate()'
julia --project=julia julia/scripts/plot_wfdb.jl data/wfdb/mitdb/100 out/mitdb100.html
julia --project=julia julia/scripts/plot_edf.jl data/edf/sleep-edfx/SC4001E0-PSG.edf out/psg.html
julia --project=julia julia/scripts/plot_mat.jl data/mat/cpsc/A0001.mat out/A0001.html
julia --project=julia julia/scripts/plot_hdf5.jl data/hdf5/but-cgm/124001_2124-04-05_ECG.h5 out/but.html
julia --project=julia julia/scripts/plot_synthetic.jl out/synthetic.html
```

`plot_edf.jl` pairs `SC4001E0-PSG.edf` with `SC4001EC-Hypnogram.edf` when that file sits beside it. Open the HTML file in a browser: drag to pan, scroll to zoom, use the channel checkboxes and the overview strip. Long series are min/max decimated until the visible window is short enough to draw every embedded sample.

Issue #2 also mentions one MIMIC-IV-ECG record. That dataset has no single pinned path in the issue, so the WFDB download script stays with MIT-BIH record 100 and PTB-XL `00001_hr`.

## Tests

```bash
./bin/test_common
./tests/smoke.sh
```

`test_common` checks CSV/JSON export, `.hea` parsing, and the default sample window. `tests/smoke.sh` runs those checks and, when the sample files are present, the four CLIs.
