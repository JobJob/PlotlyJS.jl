abstract AbstractTrace
abstract AbstractLayout

type OHLCTrace <: AbstractTrace
    open::AbstractVector
    high::AbstractVector
    low::AbstractVector
    close::AbstractVector
    dates::AbstractVector{Base.Dates.Date}
    kind::Symbol

    function OHLCTrace(o, h, l, c, d, k=:ohlc)
        if any(h .< o) || any(h .< l) || any(h .< c)
            error("high lower than one of open, low, or close")
        end
        if any(l .> o) || any(l .> h) || any(l .> c)
            error("low higher than one of open, high, or close")
        end
        new(o, h, l, c, d, k)
    end
end

type GenericTrace{T<:Associative{Symbol,Any}} <: AbstractTrace
    kind::ASCIIString
    fields::T
end

function GenericTrace(kind::AbstractString, fields=Dict{Symbol,Any}(); kwargs...)
    # use setindex! methods below to handle `_` substitution
    gt = GenericTrace(kind, fields)
    map(x->setindex!(gt, x[2], x[1]), kwargs)
    gt
end

const _layout_defaults = Dict{Symbol,Any}(:margin => Dict(:l=>50, :r=>50, :t=>60, :b=>50))

type Layout{T<:Associative{Symbol,Any}} <: AbstractLayout
    fields::T

    function Layout(fields; kwargs...)
        l = new(merge(_layout_defaults, fields))
        map(x->setindex!(l, x[2], x[1]), kwargs)
        l
    end
end

Layout{T<:Associative{Symbol,Any}}(fields::T=Dict{Symbol,Any}(); kwargs...) =
    Layout{T}(fields; kwargs...)

kind(gt::GenericTrace) = gt.kind
kind(l::Layout) = "layout"

typealias HasFields Union{GenericTrace, Layout}

# methods that allow you to do `obj["first.second.third"] = val`
Base.setindex!(gt::HasFields, val, key::ASCIIString) =
    setindex!(gt, val, map(symbol, split(key, "."))...)

Base.setindex!(gt::HasFields, val, keys::ASCIIString...) =
    setindex!(gt, val, map(symbol, keys)...)

# Now for deep setindex. The deepest the json schema ever goes is 4 levels deep
# so we will simply write out the setindex calls for 4 levels by hand. If the
# schema gets deeper in the future we can @generate them with @nexpr
function Base.setindex!(gt::HasFields, val, key::Symbol)
    # check if single key has underscores, if so split at str and call above
    if contains(string(key), "_")
        return setindex!(gt, val, replace(string(key), "_", "."))
    end
    gt.fields[key] = val
end

function Base.setindex!(gt::HasFields, val, k1::Symbol, k2::Symbol)
    d1 = get(gt.fields, k1, Dict())
    d1[k2] = val
    gt.fields[k1] = d1
    val
end

function Base.setindex!(gt::HasFields, val, k1::Symbol, k2::Symbol, k3::Symbol)
    d1 = get(gt.fields, k1, Dict())
    d2 = get(d1, k2, Dict())
    d2[k3] = val
    d1[k2] = d2
    gt.fields[k1] = d1
    val
end

function Base.setindex!(gt::HasFields, val, k1::Symbol, k2::Symbol,
                        k3::Symbol, k4::Symbol)
    d1 = get(gt.fields, k1, Dict())
    d2 = get(d1, k2, Dict())
    d3 = get(d2, k3, Dict())
    d3[k4] = val
    d2[k3] = d3
    d1[k2] = d2
    gt.fields[k1] = d1
    val
end

# now on to the simpler getindex methods. They will try to get the desired
# key, but if it doesn't exist an empty dict is returned
Base.getindex(gt::HasFields, key::ASCIIString) =
    getindex(gt, map(symbol, split(key, "."))...)

Base.getindex(gt::HasFields, keys::ASCIIString...) =
    getindex(gt, map(symbol, keys)...)

function Base.getindex(gt::HasFields, key::Symbol)
    get(gt.fields, key, Dict())
end

function Base.getindex(gt::HasFields, k1::Symbol, k2::Symbol)
    d1 = get(gt.fields, k1, Dict())
    get(d1, k2, Dict())
end

function Base.getindex(gt::HasFields, k1::Symbol, k2::Symbol, k3::Symbol)
    d1 = get(gt.fields, k1, Dict())
    d2 = get(d1, k2, Dict())
    get(d2, k3, Dict())
end

function Base.getindex(gt::HasFields, k1::Symbol, k2::Symbol,
                       k3::Symbol, k4::Symbol)
    d1 = get(gt.fields, k1, Dict())
    d2 = get(d1, k2, Dict())
    d3 = get(d2, k3, Dict())
    get(d3, k4, Dict())
end

# Function used to have meaningful display of traces and layouts
function _describe(x::HasFields)
    fields = sort(map(string, keys(x.fields)))
    n_fields = length(fields)
    if n_fields == 0
        return "$(kind(x)) with no fields"
    elseif n_fields == 1
        return "$(kind(x)) with field $(fields[1])"
    elseif n_fields == 2
        return "$(kind(x)) with fields $(fields[1]) and $(fields[2])"
    else
        return "$(kind(x)) with fields $(join(fields, ", ", ", and "))"
    end
end

_describe{T<:AbstractTrace}(::T) = "trace of type $T"

Base.writemime(io::IO, ::MIME"text/plain", g::HasFields) =
    println(io, _describe(g))
