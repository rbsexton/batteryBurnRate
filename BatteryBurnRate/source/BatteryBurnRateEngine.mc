using Toybox.System;
using Toybox.Time;
using Toybox.Time.Gregorian;
import Toybox.Lang;

// BatteryBurnRateEngine
// Calculation engine for battery burn rate estimation using least squares linear regression.
// Separated from UI concerns following MVC architecture pattern.

class BatteryBurnRateEngine {

    // Algorithm, v2.
    // Capture 16 data points per hour, plus a data point on battery
    // level change.   So the estimate is based upon at most one hour of
    // data, or less if the battery is dropping faster.

    // Primary data point collection.
    const      pdp_data_points    = 16; // This make masks easy.   ATTN! Must be 2^N
    const      pdp_data_mask      = pdp_data_points - 1;

    // The timeout determines the baseline sampling rate.  Keep at most a hour of data.
    const      pdp_sample_timeout_tunable = 225*1000; // Capture a data point if no change...
    var        pdp_sample_timeout_ms;                 // The countdown variable.
    var        pdp_sample_time_last_ms;

    hidden var pdp_data_battery as Array<Float>;        // Battery data points.
    hidden var pdp_data_time_ut as Array<Number>;       // Timestamps to go with the data.
    hidden var pdp_data_i;	            // Index.  Use with a mask.

    hidden var start_t0_ut;             // For logging

    hidden var pdp_battery_last;        // Trigger data collection on  battery level change.

    hidden var charging;                // Save the state.
    hidden var burn_rate_slope;         // Burn rate as a slope.

    // ----------------------------------------------------------
    // Constructor
    // ----------------------------------------------------------
    function initialize(time_now as Time.Moment) {
        pdp_data_time_ut = new Array<Number>[ pdp_data_points ];
        pdp_data_battery = new Array<Float> [ pdp_data_points ];
        pdp_battery_last = 200.0; // Set this to an invalid value so that it triggers immediately.

        start_t0_ut      =  time_now.value();

        charging = null;

        reset();

        var today = Gregorian.info(time_now, Time.FORMAT_MEDIUM);
        var dateString = Lang.format(
            "$1$-$2$-$3$ $4$:$5$:$6$",
            [
            today.year, today.month, today.day,
            today.hour, today.min, today.sec
            ] );

        System.println("# BatteryBurnRate v3 Started " + dateString);
        System.println("# time(h), time(s), battery level, charging(Y/N)");
    }

    // ----------------------------------------------------------
    // Reset the data collection system.
    // ----------------------------------------------------------
   function reset() {
        pdp_data_i = 0; // The total number of samples.
        pdp_sample_time_last_ms = System.getTimer();
        pdp_sample_timeout_ms   = pdp_sample_timeout_tunable / 2;

        burn_rate_slope = 0.0;
    }

    // ----------------------------------------------------------
    // Calculate the least squares fit of the data.
    // ----------------------------------------------------------
    function update_estimate() {

        // If there isn't enough data, stop now.
        if ( pdp_data_i < 2 ) {
            burn_rate_slope = 0.0;
            return;
            }

        // Fit to whatever is present, even if its not much.
        var data_offset  = pdp_data_i; // This should be the oldest point.

        // Partial data is a special case. Start at zero.
        if ( data_offset < pdp_data_points ) { data_offset = 0; }

        var fitsize = pdp_data_i;
        if ( fitsize > pdp_data_points ) { fitsize = pdp_data_points; }

        // Make a snapstop of the real data and align it + normalize to hours.
        // Recall that the data buffer pointer is always pointing to the oldest item in the ring.
        var data_x       = new [ pdp_data_points ];
        var data_y       = new [ pdp_data_points ];

        {
            var t0 = pdp_data_time_ut[data_offset & pdp_data_mask];

            // Convert from seconds to hours...

            for (var i=0; i < fitsize; i++) {
                var adj_i = (i + data_offset) & pdp_data_mask;

                var ut = pdp_data_time_ut[adj_i];

                // Seconds to Hours.
                data_x[i] = (ut - t0) *  0.000277777777777777777777;
                data_y[i] = pdp_data_battery[adj_i];
            }
        }

    // From https://www.mathsisfun.com/data/least-squares-regression.html

    {
        var sum_x, sum_y, sum_xx, sum_xy;
        sum_x = 0.0; sum_y = 0.0; sum_xx = 0.0; sum_xy = 0.0;
        for (var i=0; i < fitsize; i++){
            sum_x  += data_x[i];
            sum_y  += data_y[i];
            sum_xx += data_x[i] * data_x[i];
            sum_xy += data_x[i] * data_y[i];
        }

        var num   = fitsize * sum_xy - sum_x * sum_y;
        var denom = fitsize * sum_xx - sum_x * sum_x;

        // Check for divide by zero and zero slope
        if ( num == 0.0 || denom == 0.0 ) {
            burn_rate_slope = 0.0;
        } else {
            burn_rate_slope = num / denom;
        }
    }

    // The input unit is already in percent.
    }

