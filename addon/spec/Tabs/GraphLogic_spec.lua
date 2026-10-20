--[[
  Unit tests for GraphLogic.lua.
  Run from project root: npm test
]]

describe("GraphLogic", function()
    local Logic

    setup(function()
        _G.AltArmy = _G.AltArmy or {}
        package.path = package.path .. ";AltArmy_TBC/Tabs/?.lua"
        package.loaded["GraphLogic"] = nil
        require("GraphLogic")
        Logic = AltArmy.GraphLogic
    end)

    describe("Selection keys", function()
        it("keys a character by its storage key, so two of one name stay apart", function()
            local rogue = { name = "Frell Aa", realm = "R", key = "Player-1-A" }
            local shaman = { name = "Frell Aa", realm = "R", key = "Player-1-B" }
            assert.are.equal("R\\Player-1-A", Logic.SelectionKey(rogue))
            assert.are_not.equal(Logic.SelectionKey(rogue), Logic.SelectionKey(shaman))
        end)

        it("falls back to the name and carries a linked account's link", function()
            assert.are.equal("R\\Frell", Logic.SelectionKey({ name = "Frell", realm = "R" }))
            assert.are.equal("R\\Player-1-A\1acct",
                Logic.SelectionKey({ name = "Frell", realm = "R", key = "Player-1-A", linkId = "acct" }))
        end)

        it("moves selections saved by name to every character of that name", function()
            local selected = { ["R\\Frell Aa"] = true, ["R\\Other"] = true, ["R\\Frell\1acct"] = true }
            Logic.MigrateNameSelections(selected, {
                { name = "Frell Aa", realm = "R", key = "Player-1-A" },
                { name = "Frell Aa", realm = "R", key = "Player-1-B" },
                { name = "Frell", realm = "R", key = "Player-2-A", linkId = "acct" },
                { name = "Other", realm = "R", key = "Other" },
            })
            assert.are.same({
                ["R\\Player-1-A"] = true,
                ["R\\Player-1-B"] = true,
                ["R\\Player-2-A\1acct"] = true,
                ["R\\Other"] = true,
            }, selected)
        end)
    end)

    describe("Compare select all", function()
        it("shows the All row only when there are more than four characters", function()
            assert.is_false(Logic.ShouldShowCompareSelectAll(4))
            assert.is_true(Logic.ShouldShowCompareSelectAll(5))
        end)

        it("checks All only when every compare character is selected", function()
            assert.is_false(Logic.IsCompareSelectAllChecked(5, 4))
            assert.is_true(Logic.IsCompareSelectAllChecked(5, 5))
            assert.is_false(Logic.IsCompareSelectAllChecked(0, 0))
        end)

        it("selects all when not fully selected and deselects when fully selected", function()
            assert.is_true(Logic.GetCompareSelectAllAction(false))
            assert.is_false(Logic.GetCompareSelectAllAction(true))
        end)
    end)

    describe("ComputeSeriesAlphas", function()
        it("returns full alphas when not dimming others", function()
            local line, dash, marker = Logic.ComputeSeriesAlphas(false, false)
            assert.are.equal(0.9, line)
            assert.are.equal(0.55, dash)
            assert.are.equal(1, marker)
        end)

        it("returns full alphas for hovered series when dimming", function()
            local line, dash, marker = Logic.ComputeSeriesAlphas(true, true)
            assert.are.equal(0.9, line)
            assert.are.equal(0.55, dash)
            assert.are.equal(1, marker)
        end)

        it("returns dim alphas for non-hovered series when dimming", function()
            local line, dash, marker = Logic.ComputeSeriesAlphas(true, false)
            assert.are.equal(0.22, line)
            assert.are.equal(0.14, dash)
            assert.are.equal(0.35, marker)
        end)
    end)

    describe("HoverNeedsRebuild", function()
        local drawnKeys = { ["Realm\\Bob"] = true }

        it("returns false when hovered key is already drawn", function()
            assert.is_false(Logic.HoverNeedsRebuild("Realm\\Bob", drawnKeys, 5000, 1000))
        end)

        it("returns false when hovered key is nil", function()
            assert.is_false(Logic.HoverNeedsRebuild(nil, drawnKeys, 5000, 1000))
        end)

        it("returns false when new series fits within current scale", function()
            assert.is_false(Logic.HoverNeedsRebuild("Realm\\Alice", drawnKeys, 800, 1000))
        end)

        it("returns true when new series exceeds current scale", function()
            assert.is_true(Logic.HoverNeedsRebuild("Realm\\Alice", drawnKeys, 1500, 1000))
        end)

        it("returns false when new series equals current scale", function()
            assert.is_false(Logic.HoverNeedsRebuild("Realm\\Alice", drawnKeys, 1000, 1000))
        end)
    end)

    describe("ComputeLinearYAxis", function()
        it("snaps the axis top to nice duration ticks with 8 percent padding", function()
            local axis = Logic.ComputeLinearYAxis(100)
            assert.are.equal(0, axis.yMin)
            assert.are.equal(120, axis.paddedYMax)
            assert.are.equal(120, axis.yRange)
            assert.are.same({ 0, 30, 60, 90, 120 }, axis.gridTicks)
        end)

        it("uses a minimum range of 1 when max is zero", function()
            local axis = Logic.ComputeLinearYAxis(0)
            assert.are.equal(5, axis.paddedYMax)
            assert.are.same({ 0, 5 }, axis.gridTicks)
        end)

        it("uses 30 minute steps for multi-hour ranges", function()
            local axis = Logic.ComputeLinearYAxis(7020)
            assert.are.same({ 0, 1800, 3600, 5400, 7200, 9000 }, axis.gridTicks)
            assert.are.equal(9000, axis.paddedYMax)
        end)

        it("uses 2 minute steps for ten-minute ranges", function()
            local axis = Logic.ComputeLinearYAxis(500)
            assert.are.same({ 0, 120, 240, 360, 480, 600 }, axis.gridTicks)
            assert.are.equal(600, axis.paddedYMax)
        end)
    end)

    describe("ComputeLinearYGridTicks", function()
        it("always includes zero when the minimum is zero", function()
            local ticks, top = Logic.ComputeLinearYGridTicks(0, 600, 4)
            assert.are.equal(0, ticks[1])
            assert.is_true(top >= 600)
        end)
    end)

    describe("ComputeLogAxisFloor", function()
        it("returns 1 when the minimum is at most 1 second", function()
            assert.are.equal(1, Logic.ComputeLogAxisFloor(0))
            assert.are.equal(1, Logic.ComputeLogAxisFloor(1))
        end)

        it("picks the largest duration candidate below the minimum", function()
            assert.are.equal(5, Logic.ComputeLogAxisFloor(8))
            assert.are.equal(30, Logic.ComputeLogAxisFloor(45))
            assert.are.equal(180, Logic.ComputeLogAxisFloor(300))
        end)

        it("never returns a floor greater than 5 minutes", function()
            assert.are.equal(300, Logic.ComputeLogAxisFloor(3600))
            assert.are.equal(300, Logic.ComputeLogAxisFloor(10000))
        end)

        it("ignores the 5 minute cap when ignoreMaxFloor is set", function()
            assert.are.equal(2700, Logic.ComputeLogAxisFloor(3600, true))
            assert.are.equal(7200, Logic.ComputeLogAxisFloor(10000, true))
        end)
    end)

    describe("ComputeLogYAxis", function()
        it("uses duration-friendly ticks for grid lines and labels", function()
            local axis = Logic.ComputeLogYAxis(5000, 300)
            assert.are.equal(180, axis.yMin)
            assert.are.equal(5400, axis.paddedYMax)
            assert.are.same({ 180, 300, 600, 900, 1800, 2700, 3600, 5400 }, axis.gridTicks)
        end)

        it("falls back to 1 second when all values are very small", function()
            local axis = Logic.ComputeLogYAxis(90, 8)
            assert.are.equal(5, axis.yMin)
            assert.are.equal(120, axis.paddedYMax)
            assert.are.same({ 5, 10, 15, 30, 60, 120 }, axis.gridTicks)
        end)

        it("snaps the axis top to the next duration tick", function()
            local axis = Logic.ComputeLogYAxis(9500, 300)
            assert.are.equal(10800, axis.paddedYMax)
            assert.is_true(axis.gridTicks[#axis.gridTicks] <= axis.paddedYMax)
        end)

        it("includes power-of-two day ticks beyond 24 hours", function()
            local oneDay = 86400
            local twoDays = oneDay * 2
            local fourDays = oneDay * 4
            local axis = Logic.ComputeLogYAxis(twoDays + oneDay / 2, 3600, true)
            assert.are.equal(fourDays, axis.paddedYMax)
            local hasTick = {}
            for _, tick in ipairs(axis.gridTicks) do
                hasTick[tick] = true
            end
            assert.is_true(hasTick[oneDay])
            assert.is_true(hasTick[twoDays])
            assert.is_true(hasTick[fourDays])
        end)

        it("snaps the axis top up to 256 days", function()
            local maxDays = 86400 * 256
            local axis = Logic.ComputeLogYAxis(86400 * 200, 3600, true)
            assert.are.equal(maxDays, axis.paddedYMax)
            assert.are.equal(maxDays, axis.gridTicks[#axis.gridTicks])
        end)
    end)

    describe("FilterLogYGridTicks", function()
        local function logFraction(val, logMin, logMax)
            local logRange = logMax - logMin
            if logRange <= 0 then
                return 0
            end
            return (math.log(val) / math.log(10) - logMin) / logRange
        end

        local function assertMinSpacing(ticks, logMin, logMax, minSpacing)
            for i = 2, #ticks do
                local spacing = logFraction(ticks[i], logMin, logMax) - logFraction(ticks[i - 1], logMin, logMax)
                assert.is_true(
                    spacing + 1e-9 >= minSpacing,
                    string.format("ticks %s and %s are only %.3f apart", ticks[i - 1], ticks[i], spacing)
                )
            end
        end

        it("returns empty or single tick lists unchanged", function()
            assert.are.same({}, Logic.FilterLogYGridTicks({}, 0, 1, 0.1))
            assert.are.same({ 30 }, Logic.FilterLogYGridTicks({ 30 }, 1.47, 4.93, 0.1))
        end)

        it("always keeps the bottom tick", function()
            local axis = Logic.ComputeLogYAxis(86400, 30, true)
            local filtered = Logic.FilterLogYGridTicks(
                axis.gridTicks, axis.logMin, axis.logMax, Logic.LOG_Y_MIN_TICK_SPACING_FRACTION
            )
            assert.are.equal(axis.gridTicks[1], filtered[1])
        end)

        it("skips ticks that crowd the bottom of a wide log scale", function()
            local axis = Logic.ComputeLogYAxis(86400, 45, true)
            local filtered = Logic.FilterLogYGridTicks(
                axis.gridTicks, axis.logMin, axis.logMax, Logic.LOG_Y_MIN_TICK_SPACING_FRACTION
            )
            assert.is_true(#filtered < #axis.gridTicks)
            local hasTick = {}
            for _, tick in ipairs(filtered) do
                hasTick[tick] = true
            end
            assert.are.equal(30, filtered[1])
            assert.is_nil(hasTick[60], "1m should be skipped when too close to 30s")
            assertMinSpacing(filtered, axis.logMin, axis.logMax, Logic.LOG_Y_MIN_TICK_SPACING_FRACTION)
        end)

        it("measures spacing from the last kept tick, not the previous candidate", function()
            local logMin = math.log(30) / math.log(10)
            local logMax = math.log(86400) / math.log(10)
            local filtered = Logic.FilterLogYGridTicks(
                { 30, 60, 120, 180, 300, 600 }, logMin, logMax, 0.12
            )
            assert.are.same({ 30, 120, 600 }, filtered)
        end)

        it("keeps all ticks when the range is narrow", function()
            local axis = Logic.ComputeLogYAxis(90, 8)
            local filtered = Logic.FilterLogYGridTicks(
                axis.gridTicks, axis.logMin, axis.logMax, Logic.LOG_Y_MIN_TICK_SPACING_FRACTION
            )
            assert.are.same(axis.gridTicks, filtered)
        end)
    end)

    describe("YToFraction", function()
        local linearAxis = { yMin = 0, yRange = 100 }
        local logAxis = Logic.ComputeLogYAxis(90, 8)

        it("maps linear values proportionally", function()
            assert.are.equal(0.5, Logic.YToFraction(50, linearAxis, false))
        end)

        it("maps logarithmic values on a log scale", function()
            assert.are.equal(0, Logic.YToFraction(logAxis.yMin, logAxis, true))
            assert.is_true(Logic.YToFraction(10, logAxis, true) > Logic.YToFraction(logAxis.yMin, logAxis, true))
            assert.is_true(Logic.YToFraction(90, logAxis, true) > Logic.YToFraction(10, logAxis, true))
        end)

        it("clamps zero to the log floor", function()
            assert.are.equal(Logic.YToFraction(logAxis.yMin, logAxis, true), Logic.YToFraction(0, logAxis, true))
        end)

        it("places the smallest data point in the lower portion of the axis", function()
            local axis = Logic.ComputeLogYAxis(5000, 300)
            local minFraction = Logic.YToFraction(300, axis, true)
            assert.is_true(minFraction < 0.2)
        end)
    end)

    describe("SampleLeadingGapCurve", function()
        local gap = {
            fromLevel = 1,
            toLevel = 61,
            toY = 1000,
            totalSeconds = 60000,
        }
        local endPt = { level = 61, seconds = 1000 }

        it("includes endpoints with linearly interpolated seconds", function()
            local samples = Logic.SampleLeadingGapCurve(gap, endPt, 4)
            assert.are.equal(5, #samples)
            assert.are.equal(1, samples[1].level)
            assert.are.equal(0, samples[1].seconds)
            assert.are.equal(61, samples[5].level)
            assert.are.equal(1000, samples[5].seconds)
            assert.are.equal(250, samples[2].seconds)
        end)

        it("starts at the axis floor intersection when an axis floor is provided", function()
            local samples = Logic.SampleLeadingGapCurve(gap, endPt, 4, 300)
            assert.are.equal(5, #samples)
            assert.are.equal(19, samples[1].level)
            assert.are.equal(300, samples[1].seconds)
            assert.are.equal(61, samples[5].level)
            assert.are.equal(1000, samples[5].seconds)
        end)

        it("defaults to a smooth number of segments", function()
            local samples = Logic.SampleLeadingGapCurve(gap, endPt)
            assert.is_true(#samples >= 16)
        end)

        describe("quadratic mode (cumulative play time)", function()
            local cumGap = {
                fromLevel = 1,
                toLevel = 61,
                toY = 60000,
                totalSeconds = 60000,
            }
            local cumEnd = { level = 61, seconds = 60000 }

            it("integrates a linear time-per-level ramp as seconds = end * frac^2", function()
                local samples = Logic.SampleLeadingGapCurve(
                    cumGap, cumEnd, 4, nil, Logic.LEADING_GAP_CURVE_QUADRATIC
                )
                assert.are.equal(5, #samples)
                assert.are.equal(1, samples[1].level)
                assert.are.equal(0, samples[1].seconds)
                assert.are.equal(16, samples[2].level)
                assert.are.equal(3750, samples[2].seconds) -- 60000 * (0.25^2)
                assert.are.equal(31, samples[3].level)
                assert.are.equal(15000, samples[3].seconds) -- 60000 * (0.5^2)
                assert.are.equal(61, samples[5].level)
                assert.are.equal(60000, samples[5].seconds)
            end)

            it("finds axis floor along the quadratic curve", function()
                -- 60000 * frac^2 = 15000 => frac = 0.5 => level = 31
                local samples = Logic.SampleLeadingGapCurve(
                    cumGap, cumEnd, 4, 15000, Logic.LEADING_GAP_CURVE_QUADRATIC
                )
                assert.are.equal(5, #samples)
                assert.are.equal(31, samples[1].level)
                assert.are.equal(15000, samples[1].seconds)
                assert.are.equal(61, samples[5].level)
                assert.are.equal(60000, samples[5].seconds)
            end)

            it("stays below the linear chord at mid-span", function()
                local samples = Logic.SampleLeadingGapCurve(
                    cumGap, cumEnd, 2, nil, Logic.LEADING_GAP_CURVE_QUADRATIC
                )
                local mid = samples[2]
                assert.are.equal(31, mid.level)
                assert.is_true(mid.seconds < 30000)
            end)
        end)
    end)

    local function makePoint(level, seconds)
        return {
            level = level,
            seconds = seconds,
            fromLevel = level - 1,
            toLevel = level,
            totalSeconds = seconds,
        }
    end

    describe("ApplyRollingAverage", function()
        it("returns unchanged seconds when the window size is 1", function()
            local points = {
                makePoint(10, 100),
                makePoint(20, 200),
            }
            local smoothed = Logic.ApplyRollingAverage(points, 1)
            assert.are.equal(100, smoothed[1].seconds)
            assert.are.equal(200, smoothed[2].seconds)
        end)

        it("computes a centered rolling average with partial windows at the edges", function()
            local points = {
                makePoint(10, 100),
                makePoint(20, 200),
                makePoint(30, 300),
                makePoint(40, 400),
                makePoint(50, 500),
            }
            local smoothed = Logic.ApplyRollingAverage(points, 5)
            assert.are.equal(200, smoothed[1].seconds)
            assert.are.equal(250, smoothed[2].seconds)
            assert.are.equal(300, smoothed[3].seconds)
            assert.are.equal(350, smoothed[4].seconds)
            assert.are.equal(400, smoothed[5].seconds)
        end)

        it("defaults to a window of 5", function()
            local points = {
                makePoint(10, 100),
                makePoint(20, 200),
                makePoint(30, 300),
                makePoint(40, 400),
                makePoint(50, 500),
            }
            local smoothed = Logic.ApplyRollingAverage(points)
            assert.are.equal(300, smoothed[3].seconds)
        end)

        it("clears outlier flags so the smoothed line stays on-chart", function()
            local points = { makePoint(10, 8000) }
            points[1].isOutlier = true
            local smoothed = Logic.ApplyRollingAverage(points, 3)
            assert.is_false(smoothed[1].isOutlier)
        end)

        it("uses shrunk virtual values when shrinkOutliers is enabled", function()
            local points = {
                makePoint(10, 100),
                makePoint(20, 200),
                makePoint(30, 8000),
                makePoint(40, 120),
                makePoint(50, 110),
            }
            points[3].isOutlier = true

            local raw = Logic.ApplyRollingAverage(points, 5, false)
            assert.is_true(raw[3].seconds > 1000)

            local shrunk = Logic.ApplyRollingAverage(points, 5, true)
            assert.are.equal(146, shrunk[3].seconds)
        end)
    end)

    describe("BuildShrunkVirtualSeconds", function()
        it("replaces outlier seconds with the max non-outlier value", function()
            local points = {
                makePoint(10, 100),
                makePoint(20, 8000),
                makePoint(30, 120),
            }
            points[2].isOutlier = true

            local virtual = Logic.BuildShrunkVirtualSeconds(points)
            assert.are.equal(100, virtual[1])
            assert.are.equal(120, virtual[2])
            assert.are.equal(120, virtual[3])
        end)
    end)

    describe("ApplyOutlierFlags", function()
        it("does not flag outliers when disabled", function()
            local points = {
                makePoint(10, 100),
                makePoint(20, 10000),
            }
            local marked = Logic.ApplyOutlierFlags(points, false)
            assert.is_false(marked[2].isOutlier)
        end)

        it("flags extreme values among the longest-duration levels", function()
            local points = {
                makePoint(10, 100),
                makePoint(20, 120),
                makePoint(30, 110),
                makePoint(40, 105),
                makePoint(50, 8000),
            }
            local marked = Logic.ApplyOutlierFlags(points, true)
            assert.is_false(marked[1].isOutlier)
            assert.is_false(marked[4].isOutlier)
            assert.is_true(marked[5].isOutlier)
        end)

        it("flags only the cap-wait spike among the ten longest durations", function()
            local points = {}
            for level = 20, 49 do
                points[#points + 1] = makePoint(level, 3600)
            end
            points[#points + 1] = makePoint(61, 205200)
            for level = 62, 70 do
                points[#points + 1] = makePoint(level, 21600)
            end

            local marked = Logic.ApplyOutlierFlags(points, true)
            assert.is_true(marked[31].isOutlier)
            for i = 32, #marked do
                assert.is_false(marked[i].isOutlier)
            end
            for i = 1, 30 do
                assert.is_false(marked[i].isOutlier)
            end
        end)

        it("does not flag long durations outside the top ten", function()
            local points = { makePoint(1, 205200) }
            for level = 2, 16 do
                points[#points + 1] = makePoint(level, 21600)
            end

            local marked = Logic.ApplyOutlierFlags(points, true)
            assert.is_true(marked[1].isOutlier)
            for i = 11, #marked do
                assert.is_false(marked[i].isOutlier)
            end
        end)
    end)

    describe("BuildSeriesDrawPlan", function()
        it("spikes up to the true outlier position then returns to the next level", function()
            local points = {
                makePoint(10, 100),
                makePoint(20, 8000),
                makePoint(30, 110),
            }
            points[2].isOutlier = true

            local plan = Logic.BuildSeriesDrawPlan(points)
            assert.are.equal(2, #plan.segments)
            assert.are.equal("solid", plan.segments[1].style)
            assert.are.equal(10, plan.segments[1].from.level)
            assert.are.equal(20, plan.segments[1].to.level)
            assert.are.equal(8000, plan.segments[1].to.seconds)
            assert.is_true(plan.segments[1].isOutlierSpike)
            assert.are.equal("solid", plan.segments[2].style)
            assert.are.equal(20, plan.segments[2].from.level)
            assert.are.equal(30, plan.segments[2].to.level)
            assert.is_true(plan.segments[2].isOutlierReturn)
            assert.are.equal(3, #plan.markers)
            assert.is_true(plan.markers[2].pt.isOutlier)
        end)

        it("spikes to a trailing outlier and marks it near the plot top", function()
            local points = {
                makePoint(10, 100),
                makePoint(20, 8000),
            }
            points[2].isOutlier = true

            local plan = Logic.BuildSeriesDrawPlan(points)
            assert.are.equal(1, #plan.segments)
            assert.are.equal("solid", plan.segments[1].style)
            assert.are.equal(20, plan.segments[1].to.level)
            assert.are.equal(8000, plan.segments[1].to.seconds)
            assert.is_true(plan.segments[1].isOutlierSpike)
            assert.are.equal(2, #plan.markers)
            assert.are.equal(10, plan.markers[1].pt.level)
            assert.is_true(plan.markers[2].pt.isOutlier)
            assert.are.equal(20, plan.markers[2].pt.level)
        end)

        it("chains consecutive outliers off the chart", function()
            local points = {
                makePoint(10, 100),
                makePoint(20, 8000),
                makePoint(30, 9000),
                makePoint(40, 110),
            }
            points[2].isOutlier = true
            points[3].isOutlier = true

            local plan = Logic.BuildSeriesDrawPlan(points)
            assert.are.equal(3, #plan.segments)
            assert.is_true(plan.segments[1].isOutlierSpike)
            assert.is_true(plan.segments[2].isOutlierSpike)
            assert.are.equal(20, plan.segments[2].from.level)
            assert.are.equal(30, plan.segments[2].to.level)
            assert.is_true(plan.segments[3].isOutlierReturn)
            assert.are.equal(40, plan.segments[3].to.level)
        end)

        it("keeps solid segments between normal points", function()
            local points = {
                makePoint(10, 100),
                makePoint(20, 120),
            }
            local plan = Logic.BuildSeriesDrawPlan(points)
            assert.are.equal("solid", plan.segments[1].style)
        end)
    end)

    describe("PlotSeriesPoint", function()
        it("clamps outlier points to the plot top", function()
            local pt = makePoint(20, 8000)
            pt.isOutlier = true
            local x, y = Logic.PlotSeriesPoint(pt, 120, 500, 400)
            assert.are.equal(120, x)
            assert.are.equal(400, y)
        end)

        it("does not move outliers above their natural y when plot scale is large", function()
            local pt = makePoint(20, 8000)
            pt.isOutlier = true
            local x, y = Logic.PlotSeriesPoint(pt, 120, 200, 400)
            assert.are.equal(120, x)
            assert.are.equal(200, y)
        end)

        it("keeps normal points at their true y position", function()
            local pt = makePoint(20, 120)
            local x, y = Logic.PlotSeriesPoint(pt, 120, 180, 400)
            assert.are.equal(120, x)
            assert.are.equal(180, y)
        end)
    end)

    describe("GetSeriesScaleBounds", function()
        it("excludes outliers from axis bounds when requested", function()
            local points = {
                makePoint(10, 100),
                makePoint(20, 9000),
            }
            points[2].isOutlier = true
            local yMin, yMax = Logic.GetSeriesScaleBounds(points, true)
            assert.are.equal(100, yMin)
            assert.are.equal(100, yMax)
        end)

        it("limits bounds to points within an optional level range", function()
            local points = {
                makePoint(10, 100),
                makePoint(20, 500),
                makePoint(30, 200),
            }
            local yMin, yMax = Logic.GetSeriesScaleBounds(points, false, 15, 25)
            assert.are.equal(500, yMin)
            assert.are.equal(500, yMax)
        end)

        it("ignores level bounds when min and max are nil", function()
            local points = {
                makePoint(10, 100),
                makePoint(20, 500),
            }
            local yMin, yMax = Logic.GetSeriesScaleBounds(points, false, nil, nil)
            assert.are.equal(100, yMin)
            assert.are.equal(500, yMax)
        end)
    end)

    describe("ChooseXLabelInterval", function()
        it("returns denser intervals for narrow zoom ranges", function()
            assert.are.equal(1, Logic.ChooseXLabelInterval(5))
            assert.are.equal(2, Logic.ChooseXLabelInterval(12))
            assert.are.equal(5, Logic.ChooseXLabelInterval(30))
            assert.are.equal(10, Logic.ChooseXLabelInterval(70))
        end)
    end)

    describe("NormalizeZoomRange", function()
        it("orders, snaps, and clamps the drag range", function()
            local minLevel, maxLevel = Logic.NormalizeZoomRange(25.4, 12.6, 0, 70, 2)
            assert.are.equal(13, minLevel)
            assert.are.equal(25, maxLevel)
        end)

        it("returns nil when the span is below the minimum", function()
            assert.is_nil(Logic.NormalizeZoomRange(10, 10.5, 0, 70, 2))
        end)

        it("clamps to the full axis range", function()
            local minLevel, maxLevel = Logic.NormalizeZoomRange(-5, 80, 0, 70, 2)
            assert.are.equal(0, minLevel)
            assert.are.equal(70, maxLevel)
        end)
    end)

    describe("ClipDrawPlanToRange", function()
        it("drops markers outside the range", function()
            local points = {
                makePoint(10, 100),
                makePoint(20, 120),
                makePoint(30, 140),
            }
            local plan = Logic.BuildSeriesDrawPlan(points)
            local clipped = Logic.ClipDrawPlanToRange(plan, 15, 25)
            assert.are.equal(1, #clipped.markers)
            assert.are.equal(20, clipped.markers[1].pt.level)
        end)

        it("interpolates segment endpoints at range boundaries", function()
            local points = {
                makePoint(10, 100),
                makePoint(20, 200),
                makePoint(30, 300),
            }
            local plan = Logic.BuildSeriesDrawPlan(points)
            local clipped = Logic.ClipDrawPlanToRange(plan, 15, 25)
            assert.are.equal(2, #clipped.segments)
            assert.are.equal(15, clipped.segments[1].from.level)
            assert.are.equal(150, clipped.segments[1].from.seconds)
            assert.are.equal(20, clipped.segments[1].to.level)
            assert.are.equal(200, clipped.segments[1].to.seconds)
            assert.are.equal(20, clipped.segments[2].from.level)
            assert.are.equal(200, clipped.segments[2].from.seconds)
            assert.are.equal(25, clipped.segments[2].to.level)
            assert.are.equal(250, clipped.segments[2].to.seconds)
        end)

        it("drops segments fully outside the range", function()
            local points = {
                makePoint(10, 100),
                makePoint(20, 200),
            }
            local plan = Logic.BuildSeriesDrawPlan(points)
            local clipped = Logic.ClipDrawPlanToRange(plan, 25, 35)
            assert.are.equal(0, #clipped.segments)
            assert.are.equal(0, #clipped.markers)
        end)

        it("drops segments that collapse to a single point after clipping", function()
            local pt = makePoint(20, 200)
            local plan = {
                segments = {
                    { style = "solid", from = pt, to = pt },
                },
                markers = { { pt = pt } },
            }
            local clipped = Logic.ClipDrawPlanToRange(plan, 15, 25)
            assert.are.equal(0, #clipped.segments)
            assert.are.equal(1, #clipped.markers)
        end)
    end)

    describe("HoverNeedsRebuild with logarithmic scale", function()
        local drawnKeys = { ["Realm\\Bob"] = true }

        it("returns true when hovered series has a lower minimum", function()
            assert.is_true(Logic.HoverNeedsRebuild("Realm\\Alice", drawnKeys, 5000, 5000, 100, 300, true))
        end)

        it("returns false when hovered series fits within current log bounds", function()
            assert.is_false(Logic.HoverNeedsRebuild("Realm\\Alice", drawnKeys, 4000, 5000, 400, 300, true))
        end)
    end)

    describe("Line colors", function()
        -- RAID_CLASS_COLORS of the nine classes
        local CLASS_COLORS = {
            WARRIOR = { 0.78, 0.61, 0.43 },
            PALADIN = { 0.96, 0.55, 0.73 },
            HUNTER = { 0.67, 0.83, 0.45 },
            ROGUE = { 1.00, 0.96, 0.41 },
            PRIEST = { 1.00, 1.00, 1.00 },
            SHAMAN = { 0.00, 0.44, 0.87 },
            MAGE = { 0.25, 0.78, 0.92 },
            WARLOCK = { 0.53, 0.53, 0.93 },
            DRUID = { 1.00, 0.49, 0.04 },
        }

        local function entry(classFile)
            local c = CLASS_COLORS[classFile]
            return { classFile = classFile, r = c[1], g = c[2], b = c[3] }
        end

        local function distance(a, b)
            return Logic.ColorDistance(a.r, a.g, a.b, b.r, b.g, b.b)
        end

        local function isFallback(c)
            for _, f in ipairs(Logic.FALLBACK_LINE_COLORS) do
                if f[1] == c.r and f[2] == c.g and f[3] == c.b then return true end
            end
            return false
        end

        describe("ToOklab", function()
            it("matches the reference values", function()
                local L, a, b = Logic.ToOklab(1, 1, 1)
                assert.is_near(1, L, 1e-6)
                assert.is_near(0, a, 1e-6)
                assert.is_near(0, b, 1e-6)
                L, a, b = Logic.ToOklab(1, 0, 0)
                assert.is_near(0.6280, L, 1e-3)
                assert.is_near(0.2249, a, 1e-3)
                assert.is_near(0.1258, b, 1e-3)
                L = Logic.ToOklab(0, 0, 0)
                assert.is_near(0, L, 1e-6)
            end)
        end)

        describe("ColorDistance", function()
            it("is zero for the same color and symmetric", function()
                assert.are.equal(0, Logic.ColorDistance(0.5, 0.4, 0.3, 0.5, 0.4, 0.3))
                assert.are.equal(
                    Logic.ColorDistance(1, 0, 0, 0, 0, 1),
                    Logic.ColorDistance(0, 0, 1, 1, 0, 0)
                )
            end)

            it("puts a brightened shade of a color far closer than another hue", function()
                local r, g, b = 0.78, 0.61, 0.43
                local brighter = Logic.ColorDistance(
                    r, g, b, r + (1 - r) * 0.35, g + (1 - g) * 0.35, b + (1 - b) * 0.35
                )
                local magenta = Logic.ColorDistance(r, g, b, 0.90, 0.00, 0.98)
                assert.is_true(magenta > 0.2)
                assert.is_true(brighter < magenta / 2)
            end)
        end)

        describe("FALLBACK_LINE_COLORS", function()
            it("are each clearly distinct from every class color, the avoided colors and each other", function()
                local others = {}
                for _, c in pairs(CLASS_COLORS) do others[#others + 1] = c end
                for _, c in ipairs(Logic.LINE_COLOR_AVOID) do others[#others + 1] = c end
                local palette = Logic.FALLBACK_LINE_COLORS
                for i, f in ipairs(palette) do
                    for _, o in ipairs(others) do
                        local d = Logic.ColorDistance(f[1], f[2], f[3], o[1], o[2], o[3])
                        assert.is_true(d >= Logic.DISTINCT_COLOR_DISTANCE)
                    end
                    for j = i + 1, #palette do
                        local g = palette[j]
                        local d = Logic.ColorDistance(f[1], f[2], f[3], g[1], g[2], g[3])
                        assert.is_true(d >= Logic.DISTINCT_COLOR_DISTANCE)
                    end
                end
            end)
        end)

        describe("AssignLineColors", function()
            it("keeps the class color for the first character of each class", function()
                local colors = Logic.AssignLineColors({ entry("WARRIOR"), entry("MAGE") })
                assert.are.same({ { r = 0.78, g = 0.61, b = 0.43 }, { r = 0.25, g = 0.78, b = 0.92 } }, colors)
            end)

            it("gives later characters of a class a fallback, each distinct from everything shown", function()
                local entries = { entry("WARRIOR"), entry("MAGE"), entry("WARRIOR"), entry("WARRIOR"), entry("MAGE") }
                local colors = Logic.AssignLineColors(entries)
                assert.are.equal(5, #colors)
                for i, c in ipairs(colors) do
                    if i <= 2 then
                        assert.is_false(isFallback(c))
                    else
                        assert.is_true(isFallback(c))
                    end
                    for j = i + 1, #colors do
                        assert.is_true(distance(c, colors[j]) >= Logic.DISTINCT_COLOR_DISTANCE)
                    end
                end
            end)

            it("picks the fallback farthest from what is on the chart first", function()
                -- with no Warlock shown magenta is the farthest fallback; a Warlock's lavender pushes it back
                local colors = Logic.AssignLineColors({ entry("WARRIOR"), entry("WARRIOR") })
                assert.are.same({ r = 0.90, g = 0.00, b = 0.98 }, colors[2])
                colors = Logic.AssignLineColors({ entry("WARLOCK"), entry("WARLOCK") })
                assert.are_not.same({ r = 0.90, g = 0.00, b = 0.98 }, colors[2])
                assert.is_true(distance(colors[1], colors[2]) >= 0.2)
            end)

            it("is deterministic", function()
                local entries = { entry("HUNTER"), entry("HUNTER"), entry("DRUID"), entry("HUNTER") }
                assert.are.same(Logic.AssignLineColors(entries), Logic.AssignLineColors(entries))
            end)

            it("uses every fallback before repeating one", function()
                local entries = {}
                local n = #Logic.FALLBACK_LINE_COLORS
                for i = 1, n + 3 do entries[i] = entry("PRIEST") end
                local colors = Logic.AssignLineColors(entries)
                assert.are.equal(n + 3, #colors)
                local seen = {}
                for i = 2, n + 1 do
                    local key = colors[i].r .. "," .. colors[i].g .. "," .. colors[i].b
                    assert.is_nil(seen[key])
                    seen[key] = true
                end
                assert.is_true(isFallback(colors[n + 2]))
            end)

            it("treats characters without a class as one class", function()
                local colors = Logic.AssignLineColors({
                    { r = 0.7, g = 0.7, b = 0.7 }, { r = 0.7, g = 0.7, b = 0.7 },
                })
                assert.is_false(isFallback(colors[1]))
                assert.is_true(isFallback(colors[2]))
            end)

            it("returns an empty table for no entries", function()
                assert.are.same({}, Logic.AssignLineColors({}))
            end)
        end)
    end)
end)
