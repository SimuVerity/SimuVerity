class SimuVerityError(RuntimeError):
    """A user-facing contract or runtime error."""


class ContractError(SimuVerityError):
    """A benchmark input violates a public contract."""


class InfrastructureError(SimuVerityError):
    """The execution infrastructure failed before a score was produced."""

