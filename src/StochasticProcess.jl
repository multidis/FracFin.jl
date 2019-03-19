########## Definitions of various stochastic process ##########

abstract type AbstractRandomField end
abstract type AbstractRealRandomField <: AbstractRandomField end


"""
Generic zero-mean real-valued stochastic process.
"""
abstract type StochasticProcess{T<:TimeStyle} <: AbstractRealRandomField end
const ContinuousTimeStochasticProcess = StochasticProcess{ContinuousTime}
const DiscreteTimeStochasticProcess = StochasticProcess{DiscreteTime}


abstract type StationaryProcess{T} <: StochasticProcess{T} end
const ContinuousTimeStationaryProcess = StationaryProcess{ContinuousTime}
const DiscreteTimeStationaryProcess = StationaryProcess{DiscreteTime}


abstract type SelfSimilarProcess <: ContinuousTimeStochasticProcess end
abstract type SSSIProcess <: SelfSimilarProcess end  #


@doc raw"""
Stationary process resulting from filtration (without DC) of another process.

The causal version is defined as:
    \sum_{n=0}^{N-1} a[n+1] X(t-nδ)

and the anti-causal version:
    \sum_{n=0}^{N-1} a[n+1] X(t+nδ)

# Note
- Under assumption of stationarity, the causality has no effect on the auto-covariance function. The implementation of concrete type should follow the anti-causal convention.
- The aimed concrete type of the abstract type `IncrementProcess` is `FractionalGaussianNoise` (fGn) which is stationary. However due to the lack of multiple inheritance in Julia it is very hard to make `IncrementProcess` a subtype of `StationaryProcess`. Possible solutions to this problem include 1) SimpleTrait.jl,  2) copy functions defined for `StationaryProcess`,  3) force `FilteredProcess` to be a subtype of `StationaryProcess`. We adopt the solution 3) here.
"""
abstract type FilteredProcess{T<:TimeStyle, P<:StochasticProcess{>:T}} <: StationaryProcess{T} end

"""
Differential process `X(t±δ) - X(t)`
"""
abstract type DifferentialProcess{T<:TimeStyle, P<:StochasticProcess{>:T}} <: FilteredProcess{T, P} end  # Process as first order finite difference of another process.

"""
Discrete time differential process `X((n±l)δ) - X(nδ)` with `l` being the lag.
"""
abstract type IncrementProcess{P<:StochasticProcess} <: DifferentialProcess{DiscreteTime, P} end



#### Process specific functions ####
"""
Return the self-similar exponent of the process.
"""
ss_exponent(X::SelfSimilarProcess) = throw(NotImplementedError())

"""
Return the filter of the process.
"""
filter(X::FilteredProcess)::AbstractVector = throw(NotImplementedError())

"""
Test whether the filtration is causal:
"""
iscausal(X::FilteredProcess) = throw(NotImplementedError())

"""
Return the parent process of the filtered process.
"""
parent_process(X::FilteredProcess) = throw(NotImplementedError())

"""
Return the step `δ` of the filtered process.
"""
step(X::FilteredProcess)::Real = throw(NotImplementedError())

"""
Filter of differential process, defined as
- the causal case: X(t) - X(t-lδ)
- the anti-causal case: X(t+lδ) - X(t)
with `l = lag(X)`.
"""
function filter(X::DifferentialProcess)
    filt = vcat(1, zeros(lag(X)-1), -1)
    return iscausal(X) ? filt : reverse(filt)
end

"""
Return the lag of differential process.
"""
lag(X::DifferentialProcess) = throw(NotImplementedError())


#### Generic identifiers ####
"""
Test whether a process is time discrete (a time series).
"""
iscontinuoustime(X::StochasticProcess{ContinuousTime}) = true
iscontinuoustime(X::StochasticProcess{DiscreteTime}) = false

"""
Test whether a process is multivariate.
"""
ismultivariate(X::StochasticProcess) = false

"""
Test whether a process has stationary increments.
"""
isincrementstationary(X::StochasticProcess) = false
isincrementstationary(X::SSSIProcess) = true
isincrementstationary(X::StationaryProcess) = true

"""
Test whether a process is stationary.
"""
isstationary(X::StochasticProcess) = false
isstationary(X::StationaryProcess) = true
# isstationary(X::FilteredProcess{T, P}) where {T, P<:StationaryProcess} = true
# isstationary(X::IncrementProcess{P}) where {P<:SSSIProcess} = true


