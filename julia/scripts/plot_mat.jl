using MeddbPlots

args = parse_plot_args(ARGS; default_duration=30.0)
cli_export("meddb-mat", args.input, args.output; start=args.start, duration=args.duration, extra=args.extra)
println("wrote ", abspath(args.output))
