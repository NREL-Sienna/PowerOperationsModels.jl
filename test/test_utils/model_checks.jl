const GAEVF = JuMP.GenericAffExpr{Float64, VariableRef}
const GQEVF = JuMP.GenericQuadExpr{Float64, VariableRef}

function moi_tests(
    model::DecisionModel,
    vars::Int,
    interval::Int,
    lessthan::Int,
    greaterthan::Int,
    equalto::Int,
    binary::Bool,
    lessthan_quadratic::Union{Int, Nothing} = nothing,
)
    JuMPmodel = IOM.get_jump_model(model)
    @test JuMP.num_variables(JuMPmodel) == vars
    @test JuMP.num_constraints(JuMPmodel, GAEVF, MOI.Interval{Float64}) == interval
    @test JuMP.num_constraints(JuMPmodel, GAEVF, MOI.LessThan{Float64}) == lessthan
    @test JuMP.num_constraints(JuMPmodel, GAEVF, MOI.GreaterThan{Float64}) == greaterthan
    @test JuMP.num_constraints(JuMPmodel, GAEVF, MOI.EqualTo{Float64}) == equalto
    @test ((JuMP.VariableRef, MOI.ZeroOne) in JuMP.list_of_constraint_types(JuMPmodel)) ==
          binary
    !isnothing(lessthan_quadratic) &&
        @test JuMP.num_constraints(JuMPmodel, GQEVF, MOI.LessThan{Float64}) ==
              lessthan_quadratic
    return
end

function psi_constraint_test(
    model::DecisionModel,
    constraint_keys::Vector{<:IOM.ConstraintKey},
)
    constraints = IOM.get_constraints(model)
    for con in constraint_keys
        if get(constraints, con, nothing) !== nothing
            # Ensure constraint container does not have undefined entries:
            if typeof(constraints[con]) == DenseAxisArray
                @test all(x -> isassigned(constraints[con], x), eachindex(constraints[con]))
            else
                @test true
            end
        else
            @error con
            @test false
        end
    end
    return
end

function psi_aux_variable_test(
    model::DecisionModel,
    constraint_keys::Vector{<:IOM.AuxVarKey},
)
    op_container = IOM.get_optimization_container(model)
    vars = IOM.get_aux_variables(op_container)
    for key in constraint_keys
        @test get(vars, key, nothing) !== nothing
    end
    return
end

function psi_checkbinvar_test(
    model::DecisionModel,
    bin_variable_keys::Vector{<:IOM.VariableKey},
)
    container = IOM.get_optimization_container(model)
    for variable in bin_variable_keys
        for v in IOM.get_variable(container, variable)
            @test JuMP.is_binary(v)
        end
    end
    return
end

function psi_checkobjfun_test(model::DecisionModel, exp_type)
    model = IOM.get_jump_model(model)
    @test JuMP.objective_function_type(model) == exp_type
    return
end

function moi_lbvalue_test(
    model::DecisionModel,
    con_key::IOM.ConstraintKey,
    value::Number,
)
    for con in IOM.get_constraints(model)[con_key]
        @test JuMP.constraint_object(con).set.lower == value
    end
    return
end

function psi_checksolve_test(model::DecisionModel, status)
    model = IOM.get_jump_model(model)
    JuMP.optimize!(model)
    @test termination_status(model) in status
end

function psi_checksolve_test(model::DecisionModel, status, expected_output, tol = 0.0)
    res = solve!(model)
    model = IOM.get_jump_model(model)
    @test termination_status(model) in status
    obj_value = JuMP.objective_value(model)
    @test isapprox(obj_value, expected_output, atol = tol)
end

