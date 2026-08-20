import PowerNetworkMatrices as PNM

# Phase 2 (not started here) would replace POM's per-branch admittance derivation
# (`PNM.branch_admittance` / `PNM.get_series_susceptance`, in `AC_branches.jl`) with
# per-arc reads off the `Ybus` and its `VirtualFactorCore`. Both paths derive from the
# same device data and the same reduction, so this test is the gate: it checks whether
# they actually agree before any builder is allowed to switch over.
#
# The type-organized maps are derived, not stored on the reduction, so they come from
# `PNM.build_branch_maps_by_type(nrd)` here (POM's own `_finalize_network_reduction!` builds
# them into a `ReductionIndex` during real builds). Without them this test's outer loop
# iterates zero times and passes vacuously, so the call is required here.
# `PNM.YBUS_ELTYPE = ComplexF32` (definitions.jl:1): `Ybus.data`, and therefore
# `ArcAdmittanceMatrix`/`BA_Matrix`/`VirtualFactorCore.arc_susceptances` derived from it, carry
# only single-precision values even though their containers are declared `Float64`. The
# per-branch route (`get_series_susceptance` on the device's own `Float64` r/x) has no such
# limit. `rtol = 1e-6` is not arbitrary slack: it is ~10x the largest relative error measured
# (9.2e-8, consistent with Float32's ~1.2e-7 unit roundoff) across every case/reduction below,
# so it still fails loudly on a genuine formula divergence while tolerating the known storage
# truncation.
#
# NOT exercised here: a parallel branch group with r != 0 on any member. Both fixtures'
# parallel arcs are loss-free, so `get_series_susceptance(::AbstractBranchesParallel)`'s
# `sum(1/x_i)` (correct only when r_i == 0) is never checked against the impedance-correct
# combination BA_Matrix computes from the summed complex Ybus entry; a real disagreement there
# could be hiding under the Float32 noise floor this test already tolerates.
@testset "Per-arc DC susceptance matches the per-branch derivation" begin
    for case in ("case11_network_reductions", "c_sys14")
        sys = PSB.build_system(PSITestSystems, case)
        for reductions in (
            PNM.NetworkReduction[],
            PNM.NetworkReduction[PNM.RadialReduction()],
            PNM.NetworkReduction[PNM.RadialReduction(), PNM.DegreeTwoReduction()],
        )
            ybus = PNM.Ybus(
                sys;
                network_reductions = reductions,
                make_arc_admittance_matrices = true,
            )
            core = PNM.VirtualFactorCore(ybus)
            nrd = PNM.get_network_reduction_data(ybus)
            maps, name_to_arc, _ = PNM.build_branch_maps_by_type(nrd)
            arc_lookup = PNM.get_arc_lookup(core)
            per_arc = PNM._get_arc_susceptances(core)

            n_checked = 0
            for (branch_type, name_map) in name_to_arc
                for (name, (arc, map_name)) in name_map
                    # Arcs absorbed by the reduction (radial/degree-two) never make it
                    # into the retained arc_lookup; nothing to compare for them.
                    haskey(arc_lookup, arc) || continue
                    entry = maps[map_name][branch_type][arc]
                    from_branch = PNM.get_series_susceptance(entry, PSY.SU)
                    from_arc = per_arc[arc_lookup[arc]]
                    n_checked += 1
                    # Sign convention differs between the branch-side getter and the
                    # BA-extracted arc value (BA takes abs of the first nonzero per arc
                    # column); compare magnitudes only.
                    @test isapprox(abs(from_branch), abs(from_arc); rtol = 1e-6)
                end
            end
            @test n_checked > 0
        end
    end
end

# Series phase shift has no per-arc accessor: it is recoverable in principle from
# `angle(arc_admittance_from_to[arc, to_bus] / arc_admittance_to_from[arc, from_bus]) / 2`
# (the two ArcAdmittanceMatrix coupling terms, per `_pi_to_ybus`'s `Y12 = -Y_l*e^{jα}/tap`,
# `Y21 = -Y_l*e^{-jα}/tap`), but PNM exposes no function that does this — a caller would have
# to index `ArcAdmittanceMatrix.data` directly via `get_arc_lookup`/`get_bus_lookup`. Phase 2
# must keep `PNM.get_series_phase_shift` as a per-branch call.
