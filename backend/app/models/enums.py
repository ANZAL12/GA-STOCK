import enum


class UserRole(str, enum.Enum):
    admin = "admin"
    staff = "staff"


class SerialStatus(str, enum.Enum):
    available    = "available"
    dispatched   = "dispatched"
    damaged      = "damaged"
    lost         = "lost"
    under_repair = "under_repair"
    returned     = "returned"


class HistoryAction(str, enum.Enum):
    inward_recorded      = "inward_recorded"
    dispatched_matched   = "dispatched_matched"    # Case 1: known, Available, correct model
    dispatched_unmatched = "dispatched_unmatched"  # Case 2: not in system (old stock)
    dispatched_flagged   = "dispatched_flagged"    # Case 3/4: wrong status or wrong model
    returned             = "returned"
    status_changed       = "status_changed"        # Admin: Damaged / Lost / Under Repair
    inspected            = "inspected"             # Post-return inspection result


class InspectionResult(str, enum.Enum):
    available = "available"
    damaged   = "damaged"
