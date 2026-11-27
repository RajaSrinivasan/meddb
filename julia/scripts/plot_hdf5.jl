using MeddbPlots

args = parse_plot_args(ARGS; default_duration=30.0)
cli_export(
    "meddb-hdf5", args.input, args.output;
    start=args.start, duration=args.duration,
    pass_duration=any(==("--duration"), ARGS), extra=args.extra,
)
println("wrote ", abspath(args.output))