    // ----------------------------------------------------------
    // Notes on data collection -
    // The primary collection loop uses the system ms timer along with
    // a running error a la Bresenhams algorithm.
    // 
    // Collect a data point when the Battery level changes or there has been a timeout.
    // The net result of this is that the app keeps at most an hour of data,
    // and less if the battery level is changing fast.
    //
    // THis uses the re-running millisecond timer, getTimer(). 
    // That rolls over every 25 after the device is powered on.
    //
    // Time.
    // ----------------------------------------------------------
    function update(battery_pct, n_charging, now_s, now_ms) {

        // Pre-business.   Check for a change in system battery state,
        // and if it happens, reset data collection and re-start measurement.
        // do this rather than exiting early so that the rest of the system is
        // in a good state.
        if ( ( n_charging == null ) || ( n_charging != charging ) ) {
            charging = n_charging;
            reset();
            return;
        }

        // Use Bresenhams algorithm to determine when to sample.
        // Update the timeout.
        var timeout_happened;
        {
            var timer_ms = now_ms;
            var duration = timer_ms - pdp_sample_time_last_ms;
            pdp_sample_time_last_ms = timer_ms;

            pdp_sample_timeout_ms -= duration; // Use Bresenhams Algorithm.

            if ( pdp_sample_timeout_ms  <= 0 ) {
                timeout_happened = 1;
                pdp_sample_timeout_ms += pdp_sample_timeout_tunable;
            }
            else { timeout_happened = 0; }
        }

        // If the value of the battery percentage has changed
        // or a timeout has occurred, capture a data point.
        if ( timeout_happened == 0 && pdp_battery_last == battery_pct ) { return; }

        var i      = pdp_data_i & pdp_data_mask;

        pdp_data_time_ut[i] =  now_s.value();

        // Logging
        if ( pdp_battery_last != battery_pct ) {
            var ts = pdp_data_time_ut[i] - start_t0_ut;
            var formatted = "";
            formatted += ts* 0.000277777777777777777777 + ",";
            formatted += ts + ",";
            formatted += battery_pct + ",";
            if ( charging == 0 ) {
                formatted += "N";
            } else {
                formatted += "Y";
            }

            System.println(formatted);
        }

        pdp_data_battery[i] = battery_pct;
        pdp_battery_last    = battery_pct;

        pdp_data_i++;

        update_estimate();
    }

	// Public accessors for the View layer

    function getBurnRate() {
        return burn_rate_slope;
    }

    function getCharging() {
        return charging;
    }

    function getDataPointCount() {
        return pdp_data_i;
    }

    // Expose internal state for testing
    function _test_getBatteryLast() {
        return pdp_battery_last;
    }

    function _test_setBatteryLast(value) {
        pdp_battery_last = value;
    }

    function _test_setDataPoint(index, battery, time_ut) {
        pdp_data_battery[index] = battery;
        pdp_data_time_ut[index] = time_ut;
    }

    function _test_setDataIndex(value) {
        pdp_data_i = value;
    }

    function _test_callUpdateEstimate() {
        update_estimate();
    }
}

// -------------------------------------------------------------------------
// Unit Testing
// -------------------------------------------------------------------------

import Toybox.Test;

