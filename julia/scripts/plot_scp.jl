using MeddbPlots

args = parse_plot_args(ARGS; default_duration=10.0)
cli_export("meddb-scp", args.input, args.output; start=args.start, duration=args.duration, extra=args.extra)
println("wrote ", abspath(args.output))