function psi_ptdf_lmps(res::OptimizationProblemOutputs, ptdf)
    cp_duals = read_dual(
        res,
        IOM.ConstraintKey(CopperPlateBalanceConstraint, PSY.System);
        table_format = TableFormat.WIDE,
    )
    λ = Matrix{Float64}(cp_duals[:, propertynames(cp_duals) .!= :DateTime])

    flow_ub = read_dual(
        res,
        IOM.ConstraintKey(FlowRateConstraint, PSY.Line, "ub");
        table_format = TableFormat.WIDE,
    )
    flow_lb = read_dual(
        res,
        IOM.ConstraintKey(FlowRateConstraint, PSY.Line, "lb");
        table_format = TableFormat.WIDE,
    )
    arcs = PNM.get_arc_axis(ptdf)
    nr = PNM.get_network_reduction_data(ptdf)
    branch_names = [PSY.get_name(nr.direct_branch_map[arc]) for arc in arcs]
    μ =
        Matrix{Float64}(flow_ub[:, branch_names]) .+
        Matrix{Float64}(flow_lb[:, branch_names])

    buses = get_components(Bus, IOM.get_source_data(res))
    lmps = OrderedDict()
    for bus in buses
        bus_number = get_number(bus)
        ptdf_col = [ptdf[arc, bus_number] for arc in arcs]
        lmps[get_name(bus)] = μ * ptdf_col
    end
    lmp = λ .+ DataFrames.DataFrame(lmps)
    return lmp[!, sort(propertynames(lmp))]
end

function check_variable_unbounded(
    model::DecisionModel,
    ::Type{T},
    ::Type{U},
) where {T <: IOM.VariableType, U <: PSY.Component}
    return check_variable_unbounded(model::DecisionModel, IOM.VariableKey(T, U))
end

function check_variable_unbounded(model::DecisionModel, var_key::IOM.VariableKey)
    psi_cont = IOM.get_optimization_container(model)
    variable = IOM.get_variable(psi_cont, var_key)
    for var in variable
        if JuMP.has_lower_bound(var) || JuMP.has_upper_bound(var)
            return false
        end
    end
    return true
end

function check_variable_bounded(
    model::DecisionModel,
    ::Type{T},
    ::Type{U},
) where {T <: IOM.VariableType, U <: PSY.Component}
    return check_variable_bounded(model, IOM.VariableKey(T, U))
end

function check_variable_bounded(model::DecisionModel, var_key::IOM.VariableKey)
    psi_cont = IOM.get_optimization_container(model)
    variable = IOM.get_variable(psi_cont, var_key)
    for var in variable
        if !JuMP.has_lower_bound(var) || !JuMP.has_upper_bound(var)
            return false
        end
    end
    return true
end

function check_flow_variable_values(
    model::DecisionModel,
    ::Type{T},
    ::Type{U},
    device_name::String,
    limit::Float64,
) where {T <: IOM.VariableType, U <: PSY.Component}
    psi_cont = IOM.get_optimization_container(model)
    variable = IOM.get_variable(psi_cont, T, U)
    for var in variable[device_name, :]
        if !(IOM.jump_value(var) <= (limit + 1e-2))
            @error "$device_name out of bounds $(IOM.jump_value(var))"
            return false
        end
    end
    return true
end

branch_rating_su(d::PSY.ACTransmission) = PSY.get_rating(d, PSY.SU)
branch_rating_su(d::PSY.TwoWindingTransformer) = PSY.get_rating(PSY.get_circuit(d), PSY.SU)

# StaticBranch under DCPNetworkModel carries its flow as the BThetaBranchFlow expression
# for every ACTransmission component.
# psy6: the ThreeWindingTransformer specialization is disabled pending transformer refactor
_dcp_static_branch_uses_expression(::Type{<:PSY.ACTransmission}) = true