// Mock class for SystemStats
class MockSystemStats {
    var battery;
    var charging;

    function initialize(batteryLevel, isCharging) {
        battery = batteryLevel;
        charging = isCharging;
    }
}

// -------------------------------------------
// Test 1: Engine initializes correctly
// -------------------------------------------
(:test)
function EngineInitTest(logger as Logger) as Boolean {
    logger.debug("EngineInitTest: Testing engine initialization");

    var testTime = Gregorian.moment({:year=>2025, :month=>1, :day=>1, :hour=>8, :minute=>0, :second=>0});
    var engine = new BatteryBurnRateEngine(testTime);

    // Check initial burn rate is 0
    Test.assertMessage(engine.getBurnRate() == 0.0, "Initial burn rate should be 0");

    // Check initial data point count is 0
    Test.assertMessage(engine.getDataPointCount() == 0, "Initial data point count should be 0");

    // Check charging is null initially
    Test.assertMessage(engine.getCharging() == null, "Initial charging state should be null");

    logger.debug("EngineInitTest: PASSED");
    return true;
}

// -------------------------------------------
// Test 2: Engine reset clears state
// -------------------------------------------
(:test)
function EngineResetTest(logger as Logger) as Boolean {
    logger.debug("EngineResetTest: Testing reset functionality");

    var testTime = Gregorian.moment({:year=>2025, :month=>1, :day=>1, :hour=>8, :minute=>0, :second=>0});
    var engine = new BatteryBurnRateEngine(testTime);

    // Simulate some data by directly manipulating internal state
    engine._test_setDataIndex(5);

    // Reset the engine
    engine.reset();

    // Verify state is cleared
    Test.assertMessage(engine.getBurnRate() == 0.0, "Burn rate should be 0 after reset");
    Test.assertMessage(engine.getDataPointCount() == 0, "Data point count should be 0 after reset");

    logger.debug("EngineResetTest: PASSED");
    return true;
}

// -------------------------------------------
// Test 3: Charging state change triggers reset
// -------------------------------------------
(:test)
function EngineChargingStateChange(logger as Logger) as Boolean {
    logger.debug("EngineChargingStateChange: Testing charging state transitions");

    var testTime = Gregorian.moment({:year=>2025, :month=>1, :day=>1, :hour=>8, :minute=>0, :second=>0});
    var engine = new BatteryBurnRateEngine(testTime);

    // Initialize with not charging
    engine.update(100.0, false, testTime, 0);

    Test.assertMessage(engine.getCharging() == false, "Charging should be false");

    // Simulate some data collection
    engine._test_setDataIndex(3);

    // Change to charging - should trigger reset
    engine.update(100.0, true, testTime, 1000);

    Test.assertMessage(engine.getCharging() == true, "Charging should be true");
    Test.assertMessage(engine.getDataPointCount() == 0, "Data should be reset on charging change");

    logger.debug("EngineChargingStateChange: PASSED");
    return true;
}

// -------------------------------------------
// Test 4: Insufficient data doesn't calculate burn rate
// -------------------------------------------
(:test)
function EngineInsufficientData(logger as Logger) as Boolean {
    logger.debug("EngineInsufficientData: Testing with < 2 data points");

    var testTime = Gregorian.moment({:year=>2025, :month=>1, :day=>1, :hour=>8, :minute=>0, :second=>0});
    var engine = new BatteryBurnRateEngine(testTime);

    // Initialize charging state
    engine.update(100.0, false, testTime, 0);

    // Only one data point - should not calculate burn rate
    engine._test_setDataIndex(1);
    engine._test_callUpdateEstimate();

    Test.assertMessage(engine.getBurnRate() == 0.0, "Burn rate should be 0 with < 2 points");

    logger.debug("EngineInsufficientData: PASSED");
    return true;
}

