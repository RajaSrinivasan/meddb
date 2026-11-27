# meddb

Ada toolkit for reading clinical waveform files, plus a shared Julia plotter that writes self-contained HTML.

Phase 0–2 covers the shared model and the formats that have open PhysioNet samples: WFDB, EDF/EDF+/BDF, MATLAB `.mat`, and HDF5. Phase 3 adds SCP-ECG and HL7 aECG through libbiosig.

DICOM Waveform (issue #6) was descoped and is not implemented. There is no `meddb_dicom` crate.

## Layout

| Path | Role |
| --- | --- |
| `crates/meddb_common` | Recording metadata, channels, samples, annotations, CSV + JSON export |
| `crates/meddb_wfdb` | Binding to `libwfdb` |
| `crates/meddb_edf` | Binding to EDFlib (EDF, EDF+, BDF, BDF+) |
| `crates/meddb_mat` | Binding to `libmatio`, plus a WFDB `.hea` reader for companion headers |
| `crates/meddb_hdf5` | Binding to `libhdf5`, with HeartCycle and BUT CGM loaders |
| `crates/meddb_biosig` | Shared binding to `libbiosig` |
| `crates/meddb_scp` | SCP-ECG reader (OpenECG Hannover and the WFDB `test.scp` fixture) |
| `crates/meddb_aecg` | HL7 aECG reader. Waveforms come from libbiosig; annotation regions are read from the XML with libxml2 |
| `tools/meddb-*` | CLIs: `meddb-wfdb`, `meddb-edf`, `meddb-mat`, `meddb-hdf5`, `meddb-scp`, `meddb-aecg` |
| `julia/` | `MeddbPlots` HTML plotter |
| `scripts/download_*.sh` | Pinned sample downloads and SHA-256 checks |
| `data/` | Gitignored recordings. Checksums and this README's sibling `data/README.md` are tracked |

Each CLI prints header metadata, channel labels, sampling rates, a short sample window, and annotations. `--export PREFIX` writes `PREFIX.csv` and `PREFIX.json` for the plotter. Without `--duration` or `--full`, the tools load a 30 second window. Channels faster than 2000 Hz are listed but not loaded unless you pass `--duration` or `--full`, so a HeartCycle file that mixes 200 Hz ECG with 44.1 kHz PCG stays interactive by default.

## Build

Ubuntu packages: `gnat`, `gprbuild`, `libhdf5-dev`, `libmatio-dev`, `libbiosig-dev`, `libxml2-dev`, `pkg-config`, `curl`, `make`, `unzip`. Julia 1.10+ is used for plots. `bootstrap_deps.sh` installs `libbiosig-dev` and `libxml2-dev` with `sudo` when they are missing and the current user is not root.

```bash
./scripts/bootstrap_deps.sh    # libwfdb 10.7.0, EDFlib, and libbiosig
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
./scripts/download_scp.sh
./scripts/download_aecg.sh

bin/meddb-wfdb data/wfdb/mitdb/100 --duration 30 --export /tmp/mitdb100
julia --project=julia -e 'using Pkg; Pkg.instantiate()'
julia --project=julia julia/scripts/plot_wfdb.jl data/wfdb/mitdb/100 out/mitdb100.html
julia --project=julia julia/scripts/plot_edf.jl data/edf/sleep-edfx/SC4001E0-PSG.edf out/psg.html
julia --project=julia julia/scripts/plot_mat.jl data/mat/cpsc/A0001.mat out/A0001.html
julia --project=julia julia/scripts/plot_hdf5.jl data/hdf5/but-cgm/124001_2124-04-05_ECG.h5 out/but.html
julia --project=julia julia/scripts/plot_scp.jl data/scp/hannover/PFE105.scp out/pfe105.html
julia --project=julia julia/scripts/plot_aecg.jl data/aecg/Example-aECG.xml out/aecg.html
julia --project=julia julia/scripts/plot_synthetic.jl out/synthetic.html
```

`meddb-scp` reads SCP-ECG. The OpenECG archive contains 12 Hannover clinical records in two encodings. `data/scp/hannover/` is the redundancy-reduced set. libbiosig 3.0.2 (Ubuntu 24.04 `libbiosig-dev`) decodes those waveforms and the section 8 diagnostic text. `data/scp/hannover-high/` keeps the high-compression copies: the header and diagnostic text open, but the rhythm samples from that encoding are not usable. `data/scp/test.scp` is the WFDB 10.7.0 fixture. PTB-XL is not an SCP-ECG waveform corpus: its SCP codes live in CSV metadata.

`meddb-aecg` reads HL7 aECG XML. No public real clinical aECG corpus was available as of 26 Nov 2026. `data/aecg/Example-aECG.xml` is the official HL7 2003-12 schema fixture, used to test the parser. The CLI prints that limitation. Waveform samples come from libbiosig. Annotation regions (rhythm, P/QRS/T intervals, and lead-specific regions) are read from the XML so the plot can draw them. Representative-beat annotations from the derived series are printed as comments rather than overlaid on the 10 s rhythm strip.

`plot_edf.jl` pairs `SC4001E0-PSG.edf` with `SC4001EC-Hypnogram.edf` when that file sits beside it. Open the HTML file in a browser: drag to pan, scroll to zoom, use the channel checkboxes and the overview strip. Long series are min/max decimated until the visible window is short enough to draw every embedded sample.

Issue #2 also mentions one MIMIC-IV-ECG record. That dataset has no single pinned path in the issue, so the WFDB download script stays with MIT-BIH record 100 and PTB-XL `00001_hr`.

## Tests

```bash
./bin/test_common
./tests/smoke.sh
```

`test_common` checks CSV/JSON export, `.hea` parsing, and the default sample window. `tests/smoke.sh` runs those checks and, when the sample files are present, each CLI, including a Hannover SCP-ECG record, `test.scp`, and the HL7 aECG example.
