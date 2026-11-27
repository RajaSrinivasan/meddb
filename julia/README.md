# MeddbPlots

Julia helpers that turn a meddb CSV + JSON export into a self-contained HTML plot.

The page uses Plotly.js (the same library PlotlyJS.jl drives) inlined into the file, so it opens in any browser without a running Julia session. PlotlyJS.jl's precompilation pulls in a display stack that is unnecessary for a static file, so `MeddbPlots` writes the HTML directly and still exercises every interactive behavior the plot needs:

- pan and wheel zoom
- channel checkboxes
- an overview strip plus 5 s / 10 s / 30 s / all window buttons
- annotation diamonds and duration bands
- min/max decimation, with the visible window redrawn from the embedded samples (full resolution once the window is short enough)

## Commands

From the repository root, after `alr build` or `gprbuild -P meddb.gpr`:

```bash
julia --project=julia -e 'using Pkg; Pkg.instantiate()'
julia --project=julia julia/scripts/plot_synthetic.jl out/synthetic.html
julia --project=julia julia/scripts/plot_wfdb.jl data/wfdb/mitdb/100 out/mitdb100.html
julia --project=julia julia/scripts/plot_edf.jl data/edf/sleep-edfx/SC4001E0-PSG.edf out/psg.html
julia --project=julia julia/scripts/plot_mat.jl data/mat/cpsc/A0001.mat out/A0001.html
julia --project=julia julia/scripts/plot_hdf5.jl data/hdf5/but-cgm/124001_2124-04-05_ECG.h5 out/but.html
```

Each format script calls the matching Ada CLI, then `MeddbPlots.plot_recording`. Pass `--start` and `--duration` to choose the exported window. `plot_edf.jl` attaches a sibling `*Hypnogram.edf` when it finds one, and shortens the default window for `.bdf` files.

`load_export(prefix)` and `plot_recording(rec; outfile)` are the stable API. A format-specific script should export normalized CSV/JSON and call those two functions rather than parsing the native file in Julia.