"""
Determine whether a grid has the constant step.
"""
function isregulargrid(G::AbstractVector)
    return if 1 <= length(G) <= 2
        true
    elseif length(G) > 2  # second order difference should be close to 0
        isapprox(maximum(abs.(diff(diff(G)))), 0.0; atol=1e-10)
        # ddG = unique(diff(diff(G)))
        # length(ddG) == 1 && ddG[1] == 0.
    else
        false
    end
end



#### Statistics for stochastic process ####
"""
Auto-covariance function of a stochastic process.
"""
autocov(X::StochasticProcess{T}, t::T, s::T) where T<:TimeStyle = throw(NotImplementedError())

autocov(X::StationaryProcess{T}, t::T) where T<:TimeStyle = throw(NotImplementedError())
autocov(X::StationaryProcess{T}, t::T, s::T) where T<:TimeStyle = autocov(X, t-s)


"""
Compute the auto-covariance matrix of a stochastic process on a sampling grid.
"""
function autocov!(C::Matrix{<:Real}, X::StochasticProcess{T}, G::AbstractVector{<:T}) where T<:TimeStyle
    @assert size(C, 1) == size(C, 2) == length(G)

    # construct the covariance matrix (a symmetric matrix)
    N = size(C, 1)  # dimension of the auto-covariance matrix
    for c = 1:N, r = 1:c
        C[r,c] = autocov(X, G[r], G[c])
    end
    for c = 1:N, r = (c+1):N
        C[r,c] = C[c,r]
    end
    return Symmetric(C)
end

function autocov!(C::Matrix{<:Real}, X::StochasticProcess{T}, G1::AbstractVector{<:T}, G2::AbstractVector{<:T}) where T<:TimeStyle
    @assert size(C, 1) == length(G1) && size(C, 2) == length(G2)

    # construct the covariance matrix (a symmetric matrix)
    N,M = size(C)  # dimension of the auto-covariance matrix
    for c = 1:M, r = 1:N
        C[r,c] = autocov(X, G1[r], G2[c])
    end
    return C
end


"""
Compute the auto-covariance sequence of a stationary process on a regular grid.
"""
function autocov!(C::AbstractVector{<:Real}, X::StationaryProcess{T}, G::AbstractVector{<:T}) where T<:TimeStyle
    # @assert isregulargrid(G)
    @assert length(C) == length(G)  # check dimension

    # construct the auto-covariance kernel
    for n = 1:length(C)
        C[n] = autocov(X, G[n]-G[1])
    end
    return C
end


"""
    covseq(X::StationaryProcess, G::RegularGrid)

Return the auto-covariance sequence of a stationary process on a regular grid.
"""
covseq(X::StationaryProcess{T}, G::AbstractVector{<:T}) where T<:TimeStyle = autocov!(zeros(length(G)), X, G)
covseq(X::StationaryProcess, N::Integer) = covseq(X, 1:N)


function autocov!(C::Matrix{<:Real}, X::StationaryProcess{T}, G::AbstractVector{<:T}) where T<:TimeStyle
    # check dimension
    @assert size(C, 1) == size(C, 2) == length(G)
    # println("autocov! of StationaryProcess, $(ss_exponent(X))")

    return if isregulargrid(G)
        # construct the covariance matrix (a Toeplitz matrix)
        covmat!(C, covseq(X,G))
    else
        # if G is not regular the `covseq` can not be applied, invoke the function of `StochasticProcess`.
        invoke(autocov!, Tuple{Matrix{<:Real}, StochasticProcess{S}, AbstractVector{<:S}} where S<:TimeStyle, C, X, G)
    end
end


"""
Construct the covariance matrix from the covariance sequence.
"""
function covmat!(C::Matrix{T}, S::AbstractVector{T}) where {T<:Real}
    for c = 1:length(S), r = 1:length(S)
        C[r,c] = S[abs(r-c)+1]
    end
    return C
end

covmat(S::AbstractVector{T}) where {T<:Real} = covmat!(zeros(T, length(S), length(S)), S)


"""
Return the auto-covariance matrix of a stochastic process on a sampling grid.
"""
covmat(X::StochasticProcess, G::AbstractVector) = autocov!(zeros(length(G), length(G)), X, G)


"""
Return the auto-covariance matrix of a stochastic process between two sampling grids.

The `(i,j)`-th coefficient in the matrix is `autocov(G1[i], G2[j])`.
"""
covmat(X::StochasticProcess, G1::AbstractVector, G2::AbstractVector) = autocov!(zeros(length(G1), length(G2)), X, G1, G2)

