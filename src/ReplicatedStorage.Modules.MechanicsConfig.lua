local AXLE_BASE = {
	category = "mechanical",
	constraint = "HingeConstraint",
	motor = true,
	torque = 100000,
	connectsToNeighbors = true,
	subGrid = true,
}

local HALF_AXLE_BASE = {
	category = "mechanical",
	constraint = "HingeConstraint",
	motor = true,
	torque = 80000,
	connectsToNeighbors = true,
	subGrid = true,
}

local RAW_AXLE_BASE = {
	category = "mechanical",
	constraint = "HingeConstraint",
	motor = true,
	torque = 60000,
	connectsToNeighbors = true,
	subGrid = true,
}

local WHEEL_BASE = {
	category = "mechanical",
	constraint = "CylindricalConstraint",
	motor = true,
	torque = 50000,
	axis = "X",
	connectsToNeighbors = true,
	runtime = "wheel",
	material = "Rubber",
	friction = 1.5,
	elasticity = 0.95,
	density = 1.3,
	frictionWeight = 3,
	subGrid = true,
}

local function merge(base, overrides)
	local t = {}
	for k, v in base do t[k] = v end
	for k, v in overrides do t[k] = v end
	return t
end

return {
	------------------------------------------------------------
	-- Standard Axle (full 2x2x2, original Spinner part)
	------------------------------------------------------------

	Axle = {
		category = "mechanical",
		constraint = "HingeConstraint",
		motor = true,
		speed = 2,
		torque = 100000,
		axis = "Y",
		connectsToNeighbors = true,
		actionSides = { "Top" },
	},

	------------------------------------------------------------
	-- Normal Sized Axles (sub-grid)
	------------------------------------------------------------

	LargeAxle = merge(AXLE_BASE, { speed = 1.5, axis = "X" }),
	MediumAxle = merge(AXLE_BASE, { speed = 2, axis = "X" }),
	SmallAxle = merge(AXLE_BASE, { speed = 3, axis = "X" }),
	TinyAxle = merge(AXLE_BASE, { speed = 4, axis = "X" }),

	------------------------------------------------------------
	-- Half Sized Axles (sub-grid)
	------------------------------------------------------------

	HalfLargeAxle = merge(HALF_AXLE_BASE, { speed = 1.5, axis = "X" }),
	HalfMediumAxle = merge(HALF_AXLE_BASE, { speed = 2, axis = "X" }),
	HalfSmallAxle = merge(HALF_AXLE_BASE, { speed = 3, axis = "X" }),
	HalfTinyAxle = merge(HALF_AXLE_BASE, { speed = 4, axis = "X" }),

	------------------------------------------------------------
	-- Raw Axles (just the cylinder, sub-grid)
	------------------------------------------------------------

	RawLargeAxle = merge(RAW_AXLE_BASE, { speed = 1.5, axis = "X" }),
	RawMediumAxle = merge(RAW_AXLE_BASE, { speed = 2, axis = "X" }),
	RawSmallAxle = merge(RAW_AXLE_BASE, { speed = 3, axis = "X" }),
	RawTinyAxle = merge(RAW_AXLE_BASE, { speed = 4, axis = "X" }),

	------------------------------------------------------------
	-- Wheels (sub-grid)
	------------------------------------------------------------

	NormalWheelBlock = merge(WHEEL_BASE, { speed = 4 }),
	ThickWheelBlock = merge(WHEEL_BASE, { speed = 3, friction = 2.0 }),
	ThinWheelBlock = merge(WHEEL_BASE, { speed = 5, friction = 1.0 }),

	------------------------------------------------------------
	-- Passive rotational
	------------------------------------------------------------

	Hinge = {
		category = "mechanical",
		constraint = "HingeConstraint",
		motor = false,
		axis = "Y",
		limits = { -90, 90 },
		connectsToNeighbors = true,
	},

	Bearing = {
		category = "mechanical",
		constraint = "BallSocketConstraint",
		axis = "Y",
		connectsToNeighbors = true,
		actionSides = { "Top" },
		twistLimits = { -180, 180 },
	},

	------------------------------------------------------------
	-- Linear
	------------------------------------------------------------

	Piston = {
		category = "mechanical",
		constraint = "PrismaticConstraint",
		motor = true,
		speed = 2,
		force = 500,
		axis = "Y",
		limits = { 0, 4 },
		connectsToNeighbors = true,
	},

	Spring = {
		category = "mechanical",
		constraint = "SpringConstraint",
		connectsToNeighbors = true,
		stiffness = 500,
		damping = 50,
		freeLength = 4,
		minLength = 1,
		maxLength = 8,
	},

	Rope = {
		category = "mechanical",
		constraint = "RopeConstraint",
		connectsToNeighbors = true,
		length = 10,
	},

	------------------------------------------------------------
	-- Force blocks
	------------------------------------------------------------

	Balloon = {
		category = "force",
		connectsToNeighbors = true,
		runtime = "balloon",
		liftForce = 800,
	},

	BalloonBlock = {
		category = "force",
		connectsToNeighbors = true,
		runtime = "balloon",
		liftForce = 800,
	},

	Thruster = {
		category = "force",
		connectsToNeighbors = true,
		actionSides = { "Bottom" },
		runtime = "thruster",
		thrustForce = 1200,
		axis = "Y",
	},

	ThrusterBlock = {
		category = "force",
		connectsToNeighbors = true,
		actionSides = { "Bottom" },
		runtime = "thruster",
		thrustForce = 1200,
		axis = "Y",
	},

	------------------------------------------------------------
	-- Interactive
	------------------------------------------------------------

	RemovablePart = {
		category = "interactive",
		activatable = true,
		behavior = "remove",
	},
}
