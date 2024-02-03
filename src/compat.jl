# one-argument circshift is not defined for Julia < 1.7
# TODO: remove this when LTS is bumped.
# Copied from Julia 1.7+::
function circshift!(v::AbstractVector, i::Integer)
    length(v) == 0 && return v
    i = mod(i, length(v))
    i == 0 && return v
    l = lastindex(v)
    reverse!(v, firstindex(v), l - i)
    reverse!(v, l - i + 1, l)
    reverse!(v)
    return v
end