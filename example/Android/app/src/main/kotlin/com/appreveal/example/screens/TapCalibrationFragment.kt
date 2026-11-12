package com.appreveal.example.screens

import android.graphics.Color
import android.os.Bundle
import android.view.Gravity
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import android.widget.LinearLayout
import android.widget.TextView
import androidx.fragment.app.Fragment

/** The calibration destination already linked from Settings. */
class TapCalibrationFragment : Fragment() {
    override fun onCreateView(inflater: LayoutInflater, container: ViewGroup?, savedInstanceState: Bundle?): View {
        val context = requireContext()
        val density = resources.displayMetrics.density
        val padding = (24 * density).toInt()
        return LinearLayout(context).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER_HORIZONTAL
            setPadding(padding, padding, padding, padding)
            addView(TextView(context).apply { text = "Tap the red target to verify MCP tap_point accuracy" })
            val result = TextView(context).apply {
                text = "Target taps: 0"
                contentDescription = "calibration.result"
            }
            var count = 0
            addView(View(context).apply {
                tag = "calibration.target"
                contentDescription = "Calibration target"
                setBackgroundColor(Color.rgb(211, 47, 47))
                setOnClickListener { result.text = "Target taps: ${++count}" }
            }, LinearLayout.LayoutParams((120 * density).toInt(), (120 * density).toInt()).apply {
                topMargin = padding
                bottomMargin = padding
            })
            addView(result)
        }
    }
}