function check_flow_variable_values(
    model::DecisionModel,
    ::Type{T},
    ::Type{U},
    device_name::String,
    limit::Float64,
) where {T <: FlowActivePowerVariable, U <: PSY.Component}
    psi_cont = IOM.get_optimization_container(model)
    template = model.template
    device_model = IOM.get_model(template, U)
    dev_formulation = IOM.get_formulation(device_model)
    net_formulation = IOM.get_network_formulation(template)
    if dev_formulation <: Union{StaticBranch, StaticBranchUnbounded} &&
       net_formulation <: PTDFNetworkModel
        variable = IOM.get_expression(psi_cont, PTDFBranchFlow, U)
    elseif dev_formulation <: StaticBranch && net_formulation <: DCPNetworkModel &&
           _dcp_static_branch_uses_expression(U)
        variable = IOM.get_expression(psi_cont, BThetaBranchFlow, U)
    else
        variable = IOM.get_variable(psi_cont, T, U)
    end
    for var in variable[device_name, :]
        if !(IOM.jump_value(var) <= (limit + 1e-2))
            @error "$device_name out of bounds $(IOM.jump_value(var))"
            return false
        end
    end
    return true
end

function check_flow_variable_values(
    model::DecisionModel,
    ::Type{T},
    ::Type{U},
    device_name::String,
    limit_min::Float64,
    limit_max::Float64,
) where {T <: IOM.VariableType, U <: PSY.Component}
    psi_cont = IOM.get_optimization_container(model)
    variable = IOM.get_variable(psi_cont, T, U)
    for var in variable[device_name, :]
        if !(IOM.jump_value(var) <= (limit_max + 1e-2)) ||
           !(IOM.jump_value(var) >= (limit_min - 1e-2))
            return false
        end
    end
    return true
end

function check_flow_variable_values(
    model::DecisionModel,
    ::Type{T},
    ::Type{U},
    device_name::String,
    limit_min::Float64,
    limit_max::Float64,
) where {T <: FlowActivePowerVariable, U <: PSY.Component}
    psi_cont = IOM.get_optimization_container(model)
    template = model.template
    device_model = IOM.get_model(template, U)
    dev_formulation = IOM.get_formulation(device_model)
    net_formulation = IOM.get_network_formulation(template)
    if dev_formulation <: Union{StaticBranch, StaticBranchUnbounded} &&
       net_formulation <: PTDFNetworkModel
        variable = IOM.get_expression(psi_cont, PTDFBranchFlow, U)
    elseif dev_formulation <: StaticBranch && net_formulation <: DCPNetworkModel &&
           _dcp_static_branch_uses_expression(U)
        variable = IOM.get_expression(psi_cont, BThetaBranchFlow, U)
    else
        variable = IOM.get_variable(psi_cont, T, U)
    end
    for var in variable[device_name, :]
        if !(IOM.jump_value(var) <= (limit_max + 1e-2)) ||
           !(IOM.jump_value(var) >= (limit_min - 1e-2))
            return false
        end
    end
    return true
end

function check_flow_variable_values(
    model::DecisionModel,
    ::Type{T},
    ::Type{U},
    ::Type{V},
    device_name::String,
    limit_min::Float64,
    limit_max::Float64,
) where {T <: IOM.VariableType, U <: IOM.VariableType, V <: PSY.Component}
    psi_cont = IOM.get_optimization_container(model)
    time_steps = IOM.get_time_steps(psi_cont)
    pvariable = IOM.get_variable(psi_cont, T, V)
    qvariable = IOM.get_variable(psi_cont, U, V)
    for t in time_steps
        fp = IOM.jump_value(pvariable[device_name, t])
        fq = IOM.jump_value(qvariable[device_name, t])
        flow = sqrt((fp)^2 + (fq)^2)
        if !(flow <= (limit_max + 1e-2)^2) || !(flow >= (limit_min - 1e-2)^2)
            return false
        end
    end
    return true
end

