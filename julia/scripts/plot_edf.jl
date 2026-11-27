using MeddbPlots

function sibling_hypnogram(path)
    dir = dirname(path)
    base = basename(path)
    if occursin("PSG", base)
        candidate = joinpath(dir, replace(base, "E0-PSG" => "EC-Hypnogram"))
        isfile(candidate) && return candidate
        for name in readdir(dir)
            if occursin("Hypnogram", name)
                return joinpath(dir, name)
            end
        end
    end
    return ""
end

args = parse_plot_args(ARGS; default_duration=30.0)
extra = copy(args.extra)
duration = args.duration
lower = lowercase(args.input)
if endswith(lower, ".bdf") && !any(==("--duration"), ARGS)
    duration = 2.0
elseif occursin("psg", lowercase(basename(args.input))) && !any(==("--duration"), ARGS)
    duration = 120.0
end
if !any(x -> x in ("--hypnogram", "--annotations"), extra)
    hypo = sibling_hypnogram(args.input)
    if !isempty(hypo)
        push!(extra, "--hypnogram", hypo)
    end
end
cli_export("meddb-edf", args.input, args.output; start=args.start, duration, extra)
println("wrote ", abspath(args.output))
