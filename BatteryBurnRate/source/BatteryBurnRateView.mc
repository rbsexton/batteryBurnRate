using Toybox.WatchUi;
using Toybox.System;
using Toybox.Graphics;
using Toybox.Test;
using Toybox.AntPlus;
using Toybox.Time;
import Toybox.Lang;

// Notes.
// Functional, w/ Old code:      Code 5109 bytes, Data 1790 bytes.
// Functional  removed old code: Code 4110 bytes, Data 1451 bytes.
// Refactored with Engine:       TBD

class BatteryBurnRateView extends WatchUi.DataField {

	// Calculation engine (MVC pattern)
	hidden var engine;

	// TUNABLES
	// Make the display red if burn rate exceeds 12%/h
	const veryHighBurnRate = -12.0;

    // Set the label of the data field here.
    function initialize() {
        DataField.initialize();
		engine = new BatteryBurnRateEngine(Time.now());
    }

    // Set your layout here. Anytime the size of obscurity of
    // the draw context is changed this will be called.
    function onLayout(dc) {
        var obscurityFlags = DataField.getObscurityFlags();

        // Top left quadrant so we'll use the top left layout
        if (obscurityFlags == (OBSCURE_TOP | OBSCURE_LEFT)) {
            View.setLayout(Rez.Layouts.TopLeftLayout(dc));

        // Top right quadrant so we'll use the top right layout
        } else if (obscurityFlags == (OBSCURE_TOP | OBSCURE_RIGHT)) {
            View.setLayout(Rez.Layouts.TopRightLayout(dc));

        // Bottom left quadrant so we'll use the bottom left layout
        } else if (obscurityFlags == (OBSCURE_BOTTOM | OBSCURE_LEFT)) {
            View.setLayout(Rez.Layouts.BottomLeftLayout(dc));

        // Bottom right quadrant so we'll use the bottom right layout
        } else if (obscurityFlags == (OBSCURE_BOTTOM | OBSCURE_RIGHT)) {
            View.setLayout(Rez.Layouts.BottomRightLayout(dc));
		} else if (dc.getHeight() > 100) {
            View.setLayout(Rez.Layouts.LargestLayout(dc));
            var labelView = View.findDrawableById("label");
            labelView.locY = labelView.locY - 15;
            // var valueView = View.findDrawableById("value");
            // valueView.locY = valueView.locY + 12;
		} else if (dc.getHeight() > 65) {
            View.setLayout(Rez.Layouts.LargerLayout(dc));
            var labelView = View.findDrawableById("label");
            labelView.locY = labelView.locY - 12;
            // var valueView = View.findDrawableById("value");
            // valueView.locY = valueView.locY + 11;
        // Use the generic, centered layout
        } else {
            View.setLayout(Rez.Layouts.MainLayout(dc));
            var labelView = View.findDrawableById("label");
            labelView.locY = labelView.locY - 16;
            var valueView = View.findDrawableById("value");
            valueView.locY = valueView.locY + 7;
        }
		var labelText = View.findDrawableById("label") as WatchUi.Text;
        labelText.setText(Rez.Strings.label);
        return;
    }

    // The given info object contains all the current workout
    // information. Calculate a value and return it in this method.
    // Note that compute() and onUpdate() are asynchronous, and there is no
    // guarantee that compute() will be called before onUpdate().
    function compute(info) {
		var systemStats = System.getSystemStats();
		var n_charging  = (systemStats == null) ? null : systemStats.charging;
		var battery     = (systemStats == null) ? null : systemStats.battery;
		var now_s       = Time.now();
		var now_ms      = System.getTimer();
		engine.update(battery, n_charging, now_s, now_ms);
    }
    
	function showRemain(burnRate)
	{
		var systemStats = System.getSystemStats();
		var calculated_remain = View.findDrawableById("remain") as WatchUi.Text;
		var burnRateAsNum = burnRate;
		if (burnRate != null && burnRate instanceof String) {
			if (burnRate == "Calculating...") {
				burnRateAsNum = null;
			}
			//System.println("burn rate before conversion to float is " + burnRate);
			burnRateAsNum = burnRate.toFloat();
		}
		if (systemStats != null && systemStats.battery != null && burnRateAsNum != null && burnRateAsNum > 0) {
			var calcRemain = systemStats.battery / burnRateAsNum;
			//System.println("Time remaining is " + calcRemain + " with battery of " + systemStats.battery + " and burn of " + burnRateAsNum + " rate " + burnRate);
			if (calculated_remain != null) {
				if (calcRemain > 1) {
					calculated_remain.setText(calcRemain.format("%.1f") + " hours left");
				} else {
					calculated_remain.setText((calcRemain*60).format("%.1f") + " minutes left");
				}
			}
		} else if (calculated_remain != null && (burnRateAsNum == null || burnRateAsNum == 0)) {
			calculated_remain.setText("---");
		}
	}

   //! Display the value you computed here. This will be called
    //! once a second when the data field is visible.
    function onUpdate(dc) {
	    var dataColor;
        var label = View.findDrawableById("label") as WatchUi.Text;
		var remain = View.findDrawableById("remain") as WatchUi.Text;
		// Reverse the colors for day/night and set the default
		// value for the color of the data color.
	    if (getBackgroundColor() == Graphics.COLOR_BLACK) {
	        label.setColor(Graphics.COLOR_WHITE);
			remain.setColor(Graphics.COLOR_WHITE);
			dataColor = Graphics.COLOR_WHITE;
	    } else {
	        label.setColor(Graphics.COLOR_BLACK);
			remain.setColor(Graphics.COLOR_BLACK);
			dataColor = Graphics.COLOR_BLACK;
		}
		var background = View.findDrawableById("Background") as WatchUi.Text;
        background.setColor(getBackgroundColor());

		// Get burn rate from engine
		var burn_rate_slope = engine.getBurnRate();
		var charging = engine.getCharging();

		// Display Burn and Charge separately.  Charging isn't necessarily valid.
		if ( charging == true )  {
	        label.setText("Charge/h");
		} else {
		    label.setText("Burn/h");
		}
		// Display the data.  If its an invalid value, render as dashes
        var value = View.findDrawableById("value") as WatchUi.Text;
		//System.println("Width is " + dc.getWidth() + " height is " + dc.getHeight());
		//System.println("Value is " + value.width + " x " + value.height);
		/* if (dc.getHeight() > 100) {
			value.setSize( value.width * 1.1, value.height * 1.1);
		}
		else if (dc.getHeight() > 75) {
			value.setSize( value.width * 1.05, value.height * 1.05);
		} */
        if (  burn_rate_slope != 0 ) {

/* 			// Check for pathology and set the color if need be.
			if ( burn_rate_slope < veryHighBurnRate ) {
			    dataColor = Graphics.COLOR_RED;
			}
 */
			var abs_d = burn_rate_slope.abs();
	        value.setText(abs_d.format("%.1f") + "%");
			if (dc.getHeight() > 80) {
				showRemain(abs_d);
			}
        } else {
        	value.setText("-wait-");
    	}

		// Done with Formatting, choose the color.
        value.setColor(dataColor);

        View.onUpdate(dc);
	}
}