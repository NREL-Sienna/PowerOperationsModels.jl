function Base.show(io::IO, ::MIME"text/plain", input::PowerOperationsProblemTemplate)
    _show_method(io, input, :auto)
end

function Base.show(io::IO, ::MIME"text/html", input::PowerOperationsProblemTemplate)
    _show_method(io, input, :html; stand_alone = false, table_format = PSY.tf_html_simple)
end

function _show_method(
    io::IO,
    template::PowerOperationsProblemTemplate,
    backend::Symbol;
    kwargs...,
)
    network_model = get_network_model(template)
    table = [
        "Network Model" string(get_network_formulation(network_model))
        "Slacks" get_use_slacks(network_model)
        "PTDF" !isnothing(get_network_matrix(network_model))
        "Duals" isempty(get_duals(network_model)) ? "None" : string.(get_duals(network_model))
        "HVDC Network Model" isnothing(get_hvdc_network_model(network_model)) ? "None" : replace(string(get_hvdc_network_model(network_model)), r"[()]" => "")
    ]

    PrettyTables.pretty_table(
        io,
        table;
        backend = backend,
        show_column_labels = false,
        title = "Network Model",
        alignment = :l,
        kwargs...,
    )

    devices = get_device_models(template)
    println(io)
    header = ["Device Type", "Formulation", "Slacks"]

    table = Matrix{String}(undef, length(devices), length(header))
    for (ix, model) in enumerate(values(devices))
        table[ix, 1] = string(get_component_type(model))
        table[ix, 2] = string(get_formulation(model))
        table[ix, 3] = string(model.use_slacks)
    end

    PrettyTables.pretty_table(
        io,
        table;
        backend = backend,
        column_labels = header,
        title = "Device Models",
        alignment = :l,
    )

    branches = get_branch_models(template)
    if !isempty(branches)
        println(io)
        header = ["Branch Type", "Formulation", "Slacks"]

        table = Matrix{String}(undef, length(branches), length(header))
        for (ix, model) in enumerate(values(branches))
            table[ix, 1] = string(get_component_type(model))
            table[ix, 2] = string(get_formulation(model))
            table[ix, 3] = string(model.use_slacks)
        end

        PrettyTables.pretty_table(
            io,
            table;
            column_labels = header,
            backend = backend,
            title = "Branch Models",
            alignment = :l,
            kwargs...,
        )
    end

    services = get_service_models(template)
    if !isempty(services)
        println(io)
        # Service models are keyed per type (`Symbol(service_type)`), one model per type -
        # no per-name entries, so the table is just type / formulation / slacks.
        header = ["Service Type", "Formulation", "Slacks"]
        table = Matrix{String}(undef, length(services), length(header))
        for (ix, (_, model)) in enumerate(services)
            table[ix, 1] = string(get_component_type(model))
            table[ix, 2] = string(get_formulation(model))
            table[ix, 3] = string(model.use_slacks)
        end

        PrettyTables.pretty_table(
            io,
            table;
            column_labels = header,
            backend = backend,
            title = "Service Models",
            alignment = :l,
            kwargs...,
        )
    end
    return
end