function check_flow_variable_values(
    model::DecisionModel,
    ::Type{T},
    ::Type{U},
    ::Type{V},
    device_name::String,
    limit::Float64,
) where {T <: IOM.VariableType, U <: IOM.VariableType, V <: PSY.Component}
    psi_cont = IOM.get_optimization_container(model)
    time_steps = IOM.get_time_steps(psi_cont)
    pvariable = IOM.get_variable(psi_cont, T, V)
    qvariable = IOM.get_variable(psi_cont, U, V)
    for t in time_steps
        fp = IOM.jump_value(pvariable[device_name, t])
        fq = IOM.jump_value(qvariable[device_name, t])
        flow = sqrt((fp)^2 + (fq)^2)
        if !(flow <= (limit + 1e-2)^2)
            return false
        end
    end
    return true
end

function IOM.jump_value(int::Int)
    @warn("This is for testing purposes only.")
    return int
end

function _check_constraint_bounds(bounds::IOM.ConstraintBounds, valid_bounds::NamedTuple)
    @test bounds.coefficient.min == valid_bounds.coefficient.min
    @test bounds.coefficient.max == valid_bounds.coefficient.max
    @test bounds.rhs.min == valid_bounds.rhs.min
    @test bounds.rhs.max == valid_bounds.rhs.max
end

function _check_variable_bounds(bounds::IOM.VariableBounds, valid_bounds::NamedTuple)
    @test bounds.bounds.min == valid_bounds.min
    @test bounds.bounds.max == valid_bounds.max
end

function check_duration_on_initial_conditions_values(
    model,
    ::Type{T},
) where {T <: PSY.Component}
    initial_conditions_data =
        IOM.get_initial_conditions_data(IOM.get_optimization_container(model))
    duration_on_data = IOM.get_initial_condition(
        IOM.get_optimization_container(model),
        InitialTimeDurationOn(),
        T,
    )
    for ic in duration_on_data
        name = PSY.get_name(ic.component)
        on_var = IOM.get_initial_condition_value(initial_conditions_data, OnVariable(), T)[
            name,
            1,
        ]
        duration_on = IOM.jump_value(IOM.get_value(ic))
        if on_var == 1.0 && PSY.get_status(ic.component)
            @test duration_on == PSY.get_time_at_status(ic.component)
        elseif on_var == 1.0 && !PSY.get_status(ic.component)
            @test duration_on == 0.0
        end
    end
end

function check_duration_off_initial_conditions_values(
    model,
    ::Type{T},
) where {T <: PSY.Component}
    initial_conditions_data =
        IOM.get_initial_conditions_data(IOM.get_optimization_container(model))
    duration_off_data = IOM.get_initial_condition(
        IOM.get_optimization_container(model),
        InitialTimeDurationOff(),
        T,
    )
    for ic in duration_off_data
        name = PSY.get_name(ic.component)
        on_var = IOM.get_initial_condition_value(initial_conditions_data, OnVariable(), T)[
            name,
            1,
        ]
        duration_off = IOM.jump_value(IOM.get_value(ic))
        if on_var == 0.0 && !PSY.get_status(ic.component)
            @test duration_off == PSY.get_time_at_status(ic.component)
        elseif on_var == 0.0 && PSY.get_status(ic.component)
            @test duration_off == 0.0
        end
    end
end

function check_energy_initial_conditions_values(model, ::Type{T}) where {T <: PSY.Component}
    ic_data = IOM.get_initial_condition(
        IOM.get_optimization_container(model),
        InitialEnergyLevel(),
        T,
    )
    for ic in ic_data
        d = ic.component
        name = PSY.get_name(ic.component)
        e_value = IOM.jump_value(IOM.get_value(ic))
        @test PSY.get_initial_storage_capacity_level(d) *
              PSY.get_storage_capacity(d, PSY.SU) *
              PSY.get_conversion_factor(d) == e_value
    end
end

function check_energy_initial_conditions_values(model, ::Type{T}) where {T <: PSY.HydroGen}
    ic_data = IOM.get_initial_condition(
        IOM.get_optimization_container(model),
        InitialEnergyLevel(),
        T,
    )
    for ic in ic_data
        name = PSY.get_name(ic.component)
        e_value = IOM.jump_value(IOM.get_value(ic))
        @test PSY.get_initial_storage(ic.component) == e_value
    end
