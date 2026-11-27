module MeddbPlots

using JSON

export load_export, plot_recording, synthetic_recording, cli_export, parse_plot_args

const ROOT = normpath(joinpath(@__DIR__, "..", ".."))
const PLOTLY_URL = "https://cdn.plot.ly/plotly-2.35.2.min.js"

struct Annotation
    onset::Float64
    duration::Float64
    label::String
    description::String
end

struct Channel
    name::String
    units::String
    fs::Float64
    y::Vector{Float64}
end

struct Recording
    name::String
    format::String
    start_time::String
    duration_s::Float64
    window_start::Float64
    time::Vector{Float64}
    channels::Vector{Channel}
    annotations::Vector{Annotation}
end

function _csv_rows(path::AbstractString)
    rows = Vector{Vector{String}}()
    for line in eachline(path)
        isempty(strip(line)) && continue
        push!(rows, _split_csv(line))
    end
    return rows
end

function _split_csv(line::AbstractString)
    fields = String[]
    buf = IOBuffer()
    quoted = false
    i = 1
    chars = collect(line)
    while i <= length(chars)
        c = chars[i]
        if quoted
            if c == '"'
                if i < length(chars) && chars[i + 1] == '"'
                    print(buf, '"')
                    i += 1
                else
                    quoted = false
                end
            else
                print(buf, c)
            end
        elseif c == '"'
            quoted = true
        elseif c == ','
            push!(fields, String(take!(buf)))
        else
            print(buf, c)
        end
        i += 1
    end
    push!(fields, String(take!(buf)))
    return fields
end

function _float_or_nan(text::AbstractString)
    t = strip(text)
    isempty(t) && return NaN
    return parse(Float64, t)
end

"""
    load_export(prefix)

Load `prefix.csv` and `prefix.json` written by a meddb CLI `--export`.
"""
function load_export(prefix::AbstractString)
    meta = JSON.parsefile(prefix * ".json")
    rows = _csv_rows(prefix * ".csv")
    isempty(rows) && error("empty export $prefix.csv")
    header = rows[1]
    header[1] == "time_s" || error("export CSV must start with time_s")
    names = header[2:end]
    time = Float64[]
    columns = [Float64[] for _ in names]
    for row in rows[2:end]
        push!(time, _float_or_nan(row[1]))
        for k in eachindex(names)
            value = k + 1 <= length(row) ? row[k + 1] : ""
            push!(columns[k], _float_or_nan(value))
        end
    end
    channels = Channel[]
    for (k, name) in enumerate(names)
        units = ""
        fs = Float64(get(meta, "csv_timebase_hz", 0.0))
        for ch in meta["channels"]
            if ch["column"] == name || ch["label"] == name
                units = string(get(ch, "units", ""))
                fs = Float64(ch["sampling_rate_hz"])
                break
            end
        end
        push!(channels, Channel(name, units, fs, columns[k]))
    end
    anns = Annotation[]
    for ann in meta["annotations"]
        push!(anns, Annotation(
            Float64(ann["onset_s"]),
            Float64(ann["duration_s"]),
            string(ann["label"]),
            string(get(ann, "description", "")),
        ))
    end
    window = meta["window"]
    return Recording(
        string(meta["name"]),
        string(meta["format"]),
        string(get(meta, "start_time", "")),
        Float64(meta["duration_s"]),
        Float64(window["start_s"]),
        time,
        channels,
        anns,
    )
end

"""
    synthetic_recording(; n=80_000, fs=500.0)

Two-channel sine/square recording with one beat annotation.
`n` is large enough that the HTML plot decimates the overview.
"""
function synthetic_recording(; n::Int=80_000, fs::Float64=500.0)
    t = collect(range(0.0, step=1 / fs, length=n))
    y1 = sin.(2π .* 1.2 .* t) .+ 0.15 .* sin.(2π .* 8 .* t)
    y2 = 0.6 .* sign.(sin.(2π .* 0.5 .* t)) .+ 0.05 .* cos.(2π .* 3 .* t)
    return Recording(
        "synthetic",
        "synthetic",
        "00:00:00",
        t[end],
        0.0,
        t,
        [Channel("I", "mV", fs, y1), Channel("II", "mV", fs, y2)],
        [Annotation(1.25, 0.0, "N", "Normal beat"),
         Annotation(20.0, 5.0, "event", "Five-second mark")],
    )
