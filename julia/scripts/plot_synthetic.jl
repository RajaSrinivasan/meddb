using MeddbPlots

outfile = length(ARGS) >= 1 ? ARGS[1] : "synthetic.html"
n = length(ARGS) >= 2 ? parse(Int, ARGS[2]) : 80_000
rec = synthetic_recording(; n)
plot_recording(rec; outfile)
println("wrote ", abspath(outfile))