// -------------------------------------------
// Test 5: Two-point linear regression with known decline
// -------------------------------------------
(:test)
function EngineTwoPointLinearRegression(logger as Logger) as Boolean {
    logger.debug("EngineTwoPointLinearRegression: Testing basic regression");

    var testTime = Gregorian.moment({:year=>2025, :month=>1, :day=>1, :hour=>8, :minute=>0, :second=>0});
    var engine = new BatteryBurnRateEngine(testTime);

    // Initialize charging state
    engine.update(100.0, false, testTime, 0);

    var baseTime = testTime.value();

    // Set two data points: 100% at t=0, 90% at t=3600 seconds (1 hour)
    // Expected burn rate: -10% per hour
    engine._test_setDataPoint(0, 100.0, baseTime);
    engine._test_setDataPoint(1, 90.0, baseTime + 3600);
    engine._test_setDataIndex(2);

    engine._test_callUpdateEstimate();

    var burnRate = engine.getBurnRate();
    logger.debug("Calculated burn rate: " + burnRate + " (expected: ~-10.0)");

    // Allow small tolerance for floating point
    var expected = -10.0;
    var tolerance = 0.1;
    var withinTolerance = (burnRate >= expected - tolerance) && (burnRate <= expected + tolerance);

    Test.assertMessage(withinTolerance, "Burn rate should be approximately -10% per hour");

    logger.debug("EngineTwoPointLinearRegression: PASSED");
    return true;
}

// -------------------------------------------
// Test 6: Constant battery level results in zero slope
// -------------------------------------------
(:test)
function EngineConstantBattery(logger as Logger) as Boolean {
    logger.debug("EngineConstantBattery: Testing with constant battery level");

    var testTime = Gregorian.moment({:year=>2025, :month=>1, :day=>1, :hour=>8, :minute=>0, :second=>0});
    var engine = new BatteryBurnRateEngine(testTime);

    // Initialize charging state
    engine.update(100.0, false, testTime, 0);

    var baseTime = testTime.value();

    // Set multiple points with same battery level
    for (var i = 0; i < 5; i++) {
        engine._test_setDataPoint(i, 100.0, baseTime + (i * 600));
    }
    engine._test_setDataIndex(5);

    engine._test_callUpdateEstimate();

    var burnRate = engine.getBurnRate();
    logger.debug("Burn rate with constant battery: " + burnRate);

    Test.assertMessage(burnRate == 0.0, "Burn rate should be 0 with constant battery");

    logger.debug("EngineConstantBattery: PASSED");
    return true;
}

// -------------------------------------------
// Test 7: Null system stats handled gracefully
// -------------------------------------------
(:test)
function EngineNullSystemStats(logger as Logger) as Boolean {
    logger.debug("EngineNullSystemStats: Testing null handling");

    var testTime = Gregorian.moment({:year=>2025, :month=>1, :day=>1, :hour=>8, :minute=>0, :second=>0});
    var engine = new BatteryBurnRateEngine(testTime);

    // Call update with null - should trigger reset
    engine.update(null, null, testTime, 0);

    // Should not crash and charging should be null
    Test.assertMessage(engine.getCharging() == null, "Charging should be null after null update");
    Test.assertMessage(engine.getDataPointCount() == 0, "Data should be reset");

    logger.debug("EngineNullSystemStats: PASSED");
    return true;
}

// -------------------------------------------
// Test 8: Test all public accessors
// -------------------------------------------
(:test)
function EngineAccessors(logger as Logger) as Boolean {
    logger.debug("EngineAccessors: Testing public accessor methods");

    var testTime = Gregorian.moment({:year=>2025, :month=>1, :day=>1, :hour=>8, :minute=>0, :second=>0});
    var engine = new BatteryBurnRateEngine(testTime);

    // Test initial values via accessors
    var burnRate = engine.getBurnRate();
    var charging = engine.getCharging();
    var dataCount = engine.getDataPointCount();

    Test.assertMessage(burnRate == 0.0, "getBurnRate() should return 0.0 initially");
    Test.assertMessage(charging == null, "getCharging() should return null initially");
    Test.assertMessage(dataCount == 0, "getDataPointCount() should return 0 initially");

    // Update charging state
    engine.update(100.0, true, testTime, 0);

    charging = engine.getCharging();
    Test.assertMessage(charging == true, "getCharging() should return true after update");

    logger.debug("EngineAccessors: PASSED");
    return true;
}