end

function check_status_initial_conditions_values(model, ::Type{T}) where {T <: PSY.Component}
    initial_conditions =
        IOM.get_initial_condition(IOM.get_optimization_container(model), DeviceStatus(), T)
    initial_conditions_data =
        IOM.get_initial_conditions_data(IOM.get_optimization_container(model))
    for ic in initial_conditions
        name = PSY.get_name(ic.component)
        status = IOM.get_initial_condition_value(initial_conditions_data, OnVariable(), T)[
            name,
            1,
        ]
        @test IOM.jump_value(IOM.get_value(ic)) == status
    end
end

function check_active_power_initial_condition_values(
    model,
    ::Type{T},
) where {T <: PSY.Component}
    initial_conditions =
        IOM.get_initial_condition(IOM.get_optimization_container(model), DevicePower(), T)
    initial_conditions_data =
        IOM.get_initial_conditions_data(IOM.get_optimization_container(model))
    for ic in initial_conditions
        name = PSY.get_name(ic.component)
        power = IOM.get_initial_condition_value(
            initial_conditions_data,
            ActivePowerVariable(),
            T,
        )[
            name,
            1,
        ]
        @test IOM.jump_value(IOM.get_value(ic)) == power
    end
end

function check_active_power_abovemin_initial_condition_values(
    model,
    ::Type{T},
) where {T <: PSY.Component}
    initial_conditions = IOM.get_initial_condition(
        IOM.get_optimization_container(model),
        POM.DeviceAboveMinPower(),
        T,
    )
    initial_conditions_data =
        IOM.get_initial_conditions_data(IOM.get_optimization_container(model))
    for ic in initial_conditions
        name = PSY.get_name(ic.component)
        power = IOM.get_initial_condition_value(
            initial_conditions_data,
            PowerAboveMinimumVariable(),
            T,
        )[
            name,
            1,
        ]
        @test IOM.jump_value(IOM.get_value(ic)) == power
    end
end

function check_initialization_variable_count(
    model,
    ::S,
    ::Type{T},
) where {S <: IOM.VariableType, T <: PSY.Component}
    container = IOM.get_optimization_container(model)
    initial_conditions_data = IOM.get_initial_conditions_data(container)
    no_component = length(PSY.get_components(PSY.get_available, T, model.sys))
    variable = IOM.get_initial_condition_value(initial_conditions_data, S(), T)
    rows, cols = size(variable)
    @test rows * cols == no_component * IOM.INITIALIZATION_PROBLEM_HORIZON_COUNT
end

function check_variable_count(
    model,
    ::Type{S},
    ::Type{T},
) where {S <: IOM.VariableType, T <: PSY.Component}
    no_component = length(PSY.get_components(PSY.get_available, T, model.sys))
    time_steps = IOM.get_time_steps(IOM.get_optimization_container(model))[end]
    variable = IOM.get_variable(IOM.get_optimization_container(model), S, T)
    @test length(variable) == no_component * time_steps
end

function check_initialization_constraint_count(
    model,
    ::Type{S},
    ::Type{T};
    filter_func = PSY.get_available,
    meta = IOM.CONTAINER_KEY_EMPTY_META,
) where {S <: IOM.ConstraintType, T <: PSY.Component}
    container =
        get_initial_conditions_model_container(IOM.get_internal(model))
    no_component = length(PSY.get_components(filter_func, T, model.sys))
    time_steps = IOM.get_time_steps(container)[end]
    constraint = IOM.get_constraint(container, S, T, meta)
    @test length(constraint) == no_component * time_steps
end

function check_constraint_count(
    model,
    ::Type{S},
    ::Type{T};
    filter_func = PSY.get_available,
    meta = IOM.CONTAINER_KEY_EMPTY_META,
) where {S <: IOM.ConstraintType, T <: PSY.Component}
    no_component = length(PSY.get_components(filter_func, T, model.sys))
    time_steps = IOM.get_time_steps(IOM.get_optimization_container(model))[end]
    constraint = IOM.get_constraint(IOM.get_optimization_container(model), S, T, meta)
    @test length(constraint) == no_component * time_steps
