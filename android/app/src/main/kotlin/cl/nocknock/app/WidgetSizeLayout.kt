package cl.nocknock.app

/** Compact layouts keep the same actions without squeezing a full-size widget. */
internal enum class WidgetSizeLayout(val resource: Int, val reservedHeight: Int) {
    SUMMARY(R.layout.widget_pending_compact, 110),
    COMPACT(R.layout.widget_pending_compact, 120),
    WIDE(R.layout.widget_pending_wide, 72),
    FULL(R.layout.widget_pending, 190),
    CAPTURE_SMALL(R.layout.widget_capture_small, 0),
    CAPTURE(R.layout.widget_capture, 0);

    companion object {
        fun choose(width: Int, height: Int, capture: Boolean): WidgetSizeLayout = when {
            capture && (width < 110 || height < 100) -> CAPTURE_SMALL
            capture -> CAPTURE
            width < 230 && height < 190 -> SUMMARY
            width < 230 -> COMPACT
            height < 200 -> WIDE
            height < 340 -> COMPACT
            else -> FULL
        }
    }
}
