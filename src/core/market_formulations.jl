"""
Market model formulation that clears market components against a single system-wide
settlement balance: one `PSY.System`-keyed [`SettlementBalanceConstraint`](@ref) row per
timestep, separate from the network's physical [`CopperPlateBalanceConstraint`](@ref)/nodal
balance. The physical balance keeps its `StaticPowerLoad` parameters and gains zero-cost
`SystemBalanceSlackUp`/`SystemBalanceSlackDown` while a market model is present, since the
settlement equality — not the physical slack — is the binding accounting identity.
"""
struct SettlementMarket <: IOM.AbstractMarketModel end