end

function ensure_plotly()
    path = joinpath(ROOT, "julia", "vendor", "plotly.min.js")
    if !isfile(path)
        mkpath(dirname(path))
        run(`curl -fsSL -o $path $PLOTLY_URL`)
    end
    src = read(path, String)
    return replace(src, "</" => "<\\/")
end

function _payload(rec::Recording, max_points::Int)
    return Dict(
        "name" => rec.name,
        "format" => rec.format,
        "startTime" => rec.start_time,
        "duration" => rec.duration_s,
        "time" => [isfinite(x) ? x : nothing for x in rec.time],
        "maxPoints" => max_points,
        "channels" => [
            Dict(
                "name" => ch.name,
                "units" => ch.units,
                "fs" => ch.fs,
                "y" => [isfinite(v) ? v : nothing for v in ch.y],
            )
            for ch in rec.channels
        ],
        "annotations" => [
            Dict(
                "onset" => a.onset,
                "duration" => a.duration,
                "label" => a.label,
                "description" => a.description,
            ) for a in rec.annotations
        ],
    )
end

"""
    plot_recording(rec; outfile, max_points=2000)

Write a self-contained HTML file. The page pans and zooms, toggles channels,
shows an overview window, overlays annotations, and min/max-decimates long
series. Zooming in redraws the visible window from the embedded samples, up to
full resolution when the window is short enough.
"""
function plot_recording(rec::Recording; outfile::AbstractString, max_points::Int=2000)
    isempty(rec.channels) && error("recording has no channels to plot")
    isempty(rec.time) && error("recording has no samples to plot")
    plotly = ensure_plotly()
    data = JSON.json(_payload(rec, max_points))
    html = """
    <!DOCTYPE html>
    <html lang="en">
    <head>
    <meta charset="utf-8">
    <title>$(rec.name) — meddb</title>
    <script>$plotly</script>
    <style>
      :root { color-scheme: dark; }
      body { margin: 0; font-family: "Segoe UI", sans-serif; background: #101418; color: #e8eef4; }
      header { padding: 10px 16px 0; }
      h1 { font-size: 18px; margin: 0 0 4px; }
      p { margin: 0; color: #9aabba; font-size: 13px; }
      #toolbar { display: flex; flex-wrap: wrap; gap: 10px 16px; align-items: center; padding: 10px 16px; }
      button { background: #243140; color: #e8eef4; border: 1px solid #3d5166; border-radius: 4px; padding: 4px 10px; cursor: pointer; }
      button:hover { background: #31445a; }
      label.ch { display: inline-flex; gap: 6px; align-items: center; font-size: 13px; }
      #status { margin-left: auto; color: #8fd0ff; font-size: 13px; }
      #main { height: 68vh; }
      #overview { height: 18vh; }
    </style>
    </head>
    <body>
    <header>
      <h1 id="title"></h1>
      <p id="subtitle"></p>
    </header>
    <div id="toolbar">
      <span id="channels"></span>
      <button type="button" data-window="5">5 s</button>
      <button type="button" data-window="10">10 s</button>
      <button type="button" data-window="30">30 s</button>
      <button type="button" data-window="all">all</button>
      <span id="status"></span>
    </div>
    <div id="main"></div>
    <div id="overview"></div>
    <script>
    const REC = $data;
    const COLORS = ["#4cc2ff","#ffb020","#3dd68c","#ff6b6b","#c084fc","#f472b6","#a3e635","#38bdf8","#fb7185","#facc15","#22d3ee","#e879f9"];
    const time = REC.time;
    const t0 = time.length ? time[0] : 0;
    const t1 = time.length ? time[time.length - 1] : 0;

    function finite(v) { return v !== null && v !== undefined && !Number.isNaN(v); }

    function decimate(y, i0, i1, maxPoints) {
      const xs = [], ys = [];
      const n = Math.max(0, i1 - i0);
      if (n <= maxPoints) {
        for (let i = i0; i < i1; i++) {
          if (!finite(y[i])) continue;
          xs.push(time[i]); ys.push(y[i]);
        }
        return [xs, ys, false];
      }
      const buckets = Math.max(1, Math.floor(maxPoints / 2));
      const size = Math.ceil(n / buckets);
      for (let b = 0; b < buckets; b++) {
        const a = i0 + b * size;
        const c = Math.min(i1, a + size);
        let min = Infinity, max = -Infinity, imin = a, imax = a, seen = false;
        for (let i = a; i < c; i++) {
          const v = y[i];
          if (!finite(v)) continue;
          seen = true;
          if (v < min) { min = v; imin = i; }
          if (v > max) { max = v; imax = i; }
        }
        if (!seen) continue;
        if (imin <= imax) { xs.push(time[imin], time[imax]); ys.push(min, max); }
        else { xs.push(time[imax], time[imin]); ys.push(max, min); }
      }
      return [xs, ys, true];
    }

    function indexAt(t) {
      if (!time.length) return 0;
      let lo = 0, hi = time.length - 1;
      while (lo < hi) {
        const mid = (lo + hi) >> 1;
        if (time[mid] < t) lo = mid + 1;
        else hi = mid;
      }
      return lo;
    }

    const spans = REC.channels.map(ch => {
      let min = Infinity, max = -Infinity;
      const step = Math.max(1, Math.floor(ch.y.length / 4000));
      for (let i = 0; i < ch.y.length; i += step) {
        const v = ch.y[i];
        if (!finite(v)) continue;
        if (v < min) min = v;
        if (v > max) max = v;
      }
      if (!finite(min) || min === max) return 1;
      return Math.max(max - min, 1e-6);
    });
    const offsets = [];
    let cursor = 0;
    for (let i = REC.channels.length - 1; i >= 0; i--) {
      offsets[i] = cursor;
      cursor += spans[i] * 1.35;
    }

    const visible = REC.channels.map(() => true);
    const channelBox = document.getElementById("channels");
    REC.channels.forEach((ch, i) => {
      const label = document.createElement("label");
      label.className = "ch";
      const box = document.createElement("input");
      box.type = "checkbox";
      box.checked = true;
      box.addEventListener("change", () => {
        visible[i] = box.checked;
        Plotly.restyle("main", {visible: box.checked}, [i]);
        Plotly.restyle("overview", {visible: box.checked}, [i]);
      });
      label.appendChild(box);
      label.appendChild(document.createTextNode(ch.name + (ch.units ? " (" + ch.units + ")" : "")));
      label.style.color = COLORS[i % COLORS.length];
      channelBox.appendChild(label);
    });

    document.getElementById("title").textContent = REC.name + " (" + REC.format + ")";
    document.getElementById("subtitle").textContent =
      "start " + (REC.startTime || "0") + " · file " + REC.duration.toFixed(3) +
      " s · " + REC.channels.length + " channel(s) · " + REC.annotations.length + " annotation(s) in this export";

    function shifted(y, offset) {
      return y.map(v => finite(v) ? v + offset : null);
    }

    function tracesFor(i0, i1) {
      let decimated = false;
      const traces = REC.channels.map((ch, i) => {
        const [xs, ys, was] = decimate(ch.y, i0, i1, REC.maxPoints);
        if (was) decimated = true;
        return {
          type: "scatter",
          mode: "lines",
          name: ch.name,
          x: xs,
          y: shifted(ys, offsets[i]),
          line: {color: COLORS[i % COLORS.length], width: 1},
          visible: visible[i],
          hovertemplate: ch.name + " %{customdata:.4g} " + (ch.units || "") + "<extra></extra>",
          customdata: ys
        };
      });
      const marks = REC.annotations.filter(a => a.duration <= 0 && a.onset >= time[Math.max(0, i0)] && a.onset <= time[Math.min(time.length - 1, Math.max(i0, i1 - 1))]);
      traces.push({
        type: "scatter",
        mode: marks.length && marks.length <= 40 ? "markers+text" : "markers",
        name: "annotations",
        x: marks.map(a => a.onset),
        y: marks.map(() => cursor),
        text: marks.map(a => a.label),
        customdata: [],
        textposition: "top center",
        marker: {color: "#ffe08a", size: 8, symbol: "diamond"},
        hovertext: marks.map(a => a.label + (a.description ? " — " + a.description : "")),
        hoverinfo: "text",
        showlegend: false
      });
      return [traces, decimated];
    }

    function shapesFor() {
      return REC.annotations.filter(a => a.duration > 0).map(a => ({
        type: "rect", xref: "x", yref: "paper",
        x0: a.onset, x1: a.onset + a.duration, y0: 0, y1: 1,
        fillcolor: "rgba(255, 196, 80, 0.16)", line: {width: 0}, layer: "below"
      }));
    }

    const initialSpan = Math.min(10, t1 - t0);
    let view0 = t0;
    let view1 = t0 + (initialSpan > 0 ? initialSpan : 1);
    let ignoreRelayout = false;
    let i0 = indexAt(view0);
    let i1 = Math.max(i0 + 1, indexAt(view1));
    let built = tracesFor(i0, i1);

    const layout = {
      paper_bgcolor: "#101418",
      plot_bgcolor: "#101418",
      font: {color: "#e8eef4"},
      margin: {l: 50, r: 20, t: 10, b: 40},
      xaxis: {title: "Time (s)", range: [view0, view1], gridcolor: "#243140", zeroline: false},
      yaxis: {title: "stacked", gridcolor: "#243140", zeroline: false, showticklabels: false},
      shapes: shapesFor(),
      showlegend: false,
      dragmode: "pan"
    };
    Plotly.newPlot("main", built[0], layout, {responsive: true, scrollZoom: true, displaylogo: false});

    const overviewTraces = REC.channels.map((ch, i) => {
      const [xs, ys] = decimate(ch.y, 0, ch.y.length, 800);
      return {
        type: "scatter", mode: "lines", name: ch.name,
        x: xs, y: shifted(ys, offsets[i]),
        line: {color: COLORS[i % COLORS.length], width: 1},
        hoverinfo: "skip", showlegend: false
      };
    });
    function overviewShapes() {
      return [{
        type: "rect", xref: "x", yref: "paper",
        x0: view0, x1: view1, y0: 0, y1: 1,
        fillcolor: "rgba(76, 194, 255, 0.18)",
        line: {color: "#4cc2ff", width: 1}
      }];
    }
    Plotly.newPlot("overview", overviewTraces, {
      paper_bgcolor: "#101418", plot_bgcolor: "#161d24",
      font: {color: "#e8eef4"},
      margin: {l: 50, r: 20, t: 4, b: 30},
      xaxis: {range: [t0, t1], gridcolor: "#243140", title: "overview"},
      yaxis: {visible: false, range: [0, cursor || 1]},
      shapes: overviewShapes(),
      showlegend: false
    }, {responsive: true, displayModeBar: false, displaylogo: false});

    function setStatus(decimated, from, to) {
      const shown = Math.max(0, indexAt(to) - indexAt(from));
      document.getElementById("status").textContent =
        (decimated ? "decimated overview" : "full resolution") +
        " · " + shown + " of " + time.length + " samples · " +
        from.toFixed(3) + "–" + to.toFixed(3) + " s";
    }
    setStatus(built[1], view0, view1);

    function applyWindow(a, b, redraw) {
      view0 = Math.max(t0, Math.min(a, b));
      view1 = Math.min(t1, Math.max(a, b));
      if (view1 - view0 < 1e-6) view1 = Math.min(t1, view0 + 1e-3);
      i0 = indexAt(view0);
      i1 = Math.max(i0 + 1, indexAt(view1) + 1);
      const next = tracesFor(i0, i1);
      if (redraw) {
        ignoreRelayout = true;
        Promise.all([
          Plotly.restyle("main", {
            x: next[0].map(tr => tr.x),
            y: next[0].map(tr => tr.y),
            customdata: next[0].map(tr => tr.customdata || []),
            text: next[0].map(tr => tr.text || [])
          }, next[0].map((_, i) => i)),
          Plotly.relayout("main", {"xaxis.range": [view0, view1]})
        ]).then(() => { ignoreRelayout = false; });
      }
      Plotly.relayout("overview", {shapes: overviewShapes()});
      setStatus(next[1], view0, view1);
    }

    document.getElementById("main").on("plotly_relayout", ev => {
      if (ignoreRelayout) return;
      if (ev["xaxis.range[0]"] === undefined && ev["xaxis.range"] === undefined) {
        if (ev["xaxis.autorange"]) applyWindow(t0, t1, true);
        return;
      }
      const a = ev["xaxis.range"] ? ev["xaxis.range"][0] : ev["xaxis.range[0]"];
      const b = ev["xaxis.range"] ? ev["xaxis.range"][1] : ev["xaxis.range[1]"];
      applyWindow(a, b, true);
    });

    document.getElementById("overview").on("plotly_click", ev => {
      if (!ev.points || !ev.points.length) return;
      const width = Math.max(view1 - view0, (t1 - t0) / 20);
      const center = ev.points[0].x;
      applyWindow(center - width / 2, center + width / 2, true);
    });

    document.querySelectorAll("button[data-window]").forEach(btn => {
      btn.addEventListener("click", () => {
        const which = btn.dataset.window;
        if (which === "all") applyWindow(t0, t1, true);
        else {
          const width = parseFloat(which);
          applyWindow(view0, Math.min(t1, view0 + width), true);
        }
      });
    });

    window.addEventListener("keydown", ev => {
      const width = view1 - view0;
      if (ev.key === "ArrowRight") applyWindow(view0 + width * 0.5, view1 + width * 0.5, true);
      if (ev.key === "ArrowLeft") applyWindow(view0 - width * 0.5, view1 - width * 0.5, true);
    });
    </script>
    </body>
    </html>
    """
    open(outfile, "w") do io
        write(io, html)
    end
    return outfile
