class BatteryBurnMock extends BatteryBurnRateView {

    // Set the label of the data field here.
    function initialize() {
        BatteryBurnRateView.initialize();
    }

	// Provide access to engine for testing
	function getEngine() {
		return engine;
	}
}