"""
Return the auto-covariance matrix on an integer sampling grid `1:N`.
"""
covmat(X::StochasticProcess, N::Integer) = covmat(X, 1:N)
covmat(X::StochasticProcess, N::Integer, M::Integer) = covmat(X, 1:N, 1:M)


"""
Return the partial correlation function of a discrete time stationary process.
"""
partcorr(X::DiscreteTimeStationaryProcess, n::DiscreteTime) = throw(NotImplementedError())


"""
Compute the partial correlation sequence of a discrete time stationary process on a regular integer sampling grid.
"""
function partcorr!(C::Vector{<:Real}, X::DiscreteTimeStationaryProcess, G::AbstractVector{<:DiscreteTime})
    # check dimension
    @assert length(C) == length(G)
    @assert isregulargrid(G)

    for n = 1:length(C)
        C[n] = partcorr(X, G[n]-G[1]+1)
    end
    return C
end


"""
Return the partial correlation function of a time discrete stationary process.

# Args
- method: if set to `:LevinsonDurbin` it will use the Levinson-Durbin method which needs only the autocovariance expression of the process.
"""
function partcorr(X::DiscreteTimeStationaryProcess, G::AbstractVector{<:DiscreteTime}, method::Symbol=:None)
    if method == :LevinsonDurbin # use Levinson-Durbin
        cseq = covseq(X, G)
        pseq, sseq, rseq = LevinsonDurbin(cseq)
        return rseq
    else
        return partcorr!(zeros(length(G)), X, G)
    end
end


#### Statistical inference on stochastic process ####

"""
    cond_mean_cov(P::StochasticProcess{T}, Gx::AbstractVector{<:T}, Gy::AbstractVector{<:T}, Y::AbstractVector{<:Real}) where T<:TimeStyle

Conditional mean and covariance of a zero-mean Gaussian process `P` on the position `Gx` given the value `Y` on the position `Gy`.
"""
function cond_mean_cov(P::StochasticProcess{T}, Gx::AbstractVector{<:T}, Gy::AbstractVector{<:T}, Y::AbstractVector{<:Real}) where T<:TimeStyle
    @assert length(Gy) == length(Y)

    Σxx = covmat(P, Gx)
    Σxy = covmat(P, Gx, Gy)
    Σyy = covmat(P, Gy)
    # inverse of Σyy, method 1: pseudo inverse
    iΣyy = pinv(Matrix(Σyy))
    # # method 2: LU
    # iL = inv(cholesky(Σyy).L)
    # iΣyy = iL' * iL

    μc = Σxy * iΣyy * Y

    # μc = Σxy * iΣyy * Y
    # μc = Σxy * (Σyy\Y)
    Σc = Σxx - Σxy * iΣyy * Σxy'

    return (μ=μc, Σ=Σc, C=Σxy * iΣyy)
end

cond_mean_cov(P::StochasticProcess, gx::ContinuousTime, Gy::AbstractVector, Y::AbstractVector) = cond_mean_cov(P, [gx], Gy, Y)

"""
Conditional mean and covariance on regular grid.
"""
cond_mean_cov(P::StochasticProcess, n::DiscreteTime, Y::AbstractVector) = cond_mean_cov(P, (1:n).+length(Y), 1:length(Y), Y)


"""
EXPERIMENTAL: linear coefficient of recursive conditional mean

Predict `k` steps into the future.
"""
function cond_mean_coeff(P::StochasticProcess{T}, k::Integer, l::Integer; mode::Symbol=:recursive) where T<:TimeStyle
    @assert k>0

    Σyy = covmat(P, 0:l-1)

    if mode == :recursive
        Σxy = covmat(P, [l], 0:l-1)
        cv = Σxy * pinv(Matrix(Σyy))
        M = vcat(diagm(1 => ones(l-1))[1:l-1,:], cv)
        Cv = [cv]

        for i=2:k
            push!(Cv, Cv[end]*M)
        end

        return vcat(Cv...)
    else
        Cv = covmat(P, l:l+k-1, 0:l-1) * pinv(Matrix(Σyy))
        return Cv
    end
end


include("FBM.jl")  # Fractional Brownian Motion related
include("MFBM.jl")  # Multi-Fractional Brownian Motion related
include("FARIMA.jl")  # Fractional ARIMA related