end

function check_constraint_count(
    model,
    ::Type{POM.RampConstraint},
    ::Type{T},
) where {T <: PSY.Component}
    container = IOM.get_optimization_container(model)
    device_name_set =
        PSY.get_name.(
            IOM._get_ramp_constraint_devices(
                container,
                PSY.get_available_components(T, model.sys),
            ),
        )
    check_constraint_count(
        model,
        POM.RampConstraint,
        T;
        meta = "up",
        filter_func = x -> x.name in device_name_set,
    )
    check_constraint_count(
        model,
        POM.RampConstraint,
        T;
        meta = "dn",
        filter_func = x -> x.name in device_name_set,
    )
    return
end

function check_constraint_count(
    model,
    ::Type{POM.DurationConstraint},
    ::Type{T},
) where {T <: PSY.Component}
    container = IOM.get_optimization_container(model)
    resolution = IOM.get_resolution(container)
    steps_per_hour = 60 / Dates.value(Dates.Minute(resolution))
    fraction_of_hour = 1 / steps_per_hour
    duration_devices = filter!(
        x -> !(
            PSY.get_time_limits(x).up <= fraction_of_hour &&
            PSY.get_time_limits(x).down <= fraction_of_hour
        ),
        collect(get_components(PSY.get_available, T, model.sys)),
    )
    device_name_set = PSY.get_name.(duration_devices)
    check_constraint_count(
        model,
        POM.DurationConstraint,
        T;
        meta = "up",
        filter_func = x -> x.name in device_name_set,
    )
    return check_constraint_count(
        model,
        POM.DurationConstraint,
        T;
        meta = "dn",
        filter_func = x -> x.name in device_name_set,
    )
end

"""
Return a DataFrame from a CSV file.
"""
function read_dataframe(filename::AbstractString)
    return CSV.read(filename, DataFrames.DataFrame)
end

function _slack_indicator_value(v, var)
    if v === var
        return 1.0
    else
        return 0.0
    end
end

"""
Residual coefficient of `var` in constraint `con`. Quadratic and nonlinear rows cannot be
read with `JuMP.normalized_coefficient`, but a slack enters every row linearly, so its
coefficient is `value(slack=1, rest=0) − value(rest=0)`, which reads uniformly across
affine, quadratic and nonlinear rows.
"""
function slack_residual_coefficient(con, var)
    f = JuMP.constraint_object(con).func
    base = JuMP.value(v -> 0.0, f)
    return JuMP.value(v -> _slack_indicator_value(v, var), f) - base
end

#################################################################################
# Trait-vs-reality guards
#
# Generalized from the `slack_spec` testset in test_native_dcp_acp_models.jl. For a trait
# axis, assert that what the trait DECLARES matches what a real `build!` actually
# produces — so "the trait says yes" and "the constructor builds it" cannot drift apart.
#
# The `forbidden` list is not redundant with `declared`. On an active-power-only network a
# leaked `add_to_expression!(..., ReactivePowerBalance, ...)` is a loud `KeyError`, but a
# leaked `add_variables!(..., ReactivePowerVariable, ...)` is SILENT: free, uncosted
# columns that change neither the objective nor the solution. Only an explicit
# absence assertion catches that one.
#################################################################################

"""
A container a trait table promises (or forbids). `meta` defaults to the empty meta.
"""
struct ContainerSpec
    kind::Symbol   # :variable | :constraint | :expression | :parameter | :aux_variable
    entry_type::DataType
    component_type::DataType
    meta::String
end

ContainerSpec(kind::Symbol, entry_type::DataType, component_type::DataType) =
    ContainerSpec(kind, entry_type, component_type, IOM.CONTAINER_KEY_EMPTY_META)

