# # Running a Problem with Service Bids
#
# This tutorial shows how to price an ancillary service (a reserve) using **per-device
# offer curves** - "service bids" - instead of a single flat reserve price.
#
# By default, `PowerOperationsModels` prices every unit of a reserve award at a flat
# `DEFAULT_RESERVE_COST`. Real markets instead let each resource submit a **piecewise-linear
# price/quantity offer** for providing the service: the first few MW are cheap, later MW cost
# more. When a device carries such an offer, POM prices *that device's* reserve award by its own
# curve rather than the flat cost.
#
# We will:
#
# 1. Build a small system that already has a reserve requirement.
# 2. Attach a per-device reserve offer curve to each contributing thermal unit.
# 3. Build and solve a unit-commitment problem whose reserve is priced by those offers.
# 4. Read back the reserve award.
#
# !!! note
#     This tutorial mirrors the `test_device_reserve_offers.jl` test in the POM repository.

# ## Packages
#
# Alongside `PowerOperationsModels` we use `PowerSystems` for the data model,
# `PowerSystemCaseBuilder` for a ready-made test system, `HiGHS` as the MILP solver, and
# `InfrastructureSystems`/`Dates` for the offer-curve and time-series types.

using PowerOperationsModels
using PowerSystems
using PowerSystemCaseBuilder
using HiGHS
using Dates
import PowerSystems as PSY
import InfrastructureSystems as IS

# ## Build a system with a reserve
#
# `c_sys5_uc` is a 5-bus unit-commitment case. Passing `add_reserves = true` attaches an
# upward reserve product, `Reserve1`, with a time-varying requirement and a set of contributing
# thermal units.

sys = build_system(PSITestSystems, "c_sys5_uc"; add_reserves = true)
reserve = get_component(VariableReserve{ReserveUp}, sys, "Reserve1")

# The devices that can supply this reserve are those that list it among their services:

contributors =
    [d for d in get_components(ThermalStandard, sys) if reserve in get_services(d)]

# ## Attach a per-device reserve offer
#
# A service bid has two parts on the device:
#
# 1. The device's operation cost must be an `OfferCurveCost` - here a
#    `MarketBidCost` - which is the cost type that can *carry* ancillary
#    service offers.
# 2. The offer curve itself is a `PiecewiseStepData` time series, named after the service and
#    attached with `set_service_bid!`.
#
# The offer curve's breakpoints are cumulative **quantities** (MW) and its values are the
# **marginal prices** (\$/MWh) of each segment. Below, each unit offers two 50 MW blocks: the
# first at `price`, the second 50% more expensive. We give each unit a slightly different price
# so the solver has a meaningful merit order to sort.
#
# The offer's time series must span the model's forecast window, so we build it over the same
# initial times, horizon, and resolution as the system's forecasts.

init_times = [DateTime("2024-01-01T00:00:00"), DateTime("2024-01-02T00:00:00")]
horizon = 24
resolution = Hour(1)

## One two-segment offer: 0-50 MW at `price`, 50-100 MW at 1.5 * price.
offer_curve(price) = IS.PiecewiseStepData([0.0, 50.0, 100.0], [price, price * 1.5])

for (i, g) in enumerate(contributors)
    pmax = get_max_active_power(g, PSY.NU)
    ## Keep the unit's own marginal energy cost as its energy offer: read the proportional
    ## (linear) term of its existing variable cost before we replace the operation cost.
    energy_slope =
        PSY.get_proportional_term(PSY.get_value_curve(PSY.get_variable(get_operation_cost(g))))
    ## Give the unit a MarketBidCost carrying that energy offer ...
    set_operation_cost!(
        g,
        MarketBidCost(;
            no_load_cost = LinearCurve(0.0),
            start_up = (hot = 0.0, warm = 0.0, cold = 0.0),
            shut_down = LinearCurve(0.0),
            incremental_offer_curves = make_market_bid_curve(
                [0.0, pmax], [energy_slope], 0.0; power_units = IS.NaturalUnit(),
            ),
        ),
    )
    ## ... and its per-device reserve offer, named after the service.
    price = 8.0 + 2.0 * i
    data = Dict(it => [offer_curve(price) for _ in 1:horizon] for it in init_times)
    ts = Deterministic(get_name(reserve), data, resolution)
    set_service_bid!(sys, g, reserve, ts, IS.NaturalUnit())
end

# Each contributor now exposes its offer through `get_services_bid`:

cost = get_operation_cost(first(contributors))
bid = get_services_bid(first(contributors), cost, reserve; len = 1)

# ## Build the problem template
#
# A `ProblemTemplate` pairs component types with formulations. We use a copper-plate
# unit-commitment template and add a `RangeReserve` service model for the reserve type.
# One `ServiceModel` covers every service of that type in the system.

template = PowerOperationsProblemTemplate(CopperPlateNetworkModel)
set_device_model!(template, PowerLoad, StaticPowerLoad)
set_device_model!(template, ThermalStandard, ThermalStandardUnitCommitment)
set_service_model!(template, ServiceModel(VariableReserve{ReserveUp}, RangeReserve))

# ## Build and solve
#
# When the model is built, POM detects that the contributing units carry reserve offers and adds
# the block-offer cost terms: for each unit it creates award segments `δ_k`, constrains them by
# the offer breakpoints (`δ_k ≤ P_{k+1} - P_k`), ties their sum to the reserve award
# (`Σ_k δ_k = award`), and prices them at the offer slopes in the objective
# (`Σ_k slope_k · δ_k · Δt`). Units *without* an offer keep the flat `DEFAULT_RESERVE_COST`.

model = DecisionModel(template, sys; optimizer = HiGHS.Optimizer)
build!(model; output_dir = mktempdir())
solve!(model)

# ## Read the results
#
# The reserve award is stored per `(service, device, time)`. Its output is in natural units (MW).

results = OptimizationProblemOutputs(model)
award = read_variable(results, "ActivePowerReserveVariable__VariableReserve__ReserveUp")
first(award, 5)

# !!! note
#     The internal block-offer variable (`PiecewiseLinearBlockReserveOffer`) that decomposes each
#     award into priced segments is not exported to results - it is an implementation detail of
#     the cost. What you read back is the reserve award itself; its *price* is what the offers
#     changed.

# ## Recap
#
# We started from a system with a flat-priced reserve, attached a piecewise offer curve to each
# contributing unit via `set_service_bid!`, and solved a unit-commitment problem in which the
# reserve is priced by those per-device offers. The only modeling switch was on the data side -
# swapping each contributor's cost to a `MarketBidCost` carrying the offer; the `RangeReserve`
# service model consumes the offers automatically.
