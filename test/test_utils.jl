@testset "test key with value" begin
    d = Dict("foo" => "bar")
    @test_throws ErrorException IOM.find_key_with_value(d, "fake")
end

@testset "Test ProgressMeter" begin
    @test !POM._progress_meter_enabled()
end

@testset "Axis Array to DataFrame" begin
    # The to_dataframe test the use of the `to_matrix` and `get_column_names` methods
    one = DenseAxisArray{Float64}(undef, 1:2)
    fill!(one, 1.0)
    mock_key = IOM.VariableKey(ActivePowerVariable, ThermalStandard)
    one_df = IOM.to_dataframe(one, mock_key)
    test_df = DataFrames.DataFrame(IOM.encode_key(mock_key) => [1.0, 1.0])
    @test one_df == test_df

    two = DenseAxisArray{Float64}(undef, ["a"], 1:2)
    fill!(two, 1.0)
    two_df = IOM.to_dataframe(two, mock_key)
    test_df = DataFrames.DataFrame(:a => [1.0, 1.0])
    @test two_df == test_df

    three = DenseAxisArray{Float64}(undef, ["a"], 1:2, 1:3)
    fill!(three, 1.0)
    @test_throws MethodError IOM.to_dataframe(three, mock_key)

    four = DenseAxisArray{Float64}(undef, ["a"], 1:2, 1:3, 1:5)
    fill!(four, 1.0)
    @test_throws MethodError IOM.to_dataframe(four, mock_key)

    sparse_num =
        JuMP.Containers.@container([i = 1:10, j = (i + 1):10, t = 1:24], 0.0 + i + j + t)
    @test_throws MethodError IOM.to_dataframe(sparse_num, mock_key)

    i_num = 1:10
    j_vals = Dict("$i" => string.((i + 1):11) for i in i_num)
    sparse_valid =
        JuMP.Containers.@container([i = string.(i_num), j = j_vals[i], t = 1:24], rand())
    df = IOM.to_dataframe(sparse_valid, mock_key)
    @test size(df) == (24, 55)
end

# Note: "Test simulation output directory name" from PSI omitted because
# _get_output_dir_name is in PSI's simulation code and hasn't been split out.
