# ----------------------- #
# Display-esque functions #
# ----------------------- #

function html_body(p::Plot)
    """
    <div id="$(p.divid)"></div>

    <script>
       $(script_content(p))
     </script>
    """
end

script_content(p::Plot) = """
    thediv = document.getElementById('$(p.divid)');
    var data = $(json(p.data))
    var layout = $(json(p.layout))

    Plotly.plot(thediv, data,  layout, {showLink: false});
    """


function stringmime(::MIME"text/html", p::Plot, js::Symbol=:local)

    if js == :local
        script_txt = string("<script src=\"$(_js_path)\"></script>", "\n",
                            "<script src=\"$(_finance_js_path)\"></script>")
    elseif js == :remote
        script_txt = string("<script src=\"$(_js_cdn_path)\"></script>", "\n",
                            "<script src=\"$(_js_finance_cdn_path)\"></script>")
    elseif js == :embed
        script_txt = string("<script>$(readall(_js_path))</script>", "\n",
                            "<script>$(readall(_finance_js_path))</script>")
    else
        msg = """
        Unknown value for argument js: $js.
        Possible choices are `:local`, `:remote`, `:embed`
            """
        throw(ArgumentError(msg))
    end

    """
    <html>
    <head>
         $script_txt
    </head>
    <body>
         $(html_body(p))
    </body>
    </html>
    """

end

Base.writemime(io::IO, ::MIME"text/html", p::Plot, js::Symbol=:local) =
    print(io, stringmime(MIME"text/html"(), p, js))

function Base.writemime(io::IO, ::MIME"text/plain", p::Plot)
    println(io, """
    data: $(json(map(_describe, p.data), 2))
    layout: "$(_describe(p.layout))"
    """)
end

Base.show(io::IO, p::Plot) = writemime(io, MIME("text/plain"), p)

# ----------------------------------------- #
# SyncPlot -- sync Plot object with display #
# ----------------------------------------- #
immutable SyncPlot{TD<:AbstractPlotlyDisplay}
    plot::Plot
    view::TD
end

plot(args...; kwargs...) = SyncPlot(Plot(args...; kwargs...))

## API methods for SyncPlot
for f in [:restyle!, :relayout!, :addtraces!, :deletetraces!, :movetraces!,
          :redraw!, :extendtraces!, :prependtraces!]
    @eval function $(f)(sp::SyncPlot, args...; kwargs...)
        $(f)(sp.plot, args...; kwargs...)
        $(f)(sp.view, args...; kwargs...)
    end

    no_!_method = symbol(string(f)[1:end-1])
    @eval function $(no_!_method)(sp::SyncPlot, args...; kwargs...)
        sp2 = fork(sp)
        $f(sp2.plot, args...; kwargs...)  # only need to update the julia side
        sp2  # return so we display fresh
    end
end

Base.writemime(io::IO, ::MIME"text/html", sp::SyncPlot, js::Symbol=:local) =
    print(io, stringmime(MIME"text/html"(), sp.plot, js))

# Add some basic Julia API methods on SyncPlot that just forward onto the Plot
Base.size(sp::SyncPlot) = size(sp.plot)
Base.copy(sp::SyncPlot) = fork(sp)  # defined by each SyncPlot{TD}

# ----------------- #
# Display frontends #
# ----------------- #

include("displays/electron.jl")
include("displays/ijulia.jl")

# methods to convert from one frontend to another
let
    all_frontends = [:ElectronPlot, :JupyterPlot]
    for fe_to in all_frontends
        for fe_from in all_frontends
            @eval $(fe_to)(sp::$(fe_from)) = $(fe_to)(sp.plot)
        end
    end
end

# -------- #
# Defaults #
# -------- #

if isdefined(Main, :IJulia) && Main.IJulia.inited
    # default to JupyterDisplay
    SyncPlot(p::Plot) = SyncPlot(p, JupyterDisplay(p))
else
    # default to ElectronDisplay
    SyncPlot(p::Plot) = SyncPlot(p, ElectronDisplay())
end
