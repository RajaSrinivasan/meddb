# Sample recordings

Download scripts place open clinical files under this tree and check them against the
`SHA256SUMS` files committed here. The recordings themselves are gitignored.

| Directory | Script | Files |
| --- | --- | --- |
| `data/wfdb/` | `scripts/download_wfdb.sh` | MIT-BIH `100` and PTB-XL `00001_hr` |
| `data/edf/` | `scripts/download_edf.sh` | Sleep-EDF PSG + hypnogram, CHB-MIT `chb01_01`, Biosemi-Muse `0dfc2c2cf4_eyesclosed.bdf` |
| `data/mat/` | `scripts/download_mat.sh` | Challenge 2021 `A0001` and `HR00001` (`.mat` and `.hea`) |
| `data/hdf5/` | `scripts/download_hdf5.sh` | HeartCycle `CH07_59146237_s0000029.h5`, BUT CGM `124001_2124-04-05_ECG.h5` |

`download_edf.sh --quick` skips CHB-MIT and the BDF file. `download_hdf5.sh --quick` skips the 24-hour BUT CGM recording. Both still verify the checksums of the files they download.
