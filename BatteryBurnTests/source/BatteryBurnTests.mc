	(:test)
	function testAfterOneHour(logger) {
		var view = new BatteryBurnMock();
		var engine = view.getEngine();

		// Test that the engine was created successfully
		logger.debug("Engine initialized: " + (engine != null));

		// Test that the engine has the expected data point count (should be 0 initially)
		var dataPoints = engine.getDataPointCount();
		logger.debug("Initial data points: " + dataPoints);

		return engine != null && dataPoints == 0;
	}