end

function parse_plot_args(args; default_duration::Float64=30.0)
    if length(args) < 2
        error("usage: INPUT OUTPUT.html [--start SEC] [--duration SEC] [--hypnogram FILE] [--hea FILE]")
    end
    input = args[1]
    output = args[2]
    start = 0.0
    duration = default_duration
    extra = String[]
    i = 3
    while i <= length(args)
        flag = args[i]
        if flag in ("--start", "--duration", "--hypnogram", "--hea", "--annotations")
            i + 1 <= length(args) || error("$flag needs a value")
            if flag == "--start"
                start = parse(Float64, args[i + 1])
            elseif flag == "--duration"
                duration = parse(Float64, args[i + 1])
            else
                push!(extra, flag == "--annotations" ? "--hypnogram" : flag, args[i + 1])
            end
            i += 2
        else
            error("unknown argument $flag")
        end
    end
    return (; input, output, start, duration, extra)
end

function cli_export(tool::AbstractString, input::AbstractString, outfile::AbstractString;
                    start::Float64=0.0, duration::Float64=30.0,
                    pass_duration::Bool=true, extra::Vector{String}=String[])
    bin = joinpath(ROOT, "bin", tool)
    isfile(bin) || error("missing $bin — build the Ada tools with alr build or gprbuild -P meddb.gpr")
    dir = mktempdir()
    prefix = joinpath(dir, "recording")
    argv = String[bin, input, "--export", prefix, "--start", string(start)]
    if pass_duration
        append!(argv, ["--duration", string(duration)])
    end
    append!(argv, extra)
    run(Cmd(argv))
    rec = load_export(prefix)
    plot_recording(rec; outfile)
    return outfile
end

end