function _fetch_container(container, s::ContainerSpec)
    s.kind === :variable &&
        return IOM.get_variable(container, s.entry_type, s.component_type, s.meta)
    s.kind === :constraint &&
        return IOM.get_constraint(container, s.entry_type, s.component_type, s.meta)
    s.kind === :expression &&
        return IOM.get_expression(container, s.entry_type, s.component_type, s.meta)
    s.kind === :parameter &&
        return IOM.get_parameter(container, s.entry_type, s.component_type, s.meta)
    return IOM.get_aux_variable(container, s.entry_type, s.component_type, s.meta)
end

"""
Whether `s` exists and is non-empty in `container`. A missing container throws from the
IOM accessor rather than returning `nothing`, so absence is caught here.
"""
function container_exists(container, s::ContainerSpec)
    try
        return !isempty(_fetch_container(container, s))
    catch
        return false
    end
end

"""
    assert_trait_matches_build(axis_name, cases; declared, forbidden, template_for, extra_checks)

Trait-vs-reality guard for one trait axis.

`cases` is an iterable of `(network_formulation, optimizer, sys, formulations)`. For each
`(formulation, network_formulation)` pair this builds a real `DecisionModel` and asserts

1. every `ContainerSpec` in `declared(F, N)` exists and is non-empty;
2. every `ContainerSpec` in `forbidden(F, N)` does **not** exist;
3. `extra_checks(container, F, N)` passes — the hook for coefficient, sign and row-wiring
   assertions.

`declared` and `forbidden` MUST be computed by calling the trait function under test.
Restating the expected containers by hand reduces this to a test that agrees with itself.

Cannot catch: container-set-preserving reorderings (a collapse that moves an
`add_variables!` call produces an identical container set), coefficient errors inside a
container that exists unless `extra_checks` asserts them, and cross-stage behavior such as
which construct stage registered an initial condition.
"""
function assert_trait_matches_build(
    axis_name::String,
    cases;
    declared,
    forbidden = (F, N) -> ContainerSpec[],
    template_for,
    extra_checks = (container, F, N) -> nothing,
)
    for (network_formulation, optimizer, sys, formulations) in cases
        for formulation in formulations
            @testset "$axis_name: $network_formulation / $formulation" begin
                model = DecisionModel(
                    template_for(formulation, network_formulation),
                    sys;
                    optimizer = optimizer,
                )
                @test build!(model; output_dir = mktempdir(; cleanup = true)) ==
                      IOM.ModelBuildStatus.BUILT
                container = IOM.get_optimization_container(model)
                for spec in declared(formulation, network_formulation)
                    @test container_exists(container, spec)
                end
                for spec in forbidden(formulation, network_formulation)
                    @test !container_exists(container, spec)
                end
                extra_checks(container, formulation, network_formulation)
            end
        end
    end
    return
end

"""
Concrete subtypes of `root` reachable as exported-or-internal bindings of `mod`. Scans the
module's own names rather than `InteractiveUtils.subtypes` so the test environment needs no
extra dependency; that also scopes the answer to formulations this package actually
defines, which is what the coverage guard is asking about.
"""
function _concrete_subtypes_in(mod::Module, root::DataType)
    out = DataType[]
    for name in names(mod; all = true)
        isdefined(mod, name) || continue
        value = getfield(mod, name)
        value isa DataType || continue
        (isconcretetype(value) && value <: root) || continue
        value in out || push!(out, value)
    end
    return out
end

"""
    assert_axis_coverage(root, covered; mod = PowerOperationsModels)

Completeness guard: every concrete subtype of `root` defined in `mod` must appear in
`covered`, so adding a network formulation without adding a trait method and a test case
fails here rather than silently escaping the trait table.
"""
function assert_axis_coverage(root::DataType, covered; mod::Module = PowerOperationsModels)
    missing_types = setdiff(_concrete_subtypes_in(mod, root), collect(covered))
    @test isempty(missing_types)
    return
end
