# __precompile__()

module FracFin

# using Distributions
# using PDMats
# using StatsBase

import Base: convert, rand!, rand, length, size, show, binomial, getindex, promote_rule
import Distributions: VariateForm, Univariate, Multivariate, ValueSupport, Discrete, Continuous, Sampleable
import StatsBase: autocov!, autocov

import Wavelets.WT.daubechies
import Wavelets.Util.mirror

"""
    Exception for not implemented methods.
"""
struct NotImplementedError <: Exception
    errmsg::AbstractString
    # errpos::Int64
end
show(io::IO, exc::NotImplementedError) = print(io, string("NotImplementedError:\n",exc.errmsg))

export
    # SamplingGrid.jl
    TimeStyle,
    ContinuousTime,
    DiscreteTime,
    SamplingGrid,
    DiscreteTimeSamplingGrid,
    ContinuousTimeSamplingGrid,
    RegularGrid,
    DiscreteTimeRegularGrid,
    ContinuousTimeRegularGrid,
    # StochasticProcess.jl
    StochasticProcess,
    ContinuousTimeStochasticProcess,
    DiscreteTimeStochasticProcess,
    SelfSimilarProcess,
    StationaryProcess,
    ContinuousTimeStationaryProcess,
    DiscreteTimeStationaryProcess,
    IncrementProcess,
    FractionalIntegrated,
    FractionalGaussianNoise,
    FractionalBrownianMotion,
    FARIMA,
    autocov,
    autocov!,
    covmat,
    covseq,
    partcorr,
    partcorr!,
    # Sampler.jl
    CholeskySampler,
    LevinsonDurbin,
    HoskingSampler,
    CircSampler,
    # CRMDSampler,
    # WaveletSampler,
    rand,
    rand!,
    rand_otf,
    rand_otf!
    # rand_rfn

include("SamplingGrid.jl")
include("StochasticProcess.jl")
include("Sampler.jl")

end # module